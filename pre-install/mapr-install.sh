#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:
#TBD: Handle mapruid install

usage() {
cat << EOF

Usage:
$0 -M -s -m|-e -u -x -a -k ServicePrincipalName -n ClusterName

-M option to install MapR Metrics (Grafana, etc)
-n option to specify cluster name (no spaces)
-s option for secure cluster installation
-k option for Kerberos cluster installation (implies -s)
-m option for MFS only cluster installation
-a option for cluster with dedicated admin nodes not running nodemanager
-e option to install on edge node (no fileserver). Can combine with -s or -x
-u option to upgrade existing cluster
-x option to uninstall existing cluster, destroying all data!

MapR Install methods:
1) Manually follow documentation at http://maprdocs.mapr.com/home/install.html
2) MapR GUI installer
   https://maprdocs.mapr.com/home/MapRInstaller.html
   (curl -LO http://package.mapr.com/releases/installer/mapr-setup.sh)
3) Bash script using clush groups and yum (this script)
4) Ansible install playbooks
   https://github.com/mapr-emea/mapr-ansible

Install of MapR must be done as root
(or with passwordless sudo as mapr service account)

Kerberos configuration document:
https://mapr.com/docs/61/SecurityGuide/Configuring-Kerberos-User-Authentication.html

This script requires these clush groups: clstr cldb zk rm hist [graf otsdb]

EOF
exit 2
}

secure=false; kerberos=false; mfsonly=false; uninstall=false; upgrade=false
admin=false; edge=false; metrics=false; clname=''; logsearch=false; dare=false
DBG=false
while getopts "MsdDmuxaek:n:" opt; do
  case $opt in
    M) metrics=true ;;
    n) clname="$OPTARG" ;;
    s) secure=true; ;;
    k) kerberos=true; secure=true; pn="$OPTARG" ;;
    m) mfsonly=true ;;
    u) upgrade=true ;;
    x) uninstall=true ;;
    a) admin=true ;;
    e) edge=true ;;
    d) dare=true ;;
    D) DBG=true ;;
    \?) usage ;;
  esac
done

shift $(( OPTIND - 1 )) #Report unknown options and exit
if [[ $# -gt 0 ]]; then
   echo Unknown option or argument 1: "$1"
   echo Unknown option or argument 2: "$2"
   exit
fi

setvars() {
   ########## Site specific variables
   # If MacOS has coreutils via brew install
   if [[ -d /usr/local/opt/coreutils/libexec/gnubin ]]; then
      PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
   fi
   clname=${clname:-''} #Name for the entire cluster, no spaces
   realm="" #Kerberos Realm
   # Login to web ui; use non-root, non-mapr account to create "hadoop admin"`
   admin1='mapr' #Non-root, non-mapr linux account which has a known password
   mapruid=mapr; maprgid=mapr #MapR service account and group
   spw=2 #Storage Pool width
   if compgen -G "/etc/*release" >/dev/null; then
      gcmd="grep -m1 -i -o -e ubuntu -e redhat -e 'red hat' -e centos"
      distro=$(cat /etc/*release 2>/dev/null | eval "$gcmd")
   else
      distro=centos
   fi
   maprver=v6.1.0 #TBD: Grep repo file to confirm or alter
   nfs='mapr-nfs' #Set to null to skip MapR NFS install
   #export JAVA_HOME=/usr/java/default #Oracle JDK
   export JAVA_HOME=/usr/lib/jvm/java #Openjdk 
   # MapR rpm installs look for $JAVE_HOME,
   # all clush/ssh cmds will forward setting in ~/.ssh/environment
   (umask 0077 && echo JAVA_HOME=$JAVA_HOME >> $HOME/.ssh/environment)
   #If not root use sudo, assuming mapr account has password-less sudo
   [[ $(id -u) -ne 0 ]] && SUDO='sudo PATH=/sbin:/usr/sbin:$PATH '
   cldb1=$(nodeset -I0 -e @cldb) #first node in cldb group
   # If root has mapr public key on all nodes
   #clush() { /Users/jbenninghoff/bin/clush -l root $@; }
   if [[ $(id -u) -ne 0 ]] && [[ $(id -un) != "$mapruid" ]]; then
      echo "This script must be run as root or $mapruid (with sudo)"
      #exit 1
   fi
   t1=$SECONDS
}
setvars #Set some global vars for install

# Check install pre-requisites
chk_prereq() {
   # Check for clush groups to layout services
   groups="clstr cldb zk rm hist"
   [[ "$metrics" == true ]] && groups+=" graf otsdb"
   #[[ "$edge" == true ]] && groups+=" edge "
   if [[ $(nodeset -c @cldb) -ne $(nodeset -c @clstr) ]]; then
      groups+=" noncldb"
   fi
   clushgrps=true
   for grp in $groups; do
      gmsg="Clustershell group: $grp undefined"
      [[ $(nodeset -c "@$grp") == 0 ]] && { echo "$gmsg"; clushgrps=false; }
   done
   [[ "$clushgrps" == false ]] && exit 1

   if [[ "$uninstall" == "false" && -z "$clname" ]]; then
      echo Cluster name not set.  Use -n option to set cluster name
      usage
      exit 2
   fi
   if [[ "$kerberos" == true && $realm == "" ]]; then
      echo Kerberos Realm not set.  Set realm var in this script.
      exit 2
   fi
   cldb1=$(nodeset -I0 -e @cldb) #first node in cldb group
   if [[ -z "$cldb1" ]]; then
      echo Primary node name not set.
      echo Set or check cldb1 variable in this script
      nodeset -I0 -e @cldb
      exit 2
   fi
   clush -S -B -g clstr id $admin1 || { echo $admin1 account does not exist on all nodes; exit 3; }
   clush -S -B -g clstr id $mapruid || { echo $mapruid account does not exist on all nodes; exit 3; }
   if [[ "$admin1" != "$mapruid" ]]; then
      clush -S -B -g clstr id $admin1 || \
         { echo $admin1 account does not exist on all nodes; exit 3; }
   fi
   clush -S -B -g clstr "$JAVA_HOME/bin/java -version \
      |& grep -e x86_64 -e 64-Bit -e version" || \
      { echo $JAVA_HOME/bin/java does not exist on all nodes or is not 64bit; \
      exit 3; }
   clush -qB -g clstr 'pkill -f yum; exit 0'
   clush -SB -g clstr 'echo "MapR Repo Check "; yum --noplugins -q search mapr-core' || { echo MapR RPMs not found; exit 3; }
   clush -SB -g clstr 'echo "MapR Repo URL ";yum --noplugins repoinfo mapr\* |grep baseurl'
   #rpm --import http://package.mapr.com/releases/pub/maprgpg.key
   #clush -S -B -g clstr 'echo "MapR Repos Check "; grep -li mapr /etc/yum.repos.d/* |xargs -l grep -Hi baseurl' || { echo MapR repos not found; }
   #clush -S -B -g clstr 'echo Check for EPEL; grep -qi -m1 epel /etc/yum.repos.d/*' || { echo Warning EPEL repo not found; }
   #TBD check for gpgcheck and key(s)
   read -p "All checks passed, press enter to continue or ctrl-c to abort"
}
[[ "$uninstall" == "true" || "$edge" == "true" ]] || chk_prereq

#Find, Download and install mapr-patch
install_patch() {
   inrepo=false
   clush -SB -g clstr ${SUDO:-} "yum --noplugins info mapr-patch" && inrepo=true
   if [[ "$inrepo" == "true" ]]; then
      clush -v -g clstr ${SUDO:-} "yum --noplugins -y install mapr-patch"
   else
      rpmsite="http://package.mapr.com/patches/releases/$maprver/redhat/"
      sedcmd="s/.*\(mapr-patch-${maprver//v}.*.rpm\).*/\1/p"
      patchrpm=$(timeout 9 curl -s $rpmsite | sed -n "$sedcmd")
      if [[ $? -ne 0 ]]; then
         url=http://package.mapr.com/patches/releases/$maprver/redhat/$patchrpm
         clush -v -g clstr ${SUDO:-} "yum --noplugins -y install $url"
      else
         echo "Patch not found, patchrpm=$patchrpm"
      fi
   fi
   # If mapr-patch rpm cannot be added to local repo
   #clush -abc /tmp/mapr-patch-6.0.1.20180404222005.GA-20180626035114.x86_64.rpm
   #clush -ab "${SUDO:-} yum -y localinstall /tmp/mapr-patch-6*.rpm"
   #clush -ab "systemctl stop mapr-warden; systemctl stop mapr-zookeeper"
   #clush -ab "systemctl start mapr-zookeeper; systemctl start mapr-warden"
}

install_metrics() {
   if [[ "$uninstall" == "true" ]]; then
      sshpfx="MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket"
      sshpfx+=" maprcli node services -action stop "

      # Stop the metric services
      sshcmd="$sshpfx -name grafana -nodes $(nodeset -e @graf)"
      clush -o -qtt -w $cldb1 "su - mapr -c '$sshcmd'"
      sshcmd="$sshpfx -name opentsdb -nodes $(nodeset -e @otsdb)"
      clush -o -qtt -w $cldb1 "su - mapr -c '$sshcmd'"
      sshcmd="$sshpfx -name collectd -nodes $(nodeset -e @clstr)"
      clush -o -qtt -w $cldb1 "su - mapr -c '$sshcmd'"

      # Remove the metric rpms
      clush -g graf "${SUDO:-} yum --noplugins -y erase mapr-grafana"
      clush -g otsdb "${SUDO:-} yum --noplugins -y erase mapr-opentsdb"
      clush -g clstr "${SUDO:-} yum --noplugins -y erase mapr-collectd"

      # Reconfigure MapR
      clcmd="env MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket "
      clcmd+=" /opt/mapr/server/configure.sh -R "
      clush -g clstr "${SUDO:-} $clcmd"
      exit
   fi

   clcmd="test -f /opt/mapr/conf/disktab >& /dev/null"
   if clush -S -B -g clstr "$clcmd"; then
      echo MapR appears to be installed, installing metric packages
   else
      echo MapR appears to not be installed, install cluster first
      exit 2
   fi

   # Install RPMs
   clush -g graf "${SUDO:-} yum --noplugins -y install mapr-grafana"
   clush -g otsdb "${SUDO:-} yum --noplugins -y install mapr-opentsdb"
   clush -g clstr "${SUDO:-} yum --noplugins -y install mapr-collectd"

   # Use MapR built-in ticket with root login
   clcmd="env MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket "
   clcmd+=" /opt/mapr/server/configure.sh -R "
   clcmd+=" -OT $(nodeset -S, -e @otsdb) "
   clush -g clstr "${SUDO:-} $clcmd"
   exit
}
[[ "$metrics" == true ]] && install_metrics # And exit script

install_logsearch() {
   # Fluentd copies MapR service logs to ES
   clush -g clstr "${SUDO:-} yum --noplugins -y install mapr-fluentd"
   # ES on 3 nodes for HA
   clush -g es "${SUDO:-} yum --noplugins -y install mapr-elasticsearch"
   # Kibana provides webui to ES
   clush -g kibana "${SUDO:-} yum --noplugins -y install mapr-kibana"

   # TBD: numerous config steps for log search on secure cluster
   es1=$(nodeset -I0 -e @es) #first node in es group
}
[[ "$logsearch" == true ]] && install_logsearch # And exit script

do_upgrade() {
   #TBD: grep secure=true /opt/mapr/conf/mapr-clusters.conf && 
   # { cp ../post-install/mapr-audit.sh /tmp;
   # sudo -u $mapruid /tmp/mapr-audit.sh; }
   #sudo -u mapr bash -c : && RUNAS="sudo -u mapr"; $RUNAS bash <<EOF
   # Source cluster_checks1 function from mapr-audit.sh
   #source <(sed -n '/^ *cluster_checks1()/,/^ *} *$/p' mapr-audit.sh)
   #cluster_checks1 || { echo Could not load cluster checks function; exit 4; }

   # Unmounts all localhost loopback NFS mounts
   clush -g clstr -b ${SUDO:-} umount /mapr
   #TBD: exit if other mounts found
   clush -g clstr -b ${SUDO:-} nfsstat -m
   readtxt='Press enter to continue or ctrl-c to abort, '
   readtxt+='abort if any mounts exist'
   read -p "$readtxt"

   #Check repo version
   clush -B -g clstr ${SUDO:-} "yum --noplugins clean all"
   clcmd="${SUDO:-} 'grep -i ^baseurl=http /etc/yum.repos.d/*mapr*.repo'"
   clcmd+=" || { echo MapR repos not found; exit 3; }"
   clush -S -B -g clstr "$clcmd"
   echo
   echo Review the HTTP URLs for the correct MapR version to be upgraded to
   echo If MapR EcoSystem URL is available, all installed MapR EcoSystem RPMs
   echo will be updated
   read -p "Press enter to continue or ctrl-c to abort"

   # Check for active Yarn or JobTracker jobs
   # stop centralconfig
   # stop ingest like Sqoop or Flume, maybe in crontab or Jensen or edge nodes
   # check machines for NFS mounts with
   # 'nfsstat -m' or 'netstat -an | grep 2049' using clush -ab
   # On all NFS client machines found,
   # run lsof /mntpoint and/or fuser -c /mntpoint;
   # stop or kill all procs using NFS
   # Stop MapR
   clush -g clstr -b "${SUDO:-} service mapr-warden stop"
   clush -g zk -b "${SUDO:-} service mapr-zookeeper stop"
   clush -g clstr -b "${SUDO:-} jps"
   clush -g clstr -b "${SUDO:-} pkill -u $mapruid"
   clush -g clstr -b "${SUDO:-} ps ax | grep $mapruid"
   readtxt="If any $mapruid process is still running, "
   readtxt+="press ctrl-c to abort and kill all manually"
   read -p "$readtxt"

   # Backup conf files
   folder_list='conf/ hadoop/hadoop-*/etc/hadoop/ hadoop/hadoop-*/conf '
   folder_list+='drill/drill-*/conf/ hbase/hbase-*/conf zkdata/ '
   folder_list+='spark/spark-*/conf/ sqoop/sqoop-*/conf/ '
   folder_list+='hive/hive-*/conf/ roles/'
: << '--BLOCK-COMMENT--' 
   # Get all ecosys conf files listed in /opt/mapr/roles per host
   grepwords="-v -e cldb -e fileserver -e nodemanager -e nfs -e apiserver "
   grepwords+="-e resourcemanager "
   for role in $(ls /opt/mapr/roles |grep $grepwords); do
      cd /opt/mapr
      ls -d $role/$role-*/{conf,etc} 2>/dev/null
   done
   folder_list='conf/ hadoop/hadoop-*/etc/hadoop/ hadoop/hadoop-*/conf '
   folder_list+=$(for role in $(ls /opt/mapr/roles |grep -v -e cldb -e fileserver -e nodemanager -e nfs -e apiserver); do cd /opt/mapr; ls -d $role/$role-*/{conf,etc} 2>/dev/null; done |xargs echo; echo ' ')
--BLOCK-COMMENT--
   clcmd="${SUDO:-} cd /opt/mapr/ && "
   clcmd+="tar cfz $HOME/mapr_configs-\$(hostname -f)-\$(date "+%FT%T").tgz "
   clcmd+="${folder_list}"
   clush -g clstr -b "$clcmd"
   #ansible -i /etc/ansible/hosts all -m shell -a "$clcmd"
   clush -g clstr -b ${SUDO:-} "ls -l $HOME/mapr_configs*.tgz"
   #ansible -i /etc/ansible/hosts all -m shell -a "ls -l $HOME/mapr_conf*.tgz"
   # TBD: make /tmp script, push it to all nodes, run it on all nodes.

   # Remove mapr-patch
   clush -g clstr -b ${SUDO:-} yum --noplugins -y erase mapr-patch

   # Update all MapR RPMs on all nodes
   # yum --disablerepo mapr-eco update mapr-\*
   #Exclude specific rpms with --exclude=mapr-some-somepackage
   clush -v -g clstr ${SUDO:-} "yum --noplugins -y update mapr-\*"
   readtxt="Check console for errors.  If none, press enter to continue or "
   readtxt+="ctrl-c to abort"
   read -p "$readtxt"

   # Download and install mapr-patch
   install_patch

   # Run configure.sh -R to insure configuration is updated
   clush -g clstr -b ${SUDO:-} /opt/mapr/server/configure.sh -R
   # TBD: modify yarn-site.xml and mapred-site.xml and container-executor.cfg
   # when upgrading

   # Start rpcbind, zk and warden
   clush -g clstr -b ${SUDO:-} service rpcbind restart
   clush -g zk -b ${SUDO:-} service mapr-zookeeper start
   sleep 9
   clush -g zk -b ${SUDO:-} service mapr-zookeeper qstatus
   clush -g clstr -b ${SUDO:-} service mapr-warden start
   sleep 90
   export MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket
   maprconf='{mapr.targetversion:"`cat /opt/mapr/MapRBuildVersion`"}'
   sudo -u mapr maprcli config save -values "$maprconf"
   sudo -u mapr maprcli cluster feature enable -all
   exit
}
[[ "$upgrade" == "true" ]] && do_upgrade # And exit script

uninstall() {
   sshcmd="MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket"
   sshcmd+=" maprcli dashboard info -json "
   clush -o -qtt -w $cldb1 "su - mapr -c '$sshcmd'" |awk '/"disk_space":{/,/}/'
   read -p "All data will be lost, press enter to continue or ctrl-c to abort"
   clush -g clstr -b ${SUDO:-} umount /mapr
   clush -g clstr -b ${SUDO:-} service mapr-warden stop
   clush -g zk -b ${SUDO:-} service mapr-zookeeper stop
   clush -g clstr -b ${SUDO:-} jps
   clush -g clstr -b ${SUDO:-} pkill -u $mapruid
   clush -g clstr -b "${SUDO:-} ps ax | grep $mapruid"
   readtxt="If any $mapruid process is still running, "
   readtxt+="press ctrl-c to abort. Kill all $mapruid processes manually"
   read -p "$readtxt"
   clcmd="cp /opt/mapr/conf/disktab /var/tmp/mapr-disktab"
   clush -g clstr -b "${SUDO:-} $clcmd"
   echo Copy of disktab saved to /var/tmp/ on all nodes

   shopt -s nocasematch
   while read -p "Enter 'yes' to remove all mapr packages and /opt/mapr: "; do
      [[ "$REPLY" == "yes" ]] && break
   done

   case $distro in
      redhat|centos|red*)
         clcmd="yum clean all; yum -y erase mapr-\*"
         clush -g clstr -b ${SUDO:-} "$clcmd" ;;
      ubuntu)
         clush -g clstr -B 'dpkg -P mapr-\*' ;;
      *) echo Unknown Linux distro! $distro; exit ;;
   esac
   clush -g clstr -b ${SUDO:-} rm -rf /opt/mapr
   clush -g clstr -b ${SUDO:-} rm -rf /tmp/hadoop-mapr
   clush -g clstr -b ${SUDO:-} 'rm -rf /tmp/maprticket_*'
   exit
}
[[ "$uninstall" == "true" && "$edge" == "false" ]] && uninstall # And exit 

install_edge_node() {
   if [[ $(nodeset -c @edge) == 0 ]]; then
      echo clustershell group: edge undefined
      exit 1
   fi
   if [[ "$uninstall" == "true" ]]; then
      clush -g edge -b ${SUDO:-} umount /mapr
      clush -g edge -b ${SUDO:-} service mapr-warden stop
      clush -g edge -b ${SUDO:-} service mapr-posix-client-basic stop
      clush -g edge -b ${SUDO:-} jps
      clush -g edge -b ${SUDO:-} pkill -u $mapruid
      clush -g edge -b "${SUDO:-} ps ax | grep $mapruid"
      read -p "If any $mapruid process is still running, \
      press ctrl-c to abort and kill all manually"
      clush -g edge -b "${SUDO:-} yum clean all; yum -y erase mapr-\*"
      clush -g edge -b ${SUDO:-} rm -rf /opt/mapr
      exit
   else
      if ! clush -S -B -g edge id $mapruid; then
         echo $mapruid account does not exist on all nodes
         mustexit=true
      fi
      clcmd="$JAVA_HOME/bin/java -version |& grep -e x86_64 -e 64-Bit -e version"
      if ! clush -S -B -g edge "$clcmd"; then
         echo $JAVA_HOME/bin/java does not exist on all nodes or is not 64bit
         mustexit=true
      fi
      clush -qB -g edge 'pkill -f yum; exit 0'
      if ! clush -SB -g edge 'echo "MapR Repo Check "; yum --noplugins -q search mapr-core'; then
         echo MapR RPMs not found, define mapr repo
         mustexit=true
      fi
      if [[ "$mustexit" == "true" ]]; then
         echo Pre-requisites not met; exit 3
      fi
      clush -SB -g edge 'echo "MapR Repo URL ";yum --noplugins repoinfo mapr* |grep baseurl'
      # Install mapr-core to use warden to run HS2,Metastore,etc
      rpms="mapr-core mapr-posix-client-basic"
      clush -v -g edge "${SUDO:-} yum -y install $rpms"
      # Edge node without maprcli
      #rpms="mapr-client mapr-posix-client-basic"
      # Enables edge node as simple client with loopback NFS to maprfs
      #rpms="mapr-client mapr-nfs"
      # TBD: If mapr-core installed, install patch?

      if [[ "$secure" == "true" ]]; then
         keys="ssl_truststore,ssl_keystore,maprserverticket,mapruserticket"
         scp "root@$cldb1:/opt/mapr/conf/{$keys}" . #fetch a copy of the keys
         clush -g edge -c ssl_truststore --dest /opt/mapr/conf/
         clush -g edge -c ssl_keystore --dest /opt/mapr/conf/
         clush -g edge -c maprserverticket --dest /opt/mapr/conf/
         clush -g edge -c mapruserticket --dest /opt/mapr/conf/
         clush -g edge "${SUDO:-} chown $mapruid:$maprgid /opt/mapr/conf/{$keys}"
         clush -g edge "${SUDO:-} chmod 600 /opt/mapr/conf/{$keys}"
         clush -g edge "${SUDO:-} chmod 644 /opt/mapr/conf/ssl_truststore"
      fi
      # v4.1+ use RM zeroconf, no -RM option 
      confopts="-N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb)"
      confopts+=" -HS $(nodeset -I0 -e @hist) -u $mapruid -g $maprgid"
      confopts+=" -no-autostart"
      #confopts+=" -no-autostart -c"
      [[ "$secure" == "true" ]] && confopts+=" -S"
      clush -S -g edge "${SUDO:-} /opt/mapr/server/configure.sh $confopts"
      chmod u+s /opt/mapr/bin/fusermount
      echo Edit /opt/mapr/conf/fuse.conf. Append mapr ticket file path 
      systemctl restart mapr-warden restart
      exit
   fi
}
[[ "$edge" == "true" ]] && install_edge_node # And exit script

chk_disk_list() {
   clear
   clush -S -B -g clstr "cat /tmp/disk.list; wc /tmp/disk.list" || { echo /tmp/disk.list not found, run clush disk-test.sh; exit 4; }
   clush -S -B -g clstr 'test -f /opt/mapr/conf/disktab' >& /dev/null && { echo MapR appears to be installed; exit 3; }

   # Create multiple disk lists for heterogeneous Storage Pools
   #clush -B -g clstr "sed -n '1,10p' /tmp/disk.list > /tmp/disk.list1"
   #clush -B -g clstr "sed -n '11,\$p' /tmp/disk.list > /tmp/disk.list2"
   #clush -B -g clstr "cat /tmp/disk.list1; wc /tmp/disk.list1" || { echo /tmp/disk.list1 not found; exit 4; }
   #clush -B -g clstr "cat /tmp/disk.list2; wc /tmp/disk.list2" || { echo /tmp/disk.list2 not found; exit 4; }

   cat <<EOF3

   Ensure that all nodes have been audited with cluster-audit.sh and
   all issues fixed.  Also ensure that all nodes have met subsystem
   performance expectations as measured by memory-test.sh, network-test.sh
   and disk-test.sh. 

   Scrutinize the disk list above.  All disks will be formatted for
   MapR FS, destroying all existing data on the disks.  If the disk
   list contains an OS disk or disk not intended for MapR FS, abort
   this script and edit the disk-test.sh script to filter the disk(s)
   and rerun it with clush to generate new /tmp/disk.list files.

EOF3
   read -p "Press enter to continue or ctrl-c to abort"
}
chk_disk_list # Verify all nodes have a disk.list in /tmp and present it

install_mfs() {
   # 3 zookeeper nodes
   clush -v -g zk "${SUDO:-} yum --noplugins -y install mapr-zookeeper"
   # 3 cldb nodes for ha, 1 does writes, all 3 do reads
   clush -v -g cldb "${SUDO:-} yum --noplugins -y install \
      mapr-cldb mapr-webserver"
   # Core rpms for all installation types
   clush -v -g clstr "${SUDO:-} yum --noplugins -y install \
      mapr-fileserver $nfs"
}
install_mfs && echo Core MFS install finished

install_yarn() {
   # Service layout option #1 ====================
   # Admin services layered over data nodes
   # Admin nodes defined by rm and hist groups
   # At least 2 rm nodes
   clush -g rm "${SUDO:-} yum --noplugins -y install \
      mapr-resourcemanager"
   # Yarn history server
   clush -g hist "${SUDO:-} yum --noplugins -y install \
      mapr-historyserver"
   # All data nodes are compute nodes also
   clush -v -g clstr "${SUDO:-} yum --noplugins -y install \
      mapr-nodemanager"

   # Service layout option #2 ====================
   # Admin nodes don't run Yarn NM
   if [[ "$admin" == "true" ]]; then
      clush -g rm,cldb "${SUDO:-} yum --noplugins -y erase mapr-nodemanager"
   fi
}
[[ "$mfsonly" == "false" ]] && install_yarn && echo Yarn install finished

post_install() {
   # Set JAVA_HOME in env.sh after MapR rpms are installed
   # First rely on env.sh to find $JAVA_HOME, uncomment if it fails
   #sedcmd="'s,^#export JAVA_HOME=,export JAVA_HOME=$JAVA_HOME,'"
   #clush -g clstr "${SUDO:-} sed -i.bk $sedcmd /opt/mapr/conf/env.sh"

   # Install patch if it is available in repo or http://packages.mapr.com
   install_patch

   # Create MapR fstab
   fstab='localhost:/mapr /mapr hard,intr,nolock,noatime'
   ddcmd='dd of=/opt/mapr/conf/mapr_fstab status=none'
   echo $fstab |clush -g clstr "${SUDO:-} $ddcmd"
   clush -g clstr "${SUDO:-} mkdir -p /mapr"
}
post_install && echo Post install finished

install_keys() {
   # Remove existing keys
   secfiles="cldb.key dare.master.key maprserverticket"
   secfiles+=" ssl_truststore ssl_truststore.pem ssl_truststore.p12"
   secfiles+=" ssl_keystore ssl_keystore.pem ssl_keystore.p12"
   seckeys="{${secfiles// /,}}" # Convert to ','
   seckeys="{${seckeys//,,/,}}" # Remove any duplicate ','
   clcmd="rm -f /opt/mapr/conf/$seckeys"
   clush -g clstr "${SUDO:-} $clcmd >& /dev/null"
   #echo rm-keys done; read -p "press enter to continue or ctrl-c to abort"

   # Generate keys using primary CLDB node
   clcmd="/opt/mapr/server/configure.sh -N $clname "
   clcmd+=" -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) "
   clcmd+=" -secure -genkeys -f -u $mapruid -g $maprgid "
   clcmd+=" -on-prompt-cont y -v -no-autostart -OT $(nodeset -S, -e @otsdb) "
   [[ "$kerberos" == "true" ]] && clcmd+=" -K -P $mapruid/$clname@$realm "
   [[ "$dare" == "true" ]] && clcmd+=" -dare "
   clush -S -w $cldb1 "${SUDO:-} $clcmd"
   if [[ $? -ne 0 ]]; then
      echo "configure.sh -genkeys failed"
      echo ${SUDO:-} $clcmd
      echo check screen and $cldb1:/opt/mapr/logs for errors
      exit 2
   fi
   #echo gen-keys done; read -p "press enter to continue or ctrl-c to abort"

   # Pull a copy of the keys from first CLDB node, then push to all nodes
   for file in $secfiles; do
      ssh root@$cldb1 dd status=none if=/opt/mapr/conf/$file > ~/"$file" #Pull
      ddcmd="dd of=/opt/mapr/conf/$file status=none"
      clush -g clstr -x $cldb1 "${SUDO:-} $ddcmd" < ~/"$file" #Push
      #echo file is: $file; read -p "press enter to continue or ctrl-c to abort"
   done
   ssh root@$cldb1 "cksum /opt/mapr/conf/$seckeys"
   ssh root@$cldb1 "ls -l /opt/mapr/conf/$seckeys"
   #echo pull-keys done; read -p "press enter to continue or ctrl-c to abort"

   # Set owner and permissions on all key files pushed out
   clcmd="chown $mapruid:$maprgid /opt/mapr/conf/$seckeys"
   clush -g clstr "${SUDO:-} $clcmd"
   clcmd="chmod 400 /opt/mapr/conf/$seckeys"
   clush -g clstr "${SUDO:-} $clcmd"
   clcmd="chmod 444 /opt/mapr/conf/ssl_truststore*"
   clush -g clstr "${SUDO:-} $clcmd"
   clcmd="chmod 600 /opt/mapr/conf/{cldb.key,dare.master.key,maprserverticket}"
   clush -g clstr "${SUDO:-} $clcmd"
   #clush -b -g clstr "cksum /opt/mapr/conf/$seckeys"
   #echo install_keys; read -p "press enter to continue or ctrl-c to abort"
}
[[ "$secure" == "true" ]] && install_keys && echo MapR Keys installed

configure_mapr() {
   cfg=/opt/mapr/server/configure.sh
   # Define all configure.sh options needed
   confopts="-N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) "
   confopts+=" -u $mapruid -g $maprgid -no-autostart "
   [[ "$mfsonly" == "false" ]] && confopts+="-HS $(nodeset -I0 -e @hist) "
   [[ "$secure" == "true" ]] && confopts+=" -S "
   [[ "$kerberos" == "true" ]] && confopts+=" -K -P $mapruid/$clname@$realm "
   #TBD: Handle $pn and $realm
   if [[ "$1" == "cldb" ]]; then
      clush -S -w $(nodeset -S, -e @cldb -x $cldb1) "${SUDO:-} $cfg $confopts"
   else
      clush -S -g $1 "${SUDO:-} $cfg $confopts"
   fi
   if [[ $? -ne 0 ]]; then
      echo configure.sh failed
      echo check screen history and /opt/mapr/logs/configure.log for errors
      exit 2
   fi
   #echo configure_mapr; read -p "press enter to continue or ctrl-c to abort"
}
configure_mapr cldb && echo Configure.sh on CLDB nodes finished

format_disks() {
   disks=/tmp/disk.list
   dargs="-F -W $spw"
   clush -g $1 "${SUDO:-} rm -f /opt/mapr/conf/disktab"
   clush -S -g $1 "${SUDO:-} /opt/mapr/server/disksetup $dargs $disks"
   if [[ $? -ne 0 ]]; then
      echo disksetup failed, check terminal and /opt/mapr/logs for errors
      exit 3
   fi
   #echo format_disks(); read -p "press enter to continue or ctrl-c to abort"
}
format_disks cldb && echo CLDB disks formatted

start_mapr() {
   clush -g zk "${SUDO:-} service mapr-zookeeper start"
   clush -g $1 "${SUDO:-} service mapr-warden start"

   echo Waiting 2 minutes for system to initialize
   end=$((SECONDS+120))
   sp='/-\|'
   printf ' '
   while (( SECONDS < end )); do
      printf '\b%.1s' "$sp"
      sp=${sp#?}${sp%???}
      sleep .3
   done # Spinner from StackOverflow

   t2=$SECONDS; echo -n "Duration time for installation: "
   date -u -d @$((t2 - t1)) +"%T"
}
start_mapr cldb && echo Warden started on CLDB nodes

# Repeat configuration on non-cldb nodes
if [[ $(nodeset -c @noncldb) -ne 0 ]]; then
   configure_mapr noncldb && echo MapR noncldb configured
   format_disks noncldb && echo MapR disks formatted
   start_mapr noncldb && echo MapR warden started
fi

add_acl_lic() {
   #uid=$(id un)
   #case $uid in
   #   root) ;;
   #   $mapruid) ;;
   #esac

   sshcmd="MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket"
   sshcmd+=" maprcli node cldbmaster"
   clush -o -qtt -w $cldb1 "su - $mapruid -c '$sshcmd'" 
   if [[ $? -ne 0 ]]; then
      echo CLDB did not startup, check status and logs on $cldb1
      exit 3
   fi

   sshcmd="MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket"
   sshcmd+=" maprcli acl edit -type cluster -user $admin1:fc,a"
   clush -o -qtt -w $cldb1 "su - $mapruid -c '$sshcmd'" 

   cat << LICMESG
   With a web browser, connect to one of the webservers to continue
   with license installation:
   Webserver nodes: $(nodeset -e @cldb)

   Alternatively, the license can be installed with maprcli.
   First, get the cluster id with maprcli like this:

   maprcli dashboard info -json |grep -e id -e name
                   "name":"MyCluster",
                   "id":"1111111111111111111",

   Then you can use any browser to connect to http://mapr.com/. In the
   upper right corner there is a login link.  login and register if you
   have not already.  Once logged in, you can use the register button on
   the right of your login page to register a cluster by just entering
   a clusterid.
   Once you finish the register form, you will get back a license which
   you can copy and paste to a file on the same node you ran maprcli.
   Use that file as filename in the following maprcli command:
     maprcli license add -is_file true -license filename
   
   The license server API can also be used with a valid mapr.com
   login which requires prior registration.  Specify the generated
   cluster ID and the cluster name to the REST interface:
     curl -u jbenninghoff@maprtech.com 'https://mapr-installer-dialhome.appspot.com/trial?cluster_id=5681466578299529065&cluster_name=ps&out=text'

   Copy the resulting file (stdout) to the cluster if need be.
   Install the license on the MapR cluster:
     env MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket maprcli license add -is_file true -license /tmp/WFtest3.lic

   Restart the entire cluster:
     clush -ab systemctl restart mapr-warden

LICMESG

   sshcmd="MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket"
   sshcmd+=" maprcli dashboard info -json "
   clush -o -qtt -w $cldb1 "su - $mapruid -c '$sshcmd'" |grep -e id -e name
}
add_acl_lic

#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

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
2) Bash script using clush groups and yum (this script)
3) MapR GUI installer
   https://maprdocs.mapr.com/home/MapRInstaller.html
   (curl -LO http://package.mapr.com/releases/installer/mapr-setup.sh)
4) Ansible install playbooks
   https://github.com/mapr-emea/mapr-ansible

Install of MapR must be done as root
(or with passwordless sudo as mapr service account)

This script requires the following clush groups: clstr cldb zk rm hist

EOF
exit 2
}

secure=false; kerberos=false; mfs=false; uninstall=false; upgrade=false
admin=false; edge=false; metrics=false; clname=''
while getopts "Msmuxaek:n:" opt; do
  case $opt in
    M) metrics=true ;;
    n) clname="$OPTARG" ;;
    s) secure=true; sopt="-S" ;;
    k) kerberos=true; secure=true; sopt="-S"; pn="$OPTARG" ;;
    m) mfs=true ;;
    u) upgrade=true ;;
    x) uninstall=true ;;
    a) admin=true ;;
    e) edge=true ;;
    \?) usage ;;
  esac
done

setvars() {
   ########## Site specific variables
   clname=${clname:-''} #Name for the entire cluster, no spaces
   # Login to web ui
   admin1='mapr' #Non-root, non-mapr linux account which has a known password
   mapruid=mapr; maprgid=mapr #MapR service account and group
   spwidth=4 #Storage Pool width
   distro=$(cat /etc/*release 2>/dev/null | grep -m1 -i -o -e ubuntu -e redhat -e 'red hat' -e centos) || distro=centos
   maprver=v5.2.0 #TBD: Grep repo file to confirm or alter
   clargs='-S'
   #export JAVA_HOME=/usr/java/default #Oracle JDK
   export JAVA_HOME=/usr/lib/jvm/java #Openjdk 
   # MapR rpm installs look for $JAVE_HOME,
   # all clush/ssh cmds will forward setting in ~/.ssh/environment
   (umask 0077 && echo JAVA_HOME=$JAVA_HOME >> $HOME/.ssh/environment)
   #If not root use sudo, assuming mapr account has password-less sudo
   [ $(id -u) -ne 0 ] && SUDO='sudo PATH=/sbin:/usr/sbin:$PATH '
   # If root has mapr public key on all nodes
   #clush() { /Users/jbenninghoff/bin/clush -l root $@; }
   clushgrps=true
   [ $(id -u) -ne 0 -a $(id -un) != "$mapruid" ] && { echo This script must be run as root or $maprid; exit 1; }
}
setvars

chk_prereq() {
   # Check cluster for pre-requisites
   #Check for clush groups to layout services
   for grp in clstr cldb zk rm hist; do
      gmsg="Clustershell group: $grp undefined"
      [[ $(nodeset -c @$grp) == 0 ]] && { echo $gmsg; clushgrps=false; }
   done
   [[ "$clushgrps" == false ]] && exit 1

   if [[ "$metrics" == true ]]; then
      gmsg="Clustershell group: $metrics undefined"
      [[ $(nodeset -c @$metrics) == 0 ]] && { echo $gmsg; exit 2; }
   fi

   cldb1=$(nodeset -I0 -e @cldb) #first node in cldb group
   [[ -z "$clname" ]] && { echo Cluster name not set.  Set clname in this script; exit 2; }
   [[ -z "$admin1" ]] && { echo Admin name not set.  Set admin1 in this script; exit 2; }
   [[ -z "$cldb1" ]] && { echo Primary node name not set.  Set or check cldb1 in this script; exit 2; }
   clush -S -B -g clstr id $admin1 || { echo $admin1 account does not exist on all nodes; exit 3; }
   clush -S -B -g clstr id $mapruid || { echo $mapruid account does not exist on all nodes; exit 3; }
   clush -S -B -g clstr "$JAVA_HOME/bin/java -version |& grep -e x86_64 -e 64-Bit" || { echo $JAVA_HOME/bin/java does not exist on all nodes or is not 64bit; exit 3; }
   clush -S -B -g clstr 'echo "MapR Repo Check "; yum -q search mapr-core' || { echo MapR RPMs not found; exit 3; }
   #rpm --import http://package.mapr.com/releases/pub/maprgpg.key
   #clush -S -B -g clstr 'echo "MapR Repos Check "; grep -li mapr /etc/yum.repos.d/* |xargs -l grep -Hi baseurl' || { echo MapR repos not found; }
   #clush -S -B -g clstr 'echo Check for EPEL; grep -qi -m1 epel /etc/yum.repos.d/*' || { echo Warning EPEL repo not found; }
   #TBD check for gpgcheck and key(s)
   read -p "All checks passed, press enter to continue or ctrl-c to abort"
}
chk_prereq

install_patch() { #Find, Download and install mapr-patch version $maprver
   inrepo=false
   clush -S -B -g clstr ${SUDO:-} "yum info mapr-patch" && inrepo=true
   if [ "$inrepo" == "true" ]; then
      clush -v -g clstr ${SUDO:-} "yum -y install mapr-patch"
   else
      rpmsite="http://package.mapr.com/patches/releases/$maprver/redhat/"
      sedcmd="s/.*\(mapr-patch-${maprver//v}.*.rpm\).*/\1/p"
      patchrpm=$(timeout 9 curl -s $rpmsite | sed -n "$sedcmd")
      if [[ $? -ne 0 ]]; then
         url=http://package.mapr.com/patches/releases/$maprver/redhat/$patchrpm
         clush -v -g clstr ${SUDO:-} "yum -y install $url"
      else
         echo "Patch not found, patchrpm=$patchrpm"
      fi
   fi
   # If mapr-patch rpm cannot be added to local repo
   #clush -g clstr ${SUDO:-} 'yum -y install file:///tmp/mapr-patch\*.rpm'
}

do_upgrade() {
   #TBD: grep secure=true /opt/mapr/conf/mapr-clusters.conf && { cp ../post-install/mapr-audit.sh /tmp; sudo -u $mapruid /tmp/mapr-audit.sh; }
   #sudo -u mapr bash -c : && RUNAS="sudo -u mapr"; $RUNAS bash <<EOF
   # Source cluster_checks1 function from mapr-audit.sh
   #source <(sed -n '/^ *cluster_checks1()/,/^ *} *$/p' mapr-audit.sh)
   #cluster_checks1 || { echo Could not load cluster checks function; exit 4; }

   # Unmounts all localhost loopback NFS mounts
   clush -g clstr -b ${SUDO:-} umount /mapr
   #TBD: exit if other mounts found
   clush -g clstr -b ${SUDO:-} nfsstat -m
   read -p "Press enter to continue or ctrl-c to abort, abort if any mounts exist"

   #Check repo version
   clush -B -g clstr ${SUDO:-} "yum clean all"
   clush -S -B -g clstr ${SUDO:-} 'grep -i ^baseurl=http /etc/yum.repos.d/*mapr*.repo' || { echo MapR repos not found; exit 3; }
   echo; echo Review the HTTP URLs for the correct MapR version to be upgraded to
   echo If MapR EcoSystem URL is available, all installed MapR EcoSystem RPMs will be updated
   read -p "Press enter to continue or ctrl-c to abort"

   # Check for active Yarn or JobTracker jobs
   # stop centralconfig
   # stop ingest like Sqoop or Flume, maybe in crontab or Jensen or edge nodes
   # check machines for NFS mounts with 'nfsstat -m' or 'netstat -an | grep 2049' using clush -ab
   # On all NFS client machines found, run lsof /mntpoint and/or fuser -c /mntpoint; stop or kill all procs using NFS
   # Stop MapR
   clush -g clstr -b ${SUDO:-} service mapr-warden stop
   clush -g zk -b ${SUDO:-} service mapr-zookeeper stop
   clush -g clstr -b ${SUDO:-} jps
   clush -g clstr -b ${SUDO:-} pkill -u $mapruid
   clush -g clstr -b ${SUDO:-} "ps ax | grep $mapruid"
   read -p "If any $mapruid process still running, press ctrl-c to abort and kill all manually"

   # Backup conf files
   folder_list='conf/ hadoop/hadoop-*/etc/hadoop/ hadoop/hadoop-*/conf drill/drill-*/conf/ hbase/hbase-*/conf zkdata/ spark/spark-*/conf/ sqoop/sqoop-*/conf/ hive/hive-*/conf/ roles/'
   clush -g clstr -b ${SUDO:-} "cd /opt/mapr/ && tar cfz $HOME/mapr_configs-$(hostname -f)-$(date "+%FT%T").tgz ${folder_list}"
   clush -g clstr -b ${SUDO:-} "ls -l $HOME/mapr_configs*.tgz"

   # Remove mapr-patch
   clush -g clstr -b ${SUDO:-} yum -y erase mapr-patch

   # Update all MapR RPMs on all nodes
   clush -v -g clstr ${SUDO:-} "yum -y update mapr-\*" #Exclude specific rpms with --exclude=mapr-some-somepackage
   read -p "Check console for errors.  If none, press enter to continue or ctrl-c to abort"

   # Download and install mapr-patch
   install_patch

   # Run configure.sh -R to insure configuration is updated
   clush -g clstr -b ${SUDO:-} /opt/mapr/server/configure.sh -R
   # TBD: modify yarn-site.xml and mapred-site.xml and container-executor.cfg when upgrading

   # Start rpcbind, zk and warden
   clush -g clstr -b ${SUDO:-} service rpcbind restart
   clush -g zk -b ${SUDO:-} service mapr-zookeeper start
   sleep 9
   clush -g zk -b ${SUDO:-} service mapr-zookeeper qstatus
   clush -g clstr -b ${SUDO:-} service mapr-warden start
   sleep 90
   export MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket
   sudo -u mapr maprcli config save -values {mapr.targetversion:"`cat /opt/mapr/MapRBuildVersion`"}
   sudo -u mapr maprcli cluster feature enable -all
   exit
}
[[ "$upgrade" == "true" ]] && do_upgrade # And exit script

uninstall() {
   sshcmd="MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket"
   sshcmd+=" maprcli dashboard info -json "
   ssh -qtt root@$cldb1 "su - mapr -c '$sshcmd'" |awk '/"disk_space":{/,/}/'
   read -p "All data will be lost, press enter to continue or ctrl-c to abort"
   clush $clargs -g clstr -b ${SUDO:-} umount /mapr
   clush $clargs -g clstr -b ${SUDO:-} service mapr-warden stop
   clush $clargs -g zk -b ${SUDO:-} service mapr-zookeeper stop
   clush $clargs -g clstr -b ${SUDO:-} jps
   clush $clargs -g clstr -b ${SUDO:-} pkill -u $mapruid
   clush $clargs -g clstr -b "${SUDO:-} ps ax | grep $mapruid"
   read -p "If any $mapruid process is still running, press ctrl-c to abort and kill all manually"
   cp /opt/mapr/conf/disktab /var/tmp/mapr-disktab
   echo Copy of disktab saved to /var/tmp/

   shopt -s nocasematch
   while read -p "Enter 'yes' to remove all mapr packages and /opt/mapr: "; do
      [[ "$REPLY" == "yes" ]] && break
   done

   case $distro in
      redhat|centos|red*)
         clush $clargs -g clstr -b ${SUDO:-} "yum clean all; yum -y erase mapr-\*" ;;
      ubuntu)
         clush -g clstr -B 'dpkg -P mapr-\*' ;;
      *) echo Unknown Linux distro! $distro; exit ;;
   esac
   clush $clargs -g clstr -b ${SUDO:-} rm -rf /opt/mapr
   clush $clargs -g clstr -b ${SUDO:-} rm -rf /tmp/hadoop-mapr
   clush $clargs -g clstr -b ${SUDO:-} 'rm -rf /tmp/maprticket_*'
   exit
}
[[ "$uninstall" == "true" && "$edge" == "false" ]] && uninstall # And exit 

do_edge_node() {
   if [[ $(nodeset -c @edge) == 0 ]]; then
      echo clustershell group: edge undefined
      exit 1
   fi
   if [ "$uninstall" == "true" ]; then
      clush $clargs -g edge -b ${SUDO:-} umount /mapr
      clush $clargs -g edge -b ${SUDO:-} service mapr-warden stop
      clush $clargs -g edge -b ${SUDO:-} service mapr-posix-client-basic stop
      clush $clargs -g edge -b ${SUDO:-} jps
      clush $clargs -g edge -b ${SUDO:-} pkill -u $mapruid
      clush $clargs -g edge -b ${SUDO:-} "ps ax | grep $mapruid"
      read -p "If any $mapruid process is still running, \
      press ctrl-c to abort and kill all manually"
      clush $clargs -g edge -b ${SUDO:-} "yum clean all; yum -y erase mapr-\*"
      clush $clargs -g edge -b ${SUDO:-} rm -rf /opt/mapr
      exit
   else
      # Enables edge node to use warden to run HS2,Metastore,etc
      rpms="mapr-core mapr-posix-client-basic"
      clush $clargs -v -g edge "${SUDO:-} yum -y install $rpms"
      # Edge node without maprcli
      #rpms="mapr-client mapr-posix-client-basic"
      # Enables edge node as simple client with loopback NFS to maprfs
      #rpms="mapr-client mapr-nfs"
      # TBD: If mapr-core installed, install patch?

      if [ "$secure" == "true" ]; then
         keys="ssl_truststore,ssl_keystore,maprserverticket,mapruserticket"
         scp "root@$cldb1:/opt/mapr/conf/{$keys}" . #fetch a copy of the keys
         clush -g edge -c ssl_truststore --dest /opt/mapr/conf/
         clush -g edge -c ssl_keystore --dest /opt/mapr/conf/
         clush -g edge -c maprserverticket --dest /opt/mapr/conf/
         clush $clargs -g edge "${SUDO:-} chown $mapruid:$maprgid /opt/mapr/conf/{$keys}"
         clush $clargs -g edge "${SUDO:-} chmod 600 /opt/mapr/conf/{maprserverticket,mapruserticket}"
         clush $clargs -g edge "${SUDO:-} chmod 644 /opt/mapr/conf/ssl_truststore"
      fi
      # v4.1+ use RM zeroconf, no -RM option 
      confopts="-N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb)"
      confopts+=" -HS $(nodeset -I0 -e @hist) -u $mapruid -g $maprgid"
      confopts+=" -no-autostart -c"
      [[ "$secure" == "true" ]] && confopts+=" -S"
      clush -S $clargs -g edge "${SUDO:-} /opt/mapr/server/configure.sh $confopts"
      chmod u+s /opt/mapr/bin/fusermount
      echo Edit /opt/mapr/conf/fuse.conf. Append mapr ticket file path 
      service mapr-warden restart
      exit
   fi
}
[[ "$edge" == "true" ]] && do_edge_node # And exit script

chk_disk_list() {
   clear
   clush $clargs -B -g clstr "cat /tmp/disk.list; wc /tmp/disk.list" || { echo /tmp/disk.list not found, run clush disk-test.sh; exit 4; }
   clush $clargs -B -g clstr 'test -f /opt/mapr/conf/disktab' && { echo MapR appears to be installed; exit 3; }
   # Multiple disk lists for heterogeneous Storage Pools
   #clush $clargs -B -g clstr "sed -n '1,10p' /tmp/disk.list > /tmp/disk.list1" #Split disk.list for heterogeneous Storage Pools [$spwidth]
   #clush $clargs -B -g clstr "sed -n '11,\$p' /tmp/disk.list > /tmp/disk.list2"
   #clush $clargs -B -g clstr "cat /tmp/disk.list1; wc /tmp/disk.list1" || { echo /tmp/disk.list1 not found; exit 4; }
   #clush $clargs -B -g clstr "cat /tmp/disk.list2; wc /tmp/disk.list2" || { echo /tmp/disk.list2 not found; exit 4; }

   cat <<EOF3
   Assuming that all nodes have been audited with cluster-audit.sh and
   all issues fixed.  Also assuming that all nodes have met subsystem
   performance expectations as measured by memory-test.sh, network-test.sh
   and disk-test.sh.  Scrutinize the disk list above.  All disks will
   be formatted for MapR FS, destroying all existing data on the disks.
   If the disk list contains an OS disk or disk not intended for MapR
   FS, abort this script and edit the disk-test.sh script to filter
   the disk(s) and rerun it.
EOF3
   read -p "Press enter to continue or ctrl-c to abort"
}
chk_disk_list

base_install() {
   # Common rpms for all installation types
   clush $clargs -v -g clstr "${SUDO:-} yum -y install mapr-fileserver mapr-nfs"
   #3 zookeeper nodes
   clush $clargs -v -g zk "${SUDO:-} yum -y install mapr-zookeeper"
   # 3 cldb nodes for ha, 1 does writes, all 3 do reads
   clush $clargs -v -g cldb "${SUDO:-} yum -y install mapr-cldb mapr-webserver"
}
base_install

install_services() {
   # service layout option #1 ====================
   # admin services layered over data nodes defined in rm and cldb groups
   if [ "$mfs" == "false" ]; then
      # at least 2 rm nodes
      clush $clargs -g rm "${SUDO:-} yum -y install mapr-resourcemanager"
      #yarn history server
      clush $clargs -g hist "${SUDO:-} yum -y install mapr-historyserver"
      clush $clargs -v -g clstr "${SUDO:-} yum -y install mapr-nodemanager"
   fi

   # service layout option #2 ====================
   if [ "$admin" == "true" ]; then
      clush $clargs -g rm,cldb "${SUDO:-} yum -y erase mapr-nodemanager"
   fi
}
install_services

install_metrics() {
   clush $clargs -g clstr "${SUDO:-} yum -y install mapr-collectd"
   clush $clargs -g graf "${SUDO:-} yum -y install mapr-grafana"
   clush $clargs -g otsdb "${SUDO:-} yum -y install mapr-opentsdb"
}
[[ "$metrics" == true ]] && install_metrics

install_logmon() {
   clush $clargs -g clstr "${SUDO:-} yum -y install mapr-fluentd"
   clush $clargs -g clstr "${SUDO:-} yum -y install mapr-elasticsearch"
   clush $clargs -g kiba "${SUDO:-} yum -y install mapr-kibana"
}

install_patch

post_install() {
   # Set JAVA_HOME in env.sh after MapR rpms are installed
   sedcmd="'s,^#export JAVA_HOME=,export JAVA_HOME=$JAVA_HOME,'"
   clush $clargs -g clstr "${SUDO:-} sed -i.bk $sedcmd /opt/mapr/conf/env.sh"

   # Create MapR fstab
   fstab='localhost:/mapr /mapr hard,intr,nolock,noatime'
   ddcmd='dd of=/opt/mapr/conf/mapr_fstab status=none'
   echo $fstab |clush $clargs -g clstr "${SUDO:-} $ddcmd"
   clush $clargs -g clstr "${SUDO:-} mkdir -p /mapr"
}
post_install

post_install_keys() {
   #Configure primary CLDB node with security keys, exit if configure.sh fails
   #TBD: Use -K and -P "mapr/clustername" to enable Kerberos $pn
   clush -S $clargs -w $cldb1 "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) -S -genkeys -u $mapruid -g $maprgid -no-autostart"
   [ $? -ne 0 ] && { echo configure.sh failed, check screen and $cldb1:/opt/mapr/logs for errors; exit 2; }

   #pull a copy of the keys
   scp "$cldb1:/opt/mapr/conf/{cldb.key,ssl_truststore,ssl_keystore,maprserverticket}" .
   #Handle key copy with sudo/dd?
   clush -g cldb,zk -x $cldb1 -c cldb.key --dest /opt/mapr/conf/
   clush $clargs -g cldb,zk -x $cldb1 "${SUDO:-} chown $mapruid:$maprgid /opt/mapr/conf/cldb.key"
   clush $clargs -g cldb,zk -x $cldb1 "${SUDO:-} chmod 600 /opt/mapr/conf/cldb.key"

   clush -g clstr -x $cldb1 -c ssl_truststore --dest /opt/mapr/conf/
   clush -g clstr -x $cldb1 -c ssl_keystore --dest /opt/mapr/conf/
   clush -g clstr -x $cldb1 -c maprserverticket --dest /opt/mapr/conf/
   clush $clargs -g clstr -x $cldb1 "${SUDO:-} chown $mapruid:$maprgid /opt/mapr/conf/{ssl_truststore,ssl_keystore,maprserverticket}"
   clush $clargs -g clstr -x $cldb1 "${SUDO:-} chmod 600 /opt/mapr/conf/{ssl_keystore,maprserverticket}"
   clush $clargs -g clstr -x $cldb1 "${SUDO:-} chmod 644 /opt/mapr/conf/ssl_truststore"
}
[[ "$secure" == "true" ]] && post_install_keys

configure_mapr() {
   # Configure cluster
   # v4.1+ uses RM zeroconf, no -RM
   confopts="-N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) "
   confopts+="-HS $(nodeset -I0 -e @hist) -u $mapruid -g $maprgid -no-autostart"
   [[ "$secure" == "true" ]] && confopts+=" -S"
   [[ "$metrics" == "true" ]] && confopts+=" -OT $(nodeset -S, -e @otsdb)"

   clush -S $clargs -g clstr "${SUDO:-} /opt/mapr/server/configure.sh $confopts"
   if [[ $? -ne 0 ]]; then
      echo configure.sh failed, check screen and /opt/mapr/logs for errors
      exit 2
   fi
}
configure_mapr

format_start_mapr() {
   # Set up the disks and start the cluster
   #clush $clargs -g clstr "${SUDO:-} /opt/mapr/server/disksetup -W 5 /tmp/disk.list1
   #clush $clargs -g clstr "${SUDO:-} /opt/mapr/server/disksetup -W 6 /tmp/disk.list2
   disks=/tmp/disk.list
   clush $clargs -g clstr "${SUDO:-} /opt/mapr/server/disksetup -W $spwidth $disks"

   clush $clargs -g zk "${SUDO:-} service mapr-zookeeper start"
   clush $clargs -g clstr "${SUDO:-} service mapr-warden start"

   echo Waiting 2 minutes for system to initialize
   end=$(($SECONDS+120))
   sp='/-\|'
   printf ' '
   while (( $SECONDS < $end )); do
      printf '\b%.1s' "$sp"
      sp=${sp#?}${sp%???}
      sleep .3
   done # Spinner from StackOverflow
}
format_start_mapr

chk_acl_lic() {
   #TBD: Handle mapruid install
   #uid=$(id un)
   #case $uid in
   #   root) ;;
   #   $mapruid) ;;
   #esac

   sshcmd="MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket"
   sshcmd+=" maprcli node cldbmaster"
   ssh -qtt $cldb1 "su - $mapruid -c '$sshcmd'" 
   if [[ $? -ne 0 ]]; then
      echo CLDB did not startup, check status and logs on $cldb1
      exit 3
   fi

   sshcmd="MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket"
   sshcmd+=" maprcli acl edit -type cluster -user $admin1:fc,a"
   ssh -qtt $cldb1 "su - $mapruid -c '$sshcmd'" 

   cat << LICMESG
   With a web browser, connect to one of the webservers to continue
   with license installation:
   Webserver nodes: $(nodeset -S, -e @cldb)

   Alternatively, license can be installed with maprcli like this:
   You can use any browser to connect to mapr.com, in the upper right
   corner there is a login link.  login and register if you have not
   already.  Once logged in, you can use the register button on the
   right of your login page to register a cluster by just entering a
   clusterid.
   You can get the cluster id with maprcli like this:
   maprcli dashboard info -json |grep -e id -e name
                   "name":"ps",
                   "id":"5681466578299529065",

   Once you finish the register form, you will get back a license which
   you can copy and paste to a file on the same node you ran maprcli.
   Use that file as filename in the following maprcli command:
   maprcli license add -is_file true -license filename

LICMESG
}
chk_acl_lic

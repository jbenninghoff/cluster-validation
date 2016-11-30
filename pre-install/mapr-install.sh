#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

: << '--BLOCK-COMMENT--'
MapR Install methods:
1) Manually following http://doc.mapr.com documentation
2) Bash script using clush groups and yum
3) MapR GUI installer
4) Vinces Ansible install playbooks
--BLOCK-COMMENT--

usage() {
cat << EOF
Usage: $0 -s -m -u -x -a -e
-s option for secure cluster installation
-m option for MFS only cluster installation
-a option for cluster with dedicated admin nodes not running nodemanager
-e option for to install on edge node (no fileserver). Can combine with -s or -x
-u option to upgrade existing cluster
-x option to uninstall existing cluster, destroying all data!
EOF
exit 2
}

# Handle script options
secure=false; mfs=false; uninstall=false; upgrade=false; admin=false; edge=false
while getopts "smuxae" opt; do
  case $opt in
    s) secure=true; sopt="-S" ;;
    m) mfs=true ;;
    u) upgrade=true ;;
    x) uninstall=true ;;
    a) admin=true ;;
    e) edge=true ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
  esac
done

# Site specific variables
clname='' #Name for the entire cluster, no spaces
admin1='' #Non-root, non-mapr linux account which has a known password, needed to login to web ui
mapruid=mapr; maprgid=mapr #MapR service account and group
spwidth=4 #Storage Pool width
distro=$(cat /etc/*release | grep -m1 -i -o -e ubuntu -e redhat -e 'red hat' -e centos) || distro=centos
maprver=v5.2.0 #TBD: Grep repo file to confirm or alter
clargs='-S'
export JAVA_HOME=/usr/java/default #Oracle JDK
#export JAVA_HOME=/usr/lib/jvm/java #Openjdk 
#[ $(id -u) -ne 0 ] && SUDO="-o -qtt sudo"  #TBD: Use sudo, assuming account has password-less sudo  (sudo -i)?
[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }
#clush() { /Users/jbenninghoff/bin/clush -l root $@; } #To use this script from edge node as non-root, e.g. Mac

install-patch() { #Find, Download and install mapr-patch v5.1.x
   inrepo=false; clush -S -B -g clstr ${SUDO:-} "yum info mapr-patch" && inrepo=true
   if [ "$inrepo" == "true" ]; then
      clush -v -g clstr ${SUDO:-} "yum -y install mapr-patch"
   else
      patchrpm=$(curl -s http://package.mapr.com/patches/releases/$maprver/redhat/ | sed -n "s/.*\(mapr-patch-${maprver//v}.*.rpm\).*/\1/p")
      if [ $? -ne 0 ]; then
         echo "Patch not found, patchrpm=$patchrpm"
      else
         clush -v -g clstr ${SUDO:-} "yum -y install http://package.mapr.com/patches/releases/$maprver/redhat/$patchrpm"
      fi
   fi
}

# Check cluster for pre-requisites
#clush -S -B -g clstr 'test -f /opt/mapr/conf/disktab' && { echo MapR appears to be installed; exit 3; }
[ $(nodeset -c @clstr) -gt 0 ] || { echo clustershell group: clstr undefined; exit 1; }
[ $(nodeset -c @cldb) -gt 0 ] || { echo clustershell group: cldb undefined; exit 1; }
cldb1=$(nodeset -I0 -e @cldb) #first node in cldb group
[ $(nodeset -c @zk) -gt 0 ] || { echo clustershell group: zk undefined; exit 1; }
[ $(nodeset -c @rm) -gt 0 ] || { echo clustershell group: rm undefined; exit 1; }
[ $(nodeset -c @hist) -gt 0 ] || { echo clustershell group: hist undefined; exit 1; }
[[ -z "${clname// /}" ]] && { echo Cluster name not set.  Set clname in this script; exit 2; }
[[ -z "${admin1// /}" ]] && { echo Admin name not set.  Set admin1 in this script; exit 2; }
[[ -z "${cldb1// /}" ]] && { echo Primary node name not set.  Set or check cldb1 in this script; exit 2; }
clush -S -B -g clstr id $admin1 || { echo $admin1 account does not exist on all nodes; exit 3; }
clush -S -B -g clstr id $mapruid || { echo mapr account does not exist on all nodes; exit 3; }
clush -S -B -g clstr "$JAVA_HOME/bin/java -version |& grep -e x86_64 -e 64-Bit" || { echo $JAVA_HOME/bin/java does not exist on all nodes or is not 64bit; exit 3; }
clush -S -B -g clstr 'echo /tmp permissions; stat -c %a /tmp | grep -q 1777' || { echo Permissions not 1777 on /tmp on all nodes; exit 3; }
clush -S -B -g clstr 'echo Check repo; grep -qi mapr /etc/yum.repos.d/*' || { echo MapR repos not found; exit 3; }
clush -S -B -g clstr 'echo Check for EPEL; grep -qi -m1 epel /etc/yum.repos.d/*' || { echo Warning EPEL repo not found; }
#TBD check for gpgcheck and key(s)
read -p "All checks passed, press enter to continue or ctrl-c to abort"

if [ "$upgrade" == "true" ]; then
   #TBD: grep secure=true /opt/mapr/conf/mapr-clusters.conf && { cp ../post-install/mapr-audit.sh /tmp; sudo -u $mapruid /tmp/mapr-audit.sh; }
   #sudo -u mapr bash -c : && RUNAS="sudo -u mapr"; $RUNAS bash <<EOF
   #source <(sed -n '/^ *cluster_checks1()/,/^ *} *$/p' mapr-audit.sh) #source cluster_checks1 function from mapr-audit.sh
   #cluster_checks1 || { echo Could not load cluster checks function; exit 4; }
   clush -g clstr -b ${SUDO:-} umount /mapr #unmounts all localhost loopback NFS mounts
   clush -g clstr -b ${SUDO:-} nfsstat -m #TBD: stop if other than loopback mounts found
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

   #Backup conf files
   folder_list='conf/ hadoop/hadoop-*/etc/hadoop/ hadoop/hadoop-*/conf drill/drill-*/conf/ hbase/hbase-*/conf zkdata/ spark/spark-*/conf/ sqoop/sqoop-*/conf/ hive/hive-*/conf/ roles/'
   clush -g clstr -b ${SUDO:-} "cd /opt/mapr/ && tar cfz mapr_configs-$(hostname -f)-$(date "+%Y-%m-%dT%H-%M%z").tgz ${folder_list}"
   clush -g clstr -b ${SUDO:-} "ls -l $PWD/mapr_configs*.tgz"

   #Remove mapr-patch
   clush -g clstr -b ${SUDO:-} yum -y erase mapr-patch

   #Update all MapR RPMs on all nodes
   clush -v -g clstr ${SUDO:-} "yum -y update mapr-\*" #Exclude specific rpms with --exclude=mapr-some-somepackage
   read -p "Check console for errors.  If none, press enter to continue or ctrl-c to abort"

   #Download and install mapr-patch
   install-patch

   #Run configure.sh -R to insure configuration is updated
   clush -g clstr -b ${SUDO:-} /opt/mapr/server/configure.sh -R
   #TBD: modify yarn-site.xml and mapred-site.xml and container-executor.cfg when upgrading

   #Start rpcbind, zk and warden
   clush -g clstr -b ${SUDO:-} service rpcbind restart
   clush -g zk -b ${SUDO:-} service mapr-zookeeper start
   sleep 9
   clush -g zk -b ${SUDO:-} service mapr-zookeeper qstatus
   clush -g clstr -b ${SUDO:-} service mapr-warden start
   sleep 90
   #TBD: maprcli must be done by mapr service acct on secure cluster which requires ticket
   sudo -u mapr maprcli config save -values {mapr.targetversion:"`cat /opt/mapr/MapRBuildVersion`"}
   sudo -u mapr maprcli cluster feature enable -all
   exit
fi

if [ "$uninstall" == "true" -a "$edge" == "false" ]; then
   ssh -qtt root@$cldb1 "su - mapr -c 'MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket maprcli dashboard info -json' |awk '/"disk_space":{/,/}/'"
   read -p "All data will be lost, press enter to continue or ctrl-c to abort"
   clush $clargs -g clstr -b ${SUDO:-} umount /mapr
   clush $clargs -g clstr -b ${SUDO:-} service mapr-warden stop
   clush $clargs -g zk -b ${SUDO:-} service mapr-zookeeper stop
   clush $clargs -g clstr -b ${SUDO:-} jps
   clush $clargs -g clstr -b ${SUDO:-} pkill -u $mapruid
   clush $clargs -g clstr -b "${SUDO:-} ps ax | grep $mapruid"
   read -p "If any $mapruid process is still running, press ctrl-c to abort and kill all manually"
   cp /opt/mapr/conf/disktab /var/tmp/
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
   exit
fi

if [ "$edge" == "true" ]; then
   [ $(nodeset -c @edge) -gt 0 ] || { echo clustershell group: edge undefined; exit 1; }
   if [ "$uninstall" == "true" ]; then
      clush $clargs -g edge -b ${SUDO:-} umount /mapr
      clush $clargs -g edge -b ${SUDO:-} service mapr-warden stop
      clush $clargs -g edge -b ${SUDO:-} service mapr-posix-client-basic stop
      clush $clargs -g edge -b ${SUDO:-} jps
      clush $clargs -g edge -b ${SUDO:-} pkill -u $mapruid
      clush $clargs -g edge -b ${SUDO:-} "ps ax | grep $mapruid"
      read -p "If any $mapruid process is still running, press ctrl-c to abort and kill all manually"
      clush $clargs -g edge -b ${SUDO:-} "yum clean all; yum -y erase mapr-\*"
      clush $clargs -g edge -b ${SUDO:-} rm -rf /opt/mapr
      exit
   else
      #clush $clargs -v -g edge "${SUDO:-} yum -y install mapr-client mapr-posix-client-basic"; clnt="-c " #Edge node LBrands
      clush $clargs -v -g edge "${SUDO:-} yum -y install mapr-core mapr-posix-client-basic" #Enables edge node to use warden to run HS2,Metastore,etc
      #clush $clargs -v -g edge "${SUDO:-} yum -y install mapr-client mapr-nfs" #Enables edge node as simple client with loopback NFS to maprfs
      #If mapr-core installed, install-patch?
      if [ "$secure" == "true" ]; then
         scp "root@$cldb1:/opt/mapr/conf/{ssl_truststore,ssl_keystore,maprserverticket}" . #grab a copy of the keys
         clush -g edge -c ssl_truststore --dest /opt/mapr/conf/
         clush -g edge -c ssl_keystore --dest /opt/mapr/conf/
         clush -g edge -c maprserverticket --dest /opt/mapr/conf/
         clush $clargs -g edge "${SUDO:-} chown $mapruid:$maprgid /opt/mapr/conf/{ssl_truststore,ssl_keystore,mapruserticket,maprserverticket}"
         clush $clargs -g edge "${SUDO:-} chmod 600 /opt/mapr/conf/{maprserverticket,mapruserticket}"
         clush $clargs -g edge "${SUDO:-} chmod 644 /opt/mapr/conf/ssl_truststore"
      fi
      clush -S $clargs -g edge "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) -HS $(nodeset -I0 -e @hist) -u $mapruid -g $maprgid ${sopt:-} $clnt" # v4.1+ use RM zeroconf, no -RM option 
      chmod u+s /opt/mapr/bin/fusermount
      echo Edit /opt/mapr/conf/fuse.conf. Append mapr ticket file path 
      service mapr-warden restart
      exit
   fi
fi

clear
clush $clargs -B -g clstr "cat /tmp/disk.list; wc /tmp/disk.list" || { echo /tmp/disk.list not found, run clush disk-test.sh; exit 4; }
clush $clargs -B -g clstr 'test -f /opt/mapr/conf/disktab' && { echo MapR appears to be installed; exit 3; }
# Multiple disk lists for heterogeneous Storage Pools
#clush $clargs -B -g clstr "sed -n '1,10p' /tmp/disk.list > /tmp/disk.list1" #Split disk.list for heterogeneous Storage Pools [$spwidth]
#clush $clargs -B -g clstr "sed -n '11,\$p' /tmp/disk.list > /tmp/disk.list2"
#clush $clargs -B -g clstr "cat /tmp/disk.list1; wc /tmp/disk.list1" || { echo /tmp/disk.list1 not found; exit 4; }
#clush $clargs -B -g clstr "cat /tmp/disk.list2; wc /tmp/disk.list2" || { echo /tmp/disk.list2 not found; exit 4; }

cat - <<EOF
Assuming that all nodes have been audited with cluster-audit.sh and all issues fixed
Assuming that all nodes have met subsystem performance expectations as measured by memory-test.sh, network-test.sh and disk-test.sh
Scrutinize the disk list above.  All disks will be formatted for MapR FS, destroying all existing data on the disks
If the disk list contains an OS disk or disk not intended for MapR FS, edit the disk-test.sh script to filter the output and rerun it
EOF
read -p "Press enter to continue or ctrl-c to abort"

# Common rpms for all installation types
clush $clargs -v -g clstr "${SUDO:-} yum -y install mapr-fileserver mapr-nfs"
clush $clargs -v -g zk "${SUDO:-} yum -y install mapr-zookeeper" #3 zookeeper nodes
clush $clargs -v -g cldb "${SUDO:-} yum -y install mapr-cldb mapr-webserver" # 3 cldb nodes for ha, 1 does writes, all 3 do reads

#Download and install mapr-patch
install-patch

# service layout option #1 ====================
# admin services layered over data nodes defined in rm and cldb groups
if [ "$mfs" == "false" ]; then
   clush $clargs -g rm "${SUDO:-} yum -y install mapr-resourcemanager" # at least 2 rm nodes
   clush $clargs -g hist "${SUDO:-} yum -y install mapr-historyserver" #yarn history server
   clush $clargs -v -g clstr "${SUDO:-} yum -y install mapr-nodemanager"
fi

# service layout option #2 ====================
if [ "$admin" == "true" ]; then
   clush $clargs -g rm,cldb "${SUDO:-} yum -y erase mapr-nodemanager"
fi

# Check for correct java version and set JAVA_HOME after MapR rpms are installed
clush $clargs -g clstr "${SUDO:-} sed -i.bk \"s,^#export JAVA_HOME=,export JAVA_HOME=$JAVA_HOME,\" /opt/mapr/conf/env.sh"
clush $clargs -g clstr "${SUDO:-} echo 'localhost:/mapr /mapr hard,intr,nolock,noatime' > /opt/mapr/conf/mapr_fstab"
clush $clargs -g clstr "${SUDO:-} mkdir /mapr"

if [ "$secure" == "true" ]; then
   # Configure primary CLDB node with security keys
   clush -S $clargs -w $cldb1 "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) -S -genkeys -u $mapruid -g $maprgid -no-autostart"
   [ $? -ne 0 ] && { echo configure.sh failed, check screen and $cldb1:/opt/mapr/logs for errors; exit 2; }
   #read -p "Press enter to continue or ctrl-c to abort"
   scp "root@$cldb1:/opt/mapr/conf/{cldb.key,ssl_truststore,ssl_keystore,maprserverticket}" . #grab a copy of the keys
   #echo Needs testing
   clush -g cldb -x $cldb1 -c cldb.key --dest /opt/mapr/conf/
   clush $clargs -g cldb -x $cldb1 "${SUDO:-} chown $mapruid:$maprgid /opt/mapr/conf/cldb.key"
   clush $clargs -g cldb -x $cldb1 "${SUDO:-} chmod 600 /opt/mapr/conf/cldb.key"
   clush -g clstr -x $cldb1 -c ssl_truststore --dest /opt/mapr/conf/
   clush -g clstr -x $cldb1 -c ssl_keystore --dest /opt/mapr/conf/
   clush -g clstr -x $cldb1 -c maprserverticket --dest /opt/mapr/conf/
   clush $clargs -g clstr -x $cldb1 "${SUDO:-} chown $mapruid:$maprgid /opt/mapr/conf/{ssl_truststore,ssl_keystore,maprserverticket}"
   clush $clargs -g clstr -x $cldb1 "${SUDO:-} chmod 600 /opt/mapr/conf/{ssl_keystore,maprserverticket}"
   clush $clargs -g clstr -x $cldb1 "${SUDO:-} chmod 644 /opt/mapr/conf/ssl_truststore"
fi

# Configure cluster
if [ "$mfs" == "true" ]; then
   clush -S $clargs -g clstr "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) -u $mapruid -g $maprgid -no-autostart"
elif [ "$secure" == "true" ]; then
   clush -S $clargs -g clstr "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) -HS $(nodeset -I0 -e @hist) -u $mapruid -g $maprgid -no-autostart -S"
else
   clush -S $clargs -g clstr "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) -HS $(nodeset -I0 -e @hist) -u $mapruid -g $maprgid -no-autostart"
   #clush -S $clargs -g clstr "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) -RM $(nodeset -S, -e @rm) -HS $(nodeset -I0 -e @hist) -u $mapruid -g $maprgid -no-autostart" #v4.1+ use RM zeroconf, no -RM
fi
[ $? -ne 0 ] && { echo configure.sh failed, check screen and /opt/mapr/logs for errors; exit 2; }

# Set up the disks and start the cluster
#clush $clargs -g clstr "${SUDO:-} /opt/mapr/server/disksetup -F -W 5 /tmp/disk.list1 #file path must be last arg
#clush $clargs -g clstr "${SUDO:-} /opt/mapr/server/disksetup -F -W 6 /tmp/disk.list2
clush $clargs -g clstr "${SUDO:-} /opt/mapr/server/disksetup -F -W ${spwidth:-3}" /tmp/disk.list 
clush $clargs -g zk "${SUDO:-} service mapr-zookeeper start"
clush $clargs -g clstr "${SUDO:-} service mapr-warden start"

echo Waiting 2 minutes for system to initialize; end=$((SECONDS+120))
sp='/-\|'; printf ' '; while [ $SECONDS -lt $end ]; do printf '\b%.1s' "$sp"; sp=${sp#?}${sp%???}; sleep .3; done # Spinner from StackOverflow

echo 'maprlogin required on secure cluster to add cluster user'
ssh -qtt root@$cldb1 "su - mapr -c 'MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket maprcli node cldbmaster'" && ssh -qtt root@$cldb1 "su - mapr -c 'MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket maprcli acl edit -type cluster -user $admin1:fc,a'"
[ $? -ne 0 ] && { echo CLDB did not startup, check status and logs on $cldb1; exit 3; }

echo With a web browser, connect to one of the webservers to continue with license installation:
echo Webserver nodes: $(nodeset -S, -e @cldb)
echo
echo Alternatively, license can be installed with maprcli like this:
cat - << 'EOF2'
You can use any browser to connect to mapr.com, in the upper right corner there is a login link.  login and register if you have not already.
Once logged in, you can use the register button on the right of your login page to register a cluster by just entering a clusterid.
You can get the cluster id with maprcli like this:
maprcli dashboard info -json -cluster TestCluster |grep id
                                "id":"4878526810219217706"
Once you finish the register form, you will get back a license which you can copy and paste to a file on the same node you ran maprcli (corpmapr-r02 I believe).
Use that file as filename in the following maprcli command:
maprcli license add -is_file true -license filename
EOF2

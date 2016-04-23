#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

: << '--BLOCK-COMMENT--'
MapR Install options:
1) Manually following http://doc.mapr.com documentation
2) Bash script using clush groups and yum
3) MapR GUI installer
4) Vinces Ansible install playbooks
--BLOCK-COMMENT--

usage() {
  echo "Usage: $0 -s -m -u -a"
  echo "-s option for secure cluster installation"
  echo "-m option for MFS only cluster installation"
  echo "-a option for cluster with dedicated admin nodes installation"
  echo "-u option to uninstall existing cluster, destroying all data!"
  exit 2
}

# Handle script options
secure=false; mfs=false; uninstall=false; admin=false
while getopts ":smua:" opt; do
  case $opt in
    s) secure=true ;;
    m) mfs=true ;;
    u) uninstall=true ;;
    a) admin=true ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
  esac
done

# Site specific variables
clname='jbsec' #Name for the entire cluster, no spaces
admin1='jbenninghoff' #Non-root, non-mapr linux account which has a known password, needed to login to web ui
mapruid=mapr; maprgid=mapr #MapR service account and group
spwidth=4 #Storage Pool width
clargs='-o -qtt' #clush args needed by sudo
[ $(id -u) -ne 0 ] && SUDO=sudo  #Use sudo, assuming account has password-less sudo  (sudo -i)?
export JAVA_HOME=/usr/java/default #Oracle JDK
#export JAVA_HOME=/usr/lib/jvm/java #Openjdk 
distro=$(cat /etc/*release | grep -m1 -i -o -e ubuntu -e redhat -e 'red hat' -e centos) || distro=centos
maprver=5.1 #TBD: Grep repo file to confirm or alter

# Check cluster for pre-requisites
#clush -S -B -g clstr 'test -f /opt/mapr/conf/disktab' && { echo MapR appears to be installed; exit 3; }
grep ^clstr /etc/clustershell/groups || { echo clustershell group: clstr undefined; exit 1; }
grep ^cldb /etc/clustershell/groups || { echo clustershell group: cldb undefined; exit 1; }
cldb1=$(nodeset -I0 -e @cldb) #first node in cldb group
grep ^zk /etc/clustershell/groups || { echo clustershell group: zk undefined; exit 1; }
grep ^rm /etc/clustershell/groups || { echo clustershell group: rm undefined; exit 1; }
grep ^hist /etc/clustershell/groups || { echo clustershell group: hist undefined; exit 1; }
[[ -z "${clname// /}" ]] && { echo Cluster name not set.  Set clname in this script; exit 2; }
[[ -z "${cldb1// /}" ]] && { echo Primary node name not set.  Set or check cldb1 in this script; exit 2; }
clush -S -B -g clstr id $admin1 || { echo $admin1 account does not exist on all nodes; exit 3; }
clush -S -B -g clstr id $mapruid || { echo mapr account does not exist on all nodes; exit 3; }
clush -S -B -g clstr "$JAVA_HOME/bin/java -version |& grep -e x86_64 -e 64-Bit" || { echo $JAVA_HOME/bin/java does not exist on all nodes or is not 64bit; exit 3; }
clush -S -B -g clstr stat -c %a /tmp | grep -q 1777 || { echo Permissions not 1777 on /tmp on all nodes; exit 3; }
clush -S -B -g clstr 'grep -i mapr /etc/yum.repos.d/*' || { echo MapR repos not found; exit 3; }
clush -S -B -g clstr 'grep -i -m1 epel /etc/yum.repos.d/*' || { echo Warning EPEL repo not found; }
clush $clargs -B -g clstr "cat /tmp/disk.list; wc /tmp/disk.list" || { echo /tmp/disk.list not found, run clush disk-test.sh; exit 4; }
#clush $clargs -B -g clstr "sed -n '1,10p' /tmp/disk.list > /tmp/disk.list1" #Split disk.list for heterogeneous Storage Pools [$spwidth]
#clush $clargs -B -g clstr "sed -n '11,\$p' /tmp/disk.list > /tmp/disk.list2"
#clush $clargs -B -g clstr "cat /tmp/disk.list1; wc /tmp/disk.list1" || { echo /tmp/disk.list1 not found; exit 4; }
#clush $clargs -B -g clstr "cat /tmp/disk.list2; wc /tmp/disk.list2" || { echo /tmp/disk.list2 not found; exit 4; }

clear
cat - <<EOF
Assuming that all nodes have been audited with cluster-audit.sh and all issues fixed
Assuming that all nodes have met subsystem performance expectations as measured by memory-test.sh, network-test.sh and disk-test.sh
Scrutinize the disk list above.  All disks will be formatted for MapR FS, destroying all existing data on the disks
If the disk list contains an OS disk or disk not intended for MapR FS, edit the disk-test.sh script to filter the output and rerun it
EOF
read -p "Press enter to continue or ctrl-c to abort"

if [ "$uninstall" == "true" ]; then
   read -p "All data will be lost, press enter to continue or ctrl-c to abort"
   clush $clargs -a -b ${SUDO:-} umount /mapr
   clush $clargs -a -b ${SUDO:-} service mapr-warden stop
   clush $clargs -g zk -b ${SUDO:-} service mapr-zookeeper stop
   clush $clargs -a -b ${SUDO:-} jps
   clush $clargs -a -b ${SUDO:-} pkill -u $mapruid
   clush $clargs -a -b "${SUDO:-} ps ax | grep $mapruid"
   read -p "If any $mapruid process still running, press ctrl-c to abort and kill all manually"
   case $distro in
      redhat|centos|red*)
         clush $clargs -a -b "${SUDO:-} yum -y erase mapr-\*" ;;
      ubuntu)
         clush -a -B 'dpkg -P mapr-\*' ;;
      *) echo Unknown Linux distro! $distro; exit ;;
   esac
   clush $clargs -a -b ${SUDO:-} rm -rf /opt/mapr
   exit
fi

# Common rpms for all installation types
clush $clargs -v -g clstr "${SUDO:-} yum -y install mapr-fileserver mapr-nfs"
clush $clargs -v -g zk "${SUDO:-} yum -y install mapr-zookeeper" #3 zookeeper nodes
clush $clargs -v -g cldb "${SUDO:-} yum -y install mapr-cldb mapr-webserver" # 3 cldb nodes for ha, 1 does writes, all 3 do reads

# service layout option #1 ====================
# admin services layered over data nodes defined in rm and cldb groups
if [ "$mfs" == "false" ]; then
   clush $clargs -g rm "${SUDO:-} yum -y install mapr-resourcemanager" # at least 2 rm nodes
   clush $clargs -g hist "${SUDO:-} yum -y install mapr-historyserver mapr-webserver" #yarn history server
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
   read -p "Press enter to continue or ctrl-c to abort"
   scp "$cldb1:/opt/mapr/conf/{cldb.key,ssl_truststore,ssl_keystore,maprserverticket}" . #grab a copy of the keys
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
   clush -S $clargs -g clstr "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) -RM $(nodeset -S, -e @rm) -HS $(nodeset -I0 -e @hist) -u $mapruid -g $maprgid -no-autostart -S"
else
   clush -S $clargs -g clstr "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zk) -C $(nodeset -S, -e @cldb) -RM $(nodeset -S, -e @rm) -HS $(nodeset -I0 -e @hist) -u $mapruid -g $maprgid -no-autostart" #TBD: v4.1+ use RM zeroconf
fi
[ $? -ne 0 ] && { echo configure.sh failed, check screen and /opt/mapr/logs for errors; exit 2; }

# Set up the disks and start the cluster
#clush $clargs -g clstr "${SUDO:-} /opt/mapr/server/disksetup -F /tmp/disk.list1 -W 4
#clush $clargs -g clstr "${SUDO:-} /opt/mapr/server/disksetup -F /tmp/disk.list2 -W 5
clush $clargs -g clstr "${SUDO:-} /opt/mapr/server/disksetup -F /tmp/disk.list -W ${spwidth:-3}"
clush $clargs -g zk "${SUDO:-} service mapr-zookeeper start"
clush $clargs -g clstr "${SUDO:-} service mapr-warden start"

echo Waiting 2 minutes for system to initialize; end=$((SECONDS+120))
sp='/-\|'; printf ' '; while [ $SECONDS -lt $end ]; do printf '\b%.1s' "$sp"; sp=${sp#?}${sp%???}; sleep .3; done # Spinner from StackOverflow

echo 'maprlogin required on secure cluster to add cluster user'
ssh -qtt $cldb1 "${SUDO:-} maprcli node cldbmaster" && ssh $cldb1 "${SUDO:-} maprcli acl edit -type cluster -user $admin1:fc,a"
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
#!/bin/bash
# jbenninghoff 2013-Sep-25  vi: set ai et sw=3 tabstop=3:

#cat - << 'EOF'
# Assumes clush is installed, available from EPEL repository
# Examine the ps and jps output to insure all MapR Hadoop processes are no longer running
# Edit this script to enable a complete uninstall.  THIS WILL BE DESTRUCTIVE OF ALL DATA!
# After that, comment out the exit command below to execute the full script
#EOF

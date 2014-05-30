#!/bin/bash
# jbenninghoff@maprtech.com 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

cat - << 'EOF'
# Assumes clush is installed, available from EPEL repository
# Assumes all nodes have been audited with cluster-audit.sh and all issues fixed
# Assumes all nodes have met subsystem performance expectations as measured by memory-test.sh, network-test.sh and disk-test.sh
# Assumes MapR yum repo or repo mirror has been configured for all nodes and that MapR will run as mapr user
# Assumes jt, zkcldb and all group have been defined for clush in /etc/clustershell/groups
EOF

[ $(id -u) -ne 0 ] && SUDO=sudo
admin1=xxx #Set to a non-root, non-mapr linux account which has a known password, this will be used to login to webgui
node1=$(nodeset -I0 -e @zkcldb) #first node in zkcldb group
clargs='-B -o -qtt'
clname=TestCluster

# Identify and format the data disks for MapR, destroys all data on all disks listed in /tmp/disk.list on all nodes
clush $clargs -a "${SUDO:-} lsblk -id | grep -o ^sd. | grep -v ^sda |sort|sed 's,^,/dev/,' | tee /tmp/disk.list; wc /tmp/disk.list"
echo Scrutinize the disk list above.  All disks will be formatted for MapR FS, destroying all existing data on the disks
echo Once the disk list is approved, edit this script and remove or comment the exit statement below
exit

# Install all servers with minimal rpms to provide storage and compute plus NFS
clush $clargs -a "${SUDO:-} yum -y install mapr-fileserver mapr-nfs mapr-tasktracker"

# Service Layout option #1 ====================
# Admin services layered over data nodes defined in jt and zkcldb groups
clush $clargs -g jt "${SUDO:-} yum -y install mapr-jobtracker mapr-webserver mapr-metrics" # At least 2 JobTracker nodes
clush $clargs -g zkcldb "${SUDO:-} yum -y install mapr-cldb" # 3 CLDB nodes for HA, 1 does writes, all 3 do reads
clush $clargs -g zkcldb "${SUDO:-} yum -y install mapr-zookeeper" #3 Zookeeper nodes, fileserver, tt and nfs could be erased
ssh -qtt $node1 "${SUDO:-} yum -y install mapr-webserver"  # Install webserver to bootstrap cluster install

# Service Layout option #2 ====================
# Admin services on dedicated nodes, uncomment the line below
#clush $clargs -g jt,zkcldb "${SUDO:-} yum -y erase mapr-tasktracker"

# Check for correct java version and set JAVA_HOME
clush $clargs -a "${SUDO:-} sed -i 's,^#export JAVA_HOME=,export JAVA_HOME=/usr/java/jdk1.7.0_51,' /opt/mapr/conf/env.sh"

# Configure ALL nodes with the CLDB and Zookeeper info (-N does not like spaces in the name)
clush $clargs -a "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zkcldb) -C $(nodeset -S, -e @zkcldb) -u mapr -g mapr"
[ $? -ne 0 ] && { echo configure.sh failed, check screen for errors; exit 2; }

# Identify and format the data disks for MapR
clush $clargs -a "${SUDO:-} /opt/mapr/server/disksetup -F /tmp/disk.list"
#clush $clargs -a "${SUDO:-} /opt/mapr/server/disksetup -W $(cat /tmp/disk.list | wc -l) -F /tmp/disk.list" #Fast but less resilient storage

clush $clargs -g zkcldb "${SUDO:-} service mapr-zookeeper start"; sleep 10
ssh -qtt $node1 "${SUDO:-} service mapr-warden start"  # Start 1 CLDB and webserver on first node
echo Wait at least 90 seconds for system to initialize; sleep 90

ssh -qtt $node1 "${SUDO:-} maprcli node cldbmaster" && ssh $node1 "${SUDO:-} maprcli acl edit -type cluster -user $admin1:fc"
[ $? -ne 0 ] && { echo CLDB did not startup, check status and logs on $node1; exit 3; }

echo With a web browser, open this URL to continue with license installation:
echo "https://$node1:8443/"
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
echo
echo Start mapr-warden on all remaining servers once the license is applied
echo clush $clargs -a "${SUDO:-} service mapr-warden start"

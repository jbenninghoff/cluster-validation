#!/bin/bash
# jbenninghoff@maprtech.com 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

grep ^all /etc/clustershell/groups || { echo clustershell group: all undefined; exit 1; }
grep ^jt /etc/clustershell/groups || { echo clustershell group: jt undefined; exit 1; }
grep ^zkcldb /etc/clustershell/groups || { echo clustershell group: zkcldb undefined; exit 1; }

tmpfile=$(mktemp); trap 'rm $tmpfile' 0 1 2 3 15
clname=pslab1
admin1=jbenninghoff #Set to a non-root, non-mapr linux account which has a known password, this will be used to login to web ui
node1=$(nodeset -I0 -e @zkcldb) #first node in zkcldb group
clargs='-o -qtt'
[ $(id -u) -ne 0 ] && SUDO=sudo  #Use sudo, assuming account has passwordless sudo

cat - << 'EOF'
# Assumes clush is installed, available from EPEL repository
# Assumes all nodes have been audited with cluster-audit.sh and all issues fixed
# Assumes all nodes have met subsystem performance expectations as measured by memory-test.sh, network-test.sh and disk-test.sh
# Assumes that MapR will run as mapr user
# Assumes jt, zkcldb and all group have been defined for clush in /etc/clustershell/groups
EOF
exit #modify this script to match your set of nodes, then remove or comment out the exit command

#Create 3.x repos on all nodes #TBD does not work with sudo
#cat - << 'EOF2' | clush -a "cat - > /etc/yum.repos.d/maprtech.repo"
cat - << 'EOF2' > $tmpfile
[maprtech]
name=MapR Technologies
baseurl=http://package.mapr.com/releases/v3.1.1/redhat/
enabled=1
gpgcheck=0
protect=1
 
[maprecosystem]
name=MapR Technologies
baseurl=http://package.mapr.com/releases/ecosystem/redhat/
enabled=1
gpgcheck=0
protect=1
EOF2

clush -abc $tmpfile --dest /tmp/${tmpfile##*/}
clush $clargs -a "${SUDO:-} mv /tmp/${tmpfile##*/} /etc/yum.repos.d/maprtech.repo"
clush $clargs -a "${SUDO:-} yum clean all"

# Identify and format the data disks for MapR, destroys all data on all disks listed in /tmp/disk.list on all nodes
clush -B $clargs -a "${SUDO:-} lsblk -id | grep -o ^sd. | grep -v ^sda |sort|sed 's,^,/dev/,' | tee /tmp/disk.list; wc /tmp/disk.list"
echo Scrutinize the disk list above.  All disks will be formatted for MapR FS, destroying all existing data on the disks
echo Once the disk list is approved, edit this script and remove or comment the exit statement below
read -p "Press enter to continue or ctrl-c to abort"

# Install all servers with minimal rpms to provide storage and compute plus NFS
clush $clargs -a "${SUDO:-} yum -y install mapr-fileserver mapr-nfs mapr-tasktracker"
#read -p "Press enter to continue or ctrl-c to abort"

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
clush $clargs -a "${SUDO:-} sed -i.bak 's,^#export JAVA_HOME=,export JAVA_HOME=/usr/lib/jvm/java-1.7.0-openjdk.x86_64,' /opt/mapr/conf/env.sh"

# Configure ALL nodes with the CLDB and Zookeeper info (-N does not like spaces in the name)
#clush $clargs -a "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zkcldb) -C $(nodeset -S, -e @zkcldb) -u mapr -g mapr -no-autostart"
#[ $? -ne 0 ] && { echo configure.sh failed, check screen for errors; exit 2; }

# Identify and format the data disks for MapR
#clush $clargs -a "${SUDO:-} /opt/mapr/server/disksetup -F /tmp/disk.list"
#clush $clargs -a "${SUDO:-} /opt/mapr/server/disksetup -W $(cat /tmp/disk.list | wc -l) -F /tmp/disk.list" #Fast but less resilient storage

#clush $clargs -g zkcldb "${SUDO:-} service mapr-zookeeper start"; sleep 10
#ssh -qtt $node1 "${SUDO:-} service mapr-warden start"  # Start 1 CLDB and webserver on first node

clush $clargs -a "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zkcldb) -C $(nodeset -S, -e @zkcldb) -u mapr -g mapr -F /tmp/disk.list"
[ $? -ne 0 ] && { echo configure.sh failed, check screen for errors; exit 2; }
echo Wait at least 120 seconds for system to initialize; sleep 120

ssh -qtt $node1 "${SUDO:-} maprcli node cldbmaster" && ssh $node1 "${SUDO:-} maprcli acl edit -type cluster -user $admin1:fc"
[ $? -ne 0 ] && { echo CLDB did not startup, check status and logs on $node1; exit 3; }

echo With a web browser, open this URL to continue with license installation:
echo "https://$node1:8443/"
echo
echo Alternatively, license can be installed with maprcli like this:
cat - << 'EOF3'
You can use any browser to connect to mapr.com, in the upper right corner there is a login link.  login and register if you have not already.
Once logged in, you can use the register button on the right of your login page to register a cluster by just entering a clusterid.
You can get the cluster id with maprcli like this:
maprcli dashboard info -json -cluster TestCluster |grep id
                                "id":"4878526810219217706"
Once you finish the register form, you will get back a license which you can copy and paste to a file on the same node you ran maprcli (corpmapr-r02 I believe).
Use that file as filename in the following maprcli command:
maprcli license add -is_file true -license filename
EOF3
echo
echo Restart mapr-warden on all servers once the license is applied
echo clush $clargs -a "${SUDO:-} service mapr-warden start"

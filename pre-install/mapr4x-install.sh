#!/bin/bash
# jbenninghoff@maprtech.com 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

grep ^all /etc/clustershell/groups || { echo clustershell group: all undefined; exit 1; }
grep ^rm /etc/clustershell/groups || { echo clustershell group: rm undefined; exit 1; }
grep ^hist /etc/clustershell/groups || { echo clustershell group: rm undefined; exit 1; }
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
# Assumes MapR yum repo or repo mirror has been configured for all nodes and that MapR will run as mapr user
# e.g. clush -abc /etc/yum.repos.d/maprtech.repo
# Assumes rm, zkcldb, rm, hist and all group have been defined for clush in /etc/clustershell/groups
EOF
exit #modify this script to match your set of nodes, then remove or comment out the exit command

#Create 4.x repos on all nodes
cat - <<EOF2 | clush -ab 'cat - > /etc/yum.repos.d/maprtech.repo'
[maprtech]
name=MapR Technologies
baseurl=http://package.mapr.com/releases/v4.0.1/redhat/
enabled=1
gpgcheck=0
protect=1
 
[maprecosystem]
name=MapR Technologies
baseurl=http://package.mapr.com/releases/ecosystem-4.x/redhat/
enabled=1
gpgcheck=0
protect=1
EOF2

# Identify and format the data disks for MapR, destroys all data on all disks listed in /tmp/disk.list on all nodes
clush $clargs -a "${SUDO:-} lsblk -id | grep -o ^sd. | grep -v ^sda |sort|sed 's,^,/dev/,' | tee /tmp/disk.list; wc /tmp/disk.list"
echo Scrutinize the disk list above.  All disks will be formatted for MapR FS, destroying all existing data on the disks
echo Once the disk list is acceptable, edit this script and remove or comment the exit statement below
exit

clush $clargs -a 'rpm --import http://package.mapr.com/releases/pub/maprgpg.key'
# Install all servers with minimal rpms to provide storage and compute plus NFS
clush $clargs -v -a "${SUDO:-} yum -y install mapr-fileserver mapr-nfs mapr-tasktracker mapr-nodemanager"

# Service Layout option #1 ====================
# Admin services layered over data nodes defined in rm and zkcldb groups
clush $clargs -g rm "${SUDO:-} yum -y install mapr-webserver mapr-metrics mapr-resourcemanager" # At least 2 JobTracker nodes
clush $clargs -g zkcldb "${SUDO:-} yum -y install mapr-cldb" # 3 CLDB nodes for HA, 1 does writes, all 3 do reads
clush $clargs -g zkcldb "${SUDO:-} yum -y install mapr-zookeeper" #3 Zookeeper nodes, fileserver, tt and nfs could be erased
clush $clargs -g hist "${SUDO:-} yum -y install mapr-historyserver" #YARN history server

# Service Layout option #2 ====================
# Admin services on dedicated nodes, uncomment the line below
#clush $clargs -g rm,zkcldb "${SUDO:-} yum -y erase mapr-tasktracker mapr-nodemanager"

# Check for correct java version and set JAVA_HOME
clush $clargs -a "${SUDO:-} sed -i 's,^#export JAVA_HOME=,export JAVA_HOME=/usr/lib/jvm/java-1.7.0-openjdk-1.7.0.55.x86_64,' /opt/mapr/conf/env.sh"

# Configure ALL nodes with the CLDB and Zookeeper info (-N does not like spaces in the name)
clush $clargs -a "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @zkcldb) -C $(nodeset -S, -e @zkcldb) -RM $(nodeset -S, -e @rm) -HS $(nodeset -e @hist) -F /tmp/disk.list -u mapr -g mapr"
[ $? -ne 0 ] && { echo configure.sh failed, check screen for errors; exit 2; }
echo Wait at least 2 minutes for system to initialize; sleep 120

ssh -qtt $node1 "${SUDO:-} maprcli node cldbmaster" && ssh $node1 "${SUDO:-} maprcli acl edit -type cluster -user $admin1:fc"
[ $? -ne 0 ] && { echo CLDB did not startup, check status and logs on $node1; exit 3; }

echo With a web browser, connect to one of the webservers to continue with license installation:
echo Webserver nodes: $(nodeset -S, -e @rm)
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

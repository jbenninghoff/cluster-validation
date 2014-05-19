#!/bin/bash
# jbenninghoff@maprtech.com 2014-Feb-09  vi: set ai et sw=3 tabstop=3:
# Custom install script for MapR Hadoop cluster using passwordless sudo

# Assumes clush is installed, available from EPEL repository
# Assumes all nodes have been audited with cluster-audit.sh and all issues fixed
# Assumes all nodes have met subsystem performance expectations as measured by memory-test.sh, network-test.sh and disk-test.sh
# Assumes MapR yum repo or repo mirror has been configured for all nodes and that MapR will run as mapr user
# Assumes jt, zkcldb and all group have been defined for clush
# Assumes /tmp/disk.list exists on all fileserver nodes and the list has been carefully scrutinized

# Identify and format the data disks for MapR, destroys all data on disks in /tmp/disk.list on all nodes
clush -Ba "lsblk -id | grep -o ^sd. | grep -v ^sda |sort|sed 's,^,/dev/,' | tee /tmp/disk.list; wc /tmp/disk.list"
exit; # Delete this line once disk.list has been scrutinized thoroughly!!

# Install all servers with minimal rpms to provide storage and compute plus NFS
clush -Ba -o -qtt 'sudo yum -y install mapr-fileserver mapr-nfs mapr-tasktracker'

# Admin services layered over specific data nodes, defined in clush groups; zkcldb and jt.
clush -Bg jt -o -qtt 'sudo yum -y install mapr-jobtracker mapr-webserver mapr-metrics mysql' # At least 2 JobTracker nodes
clush -Bg zkcldb -o -qtt 'sudo yum -y install mapr-zookeeper mapr-cldb' # 3 CLDB nodes for HA, 1 does writes, all 3 do reads, zookeeper is very lightweight process
node1=$(nodeset -I0 -e @zkcldb) #first node in zkcldb group
ssh -qtt $node1 sudo yum -y install mapr-webserver #add webserver to 1st CLDB node for cluster bootstrap

# Configure ALL nodes with CLDB and Zookeeper info (-N does not like spaces in the name)
clush -Ba -o -qtt "sudo /opt/mapr/server/configure.sh -N TestCluster -Z $(nodeset -S, -e @zkcldb) -C $(nodeset -S, -e @zkcldb) -u mapr -g mapr"
clush -Ba -o -qtt 'sudo /opt/mapr/server/disksetup -F /tmp/disk.list'
#clush -Ba -o -qtt "sudo /opt/mapr/server/disksetup -W $(cat /tmp/disk.list | wc -l) -F /tmp/disk.list" #Faster but less resilient storage

# Check for correct java version and set JAVA_HOME
#clush -ab -o -qtt 'sudo sed -e "s/^#export JAVA_HOME=/export JAVA_HOME=\/usr\/java\/jdk1.7.0_51/g" /opt/mapr/conf/env.sh | sudo tee /opt/mapr/conf/env.sh'

clush -Bg zkcldb -o -qtt 'sudo service mapr-zookeeper start; sleep 10'
ssh -t $node1 sudo service mapr-warden start  # Start 1 CLDB and webserver

echo Wait at least 90 seconds for system to initialize; sleep 90
ssh -t $node1 sudo maprcli acl edit -type cluster -user xxx:fc

echo With a web browser, open this URL to continue with license installation:
echo "https://$node1:8443/"

#echo
#echo Start mapr-warden on all remaining servers once the license is applied
#echo With a command like this: clush -Ba -o -qtt 'sudo service mapr-warden start'

#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

clname='' #Set to a name for the entire cluster, no spaces
admin1='' #Set to a non-root, non-mapr linux account which has a known password, this will be used to login to web ui
mapruid=mapr; maprgid=mapr
spwidth=4
node1=$(nodeset -I0 -e @dzk) #first node in dzk group
export JAVA_HOME=/usr/java/default #Oracle JDK
#export JAVA_HOME=/usr/lib/jvm/java #Openjdk 
clargs='-o -qtt'
[ $(id -u) -ne 0 ] && SUDO=sudo  #Use sudo, assuming account has passwordless sudo  (sudo -i)?

grep ^dev /etc/clustershell/groups || { echo clustershell group: dev undefined; exit 1; }
grep ^dcldb /etc/clustershell/groups || { echo clustershell group: dcldb undefined; exit 1; }
grep ^dzk /etc/clustershell/groups || { echo clustershell group: dzk undefined; exit 1; }
grep ^drm /etc/clustershell/groups || { echo clustershell group: drm undefined; exit 1; }
grep ^dhist /etc/clustershell/groups || { echo clustershell group: rm undefined; exit 1; }
[[ -z "${clname// /}" ]] && { echo Cluster name not set.  Set clname in this script; exit 2; }
[[ -z "${node1// /}" ]] && { echo Primary node name not set.  Set or check node1 in this script; exit 2; }
clush -S -B -g dev id $admin1 || { echo $admin1 account does not exist on all nodes; exit 3; }
clush -S -B -g dev id mapr || { echo mapr account does not exist on all nodes; exit 3; }
clush -S -B -g dev "$JAVA_HOME/bin/java -version |& grep -e x86_64 -e 64-Bit" || { echo $JAVA_HOME/bin/java does not exist on all nodes or is not 64bit; exit 3; }
clush -S -B -g dev 'grep -i mapr /etc/yum.repos.d/*' || { echo MapR repos not found; exit 3; }
clush -S -B -g dev 'grep -i -m1 epel /etc/yum.repos.d/*' || { echo Warning EPEL repo not found; }

# Identify and format the data disks for MapR, destroys all data on all disks listed in /tmp/disk.list on all nodes
#echo;clush $clargs -B -g dev "${SUDO:-} lsblk -id | grep -o ^sd. | grep -v ^sda |sort|sed 's,^,/dev/,' | tee /tmp/disk.list; wc /tmp/disk.list"; echo
echo
# Use /tmp/disk.list created by disk-test.sh
clush $clargs -B -g dev "cat /tmp/disk.list; wc /tmp/disk.list" || { echo /tmp/disk.list not found; exit 4; }
echo

cat - <<EOF
Assuming that all nodes have been audited with cluster-audit.sh and all issues fixed
Assuming that all nodes have met subsystem performance expectations as measured by memory-test.sh, network-test.sh and disk-test.sh
Scrutinize the disk list above.  All disks will be formatted for MapR FS, destroying all existing data on the disks
If the disk list contains an OS disk or disk not intended for MapR FS, edit the disk-test.sh script to filter the output and rerun it
EOF
read -p "Press enter to continue or ctrl-c to abort"

# Install all servers with minimal rpms to provide storage, compute and NFS
clush $clargs -v -g dev "${SUDO:-} yum -y install mapr-fileserver mapr-nodemanager mapr-nfs"

# Service Layout option #1 ====================
# Admin services layered over data nodes defined in drm and dcldb groups
clush $clargs -g dzk "${SUDO:-} yum -y install mapr-zookeeper" #3 Zookeeper nodes, fileserver, tt and nfs could be erased
clush $clargs -g dcldb "${SUDO:-} yum -y install mapr-cldb" # 3 CLDB nodes for HA, 1 does writes, all 3 do reads
clush $clargs -g drm "${SUDO:-} yum -y install mapr-resourcemanager" # At least 2 RM nodes
clush $clargs -g dhist "${SUDO:-} yum -y install mapr-webserver mapr-historyserver" #YARN history server
#clush $clargs -g drm "${SUDO:-} yum -y install mapr-webserver mapr-metrics mapr-resourcemanager" # At least 2 RM nodes

# Service Layout option #2 ====================
# Admin services on dedicated nodes, uncomment the line below
#clush $clargs -g drm,dcldb "${SUDO:-} yum -y erase mapr-nodemanager"

# Check for correct java version and set JAVA_HOME
# clush $clargs -g dev "${SUDO:-} sed -i 's,^#export JAVA_HOME=,export JAVA_HOME=/usr/lib/jvm/java-1.7.0-openjdk-1.7.0.55.x86_64,' /opt/mapr/conf/env.sh"
clush $clargs -g dev "${SUDO:-} sed -i \"s,^#export JAVA_HOME=,export JAVA_HOME=$JAVA_HOME,\" /opt/mapr/conf/env.sh"

# Configure ALL nodes with the CLDB and Zookeeper info (-N does not like spaces in the name)
clush $clargs -g dev "${SUDO:-} /opt/mapr/server/configure.sh -N $clname -Z $(nodeset -S, -e @dzk) -C $(nodeset -S, -e @dcldb) -RM $(nodeset -S, -e @drm) -HS $(nodeset -e @dhist) -u mapr -g mapr -F /tmp/disk.list -disk-opts FW${spwidth:-3}"
[ $? -ne 0 ] && { echo configure.sh failed, check screen and /opt/mapr/logs for errors; exit 2; }
#echo Waiting 2 minutes for system to initialize; sleep 120
echo Waiting 2 minutes for system to initialize; end=$((SECONDS+120))
sp='/-\|'; printf ' '; while [ $SECONDS -lt $end ]; do printf '\b%.1s' "$sp"; sp=${sp#?}${sp%???}; sleep .3; done # Spinner from StackOverflow

ssh -qtt $node1 "${SUDO:-} maprcli node cldbmaster" && ssh $node1 "${SUDO:-} maprcli acl edit -type cluster -user $admin1:fc"
[ $? -ne 0 ] && { echo CLDB did not startup, check status and logs on $node1; exit 3; }

echo With a web browser, connect to one of the webservers to continue with license installation:
echo Webserver nodes: $(nodeset -S, -e @dhist)
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

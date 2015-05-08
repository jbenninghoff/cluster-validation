#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

export JAVA_HOME=/usr/java/default #Oracle JDK
clargs='-o -qtt'
[ $(id -u) -ne 0 ] && SUDO=sudo  #Use sudo, assuming account has passwordless sudo  (sudo -i)?

grep ^hbm /etc/clustershell/groups || { echo clustershell group: hbm undefined; exit 1; }
grep ^hbr /etc/clustershell/groups || { echo clustershell group: hbr undefined; exit 1; }
grep ^dzk /etc/clustershell/groups || { echo clustershell group: dzk undefined; exit 1; }
grep ^dcldb /etc/clustershell/groups || { echo clustershell group: dcldb undefined; exit 1; }
clush -ab "java -version |& grep -e x86_64 -e 64-Bit"
clush -S -B -g hbm,hbr "$JAVA_HOME/bin/java -version |& grep -e x86_64 -e 64-Bit" || { echo $JAVA_HOME/bin/java does not exist on all nodes or is not 64bit; exit 3; }
# Check for JAVA_HOME setting
clush $clargs -g hbm,hbr "${SUDO:-} grep '^export JAVA_HOME' /opt/mapr/conf/env.sh"
clush -S -B -g hbm,hbr 'grep -i mapr /etc/yum.repos.d/*' || { echo MapR repos not found; exit 3; }

# Install HBase Region Servers
clush $clargs -v -g hbr "${SUDO:-} yum -y install mapr-hbase-regionserver"
# Install HBase Region Servers
clush $clargs -v -g hbm "${SUDO:-} yum -y install mapr-hbase-master"

# Configure ALL nodes with the CLDB and Zookeeper info (-N does not like spaces in the name)
clush $clargs -g hbm,hbr "${SUDO:-} /opt/mapr/server/configure.sh -Z $(nodeset -S, -e @dzk) -C $(nodeset -S, -e @dcldb) -R"

echo Restart Warden on all nodes
read -p "Press enter to continue or ctrl-c to abort"
clush $clargs -a "${SUDO:-} service mapr-warden restart"

echo Waiting 2 minutes for system to initialize; end=$((SECONDS+120))
sp='/-\|'; printf ' '; while [ $SECONDS -lt $end ]; do printf '\b%.1s' "$sp"; sp=${sp#?}${sp%???}; sleep .3; done # Spinner from StackOverflow
ssh -qtt $(nodeset -I0 -e @dzk) "${SUDO:-} maprcli node cldbmaster"
[ $? -ne 0 ] && { echo CLDB did not startup, check status and logs on $node1; exit 3; }

#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

clargs='-o -qtt'
[ $(id -u) -ne 0 ] && SUDO=sudo  #Use sudo, assuming account has passwordless sudo  (sudo -i)?

#Define these groups in /etc/clustershell/groups for use by the automated install script
#Replace the text in angle brackets, including brackets, with site specific host names
cat - EOF | ${SUDO:-} tee -a /etc/clustershell/groups >/dev/null
dev: @all
dzk: <replace this with 3 node names to run Zookeeper on>
dcldb: <replace this with 3 node names to run CLDB on, can also just be @dzk>
drm: <replace this with 2 or 3 node names to run Resource Manager on. Use nodes other than CLDB and ZK nodes>
dhist: <replace this with 1 node name to run Yarn History service on. Use nodes other than CLDB and ZK nodes>
EOF

clush -S -B -g dev 'grep -i mapr /etc/yum.repos.d/*' && { echo MapR repos found; exit 1; }
clush -S -B -g dev 'grep -i -m1 epel /etc/yum.repos.d/*' || { echo Warning, EPEL repo not found; }

#Create 4.x repos on all nodes
cat - <<EOF2 | clush -b -g dev "${SUDO:-} tee /etc/yum.repos.d/maprtech.repo >/dev/null"
[maprtech]
name=MapR Technologies
baseurl=http://package.mapr.com/releases/v4.1/redhat/
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
clush $clargs -g dev 'rpm --import http://package.mapr.com/releases/pub/maprgpg.key'
clush $clargs -g dev 'yum clean all'


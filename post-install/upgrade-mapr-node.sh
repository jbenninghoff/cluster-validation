#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

# Node by node upgrade script for rolling upgrade 
# Assumes ZK upgraded, JT not on CLDB nodes
# Upgrade CLDB nodes first

service mapr-warden stop
if lsb_release -i | grep -i -e ubuntu > /dev/null; then
   apt-get update > /dev/null; dpkg -l 'mapr-*' |  awk '/^i/{print $2}' | xargs apt-get -y install
elif lsb_release -i | grep -i -e redhat -e centos > /dev/null; then
   yum clean all; yum -y --disablerepo=maprecosystem update 'mapr-*'
fi
cat /opt/mapr/MapRBuildVersion
/opt/mapr/server/upgrade2maprexecute
/opt/mapr/server/configure.sh -C hbase15,hbase16,hbase17 -Z hbase15,hbase16,hbase17,hbase18,hbase19
service mapr-warden start
sleep 3   
maprcli node cldbmaster
sleep 3   
maprcli node list -columns hostname,svc 

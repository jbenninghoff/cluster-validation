#!/bin/bash
# jbenninghoff 2013-Sep-19  vi: set ai et sw=3 tabstop=3:

# stop centralconfig?
# stop ingest
# stop oozie
#check machines for NFS mounts with 'netstat -an | grep 2049'
#on all NFS client machines found, run lsof /mntpoint and/or fuser -c /mntpoint; kill all procs using NFS
clush -a -B umount -lf /mapr
clush -a -B service mapr-warden stop
clush -a -B service mapr-zookeeper stop
clush -a -B jps; clush -a -B 'ps ax | grep mapr'
echo Make sure all MapR Hadoop processes have stopped
sleep 9
clush -a -B jps; clush -a -B 'ps ax | grep mapr'

# Edit the url for version and edit the path to the yum repo file as needed
sed -i '0,/baseurl=.*package.mapr.com.*/{s,,baseurl=http://package.mapr.com/releases/v3.0.2/redhat,}' /etc/yum.repos.d/mapr.repo
[ $? != 0 ] && { echo "/etc/yum.repos.d/mapr.repo not found or needs hand edit"; exit; }
clush -abc /etc/yum.repos.d/mapr.repo  # Copy the edited mapr.repo file to all the nodes
clush -ab yum clean all

#yum --disablerepo=maprecosystem check-update mapr-\* | grep ^mapr #If you want to preview the updates
clush -ab 'sudo yum -y --disablerepo=maprecosystem update mapr-\*' |& tee mapr-main-updates.log
clush -ab 'sudo yum -y --disablerepo=mapr update mapr-\*' |& tee mapr-eco-updates.log
clush -ab '/opt/mapr/server/configure.sh -R -u mapr -g mapr -d hostname:3306 -du mapr -dp whatever' # assuming MapR to be run as mapr user.  Update seems to reset MapR user to root

clush -a -B service mapr-zookeeper start
clush -a -B service mapr-warden start
clush -aB /opt/mapr/server/upgrade2mapruser.sh
sleep 9; clush -a -B mount /mapr
maprcli config save -values {"cldb.v3.features.enabled":"1"}  # This can be done later if needed
maprcli config save -values {mapr.targetversion:"$(</opt/mapr/MapRBuildVersion)"}  # This can be done through MCS also

# If CLDB has problems restarting or MapR FS needs rebuilding
#maprcli config save -values {"cldb.ignore.stale.zk":"true"}
#clush -Ba '/opt/mapr/zookeeper/zk_cleanup.sh'
#clush -Ba 'rm -rf /opt/mapr/zkdata/version-2/*'
# After restarting warden run next line
#maprcli config save -values {"cldb.ignore.stale.zk":"false"}

# Rebuild the MapR filesystem, destroys all data, normally not wanted
#clush -a -B service mapr-warden stop
#clush -a -B service mapr-zookeeper stop
#clush -Ba 'rm -f /opt/mapr/conf/disktab'
#clush -Ba "lsblk -id | grep -o ^sd. | grep -v ^sda |sort|sed 's,^,/dev/,' | tee /tmp/disk.list; wc /tmp/disk.list"
#clush -Ba '/opt/mapr/server/disksetup -W $(cat /tmp/disk.list | wc -l) -F /tmp/disk.list'

# 1391  hadoop fs -ls /
# 1392  clush -b -g zkcldb ls /opt/mapr/zkdata
# 1393  clush -ab service mapr-warden stop
# 1394  clush -b -g zkcldb service mapr-zookeeper stop
# 1395  clush -b -g zkcldb ls /opt/mapr/zookeeper/zk_cleanup.sh
# 1396  clush -b -g zkcldb rm -rf  /opt/mapr/zkdata/*
# 1405  clush -b -g zkcldb rm -rf  /opt/mapr/zkdata/*
# 1407  clush -b -g zkcldb ls /opt/mapr/zkdata/
# 1408  echo 0 > /opt/mapr/zkdata/myid
# 1409  ssh cent02 'echo 1 > /opt/mapr/zkdata/myid'
# 1410  ssh cent03 'echo 2 > /opt/mapr/zkdata/myid'
# 1411  clush -b -g zkcldb service mapr-zookeeper start
# 1412  clush -b -g zkcldb service mapr-zookeeper qstatus
# 1417  less /opt/mapr/conf/cldb.conf
# 1422  echo cldb.ignore.stale.zk=true
# 1423  echo cldb.ignore.stale.zk=true | clush -b -g zkcldb 'cat - >> /opt/mapr/conf/cldb.conf'
# 1424  clush -b -g zkcldb 'tail /opt/mapr/conf/cldb.conf'
# 1425  clush -ab service mapr-warden start
# 1428  clush -b -g zkcldb 'tail /opt/mapr/logs/cldb.log'
#sleep 180
# 1429  maprcli node cldbmaster
# 1430  hadoop fs -ls /
# 1423  clush -b -g zkcldb 'sed "/cldb.ignore.stale.zk=true/s//#cldb.ignore.stale.zk=true/" /opt/mapr/conf/cldb.conf'
# clush -b -g zkcldb 'sed -i.bak "/cldb.ignore.stale.zk=true/s//#cldb.ignore.stale.zk=true/" /opt/mapr/conf/cldb.conf'
# 1425  clush -ab service mapr-warden restart


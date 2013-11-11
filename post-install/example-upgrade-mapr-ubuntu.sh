#!/bin/bash
# jbenninghoff@maprtech.com 2013-Sep-19  vi: set ai et sw=3 tabstop=3:

#Can run as a script as long as clustershell is set up correctly and no Hadoop jobs are running.  Does not address HBase or ecosystem components, additional steps required, see the docs.

#root@n001:~# cat /etc/clustershell/groups
#zk: n0[09-10,19,29,35].hadoop.prod.sfo1.beats
#cldb: n0[11,20,30,39].hadoop.prod.sfo1.beats
#jt: n0[13,21,31,40].hadoop.prod.sfo1.beats
#nfs: n0[02-08/2,12-18/2,22-28/2,32-38/2].hadoop.prod.sfo1.beats
#all: n0[01-40].hadoop.prod.sfo1.beats

clush -B -w @all ‘echo “deb http://package.mapr.com/releases/v3.0.2/ubuntu/ mapr optional” >> /etc/apt/sources.list’
clush -B -w @all apt-get update
hadoop job -list  # make sure none are running
clush -aB umount /mapr
maprcli node services -nodes `nodeset -e @nfs` -nfs stop
maprcli node list -columns svc | grep nfs
clush -B -w @cldb service mapr-warden stop
clush -B -w @all  service mapr-warden stop
clush -B -w @all  service mapr-zookeeper stop
clush -B -w @all  'dpkg -l | grep mapr'
clush -B -w @all  apt-get -y --allow-unauthenticated install mapr-core mapr-fileserver mapr-tasktracker
clush -B -w @nfs  apt-get -y --allow-unauthenticated install mapr-nfs
clush -B -w @zk   apt-get -y --allow-unauthenticated install mapr-zk-internal mapr-zookeeper
clush -B -w @cldb apt-get -y --allow-unauthenticated install mapr-cldb
clush -B -w @jt   apt-get -y --allow-unauthenticated install mapr-jobtracker mapr-metrics mapr-webserver
clush -B -w @all  'dpkg -l | grep mapr'
clush -B -w @all  cat /opt/mapr/MapRBuildVersion
clush -B -w @all  /opt/mapr/server/configure.sh -R
clush -B -w @zk   service mapr-zookeeper start
clush -B -w @zk   service mapr-zookeeper qstatus
clush -B -w @all  service mapr-warden start
maprcli node cldbmaster
maprcli config save -values {mapr.targetversion:"`cat /opt/mapr/MapRBuildVersion`"}
maprcli config load -keys mapr.targetversion
exit


clush -a -B umount /mapr
clush -a -B service mapr-warden stop
clush -a -B service mapr-zookeeper stop
clush -a -B jps; clush -a -B 'ps ax | grep mapr'
echo Make sure all MapR Hadoop processes have stopped
sleep 9
clush -a -B jps; clush -a -B 'ps ax | grep mapr'

# Edit the url for version and edit the path to the yum repo file as needed
sed -i '/baseurl=.*package.mapr.com/{s,^.*$,baseurl=http://package.mapr.com/releases/v3.0.1/redhat,;q}' /etc/yum.repos.d/mapr.repo
[ $? != 0 ] && { echo "/etc/yum.repos.d/mapr.repo not found or needs hand edit"; exit; }
clush -abc /etc/yum.repos.d/mapr.repo  # Copy the edited mapr.repo file to all the nodes
clush -ab yum clean all

#yum --disablerepo=maprecosystem check-update mapr-\* | grep ^mapr #If you want to preview the updates
clush -ab 'yum -y --disablerepo=maprecosystem update mapr-\*'
clush -ab '/opt/mapr/server/configure.sh -R -u mapr -g mapr' # assuming MapR to be run as mapr user.  Update seems to reset MapR user to root

clush -a -B service mapr-zookeeper start
clush -a -B service mapr-warden start
clush -aB /opt/mapr/server/upgrade2mapruser.sh
sleep 9; clush -a -B mount /mapr
maprcli config save -values {mapr.targetversion:"$(</opt/mapr/MapRBuildVersion)"}  # This can be done through MCS also
maprcli config save -values {"cldb.v3.features.enabled":"1"}

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

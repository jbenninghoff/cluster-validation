#!/bin/bash
# jbenninghoff@maprtech.com 2013-Sep-25  vi: set ai et sw=3 tabstop=3:

#
# Simple script to run the MapR RWSpeedTest on a single node.
#
# RWSpeedTest is NOT like DFSIO ... it is not a MapReduce job.
# So to run on all nodes in cluster you need to use clush

MAPR_HOME=${MAPR_HOME:-/opt/mapr}
localvol=localvol-$(hostname -s)

maprcli volume unmount -name $localvol
maprcli volume remove -name $localvol
# Make local volume
maprcli volume create -name $localvol -path /$localvol -replication 1 -localvolumehost $(<$MAPR_HOME/hostname)
hadoop mfs -setcompression off /$localvol

#find jars, there should only be one of these jars ... let's hope :)
MFS_TEST_JAR=$(find $MAPR_HOME/lib -name maprfs-diagnostic-tools-\*.jar)

# Find the total number of cores and use half of them
ncpu=$(grep -c ^processor /proc/cpuinfo)
((ncpu=ncpu/2))

# Find the available MapR disk space on this node
fsize=$(/opt/mapr/server/mrconfig sp list | awk '/totalfree/{print $9}')
# Use 100th of available space divided by the number of cores that wil be used
((fsize=(fsize/100)/ncpu)) #Check if big enough to exceed MFS cache

#usage: RWSpeedTest filename [-]megabytes uri

# A simple single core (1 process) test to verify node if needed
#hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest /$localvol/RWTestSingleTest $fsize maprfs:/// ; exit

#run RWSpeedTest writes
for i in $(seq 1 $ncpu); do
   hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest /$localvol/RWTest${i} $fsize maprfs:/// &
done
wait

#run RWSpeedTest reads
for i in $(seq 1 $ncpu); do
   hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest /$localvol/RWTest${i} -$fsize maprfs:/// &
done
wait

maprcli volume unmount -name $localvol
maprcli volume remove -name $localvol

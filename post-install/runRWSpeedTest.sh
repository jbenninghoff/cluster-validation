#!/bin/bash
# jbenninghoff 2013-Sep-25  vi: set ai et sw=3 tabstop=3:

#
# Simple script to run the MapR RWSpeedTest on a single node.
#
# RWSpeedTest is NOT like DFSIO ... it is not a MapReduce job.
# So to run on all nodes in cluster you need to use clush
[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }
tmpfile=$(mktemp); trap 'rm $tmpfile' 0 1 2 3 15
localvol=localvol-$(hostname -s)
MAPR_HOME=${MAPR_HOME:-/opt/mapr}

if ! maprcli volume info -name $localvol > /dev/null; then #If local volume doesn't exist
   hadoop fs -stat /$localvol #Check if folder exists
   # Make local volume configured with replication 1 and compression off
   maprcli volume create -name $localvol -path /$localvol -replication 1 -localvolumehost $(<$MAPR_HOME/hostname)
   hadoop mfs -setcompression off /$localvol
fi

#find jars, there should only be one of these jars ... let's hope :)
MFS_TEST_JAR=$(find $MAPR_HOME/lib -name maprfs-diagnostic-tools-\*.jar)

# Set number of Java processes to launch. Set equal to half the number of cores
nproc=$(grep -c ^processor /proc/cpuinfo)
#TBD Try setting number of Java processes to number of data drives
nproc=$(/opt/mapr/server/mrconfig sp list -v | grep -o '/dev/[^ ]*' | sort -u | wc -l)
#nproc=$(maprcli node list -columns service,'MapRfs disks' |grep nodemanager | awk '{split($0,arr1); for (x in arr1) { if (match(x,/^[0-9]+$/) > 0) print x; count+=x}}; END{print count}')
echo nproc: $nproc
((nproc=nproc/2))
echo "nproc/2:" $nproc

# Find the available MapR disk space on this node
fsize=$(/opt/mapr/server/mrconfig sp list | awk '/totalfree/{print $9}')
echo SP list:
/opt/mapr/server/mrconfig sp list
# Use 100th of available space divided by the number of processes that wil be used
#((fsize=(fsize/100)/nproc)) #Check if big enough to exceed MFS cache
((fsize=(fsize/100)/(${1:-1}*nproc))) #Check if big enough to exceed MFS cache
echo File size set to $fsize MB
#Add loop to run with file sizes 256MB, 1GB and calculated size
#read -p "Press enter to continue or ctrl-c to abort"

#usage: RWSpeedTest filename [-]megabytes uri

# A simple single core (1 process) test to verify node if needed
#hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest /$localvol/RWTestSingleTest $fsize maprfs:/// ; exit

export HADOOP_ROOT_LOGGER="WARN,console"
#run RWSpeedTest writes
for i in $(seq 1 $nproc); do
   hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest /$localvol/RWTest${i} $fsize maprfs:/// &
done | tee $tmpfile
awk '/Write rate:/{mbs+=$3};END{print "Aggregate Write Rate for this node is:", mbs, "MB/sec";}' $tmpfile
wait
sleep 9

#run RWSpeedTest reads
for i in $(seq 1 $nproc); do
   hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest /$localvol/RWTest${i} -$fsize maprfs:/// &
done | tee $tmpfile
awk '/Read rate:/{mbs+=$3};END{print "Aggregate Read Rate for this node is:", mbs, "MB/sec";}' $tmpfile
wait

maprcli volume unmount -name $localvol
maprcli volume remove -name $localvol

#!/bin/bash
# jbenninghoff 2013-Sep-25  vi: set ai et sw=3 tabstop=3:

usage() {
cat << EOF

# Simple script to run the MapR RWSpeedTest on a single node.
# RWSpeedTest is NOT like DFSIO ... it is not a MapReduce job.
# So to run on all nodes in a cluster you need to use clush

Usage: $0 [-d] [s] [-x <int>]
-d option for script debug
-s option to run a set of fixed size tests
-x option for file size divider

EOF
exit
}

dbug=false; fact=1; sizes=false
while getopts "dsx:" opt; do
   case $opt in
      d) dbg=true ;;
      s) sizes=true ;;
      x) [[ "$OPTARG" =~ ^[0-9.]+$ ]] && fact=$OPTARG || { echo $OPTARG is not an number; usage; } ;;
      :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
      *) usage ;;
   esac
done

[ $(id -un) != mapr -a $(id -u) -ne 0 ] && { echo This script must be run as root or mapr; exit 1; }
tmpfile=$(mktemp); trap 'rm $tmpfile' EXIT
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

#set number of Java processes to half the number of data drives
ndisk=$(/opt/mapr/server/mrconfig sp list -v | grep -o '/dev/[^ ]*' | sort -u | wc -l)
#ndisk=$(maprcli node list -columns service,'MapRfs disks' |grep nodemanager | awk '{split($0,arr1); for (x in arr1) { if (match(x,/^[0-9]+$/) > 0) print x; count+=x}}; END{print count}')
echo ndisk: $ndisk
(( ndisk=ndisk/2 ))
echo nproc: $ndisk

echo SP list:
/opt/mapr/server/mrconfig sp list -v
# Find the available MapR disk space on this node
fsize=$(/opt/mapr/server/mrconfig sp list | awk '/totalfree/{print $9}')
#echo Total File space $fsize MB

# Use 1% of available space divided by the number of processes that wil be used
(( fsize=(fsize/100)/(${fact:-1}*ndisk) )) #Check if big enough to exceed MFS cache
echo File size set to $fsize MB
#TBD: Add loop to run with file sizes 256MB, 1GB and calculated size
#read -p "Press enter to continue or ctrl-c to abort"

# Usage: RWSpeedTest filename [-]megabytes uri
# A simple single core (1 process) test to verify node if needed
if [ -n "$dbg" ]; then
   hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest /$localvol/RWTestSingleTest $fsize maprfs:///
   exit
fi

export HADOOP_ROOT_LOGGER="WARN,console"

#run RWSpeedTest writes uncompressed
for i in $(seq 1 $ndisk); do
   hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest /$localvol/RWTest${i} $fsize maprfs:/// &
done | tee $tmpfile
wait
sleep 3
awk '/Write rate:/{mbs+=$3};END{print "Aggregate Write Rate for this node is:", mbs, "MB/sec";}' $tmpfile

#run RWSpeedTest reads uncompressed
for i in $(seq 1 $ndisk); do
   hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest /$localvol/RWTest${i} -$fsize maprfs:/// &
done | tee $tmpfile
wait
sleep 3
awk '/Read rate:/{mbs+=$3};END{print "Aggregate Read Rate for this node is:", mbs, "MB/sec";}' $tmpfile
sleep 3

hadoop fs -rm -r /$localvol/\*
hadoop mfs -setcompression on /$localvol

#run RWSpeedTest writes on compressed volume
for i in $(seq 1 $ndisk); do
   hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest /$localvol/RWTest${i} $fsize maprfs:/// &
done | tee $tmpfile
wait
sleep 3
awk '/Write rate:/{mbs+=$3};END{print "Aggregate Write Rate using MFS compression for this node is:", mbs, "MB/sec";}' $tmpfile

#run RWSpeedTest reads on compressed volume
for i in $(seq 1 $ndisk); do
   hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest /$localvol/RWTest${i} -$fsize maprfs:/// &
done | tee $tmpfile
wait
sleep 3
awk '/Read rate:/{mbs+=$3};END{print "Aggregate Read Rate using MFS compression for this node is:", mbs, "MB/sec";}' $tmpfile
sleep 3

maprcli volume unmount -name $localvol
maprcli volume remove -name $localvol

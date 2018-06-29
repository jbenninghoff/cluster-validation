#!/bin/bash
# jbenninghoff 2013-Sep-25  vi: set ai et sw=3 tabstop=3:

usage() {
cat << EOF

# Simple script to run the MapR RWSpeedTest on a single node in a local volume.
# RWSpeedTest is NOT like DFSIO ... it is not a MapReduce job.
# So to run on all nodes in a cluster you need to use clush
# RWSpeedTest measures MFS throughput
# Compare Local volume Aggregate results with disk-test.sh Sequential Aggregate results per node

Usage: $0 [-n] [-r] [-p] [-d] [-s] [-x <int>]
-d option for script debug
-s option to run a set of fixed size tests
-x option for file size divider
-p option to preserve local volume [default is to delete it]
-r option to use regular 3x replication volume
-n option to skip compression on tests

EOF

}

dbg=false; fact=1; sizes=false; preserve=false; volume=local; compression=true
while getopts "nrpdsx:" opt; do
   case $opt in
      n) compression=false ;;
      r) volume=regular ;;
      p) preserve=true ;;
      d) dbg=true ;;
      s) sizes=true ;;
      x) [[ "$OPTARG" =~ ^[0-9.]+$ ]] && fact=$OPTARG || { echo $OPTARG is not an number; usage; exit 1; } ;;
      :) echo "Option -$OPTARG requires an argument." >&2; usage; exit 2 ;;
      *) usage; exit 3 ;;
   esac
done

mapracct=$(stat -c "%U" /opt/mapr/conf/mapruserticket)
tmpfile=$(mktemp); trap "rm $tmpfile; echo EXIT sigspec: $?; exit" EXIT
localvol=localvol-$(hostname -s)
MAPR_HOME=${MAPR_HOME:-/opt/mapr}
if [[ $(id -un) != $mapracct && $(id -u) -ne 0 ]]; then
   echo This script must be run as root or mapr; exit 1
fi

#Check if folder exists and clear it out
if hadoop fs -stat /$localvol >& /dev/null; then
   hadoop fs -rm -r /$localvol/\*
fi
#TBD: ! maprcli volume info -name $localvol > /dev/null #vol exists?

if [[ $volume == "regular" ]]; then
   # Make regular volume configured with replication 3 and compression off
   regvol=mfs-benchmarks-$(hostname -s)
   opts="-name $regvol -path /$regvol -replication 3"
   opts+=" -topology /data/default-rack"
   maprcli volume create "$opts"
   hadoop fs -rm -r /$regvol/\* >/dev/null
   hadoop mfs -setcompression off /$regvol
else
   # Make local volume configured with replication 1 and compression off
   opts="-name $localvol -path /$localvol -replication 1 "
   opts+=" -localvolumehost $(<$MAPR_HOME/hostname)"
   maprcli volume create "$opts"
   hadoop mfs -setcompression off /$localvol
fi

#find jars, there should only be one of these jars ... let's hope :)
MFS_TEST_JAR=$(find $MAPR_HOME/lib -name maprfs-diagnostic-tools-\*.jar)

#set number of Java processes to the number of data drives
pcmd="grep -o '/dev/[^ ,]*' | sort -u | wc -l"
ndisk=$(/opt/mapr/server/mrconfig sp list -v | "$pcmd")
#(( ndisk=ndisk*2 )) #Modify the process count if need be
echo ndisk: $ndisk
echo

# Show the Storage Pools on this node
/opt/mapr/server/mrconfig sp list -v
echo

# Find the available MapR storage space on this node
fsize=$(/opt/mapr/server/mrconfig sp list | awk '/totalfree/{print $9}')
#echo Total File space $fsize MB

# Use 1% of available space
(( fsize=(fsize/100) )) 
# Divide by the number of processes that wil be run to set the file size
(( fsize=(fsize/(${fact:-1}*ndisk) ) ))
# TBD: Check if $fsize is big enough to exceed MFS cache
echo Num processes: $ndisk
echo File size set to $fsize MB; echo
#read -p "Press enter to continue or ctrl-c to abort"

# Usage: RWSpeedTest filename [-]megabytes uri
# A simple single core (1 process) test to verify node if needed
if [ -n "$dbg" ]; then
   opts="/$localvol/RWTestSingleTest $fsize maprfs:///"
   hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest "$opts"
   exit
fi

export HADOOP_ROOT_LOGGER="WARN,console"

#TBD: Add loop to run with specific file sizes 256MB, 1GB and calculated size
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

if [[ $compression == "true" ]]; then
   hadoop fs -rm -r /$localvol/\*
   hadoop mfs -setcompression on /$localvol
   echo

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
fi

if [[ $preserve == "false" ]]; then
   maprcli volume unmount -name $localvol
   maprcli volume remove -name $localvol
fi

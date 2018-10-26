#!/bin/bash
# jbenninghoff 2013-Apr-08  vi: set ai et sw=3 tabstop=3:
#
# This test will create <n> files of size <fsize>, where <n> is defined as
#  Number of total disk available in the cluster (for YARN clusters), OR
#  Number of Map Slots (for MapReduce Version 1 clusters)
# fsize is defined as 250MB to avoid file sharding due to chunksize
#
# For YARN clusters, the first arg to the script becomes a multiplier of files.
# This arg can be used to find the maximum throughput per map task
#
# The output is appended to a TestDFSIO.log file for all runs.  The
# key metrics reported are elapsed time and throughput (per map task).
#
# DFSIO creates a directory TestDFSIO under /benchmarks in the 
# distributed file system.   The folder "/benchmarks" can be its own
# volume in MapR (see mkBMvol.sh)

MRV=$(hadoop version | awk 'NR==1{printf("%1.1s\n",$2)}')
# Size of files to be written (in MB)
fsize=250
filesPerDisk=${1:-1}

if [ $MRV == "2" ] ; then
   hadooppath=$(ls -c1 -d /opt/mapr/hadoop/hadoop-* |sort -n |tail -1)
   jarpath="$hadooppath/share/hadoop/mapreduce/"
   jarpath+="hadoop-mapreduce-client-jobclient-${hadoopver}*-tests.jar"
   jarpath=$(eval ls $jarpath)
   hadoopver=${hadooppath#*/hadoop-}

   clcmd="/opt/mapr/server/mrconfig sp list -v "
   clcmd+=" |grep -o '/dev/[^ ,]*' | sort -u | wc -l"
   tdisks=$(clush -aN "$clcmd" |awk '{ndisks+=$1}; END{print ndisks}')
   #tdisks=$(( $tdisks * $filesPerDisk ))
   tdisks=$(echo "$tdisks * $filesPerDisk" |bc )
   mapDisks=$(echo "scale=2; 1 / $filesPerDisk" | bc)
   echo Number of disks per Map task: $mapDisks
   echo tdisks: $tdisks; echo filesPerDisk: $filesPerDisk; echo fsize: $fsize
   read -p "Press enter to continue or ctrl-c to abort" 

   # Use "mapreduce" properties to force <N> containers per available disk
   # Default is 1 container/disk (so map.disk=1 and nrFiles is tdisks*1 )
   # The intent is to create one 'wave' of map tasks with max containers
   # per node utilized.  More than 1 container/disk can be specified to
   # discover peak cluster throughput
   hadoop jar $jarpath TestDFSIO \
      -Dmapreduce.job.name=DFSIO-write \
      -Dmapreduce.map.cpu.vcores=0 \
      -Dmapreduce.map.memory.mb=768 \
      -Dmapreduce.map.disk=${mapDisks:-1} \
      -Dmapreduce.map.speculative=false \
      -Dmapreduce.reduce.speculative=false \
      -write -nrFiles $tdisks \
      -fileSize $fsize  -bufferSize 65536

   hadoop jar $jarpath TestDFSIO \
      -Dmapreduce.job.name=DFSIO-read \
      -Dmapreduce.map.cpu.vcores=0 \
      -Dmapreduce.map.memory.mb=768 \
      -Dmapreduce.map.disk=${mapDisks:-1} \
      -Dmapreduce.map.speculative=false \
      -Dmapreduce.reduce.speculative=false \
      -read -nrFiles $tdisks \
      -fileSize $fsize  -bufferSize 65536

# Optional settings to ratchet down memory consumption
#     -Dmapreduce.map.memory.mb=768       # default 1024
#     -Dmapreduce.map.java.opts=-Xmx768m  # default -Xmx900m

else  # $MRV == 1

   HHOME=$(ls -d /opt/mapr/hadoop/hadoop-0*)
   HVER=${HHOME#*/hadoop-}
   TJAR=$HHOME/hadoop-${HVER}-dev-test.jar
   mtasks=$(maprcli dashboard info -json | grep map_task_capacity | grep -o '[0-9][0-9]*')

      # DFSIO write test 
   hadoop jar $TJAR TestDFSIO \
      -Dmapred.job.name=DFSIO-write \
      -Dmapred.map.tasks.speculative.execution=false \
      -Dmapred.reduce.tasks.speculative.execution=false \
      -write -nrFiles $mtasks -fileSize $fsize -bufferSize 65536

      # DFSIO read test
   hadoop jar $TJAR TestDFSIO \
      -Dmapred.job.name=DFSIO-read \
      -Dmapred.map.tasks.speculative.execution=false \
      -Dmapred.reduce.tasks.speculative.execution=false \
      -read -nrFiles $mtasks -fileSize $fsize -bufferSize 65536

fi

echo "Results appended to ./TestDFSIO_results.log"
echo "  NOTE: Resulting metric is per map slot / container"

# Quick test of map-reduce.  Can be used right after building/rebuild a cluster
# hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar pi 10 10
# hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar wordcount file:///etc/services apacheWC

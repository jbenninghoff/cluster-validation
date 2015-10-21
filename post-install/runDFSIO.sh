#!/bin/bash
# jbenninghoff 2013-Apr-08  vi: set ai et sw=3 tabstop=3:
#
# DFSIO creates a directory TestDFSIO within /benchmarks in the 
# distributed file system.   You'll want "/benchmarks" to be its own
# volume (see mkbenchmarksvol.sh)
#
# Test will create <n> files of size <fsize>, where <n> is defined as
#  Number of Map Slots (for MapReduce Version 1 clusters), OR
#  Number of total disk available in the cluster (for YARN clusters)
#
# For YARN clusters, the xtra parameter filesPerDisk enables 
# multiple map containers to be launched against the individual 
# NodeManagers (scaled so the the same volume of data is tested).
# Effectively, the "fsize" argument becomes a "bytesPerDisk" arg
# for YARN clusters.

MRV=$(hadoop version | awk 'NR==1{printf("%1.1s\n",$2)}')
# Size of files to be written (in MB)
fsize=4000

if [ $MRV == "2" ] ; then
   HHOME=$(ls -d /opt/mapr/hadoop/hadoop-2*)
   HVER=${HHOME#*/hadoop-}
   TJAR=$(ls $HHOME/share/hadoop/mapreduce/hadoop-mapreduce-client-jobclient-$HVER-*-tests.jar)
   tdisks=$(maprcli dashboard info -json | grep total_disks| grep -o '[0-9][0-9]*')
   # Use "mapreduce" properties to force <N> containers per available disk
   # Default is 1 (so map.disk=1 and nrFiles is tdisks*1 )
   # The intent is to create one 'wave' of map tasks with max containers per node utilized
   filesPerDisk=1
   mapDisk=`echo "scale=2; 1 / $filesPerDisk" | bc`; echo $mapDisk
   hadoop jar $TJAR TestDFSIO \
      -Dmapreduce.job.name=DFSIO-write \
      -Dmapreduce.map.cpu.vcores=0 \
      -Dmapreduce.map.memory.mb=768 \
      -Dmapreduce.map.disk=${mapDisk:-1} \
      -Dmapreduce.map.speculative=false \
      -Dmapreduce.reduce.speculative=false \
      -write -nrFiles $[$tdisks*$filesPerDisk] \
      -fileSize $[fsize * ${1:-2}]  -bufferSize 65536

   hadoop jar $TJAR TestDFSIO \
      -Dmapreduce.job.name=DFSIO-read \
      -Dmapreduce.map.cpu.vcores=0 \
      -Dmapreduce.map.memory.mb=768 \
      -Dmapreduce.map.disk=${mapDisk:-1} \
      -Dmapreduce.map.speculative=false \
      -Dmapreduce.reduce.speculative=false \
      -read -nrFiles $[tdisks*$filesPerDisk] \
      -fileSize $[fsize * ${1:-2}]  -bufferSize 65536

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

#!/bin/bash
# jbenninghoff 2013-Jul-22  vi: set ai et sw=3 tabstop=3:

# Remove and recreate a MapR 1x volume just for benchmarking
# Use replication 1 to get peak write performance
if maprcli volume info -name benchmarks1x > /dev/null; then
   maprcli volume unmount -name benchmarks1x
   maprcli volume remove -name benchmarks1x
   sleep 2
fi
maprcli volume create -name benchmarks1x -path /benchmarks1x -replication 1
# use -topology /data... if needed
hadoop fs -chmod 777 /benchmarks1x #open the folder up for all to use

# Create standard 3x benchmarks volume/folder
if maprcli volume info -name benchmarks > /dev/null; then
   maprcli volume unmount -name benchmarks
   maprcli volume remove -name benchmarks
   sleep 2
fi
maprcli volume create -name benchmarks -path /benchmarks
hadoop fs -chmod 777 /benchmarks #open the folder up for all to use

# Increase MFS cache on all nodes (with clush)
# wconf=/opt/mapr/conf/warden.conf
# sed -i 's/mfs.heapsize.percent=20/mfs.heapsize.percent=30/' "$wconf"
# /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml
# <name>mapred.tasktracker.map.tasks.maximum</name> <value>CPUS-1</value> 
# <name>mapred.tasktracker.reduce.tasks.maximum</name> <value>CPUS/2</value> 

#source maprcli_check function from mapr-audit.sh
#source <(awk '/^ *maprcli_check\(\)/,/^ *} *$/' mapr-audit.sh)

#hadoop fs -stat /benchmarks #Check if folder exists and ... TBD
#hadoop mfs -setcompression off /benchmarks
#compression may help but not allowed by sortbenchmark.org
#hadoop mfs -setchunksize $[512*1024*1024] /benchmarks 
#default 256MB, optimal chunksize determined by cluster size


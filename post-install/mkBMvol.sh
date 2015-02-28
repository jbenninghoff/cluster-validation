#!/bin/bash
# jbenninghoff 2013-Jul-22  vi: set ai et sw=3 tabstop=3:

# Increase MFS cache on all nodes (with clush)
# sed -i 's/mfs.heapsize.percent=20/mfs.heapsize.percent=30/' /opt/mapr/conf/warden.conf
# /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml
# <name>mapred.tasktracker.map.tasks.maximum</name> <value>CPUS-1</value> 
# <name>mapred.tasktracker.reduce.tasks.maximum</name> <value>CPUS/2</value> 

# Remove and recreate a MapR volume just for benchmarking, best if run only once
maprcli volume unmount -name benchmarks
maprcli volume remove -name benchmarks
sleep 2

maprcli volume create -name benchmarks -path /benchmarks -replication 1 # use -topology /data... if desired
#hadoop mfs -setcompression off /benchmarks #compression may help but not allowed by sortbenchmark.org
#hadoop mfs -setchunksize $[512*1024*1024] /benchmarks  #default 256MB, optimal chunksize determined by cluster size


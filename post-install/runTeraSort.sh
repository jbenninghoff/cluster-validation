#!/bin/bash
# jbenninghoff@maprtech.com 2013-Mar-8 vi: set ai et sw=3 tabstop=3:

rtasks=$(maprcli dashboard info -json | grep reduce_task_capacity | grep -o '[0-9]*')

# TeraSort
hadoop fs -rmr /benchmarks/tera/run1
hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar terasort \
-Dmapred.reduce.tasks=$rtasks \
-Dmapreduce.maprfs.use.compression=false \
-Dmapred.map.tasks.speculative.execution=false \
-Dmapred.reduce.tasks.speculative.execution=false \
-Dmapreduce.map.log.level=NONE \
-Dmapreduce.reduce.log.level=NONE \
-Dio.sort.mb=450 \
-Dmapred.map.child.java.opts="-Xmx1200m" \
-Dmapred.reduce.child.java.opts="-Xmx3000m" \
-Dmapred.reduce.slowstart.completed.maps=0 \
-Dmapred.reduce.parallel.copies=4 \
/benchmarks/tera/in /benchmarks/tera/run1
# Reduce heap size above suitable for large memory nodes
# Reduce heap size should be reduced on small memory nodes

logname=terasort-run1-$(date -Imin|cut -c-16).log
hadoop job -history /benchmarks/tera/run1 > $logname  # capture the run log
head -22 $logname 

: << '--BLOCK-COMMENT--'
# options used in world record terasort run on large cluster:
-Dmapred.job.reduce.input.buffer.percent=1.0 \
-Dmapred.maxthreads.generate.mapoutput=6 \
-Dmapred.maxthreads.partition.closer=6 \
-Dmapred.job.shuffle.input.buffer.percent=0.70 \
-Dmapred.job.shuffle.merge.percent=1.0 \

# TeraSort options worth experimenting with below:
-Dmapred.job.shuffle.input.buffer.percent=0.8 \
-Dmapred.inmem.merge.threshold=0 \
-Dmapred.job.shuffle.merge.percent=1.0 \
-Dmapred.job.reduce.input.buffer.percent=1.0 \
-Dmapred.reduce.parallel.copies=2 \
-Dio.sort.factor=20 \
-Dmapred.map.child.java.opts=" -Xmx1000m" \
-Dmapred.reduce.child.java.opts=" -Xmx5000m" \
-Dmapred.reduce.slowstart.completed.maps=0.0 \
-Dmapreduce.jobtracker.heartbeat.interval.min=1 \
-Dmapreduce.tasktracker.prefetch.maptasks=0.0 \
-Dmapred.inmem.merge.threshold=500 \
-Dmapred.committer.job.setup.cleanup.needed=false \
-Dmapreduce.tasktracker.outofband.heartbeat=true \
-Dmapred.tasktracker.shuffle.readahead.bytes=7 \
-Dmapr.map.keyprefix.ints=2 \

#tasktracker.http.threads=70
# terasort param ignored in new terasort package:  -Dmapred.map.tasks=$nf 
#hadoop fs -ls /benchmarks/tera/run1/_partition.lst  #file in java io error, volume issue?

# To validate TeraSort output, uncomment below and change output folder
# hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar teravalidate /benchmarks/tera/run1 /benchmarks/tera/run1validate2
--BLOCK-COMMENT--

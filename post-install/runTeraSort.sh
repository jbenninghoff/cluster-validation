#!/bin/bash
# jbenninghoff@maprtech.com 2013-Mar-8 vi: set ai et sw=3 tabstop=3:

nodes=$(maprcli node list -columns hostname,cpus,ttReduceSlots | awk '/^[1-9]/{if ($2>1) count++};END{print count}')
((rtasks=nodes*2)) # Start with 2 reduce tasks per node, reduce tasks per node limited by available RAM

# TeraSort baseline execution, start with this before experimenting with any options in the block comment
hadoop fs -rmr /benchmarks/tera/run1
hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar terasort \
-Dmapred.reduce.tasks=$rtasks \
-Dmapred.reduce.child.java.opts="-Xmx3000m" \
-Dmapred.job.shuffle.input.buffer.percent=0.7 \
/benchmarks/tera/in /benchmarks/tera/run1

# Capture the job history log
logname=terasort-run1-$(date -Imin|cut -c-16).log
hadoop job -history /benchmarks/tera/run1 > $logname  # capture the run log
head -32 $logname  # show the top of the log with elapsed time, etc

# To validate TeraSort output, uncomment below and change output folder
# hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar teravalidate /benchmarks/tera/run1 /benchmarks/tera/run1validate

: << '--BLOCK-COMMENT--'
# Experimental options below, use if you know what you are doing
-Dmapred.map.tasks.speculative.execution=false \
-Dmapred.reduce.tasks.speculative.execution=false \
# Default io.sort.mb is 380MB which is sufficient for default MFS ChunkSize (256MB)
-Dio.sort.mb=380 \
# Default map and reduce heap sizes are auto-tuned, should work out of the box per Srivas
-Dmapred.map.child.java.opts="-Xmx1000m" \
-Dmapred.reduce.child.java.opts="-Xmx3000m" \
#1TB requires 334 reduce tasks using 3GB heap, 250 reduce tasks using 4GB heap, to fit all 1TB in RAM
# slowstart setting controls overlap of reduce tasks with map tasks
-Dmapred.reduce.slowstart.completed.maps=0 \
# Parallel copies has mixed results
-Dmapred.reduce.parallel.copies=4 \
# Disable logging for final peak performance run ??
-Dmapreduce.map.log.level=NONE \
-Dmapreduce.reduce.log.level=NONE \
# Disable compression for sortbenchmark.org rules
-Dmapreduce.maprfs.use.compression=false \
# options used in world record terasort run on large cluster:
-Dmapred.maxthreads.generate.mapoutput=6 \
-Dmapred.maxthreads.partition.closer=6 \
# Apache docs on important reduce task settings:
# http://hadoop.apache.org/docs/r1.2.1/mapred_tutorial.html#Shuffle%2FReduce+Parameters
# percentage of heap to store map outputs during the shuffle.
-Dmapred.job.shuffle.input.buffer.percent=0.70 \
-Dmapred.job.shuffle.merge.percent=1.0 \

#Bundle of reduce options to try:
-Dmapred.reduce.child.java.opts="-Xmx3000m" \
-Dmapred.job.shuffle.input.buffer.percent=0.7 \
-Dmapred.job.shuffle.merge.percent=1.0 \

# TeraSort options worth experimenting with below:
# buffer.percent triggers BUG in MapR 2.1x
-Dmapred.job.reduce.input.buffer.percent=1.0 \
-Dmapred.job.shuffle.input.buffer.percent=0.8 \
-Dmapred.inmem.merge.threshold=0 \
-Dmapred.job.shuffle.merge.percent=1.0 \
-Dio.sort.factor=20 \
-Dmapreduce.jobtracker.heartbeat.interval.min=1 \
-Dmapreduce.tasktracker.prefetch.maptasks=0.0 \
-Dmapred.committer.job.setup.cleanup.needed=false \
-Dmapreduce.tasktracker.outofband.heartbeat=true \
-Dmapred.tasktracker.shuffle.readahead.bytes=7 \
-Dmapr.map.keyprefix.ints=2 \

#tasktracker.http.threads=70
# terasort param ignored in new terasort package:  -Dmapred.map.tasks=$nf 
--BLOCK-COMMENT--

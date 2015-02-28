#!/bin/bash
# jbenninghoff@maprtech.com 2013-Mar-8 vi: set ai et sw=3 tabstop=3:

#MRV=$(maprcli cluster mapreduce get |tail -1 |awk '{print $1}')
MRV=$(hadoop version | awk 'NR==1{printf("%1.1s\n",$2)}')

if [ "$MRV" == "1" ] ; then # MRv1
    nodes=$(maprcli node list -columns hostname,cpus,ttReduceSlots | awk '/^[1-9]/{if ($2>0) count++};END{print count}')
    ((rtasks=nodes*${1:-2})) # Start with 2 reduce tasks per node, reduce tasks per node limited by available RAM
    echo rtasks=$rtasks

    # TeraSort baseline execution, start with this before experimenting with any options on MapR v3.x
    hadoop fs -rmr /benchmarks/tera/run1
    hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar terasort \
    -Dmapred.reduce.tasks=$rtasks \
    -Dmapred.reduce.child.java.opts="-Xmx3000m" \
    -Dmapred.reduce.tasks.speculative.execution=false \
    -Dmapred.map.tasks.speculative.execution=false \
    /benchmarks/tera/in /benchmarks/tera/run1

    # Capture the job history log
    logname=terasort-run1-$(date -Imin|cut -c-16).log
    hadoop job -history /benchmarks/tera/run1 > $logname  # capture the run log
    cat $0 >> $logname
    head -32 $logname  # show the top of the log with elapsed time, etc

    # To validate TeraSort output, uncomment below and change output folder
    # hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar teravalidate /benchmarks/tera/run1 /benchmarks/tera/run1validate

    #-Dmapred.job.shuffle.input.buffer.percent=.90 \
    #-Dmapred.job.shuffle.merge.percent=.90 \
    #-Dmapreduce.maprfs.use.compression=true \
    #-Dmapred.job.reduce.input.buffer.percent=0.80 \
    #-Dmapred.inmem.merge.threshold=0 \
    #-Dmapred.reduce.slowstart.completed.maps=0.75 \
    #-Dmapred.map.child.java.opts="-Xmx880m" \
else # MRv2 Yarn
    nodes=$(maprcli node list -columns hostname,cpus,service |grep nodemanager |wc --lines)
    ((rtasks=nodes*${1:-2})) # Start with 2 reduce tasks per node, reduce tasks per node limited by available RAM
    echo rtasks=$rtasks

    # TeraSort baseline execution, start with this before experimenting with any options on MapR v3.x
    hadoop fs -rm -r /benchmarks/tera/run1
    hadoop jar /opt/mapr/hadoop/hadoop-2.4.1/share/hadoop/mapreduce/hadoop-mapreduce-examples-2.4.1-mapr-1408.jar terasort \
    -Dmapreduce.reduce.memory.mb=3072 \
    -Dmapreduce.map.memory.mb=1024 \
    -Dmapred.maxthreads.generate.mapoutput=2 \
    -Dmapreduce.tasktracker.reserved.physicalmemory.mb.low=0.95 \
    -Dmapred.maxthreads.partition.closer=2 \
    -Dmapreduce.map.sort.spill.percent=0.99 \
    -Dmapreduce.reduce.merge.inmem.threshold=0 \
    -Dmapreduce.job.reduce.slowstart.completedmaps=1 \
    -Dmapreduce.reduce.shuffle.parallelcopies=40 \
    -Dmapreduce.map.speculative=false \
    -Dmapreduce.reduce.speculative=false \
    -Dmapreduce.map.output.compress=false \
    -Dmapreduce.task.io.sort.mb=480 \
    -Dmapreduce.task.io.sort.factor=400 \
    -Dmapreduce.job.reduces=$rtasks \
    /benchmarks/tera/in /benchmarks/tera/run1 2>&1 | tee terasort.tmp

    sleep 1

    # Capture the job history log
    logname=terasort-run1-$(date -Imin|cut -c-16).log
    myj=$(grep 'INFO mapreduce.Job: Running job' terasort.tmp |awk '{print $7}')
    myf=$(hadoop fs -ls /var/mapr/cluster/yarn/rm/staging/history/done_intermediate/mapr/*$myj*.jhist |awk '{print $8}')
    echo "HISTORY FILE: $myf"

    mapred job -history $myf > $logname  # capture the run log
    cat $0 >> $logname
    head -32 $logname  # show the top of the log with elapsed time, etc

    # To validate TeraSort output, uncomment below and change output folder
    # hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar teravalidate /benchmarks/tera/run1 /benchmarks/tera/run1validate
fi

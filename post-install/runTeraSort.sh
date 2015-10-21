#!/bin/bash
# jbenninghoff 2013-Mar-8 vi: set ai et sw=3 tabstop=3:

#MRV=$(maprcli cluster mapreduce get |tail -1 |awk '{print $1}')
logname=terasort-$(date -Imin|cut -c-16).log
MRV=$(hadoop version | awk 'NR==1{printf("%1.1s\n",$2)}')

if [ "$MRV" == "1" ] ; then # MRv1
    nodes=$(maprcli node list -columns hostname,cpus,ttReduceSlots | awk '/^[1-9]/{if ($2>0) count++};END{print count}')
    ((rtasks=nodes*${1:-2})) # Start with 2 reduce tasks per node, reduce tasks per node limited by available RAM
    echo rtasks=$rtasks

    # TeraSort baseline execution, start with this before experimenting with any options on MapR v3.x
    hadoop fs -rmr /benchmarks/tera/out
    hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar terasort \
    -Dmapred.reduce.tasks=$rtasks \
    -Dmapred.reduce.child.java.opts="-Xmx3000m" \
    -Dmapred.reduce.tasks.speculative.execution=false \
    -Dmapred.map.tasks.speculative.execution=false \
    /benchmarks/tera/in /benchmarks/tera/out

    # Capture the job history log
    hadoop job -history /benchmarks/tera/out >> $logname  # capture the run log
    cat $0 >> $logname
    head -32 $logname  # show the top of the log with elapsed time, etc

    # To validate TeraSort output, uncomment below and change output folder
    # hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar teravalidate /benchmarks/tera/out /benchmarks/tera/validate

    #-Dmapred.job.shuffle.input.buffer.percent=.90 \
    #-Dmapred.job.shuffle.merge.percent=.90 \
    #-Dmapred.job.reduce.input.buffer.percent=0.80 \
    #-Dmapred.inmem.merge.threshold=0 \
    #-Dmapred.reduce.slowstart.completed.maps=0.75 \
    #-Dmapred.map.child.java.opts="-Xmx880m" \
else # MRv2 Yarn ====================================================
    nodes=$(maprcli node list -columns hostname,cpus,service |grep nodemanager |wc --lines)
    ((rtasks=nodes*${1:-1})) # Start with 1 reduce task per node, reduce tasks per node limited by available RAM
    #rtasks=500
    echo nodes=$nodes | tee $logname
    echo rtasks=$rtasks | tee -a $logname

    # TeraSort baseline execution, start with this before experimenting with any options on MapR v3.x
    hadoop fs -rm -r /benchmarks/tera/out/tb
    hadoop jar /opt/mapr/hadoop/hadoop-2.*/share/hadoop/mapreduce/hadoop-mapreduce-examples-2.*-mapr-*.jar terasort \
    -Dmapreduce.map.disk=0 \
    -Dmapreduce.map.cpu.vcores=0 \
    -Dmapreduce.map.output.compress=false \
    -Dmapreduce.map.sort.spill.percent=0.99 \
    -Dmapreduce.reduce.disk=0 \
    -Dmapreduce.reduce.cpu.vcores=0 \
    -Dmapreduce.reduce.memory.mb=2700 \
    -Dmapreduce.reduce.shuffle.parallelcopies=20 \
    -Dmapreduce.reduce.merge.inmem.threshold=0 \
    -Dmapreduce.task.io.sort.mb=480 \
    -Dmapreduce.task.io.sort.factor=100 \
    -Dmapreduce.job.reduces=$rtasks \
    -Dmapreduce.job.reduce.slowstart.completedmaps=0.55 \
    -Dyarn.app.mapreduce.am.log.level=ERROR \
    -Dmapreduce.map.speculative=false \
    -Dmapreduce.reduce.speculative=false \
    /benchmarks/tera/in/tb /benchmarks/tera/out/tb 2>&1 | tee terasort.tmp

    sleep 3
#    -Dmapreduce.map.memory.mb=2100 \
#    -Dmapreduce.map.java.opts="-Xmx1900m -Xms1900m" \
#    -Dmapreduce.input.fileinputformat.split.minsize=$[2*128*1024*1024] \
#    -Dmapreduce.input.fileinputformat.split.minsize=805306368 \
#    -Dmapreduce.reduce.shuffle.input.buffer.percent=0.85 \
#    -Dmapreduce.maprfs.use.compression=false \
#    -Dmapreduce.reduce.java.opts="-Xmx4100m" \
#    -Dmapreduce.reduce.sort.spill.percent=0.90 \
#    -Dmapreduce.reduce.shuffle.merge.percent=0.90 \
#    -Dmapreduce.maxthreads.generate.mapoutput=2 \
#    -Dmapreduce.maxthreads.partition.closer=2 \
#    -Dyarn.app.mapreduce.am.log.level=ERROR \

#    -Dmapreduce.reduce.shuffle.memory.limit.percent=.50 \
#    -Dmapreduce.reduce.input.buffer.percent=.20 \
#    -Dmapreduce.merge.inmem.threshold=0 \
#    -Dmapreduce.reduce.child.java.opts="-Xmx4300m -Xms4300m" \

#    -Dyarn.nodemanager.vmem-pmem-ratio=1.0 \

#    -Dmapreduce.map.child.java.opts="-Xmx650m -Xms650m" \
#    -Dmapred.reduce.child.java.opts="-Xmx1500m" \
#    -Dmapreduce.tasktracker.reserved.physicalmemory.mb.low=0.95 \
#    -Dyarn.nodemanager.vmem-pmem-ratio=1.0 \
#    -Dmapreduce.job.reduce.input.buffer.percent=0.80 \

    # Capture the job history log
    myj=$(grep 'INFO mapreduce.Job: Running job' terasort.tmp |awk '{print $7}')
    myd=$(date +'%Y/%m/%d')
    until (hadoop fs -stat /var/mapr/cluster/yarn/rm/staging/history/done/$myd/000000/$myj\*.jhist); do
       echo Waiting for /var/mapr/cluster/yarn/rm/staging/history/done/$myd/000000/$myj\*.jhist; sleep 5
    done
    myf=$(hadoop fs -ls /var/mapr/cluster/yarn/rm/staging/history/done/$myd/000000/$myj\*.jhist |awk '{print $8}')
    echo "HISTORY FILE: $myf"

    mapred job -history $myf >> $logname  # capture the run log
    cat $0 >> $logname # append actual script run to the log
    head -22 $logname  # show the top of the log with elapsed time, etc

    # To validate TeraSort output, uncomment below and change output folder
    # hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar teravalidate /benchmarks/tera/out /benchmarks/tera/validate
fi

#!/bin/bash
# jbenninghoff 2013-Jul-22  vi: set ai et sw=3 tabstop=3:

# TeraGen (specify size using 100 Byte records, 1TB = $[10*1000*1000*1000])

#MRV=$(maprcli cluster mapreduce get |tail -1 |awk '{print $1}')
MRV=$(hadoop version | awk 'NR==1{printf("%1.1s\n",$2)}')

if [ "$MRV" == "1" ] ; then # MRv1
    mtasks=$(maprcli dashboard info -json | grep map_task_capacity | grep -o '[0-9]*')
    echo -n "Running Teragen with $mtasks mappers"

    hadoop fs -rmr /benchmarks/tera/in
    #hadoop mfs -setchunksize $[512*1024*1024]  /benchmarks/tera  # Larger chunk size, fewer map tasks but bigger heap needed

    hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar teragen \
    -Dmapred.map.tasks=$mtasks \
    -Dmapred.map.tasks.speculative.execution=false \
    -Dmapred.reduce.tasks.speculative.execution=false \
    $[100*1000*1000] \
    /benchmarks/tera/in
else # MRv2 Yarn
    hadoop fs -rm -r /benchmarks/tera/in

    #DISKS="`maprcli node list -columns hostname,cpus,service,disks |grep nodemanager | awk '{count+=$2}; END{print count}'`"
    DISKS=$(maprcli node list -columns service,disks |grep nodemanager | awk '{split($0,arr1); for (x in arr1) { if (match(arr1[x], /^[0-9]+$/) > 0) count+=arr1[x]}}; END{print count}')
    ((DISKS=DISKS*${1:-1})); echo DISKS: $DISKS

    hadoop jar /opt/mapr/hadoop/hadoop-2.4.1/share/hadoop/mapreduce/hadoop-mapreduce-examples-2.4.1-mapr-1408.jar teragen \
    -Dmapreduce.job.maps=$DISKS \
    -Dmapreduce.map.speculative=false \
    -Dmapreduce.reduce.speculative=false \
    $[1000*1000*1000] \
    /benchmarks/tera/in
   
   # or try: 3906 chunks / # nodes n, round to whole number i, then i * n
   #-Dmapreduce.job.maps=3920 \ 
fi

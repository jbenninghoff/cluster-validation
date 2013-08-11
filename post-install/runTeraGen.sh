#!/bin/bash
# jbenninghoff@maprtech.com 2013-Jul-22  vi: set ai et sw=3 tabstop=3:

# TeraGen (specify size using 100 Byte records, 1TB = $[10*1000*1000*1000])

mtasks=$(maprcli dashboard info -json | grep map_task_capacity | grep -o '[0-9]*')
rtasks=$(maprcli dashboard info -json | grep reduce_task_capacity | grep -o '[0-9]*')
echo -n "Running Teragen with $mtasks mappers"

hadoop fs -rmr /benchmarks/tera/in
#hadoop mfs -setchunksize $[256*1024*1024]  /benchmarks/tera

hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar teragen \
   -Dmapred.map.tasks=$mtasks \
   -Dmapreduce.maprfs.use.compression=false \
   -Dmapred.map.tasks.speculative.execution=false \
   -Dmapred.reduce.tasks.speculative.execution=false \
   $[10*1000*1000*1000] \
   /benchmarks/tera/in
sleep 3

# Check TeraGenerated chunks per node
chunksPerNodeValuesSet=$(
 hadoop mfs -ls '/benchmarks/tera/in/part*' |
 grep ':5660' | grep -v -E 'p [0-9]+\.[0-9]+\.[0-9]+' |
 tr -s '[:blank:]' ' ' | cut -d' ' -f 4 |
 sort | uniq -c |
 tr -s '[:blank:]' ' ' | cut -d' ' -f 2 |
 sort | uniq | wc -l
)

#Check resulting value
if (( chunksPerNodeValuesSet == 1 )) ; then
 echo Verified equal numChunks per node
else
 echo Unequal chunk distribution. Rerun teragen
fi

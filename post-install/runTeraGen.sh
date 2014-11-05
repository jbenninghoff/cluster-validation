#!/bin/bash
# jbenninghoff@maprtech.com 2013-Jul-22  vi: set ai et sw=3 tabstop=3:

# TeraGen (specify size using 100 Byte records, 1TB = $[10*1000*1000*1000])

mtasks=$(maprcli dashboard info -json | grep map_task_capacity | grep -o '[0-9]*')
echo -n "Running Teragen with $mtasks mappers"

hadoop fs -rmr /benchmarks/tera/in
#hadoop mfs -setchunksize $[512*1024*1024]  /benchmarks/tera  # Larger chunk size, fewer map tasks but bigger heap needed

hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar teragen \
   -Dmapred.map.tasks=$mtasks \
   -Dmapred.map.tasks.speculative.execution=false \
   -Dmapred.reduce.tasks.speculative.execution=false \
   $[10*1000*1000*1000] \
   /benchmarks/tera/in

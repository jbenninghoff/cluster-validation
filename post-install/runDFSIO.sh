#!/bin/bash
# jbenninghoff@maprtech.com 2013-Apr-08  vi: set ai et sw=3 tabstop=3:

mtasks=$(maprcli dashboard info -json | grep map_task_capacity | grep -o '[0-9][0-9]*')
# DFSIO write test (file size in MB)
hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-test.jar TestDFSIO\
  -Dmapred.job.name=DFSIO-write\
  -Dmapred.map.tasks.speculative.execution=false\
  -Dmapred.reduce.tasks.speculative.execution=false\
  -write -nrFiles $mtasks -fileSize 10000 -bufferSize 65536

# DFSIO read test
hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-test.jar TestDFSIO\
  -Dmapred.job.name=DFSIO-read\
  -Dmapred.map.tasks.speculative.execution=false\
  -Dmapred.reduce.tasks.speculative.execution=false\
  -read -nrFiles $mtasks -fileSize 10000 -bufferSize 65536

echo Resulting metric is per map slot 

# Quick test of map-reduce.  Can be used right after building/rebuild a cluster
# hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar pi 10 10
# hadoop jar /opt/mapr/hadoop/hadoop-0.20.2/hadoop-0.20.2-dev-examples.jar wordcount file:///etc/services apacheWC

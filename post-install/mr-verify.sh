#!/bin/bash

# Quick smoke-test for MapReduce on Yarn using builtin example code
[[ $(id -u) -eq 0 ]] && { echo This script must be run as non-root; exit 1; }
srvid=$(awk -F= '/mapr.daemon.user/{ print $2}' /opt/mapr/conf/daemon.conf)
if [[ "$srvid" == $(id -un) ]]; then
   echo This script should also be run as non-service-account
fi

#readarray -t factors < <(maprcli dashboard info -json | \
#  grep -e num_node_managers -e total_disks | grep -o '[0-9]*')
#nmaps=$(( ${factors[0]} * ${factors[1]} ))
#nmaps=${factors[1]}
#nmaps=$(maprcli dashboard info -json |grep num_node_managers |grep -o '[0-9]*')
nmaps=$(maprcli dashboard info -json |grep total_disks |grep -o '[0-9]*')
#exjar=$(eval echo /opt/mapr/hadoop/hadoop-2*)
#exjar+=/share/hadoop/mapreduce/
#exjar+=hadoop-mapreduce-examples-2.7.0-mapr-1803.jar
exjar=$(find /opt/mapr/hadoop -name hadoop-mapreduce-examples\*.jar \
          2>/dev/null |grep -v sources)

hadoop jar $exjar pi $nmaps 4000

#4000 nSamples takes ~same time 400.

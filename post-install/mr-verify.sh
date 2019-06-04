#!/bin/bash
# Quick smoke-test for MapReduce on Yarn using builtin example code

[[ $(id -u) -eq 0 ]] && { echo This script must be run as non-root; exit 1; }

# Extract service account name from daemon.conf (typically 'mapr')
srvid=$(awk -F= '/mapr.daemon.user/{print $2}' /opt/mapr/conf/daemon.conf)
if [[ "$srvid" == $(id -un) ]]; then
   echo This script should ALSO be run as non-service-account
fi

#readarray -t factors < <(maprcli dashboard info -json | \
#  grep -e num_node_managers -e total_disks | grep -o '[0-9]*')
#nmaps=$(( ${factors[0]} * ${factors[1]} )); #nmaps=${factors[1]}

# Get total disk count and set up to use one map task per disk
nmaps=$(maprcli dashboard info -json |grep total_disks |grep -o '[0-9]*')
exjar=$(find /opt/mapr/hadoop -name hadoop-mapreduce-examples\*.jar \
        2>/dev/null |grep -v sources)

# Run the Pi example mapreduce job, expect ~3.14.... on the console
hadoop jar "$exjar" pi "$nmaps" 4000
# If this job is not successful, the cluster is not ready
#4000 nSamples takes ~same time as 400.

#!/bin/bash
# jbenninghoff@maprtech.com 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

# Assumes clush is installed, available from EPEL repository
# A sequence of maprcli commands to probe installed system configuration
# Log stdout/stderr with 'mapr-audit.sh |& tee mapr-audit.log'

shopt -s expand_aliases

sep='====================================================================='
D=$(dirname "$0"); abspath=$(cd "$D" 2>/dev/null && pwd || echo "$D")

unalias psh 2>/dev/null; alias psh='clush -ab'
parg='-g mapr' # Assuming clush group 'mapr' is configured to reach all nodes
parg='-a' # Assuming clush is configured to reach all nodes
snode='ssh lgpbd1000' #Single node to run maprcli commands from
snode='' #Set to null if current node can run maprcli commands as well as clush commands

echo ==================== MapR audits ================================
date; echo $sep
$node maprcli dashboard info -json

echo $sep
echo MapR Alarms
$node maprcli alarm list -json

echo $sep
$node maprcli node list -columns hostname,svc

echo $sep
$node maprcli node list -columns hostname,ttmapSlots,ttReduceSlots

echo $sep
$node hadoop job -list

echo $sep
$node hadoop conf -dump | sort

echo $sep
$node maprcli config load -json

echo $sep
echo mapred-site.xml checksum
psh $parg sum /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml

echo $sep
psh $parg cat /opt/mapr/conf/env.sh
psh $parg grep centralconfig /opt/mapr/conf/warden.conf
psh $parg grep ROOT_LOGGER /opt/mapr/hadoop/hadoop-0.20.2/conf/hadoop-env.sh
psh $parg /opt/mapr/server/mrconfig sp list

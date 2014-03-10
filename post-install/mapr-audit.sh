#!/bin/bash
# jbenninghoff@maprtech.com 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

# Assumes clush is installed, available from EPEL repository
# A sequence of maprcli commands to probe installed system configuration
# Log stdout/stderr with 'mapr-audit.sh |& tee mapr-audit.log'

verbose=false
while getopts ":v" opt; do
  case $opt in
    v) verbose=true ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit ;;
  esac
done
# set verbose to false, true or full
# Use new bash case switch/fallthrough using ;& instead of ;;
# case $verbose in
#   false)
#     date; echo $sep ...
#     ;&
#   true)
#     maprcli ...
#     ;&
#   full)
#     clush ...
#     ;&
# esac

sep='====================================================================='
D=$(dirname "$0"); abspath=$(cd "$D" 2>/dev/null && pwd || echo "$D")

shopt -s expand_aliases
unalias psh 2>/dev/null; alias psh='clush -b'
parg='-g mapr' # Assuming clush group 'mapr' is configured to reach all nodes
parg='-a' # Assuming clush is configured to reach all nodes
snode='ssh lgpbd1000' #Single node to run maprcli commands from
snode='' #Set to null if current node can run maprcli commands as well as clush commands

echo ==================== MapR audits ================================
date; echo $sep
$node hadoop job -list; echo $sep
$node maprcli dashboard info -json; echo $sep

echo MapR Alarms
$node maprcli alarm list -json; echo $sep
echo MapR Services
$node maprcli node list -columns hostname,svc
echo zookeepers:
$node maprcli node listzookeepers; echo $sep
echo MapR map and reduce slots
$node maprcli node list -columns hostname,cpus,ttmapSlots,ttReduceSlots; echo $sep
echo MapR Volumes
$node maprcli volume list -columns numreplicas,mountdir,used,numcontainers,logicalUsed; echo $sep
echo MapR Storage Pools
psh $parg /opt/mapr/server/mrconfig sp list; echo $sep
[ "$verbose" == "true" ] && $node maprcli dump balancerinfo | sort -r; echo $sep
#$node maprcli dump balancerinfo | sort | awk '$1 == prvkey {size += $9}; $1 != prvkey {if (prvkey!="") print size; prvkey=$1; size=$9}'

psh $parg cat /opt/mapr/conf/env.sh
echo mapred-site.xml checksum
psh $parg sum /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml; echo $sep
psh $parg grep centralconfig /opt/mapr/conf/warden.conf
psh $parg grep ROOT_LOGGER /opt/mapr/hadoop/hadoop-0.20.2/conf/hadoop-env.sh
psh $parg 'maprcli disk list -output terse -system 0 -host $(hostname)'
psh $parg 'ls /opt/mapr/roles'
[ "$verbose" == "true" ] && psh $parg '/opt/mapr/server/mrconfig dg list | grep -A4 StripeDepth'
[ "$verbose" == "true" ] && $node hadoop conf -dump | sort; echo $sep
[ "$verbose" == "true" ] && $node maprcli config load -json; echo $sep
# TBD:
# check all mapr-* packages installed
# check all hadoop* packages installed

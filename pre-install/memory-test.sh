#!/bin/bash
# jbenning@cisco.com 2012-Jan-19  vi: set ai et sw=3 tabstop=3:
# Run Stream benchmark or mem latency benchmark

D=$(dirname "$0")
abspath=$(cd "$D" 2>/dev/null && pwd || echo "$D")

sockets=$(grep '^physical' /proc/cpuinfo | sort -u | grep -c ^)
cores=$(grep '^cpu cores' /proc/cpuinfo | sort -u | awk '{print $NF}')
thrds=$(grep '^siblings' /proc/cpuinfo | sort -u | awk '{print $NF}')
NAME=$abspath/stream59 #no AVX,just movnt, best Stream build of the 3
#objdump -d $NAME | grep 'movnt.*mm' | head
eval enpath=$(echo /sys/kernel/mm/*transparent_hugepage/enabled)

if [ "$1" == "lat" ]; then
   echo 'Running lat_mem(lmbench) to measure memory latency in nano seconds'
   echo always > $enpath
   taskset 0x1 $abspath/lat_mem_rd -N3 -P1 2048m 513 2>&1
   # Pinned to 1st socket.  Pinning to 2nd socket (0x8) shows slower latency
else
   # To enable/disable hugepages, you must run as root
   echo never > $enpath
   if [ $cores == $thrds ]; then
     $NAME
   else
     OMP_NUM_THREADS=$((cores * sockets)) KMP_AFFINITY=granularity=core,scatter $NAME
   fi
   echo always > $enpath
fi


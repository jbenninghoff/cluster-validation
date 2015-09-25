#!/bin/bash
# jbenninghoff 2012-Jan-19  vi: set ai et sw=3 tabstop=3:
# Run Stream benchmark or mem latency benchmark

sockets=$(grep '^physical' /proc/cpuinfo | sort -u | grep -c ^)
cores=$(grep '^cpu cores' /proc/cpuinfo | sort -u | awk '{print $NF}')
thrds=$(grep '^siblings' /proc/cpuinfo | sort -u | awk '{print $NF}')
scriptdir="$(cd "$(dirname "$0")"; pwd -P)" #absolute path to this script's folder
#objdump -d $scriptdir/stream59

if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
  enpath=/sys/kernel/mm/transparent_hugepage/enabled
elif [ -f /sys/kernel/mm/redhat_transparent_hugepage/enabled ]; then
  enpath=/sys/kernel/mm/redhat_transparent_hugepage/enabled
else
  echo Transparent Huge Page setting not found, performance may be affected
fi

# -t (THP) option to set THP for peak performance
while getopts ":t" opt; do
  case $opt in
    t) thp=setit ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit ;;
  esac
done

if [ -n "$enpath" -a -n "$thp" ]; then # save current THP setting
  # To enable/disable hugepages, you must run as root
  thp=$(cat $enpath | grep -o '\[.*\]')
  thp=${thp#[}; thp=${thp%]} #strip [] brackets off string
fi

if [ "$1" == "lat" ]; then
   #http://www.bitmover.com/lmbench/lat_mem_rd.8.html (also in my evernotes)
   echo 'Running lat_mem(lmbench) to measure memory latency in nano seconds'
   [ -n "$thp" -a $(id -u) -eq 0 ] && echo always > $enpath
   taskset 0x1 $scriptdir/lat_mem_rd -N3 -P1 2048m 513 2>&1
   # Pinned to 1st socket.  Pinning to 2nd socket (0x8) shows slower latency
   [ -n "$thp" -a $(id -u) -eq 0 ] && echo $thp > $enpath
else
   [ -n "$thp" -a $(id -u) -eq 0 ] && echo never > $enpath
   if [ $cores == $thrds ]; then
     $scriptdir/stream59
   else
     OMP_NUM_THREADS=$((cores * sockets)) KMP_AFFINITY=granularity=core,scatter $scriptdir/stream59
   fi
   [ -n "$thp" -a $(id -u) -eq 0 ] && echo $thp > $enpath
fi


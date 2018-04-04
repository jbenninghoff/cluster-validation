#!/bin/bash
#jbenninghoff 2017-Apr-26 vi: set ai et sw=3 tabstop=3 retab
set -o nounset

usage() {
cat << EOF
Usage: $0 -t <int> -r <big int> -m <optional table path> -s <hostlist> -w <workload file> -c -n -T -p -d
-t Thread count (30/client HBase default, 20/client for MapR-DB)
-r Row count (100M default)
-m MapR-DB (using /tables/usertable)
-s Specify comma separated list of YCSB client hostnames
-w Custom workload file (default is auto-generated test-workload.txt)
-c Disable client buffering (client buffering provides best performance)
-n Skip load phase
-T Create table
-p Presplit the table
-d Enable debug

This script runs one YCSB client against an HBase or MapR-DB cluster to
measure throughput and latency.  The output is saved to a log file.

The script can be invoked by clush to run multiple YCSB clients.
To do so, the MapR HBase client and YCSB package must be installed
on all client nodes. A clush group such as 'ycsb' should be defined.
The clush command would be:

clush -b -g ycsb \$PWD/runYCSB.sh -s \$(nodeset -S, -e @ycsb) #plus any other YCSB options needed

Make sure MapR HBase client package, mapr-hbase, is installed on this node and all YCSB client nodes.

YCSB package available here:
https://github.com/brianfrankcooper/YCSB

EOF
}

# Handle script arguments
DBG=''; clients=''; rows=$[100*1000*1000]; threads=30; table=usertable;
cbuff=true; wkld=test-workload.txt load=true; create=false; istart=0; seq=0
presplit=false
while getopts "Tdpncmt:r:s:w:" opt; do
  case $opt in
    d) DBG=true ;;
    c) cbuff=false ;;
    n) load=false ;;
    p) presplit=true ;;
    T) create=true ;;
    m) table=/benchmarks/usertable; threads=20; echo Using $table ;;
    t) [[ "$OPTARG" =~ ^[0-9]+$ ]] && threads=$OPTARG || { echo $OPTARG is not an number; exit; } ;;
    r) [[ "$OPTARG" =~ ^[0-9]+$ ]] && rows=$OPTARG || { echo $OPTARG is not an number; exit; } ;;
    s) [[ "$OPTARG" =~ .*,.* ]] && clients=$OPTARG || { echo $OPTARG is not a host list; exit; } ;;
    w) [[ -n "$OPTARG" ]] && { wkld=$OPTARG; echo Using $wkld; } ;;
    \?) usage; exit ;;
  esac
done
[ -n "$DBG" ] && { echo clients: $clients, rows: $rows, threads: $threads, table: $table, wkld: $wkld, load: $load, cbuff: $cbuff; sleep 3; }

# Set up some variables
setvars() {
   hostcount=1
   thishost=$(hostname -s)
   opcount=$[rows/hostcount]
   if [ -n "$clients" ]; then
      hostarray=(${clients//,/ })
      hostcount=${#hostarray[@]}
      opcount=$[rows/hostcount]
      i=0
      for host in ${hostarray[@]}; do
         [ "$host" == "$thishost" ] && { istart=$[opcount*i]; seq=$i; }
         ((i++))
      done
   fi
   [ $[$opcount / (1000)] -gt 0 ] && mag=$[$opcount / (1000)]K
   [ $[$opcount / (1000*1000)] -gt 0 ] && mag=$[$opcount / (1000*1000)]M
   [ $[$opcount / (1000*1000*1000)] -gt 0 ] && mag=$[$opcount / (1000*1000*1000)]B
   ycsbdir=/home/mapr/cluster-validation/post-install/ycsb-0.12.0
   ycsbargs="-s -P $wkld -threads $threads -p table=$table "
   ycsbargs+=" -p clientbuffering=$cbuff -p recordcount=$rows"
   ycsbargs+=" -p operationcount=$opcount -cp $(hbase classpath)"
   tmpdate=$(date '+%Y-%m-%dT%H+%M')
   teelog="ycsb-${threads}T-$thishost-$seq-$mag-${table//\//-}-$tmpdate"
   #export JAVA_CLASSPATH=$(hbase classpath) #YCSB insists on -cp 
}
setvars

[ -n "$DBG" ] && { echo bin/ycsb run hbase10 $ycsbargs -p insertcount=$opcount -p insertstart=$istart  tee $teelog; exit; }

#Create table if requested
if [ "$create" == "true" ]; then
   hbase shell <<< "disable '$table'; drop '$table'"
   if [ "$presplit" == "true" ]; then
      hbase shell <<-EOF
         #nreg=64 #num of regions
         #keyrange=9.999999E18 #Max row key value
         #regsize=keyrange/nreg #Region size
         #splits=(1..nreg-1).map {|i| "user#{sprintf '%019d', i*regsize}"}
         nreg=71; keyrange=9.999999E18; regsize=keyrange/nreg #Based 100M rows, ~64 used regions
         splits=(8..nreg-1).map {|i| "user#{sprintf '%019d', i*regsize}"} #zero padded keys do not appear to be used by YCSB
         create '$table', {NAME=>'family',COMPRESSION=>'none',IN_MEMORY=>'true'}, SPLITS => splits
EOF
   else
      hbase shell <<-EOF2
         # Simple table for MapR-DB
         create '$table', {NAME=>'family',IN_MEMORY=>'true'}
         #create '$table',{NAME=>'family',COMPRESSION=>'none',IN_MEMORY=>'true'}
EOF2
   fi
fi

#Check for table
gs1='is not a MapRDB'
gs2='does not exist'
if (hbase shell <<< "exists '$table'" |grep -q -e "$gs1" -e "$gs2"); then
   echo Table Does Not Exist; exit 2
fi

#Generate a workload file
cd $ycsbdir
cat <<EOF3 >test-workload.txt
workload=com.yahoo.ycsb.workloads.CoreWorkload

#100M rows, 5x500 byte row length(2.5K) ~= 250GB data set
recordcount=$rows
fieldlength=500
fieldcount=5
columnfamily=family
insertstart=$istart
insertcount=$opcount
#must be here due to ycsb bug. Will specify to YCSB CLI.
# 0 means run forever
operationcount=$opcount

#Op proportions
readproportion=0.0
scanproportion=0.0
insertproportion=0.0
updateproportion=1.0
#caution: insert changes size of db which makes comparisons across 
#runs impossible. Use with caution. Since the work of an update is
#identical to insert we recommend not using insert.
#readmodifywriteproportion=0.05

#distribution
#readallfields=true
requestdistribution=zipfian
maxscanlength=100
scanlengthdistribution=uniform
EOF3

[ -n "$DBG" ] && { echo bin/ycsb run hbase10 $ycsbargs -p insertcount=$opcount -p insertstart=$istart  tee $teelog; exit; }

#YCSB load phase
if [ "$load" == "true" ]; then
   teelog1=${teelog}-load.log
   bin/ycsb load hbase10 $ycsbargs -p insertcount=$opcount -p insertstart=$istart |& tee $teelog1
fi

#YCSB run phase
teelog2=${teelog}-run.log
bin/ycsb run hbase10 $ycsbargs |& tee $teelog2

#teelog3=${teelog}-run2.log
#bin/ycsb run hbase10 $ycsbargs |& tee $teelog3


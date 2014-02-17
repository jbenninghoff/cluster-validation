#!/bin/bash
# jbenninghoff@maprtech.com 2013-Sep-13  vi: set ai et sw=3 tabstop=3:

# The YCSB package must be downloaded and extracted
# https://github.com/mapr/YCSB
#
# Create a MapR volume for the tables
#maprcli volume create -name tables -path /tables -topology /data/default-rack -replication 3 -replicationtype low_latency 
#hadoop mfs -setcompression off /tables

table=/tables/usertable  #YCSB uses a table called usertable

hbase shell <<EOF
disable '$table'
drop '$table'
create '$table','family'
#for i in 'a'..'z' do for j in 'a'..'z' do put 'usertable', "row-#{i}#{j}", "family:#{j}", "#{j}" end end
#scan 'TestTable', {LIMIT=>10}
EOF

# Run workloada through workloadd as defined by YCSB in the workloads folder
# Each workload requires the dataset to be loaded and the test run (-t)
export HBASE_CLASSPATH=core/lib/core-0.1.4.jar:hbase-binding/lib/hbase-binding-0.1.4.jar
[ -f workloads/workloada ] || { echo YCSB workloads not found; exit 1; }
hbase com.yahoo.ycsb.Client -db com.yahoo.ycsb.db.HBaseClient -P workloads/workloada -threads 4 -p columnfamily=family -p recordcount=100000000 -load |tee ycsb-bigKey-wkldA-100M-load.log
hbase com.yahoo.ycsb.Client -db com.yahoo.ycsb.db.HBaseClient -P workloads/workloada -threads 4 -p columnfamily=family -p recordcount=100000000 -t |tee ycsb-bigKey-wkldA-100M-run.log

hbase com.yahoo.ycsb.Client -db com.yahoo.ycsb.db.HBaseClient -P workloads/workloadb -threads 4 -p columnfamily=family -p recordcount=100000000 -load |tee ycsb-bigKey-wkldB-100M-load.log
hbase com.yahoo.ycsb.Client -db com.yahoo.ycsb.db.HBaseClient -P workloads/workloadb -threads 4 -p columnfamily=family -p recordcount=100000000 -t |tee ycsb-bigKey-wkldB-100M-run.log

hbase com.yahoo.ycsb.Client -db com.yahoo.ycsb.db.HBaseClient -P workloads/workloadc -threads 4 -p columnfamily=family -p recordcount=100000000 -load |tee ycsb-bigKey-wkldC-100M-load.log
hbase com.yahoo.ycsb.Client -db com.yahoo.ycsb.db.HBaseClient -P workloads/workloadc -threads 4 -p columnfamily=family -p recordcount=100000000 -t |tee ycsb-bigKey-wkldC-100M-run.log

hbase com.yahoo.ycsb.Client -db com.yahoo.ycsb.db.HBaseClient -P workloads/workloadd -threads 4 -p columnfamily=family -p recordcount=100000000 -load |tee ycsb-bigKey-wkldD-100M-load.log
hbase com.yahoo.ycsb.Client -db com.yahoo.ycsb.db.HBaseClient -P workloads/workloadd -threads 4 -p columnfamily=family -p recordcount=100000000 -t |tee ycsb-bigKey-wkldD-100M-run.log

columns=$(stty -a | awk '/columns/{printf "%d\n",$7}')
/opt/mapr/bin/maprcli table region list -path $table | cut -c -$columns
./regionsp.py $table

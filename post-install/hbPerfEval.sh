#!/bin/bash
# jbenninghoff@maprtech.com 2013-Sep-13  vi: set ai et sw=3 tabstop=3:

#maprcli volume create -name tables -path /tables -topology /data/default-rack -replication 3 -replicationtype low_latency 
#hadoop mfs -setcompression off /tables

/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation --nomapred sequentialWrite 4 |& tee hbasePerfEvalSeqWrite.log
/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation sequentialWrite 20 |& tee hbasePerfEvalSeqWrite20P.log
/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation --nomapred randomWrite 4 |& tee hbasePerfEvalRanWrite.log
/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation randomWrite 20 |& tee hbasePerfEvalRanWrite20P.log
/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation --nomapred sequentialRead 4 |& tee hbasePerfEvalSeqRead.log
/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation sequentialRead 20 |& tee hbasePerfEvalSeqRead20P.log
/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation --nomapred randomRead 4 |& tee hbasePerfEvalRanRead.log
/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation randomRead 20 |& tee hbasePerfEvalRanRead20P.log
# Very time consuming tests:
#/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation --nomapred randomSeekScan 4 |& tee hbasePerfEvalRanSeekScan.log
#/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation randomSeekScan 20 |& tee hbasePerfEvalRanSeekScan20P.log
#/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation --nomapred scanRange1000 4 |& tee hbasePerfEvalScanRange1K.log
#/usr/bin/time hbase org.apache.hadoop.hbase.PerformanceEvaluation scanRange1000 20 |& tee hbasePerfEvalScanRange1K20P.log

table=/tables/TestTable

hbase shell <<EOF
scan '$table', {LIMIT=>30}
EOF

columns=$(stty -a | awk '/columns/{printf "%d\n",$7}')
/opt/mapr/bin/maprcli table region list -path $table | cut -c -$columns
./regionsp.py $table

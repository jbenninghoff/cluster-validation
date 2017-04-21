#!/bin/bash
# jbenninghoff 2017-Apr-14  vi: set ai et sw=3 tabstop=3:

tsjar=spark-terasort-1.1-SNAPSHOT.jar
tsjar=spark-terasort-1.1-SNAPSHOT-jar-with-dependencies.jar
PATH=/opt/mapr/spark/spark-1.6.1/bin:$PATH

spark-submit --master yarn-client \
  --name 'TeraGen' \
  --class com.github.ehiggs.spark.terasort.TeraGen \
  --num-executors 10 \
  --executor-cores 1 \
  --executor-memory 1500M \
  $tsjar 50G /user/$USER/spark-terasort

: << '--BLOCK-COMMENT--'
exit
--BLOCK-COMMENT--

export DRIVER_MEMORY=1g
spark-submit --master yarn-cluster \
  --name 'TeraSort' \
  --class com.github.ehiggs.spark.terasort.TeraSort \
  --num-executors 5 \
  --executor-cores 2 \
  --executor-memory 4G \
  $tsjar /user/$USER/spark-terasort /user/$USER/terasort-output

#  --conf 'spark.driver.extraClassPath=/opt/mapr/lib/libprotodefs-4.0.1-mapr.jar:/opt/mapr/lib/protobuf-java-2.5.0.jar:/opt/mapr/lib/guava-13.0.1.jar' \
#  --class org.apache.spark.examples.terasort.TeraGen \
# --conf 'mapreduce.terasort.num.partitions=5' \
# --spark.driver.extraJavaOptions -Dspark.driver.port=40880 \
# --driver-java-options=-Dspark.driver.port=40880 \ #FW hole didn't work

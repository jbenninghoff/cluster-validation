#!/bin/bash
# jbenninghoff 2017-Apr-14  vi: set ai et sw=3 tabstop=3:

vcores=$(maprcli dashboard info -json |awk -F: '/total_vcores/{printf("%i\n", $2)}')
vram=$(maprcli dashboard info -json |awk -F: '/total_memory_mb/{printf("%i\n", $2)}')
vtasks=$((vram/4096))
ecores=$((vcores/vtasks))
[[ "$ecores" -eq 0 ]] && ecores=1
tsjar=spark-terasort-1.1-SNAPSHOT-jar-with-dependencies.jar
tsjar=spark-terasort-1.1-SNAPSHOT.jar
#PATH=/opt/mapr/spark/spark-1.6.1/bin:$PATH
spkhome=$(find /opt/mapr/spark -maxdepth 1 -type d -name spark-\* \
         |sort -n |tail -1)
PATH=$spkhome/bin:$PATH
#spkjar=$(find $spkhome -name spark-examples\*.jar)
#spkclass=org.apache.spark.examples.SparkPi

#spark-submit --master yarn-client \
spark-submit --master yarn --deploy-mode cluster \
  --name 'TeraGen' \
  --class com.github.ehiggs.spark.terasort.TeraGen \
  --num-executors 10 \
  --executor-cores 1 \
  --executor-memory 1500M \
  $tsjar 50G /user/$USER/spark-terasort
# Small 50G test to verify all is in order, increase to 1T or more
# Move block comment line up to skip TeraGen once data is created

: << '--BLOCK-COMMENT--'
exit
  --executor-cores 4
  --executor-memory 16G
--BLOCK-COMMENT--

#export DRIVER_MEMORY=1g
#spark-submit --master yarn-cluster \
spark-submit --master yarn --deploy-mode client --driver-memory 1g \
  --name 'TeraSort' \
  --class com.github.ehiggs.spark.terasort.TeraSort \
  --num-executors $vtasks \
  --executor-cores $ecores \
  --executor-memory 4G \
  $tsjar /user/$USER/spark-terasort /user/$USER/terasort-output
#Many small executors seems to perform better than fewer large executors

#  --conf 'spark.driver.extraClassPath=/opt/mapr/lib/libprotodefs-4.0.1-mapr.jar:/opt/mapr/lib/protobuf-java-2.5.0.jar:/opt/mapr/lib/guava-13.0.1.jar' \
# --class org.apache.spark.examples.terasort.TeraGen \
# --conf 'mapreduce.terasort.num.partitions=5' \
# --spark.driver.extraJavaOptions -Dspark.driver.port=40880 \
# --driver-java-options=-Dspark.driver.port=40880 \ #FW hole didn't work

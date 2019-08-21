#!/bin/bash
# Quick smoke-test for Spark on Yarn using builtin example code

# Check UID
[[ $(id -u) -eq 0 ]] && { echo This script must be run as non-root; exit 1; }
if [[ -f /opt/mapr/conf/daemon.conf ]]; then                                    
   srvid=$(awk -F= '/mapr.daemon.user/{print $2}' /opt/mapr/conf/daemon.conf)
fi
if [[ "$srvid" == $(id -un) ]]; then
   echo "This script should be run as a non service ($srvid) account"
fi

spkhome=$(find /opt/mapr/spark -maxdepth 1 -type d -name spark-\* \
         |sort -n |tail -1)
spkjar=$(find "$spkhome" -name spark-examples\*.jar)
# JavaWordCount requires script arg to be an existing file in maprfs:///
spkclass=org.apache.spark.examples.JavaWordCount
spkclass=org.apache.spark.examples.SparkPi
#spkdrv=$(hostname -i)
#$spkhome/bin/spark-submit --conf spark.driver.host=$spkdrv \

"$spkhome/bin/spark-submit" \
   --master yarn \
   --deploy-mode client \
   --class $spkclass \
   "$spkjar" "${1:-40}"

# Cluster mode, use sparkhistory logs to view stdout
#$spkhome/bin/spark-submit --master yarn --deploy-mode cluster \
#   --class $spkclass $spkjar 40

# /opt/mapr/hadoop/hadoop-2.7.0/bin/yarn logs -applicationId application_1469809164296_0036 |awk '/^LogType:stdout/,/^End of LogType:stdout/' #Look for Pi answer 3.14....

# /opt/mapr/spark-1.6.1-bin-without-hadoop/bin/spark-submit --driver-java-options="-Dmylevel=WARN" --driver-library-path /opt/mapr/spark-1.6.1-bin-without-hadoop/lib --master yarn-client --class org.apache.spark.examples.SparkPi /opt/mapr/spark-1.6.1-bin-without-hadoop/lib/spark-examples-1.6.1-hadoop2.2.0.jar 40 #log4j filter by setting mylevel
# log4j setting to pass runtime level as shown above: /opt/mapr/spark-1.6.1-bin-without-hadoop/conf/log4j.properties:log4j.appender.console.threshold=${mylevel}

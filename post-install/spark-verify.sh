#!/bin/bash
# Quick smoke-test for MapReduce on Yarn using builtin example code

# Check UID
[[ $(id -u) -eq 0 ]] && { echo This script must be run as non-root; exit 1; }
if [[ -f /opt/mapr/conf/daemon.conf ]]; then                                    
   srvid=$(awk -F= '/mapr.daemon.user/{print $2}' /opt/mapr/conf/daemon.conf)
fi
if [[ "$srvid" == $(id -un) ]]; then
   echo This script should be run as non-service-account
fi

#readarray -t factors < <(maprcli dashboard info -json | \
#  grep -e num_node_managers -e total_disks | grep -o '[0-9]*')
#nmaps=$(( ${factors[0]} * ${factors[1]} ))
#exjar=$(eval echo /opt/mapr/hadoop/hadoop-2*)
#exjar+=/share/hadoop/mapreduce/
#exjar+=hadoop-mapreduce-examples-2.7.0-mapr-1803.jar

sphome=$(eval echo /opt/mapr/spark/spark-2.*)
spclass=org.apache.spark.examples.SparkPi
spjar=$(eval echo $sphome/lib/spark-examples-*.jar)
$sphome/bin/spark-submit --master yarn-cluster --class $spclass $spjar 40

# /opt/mapr/hadoop/hadoop-2.7.0/bin/yarn logs -applicationId application_1469809164296_0036 |awk '/^LogType:stdout/,/^End of LogType:stdout/' #Look for Pi answer 3.14....
$sphome/bin/spark-submit --master yarn-client --class $spclass $spjar 40

# /opt/mapr/spark-1.6.1-bin-without-hadoop/bin/spark-submit --driver-library-path /opt/mapr/spark-1.6.1-bin-without-hadoop/lib --master yarn-client --class org.apache.spark.examples.SparkPi /opt/mapr/spark-1.6.1-bin-without-hadoop/lib/spark-examples-1.6.1-hadoop2.2.0.jar 40
# /opt/mapr/spark-1.6.1-bin-without-hadoop/bin/spark-submit --driver-java-options="-Dmylevel=WARN" --driver-library-path /opt/mapr/spark-1.6.1-bin-without-hadoop/lib --master yarn-client --class org.apache.spark.examples.SparkPi /opt/mapr/spark-1.6.1-bin-without-hadoop/lib/spark-examples-1.6.1-hadoop2.2.0.jar 40 #log4j filter by setting mylevel
# log4j setting to pass runtime level as shown above: /opt/mapr/spark-1.6.1-bin-without-hadoop/conf/log4j.properties:log4j.appender.console.threshold=${mylevel}

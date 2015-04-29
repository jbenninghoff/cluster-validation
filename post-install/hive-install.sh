#!/bin/bash

# Script to install and configure Hive
[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }

yum -y install mapr-hive mapr-hivemetastore mapr-hiveserver2 mapr-pig
ln -s /opt/mapr/lib/mysql-connector-java-5.*-bin.jar /opt/mapr/hive/hive-0.13/lib/
chmod 755 /opt/mapr/lib/mysql-connector-java-5.*-bin.jar
#yum -y install mysql-connector-java


cat - <<EOF > /opt/mapr/hive/hive-0.13/conf/hive-site.xml
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<!--
   Licensed to the Apache Software Foundation (ASF) under one or more
   contributor license agreements.  See the NOTICE file distributed with
   this work for additional information regarding copyright ownership.
   The ASF licenses this file to You under the Apache License, Version 2.0
   (the "License"); you may not use this file except in compliance with
   the License.  You may obtain a copy of the License at
       http://www.apache.org/licenses/LICENSE-2.0
   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-->

<configuration>
<!-- Hive client, metastore and server configuration all contained in this config file as of Hive 0.13 -->

<!-- Client Configuration ========================  -->
 <property>
    <name>hive.metastore.uris</name>
    <description>Use blank(no value) to enable local metastore, use a URI to connect to a 'remote'(networked) metastore.</description>
    <value>thrift://maprnode1:9083</value>
 </property>

<!-- MetaStore Configuration ========================  -->
<!-- https://cwiki.apache.org/confluence/display/Hive/Configuration+Properties#ConfigurationProperties-MetaStore -->
<property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:mysql://maprnode1:3306/hive?createDatabaseIfNotExist=true</value>
    <description>JDBC connect string for a JDBC metastore such as MySQL</description>
</property>
 
 <property>
    <name>javax.jdo.option.ConnectionDriverName</name>
    <value>com.mysql.jdbc.Driver</value>
    <description>Driver class name for a JDBC metastore</description>
 </property>
 
 <property>
    <name>javax.jdo.option.ConnectionUserName</name>
    <value>mapr</value>
    <description>username to use against metastore database</description>
 </property>
 
 <property>
    <name>javax.jdo.option.ConnectionPassword</name>
    <value>mapr</value>
    <description>password to use against metastore database</description>
 </property>
 
<property>
  <name>hive.metastore.execute.setugi</name>
  <value>true</value>
  <description>Set this property to enable Hive Metastore service impersonation in unsecure mode. In unsecure mode, setting this property to true will cause the metastore to execute DFS operations using the client's reported user and group permissions. Note that this property must be set on both the client and server sides. Further note that its best effort. If client sets its to true and server sets it to false, client setting will be ignored.</description>
</property>


<!-- Hive Server Configuration ========================  -->
<!-- https://cwiki.apache.org/confluence/display/Hive/Configuration+Properties#ConfigurationProperties-HiveServer2 -->
<property>
   <name>hive.server2.thrift.port</name>
   <value>10001</value>
   <description>TCP port number for Hive Server to listen on, default 10000, conflict with webmin</description>
</property>

<property>
  <name>hive.server2.enable.impersonation</name>
  <value>true</value>
  <description>Set this property to enable impersonation in Hive Server 2, not in above URL?</description>
</property>

<property>
  <name>hive.server2.enable.doAs</name>
  <value>true</value>
  <description>Set this property to enable impersonation in Hive Server 2</description>
</property>


<!-- Misc Configuration ========================  -->
<!-- commented out
<property>
  <name>hive.support.concurrency</name>
  <description>Enable Hive's Table Lock Manager Service, requires zookeeper config</description>
  <value>true</value>
</property>
 
<property>
  <name>hive.zookeeper.quorum</name>
  <description>Zookeeper quorum used by Hive's Table Lock Manager</description>
  <value>evlbigdata04,evlbigdata05,evlbigdata06</value>
</property>
 
<property>
  <name>hive.zookeeper.client.port</name>
  <value>5181</value>
  <description>The Zookeeper client port. The MapR default clientPort is 5181.</description>
</property>
<property>
  <name>datanucleus.autoCreateSchema</name>
  <value>true</value>
</property>
<property>
  <name>datanucleus.autoCreateTables</name>
  <value>true</value>
</property>
<property>
  <name>datanucleus.autoCreateColumns</name>
  <value>true</value>
</property>
<property>
  <name>datanucleus.fixedDatastore</name>
  <value>false</value>
</property>
<property>
  <name>datanucleus.autoStartMechanism</name>
  <value>SchemaTable</value>
</property>
-->

</configuration>

EOF

/opt/mapr/server/configure.sh -R

maprcli node services -name hivemeta -action start -nodes maprnode1
maprcli node services -name hs2 -action start -nodes maprnode1

hadoop fs -mkdir /user/hive
hadoop fs -chmod 0777 /user/hive
hadoop fs -mkdir /user/hive/warehouse
hadoop fs -chmod 1777 /user/hive/warehouse  #accessible to all but can only delete own files
hadoop fs -mkdir /tmp
hadoop fs -chmod 777 /tmp

echo Run hive-verify.sh as non-root user next.

#cp /opt/mapr/hive/hive-0.13/conf/hive-log4j.properties.template /opt/mapr/hive/hive-0.13/conf/hive-log4j.properties
#vi /opt/mapr/hive/hive-0.13/conf/hive-log4j.properties
#hive.log.dir=/tmp/hive/benningj
#mkdir -p /tmp/hive/benningj
#chmod 777 /tmp/hive/benningj
#chmod 777 /tmp/hive

#hadoop fs -ls || { echo Hive requires user directory, directory not found; exit 1; }
#hadoop fs -mkdir /user/$(id -un) && sudo hadoop fs -chown $(id -un):$(id -gn) /user/$(id -un)

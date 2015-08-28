#!/bin/bash
# nestrada 2015-May-1

[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }

usage() {
  echo "Usage: $0 <mysql hostname> <metastore hostname> <hiveserver2 hostname>"
  echo Hostname groups not found in clustershell groups configuration file
  echo Provide all required hostnames for installation.
  exit 2
}

nodeset -e @mysql || usage
nodeset -e @hivemeta || usage
nodeset -e @hs2 || usage

# Configure clush groups
grep '## AUTOGEN-HIVE ##' /etc/clustershell/groups >/dev/null 2>&1
if [ "$?" != "0" ] ; then
  cat - <<EOF >> /etc/clustershell/groups
## AUTOGEN-HIVE ##
mysql: $(nodeset -e @mysql)
hivemeta: $(nodeset -e @hivemeta)
hs2: $(nodeset -e @hs2)
EOF
fi

#install mysql, hive, hive metastore, and hiveserver2
clush -g mysql "yum install -y mysql-server"
clush -g hivemeta "yum install -y mapr-hive  mapr-hivemetastore mysql"
clush -g hs2 "yum install -y mapr-hiveserver2 mysql"

#initial mysql configuration
clush -g mysql "service mysqld start"
#set mysql root password
ROOT_PASSWORD=mapr
clush -g mysql "mysqladmin -u root password $ROOT_PASSWORD"

#node variables needed for mysql and  hive-site.xml configuration
MYSQL_NODE=$(nodeset -e @mysql)
METASTORE_NODE=$(nodeset -e @hivemeta)
HS2_NODE=$(nodeset -e @hs2)
ZK_NODES=$(nodeset -S, -e @zk)

#set up mysql database and user
DATABASE=hive
USER=hive
PASSWORD=mapr

clush -g mysql mysql -u root -p$ROOT_PASSWORD << EOF
create database $DATABASE;
create user '$USER'@'%' identified by '$PASSWORD';
grant all privileges on $DATABASE.* to '$USER'@'%' with grant option;
create user '$USER'@'localhost' IDENTIFIED BY '$PASSWORD';
grant all privileges on $DATABASE.* to '$USER'@'localhost' with grant option;
create user '$USER'@'$METASTORE_NODE' IDENTIFIED BY '$PASSWORD';
grant all privileges on $DATABASE.* to '$USER'@'$METASTORE_NODE' with grant option;
create user '$USER'@'$HS2_NODE' IDENTIFIED BY '$PASSWORD';
grant all privileges on $DATABASE.* to '$USER'@'$HS2_NODE' with grant option;
flush privileges;
EOF

# The driver for the MySQL JDBC connector (a jar file) is part of the MapR distribution under /opt/mapr/lib/.
# Link this jar file into the Hive lib directory.
clush -g mysql "ln -s /opt/mapr/lib/mysql-connector-java-5.1.25-bin.jar /opt/mapr/hive/hive-0.13/lib/mysql-connector-java-5.1.25-bin.jar"

#create or modify the hive-site.xml
clush -g hivemeta,hs2 "cat - > /opt/mapr/hive/hive-0.13/conf/hive-site.xml" <<EOF
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
    <value>thrift://$METASTORE_NODE:9083</value>
</property>

<!-- MetaStore Configuration ========================  -->
<!-- https://cwiki.apache.org/confluence/display/Hive/Configuration+Properties#ConfigurationProperties-MetaStore -->
<property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:mysql://$MYSQL_NODE:3306/hive?createDatabaseIfNotExist=true</value>
    <description>JDBC connect string for a JDBC metastore</description>
</property>

<property>
    <name>javax.jdo.option.ConnectionDriverName</name>
    <value>com.mysql.jdbc.Driver</value>
    <description>Driver class name for a JDBC metastore</description>
</property>

<property>
    <name>javax.jdo.option.ConnectionUserName</name>
    <value>$USER</value>
    <description>username to use against metastore database</description>
</property>

<property>
    <name>javax.jdo.option.ConnectionPassword</name>
    <value>$PASSWORD</value>
    <description>password to use against metastore database</description>
</property>

<property>
    <name>hive.metastore.uris</name>
    <value>thrift://$METASTORE_NODE:9083</value>
</property>

<property>
  <name>hive.metastore.execute.setugi</name>
  <value>true</value>
  <description> Set this property to enable Hive Metastore service impersonation in unsecure mode.
   In unsecure mode, setting this property to true causes the metastore to execute DFS operations
   using the client's reported user and group permissions. Note that this property must be set on
   BOTH the client and server sides. </description>
</property>

<!-- Hive Server2 Configuration ========================  -->
<!-- https://cwiki.apache.org/confluence/display/Hive/Configuration+Properties#ConfigurationProperties-HiveServer2 -->
<property>
    <name>hive.server2.authentication</name>
    <value>PAM</value>
</property>

<property>
    <name>hive.server2.authentication.pam.services</name>
    <value>login,sudo</value>
    <description>comma separated list of pam modules to verify</description>
</property>

<property>
   <name>hive.server2.thrift.port</name>
   <value>10000</value>
   <description>TCP port number for Hive Server to listen on, default 10000, conflicts with webmin</description>
</property>

<property>
  <name>hive.server2.enable.impersonation</name>
  <value>true</value>
  <description>Set this property to enable impersonation in Hive Server 2, not in cwiki URL?</description>
</property>

<property>
  <name>hive.server2.enable.doAs</name>
  <value>true</value>
  <description>Set this property to enable impersonation in Hive Server 2</description>
</property>

<!-- Misc Configuration ========================  -->
<property>
  <name>hive.support.concurrency</name>
  <value>true</value>
  <description>Enable Hive's Table Lock Manager Service</description>
</property>

<property>
  <name>hive.zookeeper.quorum</name>
  <value>$ZK_NODES</value>
  <description>Zookeeper quorum used by Hive's Table Lock Manager</description>
</property>

<property>
  <name>hive.zookeeper.client.port</name>
  <value>5181</value>
  <description>The Zookeeper client port. The MapR default clientPort is 5181.</description>
</property>

<!-- Commented out by default
<property>
    <name>hive.security.authorization.enabled</name>
    <name>false</name>
    <description>Enable for secure MapR clusters</description>
</property>

<property>
    <name>hive.security.authorization.manager</name>
    <value>org.apache.hadoop.hive.ql.security.authorization.StorageBasedAuthorizationProvider</value>
</property>

<property>
    <name>hive.metastore.pre.event.listeners</name>
    <value>org.apache.hadoop.hive.ql.security.authorization.AuthorizationPreEventListener</value>
</property>

<property>
    <name>hive.security.metastore.authorization.manager</name>
    <value>org.apache.hadoop.hive.ql.security.authorization.StorageBasedAuthorizationProvider</value>
</property>

<property>
  <name>hive.optimize.insert.dest.volume</name>
  <value>true</value>
  <description>For CREATE TABLE AS and INSERT queries create the scratch directory under the destination directory. This avoids the data move across volumes and improves performance.</description>
</property>
-->

</configuration>
EOF

clush -a "/opt/mapr/server/configure.sh -R"

sleep 5

#stop and start Metastore and HiveServer2
maprcli node services -name hivemeta -action start -nodes $METASTORE_NODE
maprcli node services -name hs2 -action start -nodes $HS2_NODE

hadoop fs -mkdir /user/hive
hadoop fs -chmod 0777 /user/hive
hadoop fs -mkdir /user/hive/warehouse
hadoop fs -chmod 1777 /user/hive/warehouse  #accessible to all but can only delete own files
hadoop fs -mkdir /tmp
hadoop fs -chmod 1777 /tmp

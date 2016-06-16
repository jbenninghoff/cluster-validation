#!/bin/bash
# nestrada 2015-May-1

[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }
[ type clush >/dev/null 2>&1 ] || { echo clush required for install; exit 3; }

usage() {
  echo "Usage: $0 <mysql hostname> <hiveserver2 hostname> <metastore hostname>"
  echo Provide all required hostnames for installation, metastore optional
  exit 2
}

[ $# -ne 2 ] && usage

# Configure clush groups
grep ^mysql: /etc/clustershell/groups || echo mysql: $1 >> /etc/clustershell/groups
grep ^hs2: /etc/clustershell/groups || echo hs2: $2 >> /etc/clustershell/groups
grep ^hivemeta: /etc/clustershell/groups || echo hivemeta: $3 >> /etc/clustershell/groups

# when is metastore service (vs embedded metastore class) actually needed?
# metastore service provides shared MySQL account access
# See http://doc.mapr.com/display/MapR/Hive
# Install mysql, hive, hive metastore, and hiveserver2
clush -g mysql "yum install -y mysql-server"
clush -g hs2 "yum install -y mapr-hiveserver2 mapr-hive mysql"
clush -g hivemeta "yum install -y mapr-hivemetastore mapr-hive mysql"
# Capture latest installed Hive version/path
hivepath=$(ls /opt/mapr/hive -c1 | sort -n | tail -1 | xargs -i echo /opt/mapr/hive/{})
#TBD: check /opt/mapr/conf/env for HIVE/SASL settings

#initial mysql configuration
clush -g mysql "service mysqld start"
#set mysql root password
ROOT_PASSWORD=mapr
clush -g mysql "mysqladmin -u root password $ROOT_PASSWORD"

#node variables needed for mysql and  hive-site.xml configuration
MYSQL_NODE=$(nodeset -e @mysql)
METASTORE_NODE=$(nodeset -e @hivemeta)
METASTORE_URI=thrift://$METASTORE_NODE:9083
METASTORE_URI='' #Set to empty value to use embedded metastore class
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
clush -g mysql "ln -s /opt/mapr/lib/mysql-connector-java-5.1.*-bin.jar $hivepath/lib/"

#create or modify the hive-site.xml
clush -g hivemeta,hs2 "cat - > $hivepath/conf/hive-site.xml" <<EOF
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
    <value>thrift://$METASTORE_NODE:9083</value>
    <description>Use blank(no value) to enable local metastore, use a URI to connect to a 'remote'(networked) metastore.</description>
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

<!-- SASL configuration on secure cluster, uncomment sasl property and comment out setugi property

<property>
  <name>hive.metastore.sasl.enabled</name>
  <value>true</value>
  <description> Set this property to enable Hive Metastore SASL on secure cluster
  </description>
</property>

-->

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
<!-- TBD: add settings for authentication on secure cluster -->
<property>
    <name>hive.server2.authentication</name>
    <value>PAM</value>
</property>

<property>
    <name>hive.server2.authentication.pam.services</name>
    <value>login,sudo,sshd</value>
    <description>comma separated list of pam modules to verify</description>
</property>

<property>
   <name>hive.server2.thrift.port</name>
   <value>10000</value>
   <description>TCP port number for Hive Server to listen on, default 10000, conflicts with webmin</description>
</property>

<property>
  <name>hive.server2.enable.doAs</name>
  <value>true</value>
  <description>Set this property to enable impersonation in Hive Server 2</description>
</property>

<!-- This value appears to be obsolete
<property>
  <name>hive.server2.enable.impersonation</name>
  <value>true</value>
  <description>Set this property to enable impersonation in Hive Server 2, not in cwiki URL?</description>
</property>
-->

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
Use these 3 settings in MapR secure cluster mode
<property><name>hive.server2.use.SSL</name><value>false</value> </property>
<property><name>hive.server2.keystore.path</name><value>/opt/mapr/conf/ssl_keystore</value></property>
<property><name>hive.server2.keystore.password</name><value>ChangeMe</value></property>

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
    <name>hive.security.metastore.authorization.manager</name>
    <value>org.apache.hadoop.hive.ql.security.authorization.StorageBasedAuthorizationProvider</value>
</property>

<property>
    <name>hive.metastore.pre.event.listeners</name>
    <value>org.apache.hadoop.hive.ql.security.authorization.AuthorizationPreEventListener</value>
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

echo Run hive-verify.sh as non-root user next.


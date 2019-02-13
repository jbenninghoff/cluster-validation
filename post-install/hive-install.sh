#!/bin/bash
# jbenninghoff 2014-Aug-24  vi: set ai et sw=3 ts=3:

[[ $(id -u) -ne 0 ]] && { echo This script must be run as root; exit 1; }
type clush >/dev/null 2>&1 || { echo clush required for install; exit 3; }

usage() {
  echo "Usage: $0 <mysql hostname> <hiveserver2 hostname> <metastore hostname>"
  echo Provide all required hostnames for installation, metastore optional
  exit 2
}
[[ $# -ne 3 ]] && usage

# Configure clush groups
clush_grps() {
   clgrps=/etc/clustershell/groups
   clgrps=/etc/clustershell/groups.d/local.cfg
   grep ^mysql: $clgrps || echo mysql: $1 >> $clgrps
   grep ^hs2: $clgrps || echo hs2: $2 >> $clgrps
   grep ^hivemeta: $clgrps || echo hivemeta: $3 >> $clgrps
   tail $clgrps
   read -p "Press enter to continue or ctrl-c to abort"
}
clush_grps

# Install all Hive RPMs
hive_rpms() {
   # Embedded metastore class (without service) requires multiple MySQL accts
   # Metastore service provides single (shared) MySQL account access
   # See http://doc.mapr.com/display/MapR/Hive
   # Install hive, hive metastore, and hiveserver2
   clush -g hs2 "yum install -y mapr-hiveserver2 mapr-hive mysql"
   clush -g hivemeta "yum install -y mapr-hivemetastore mapr-hive mysql"
   clush -g all "yum install -y mapr-hive"
   # Capture latest installed Hive version/path
   hivepath=$(ls /opt/mapr/hive/hive-* -dC1 | sort -n | tail -1)
   #TBD: check /opt/mapr/conf/env for HIVE/SASL settings
   echo hivepath: $hivepath
   read -p "Press enter to continue or ctrl-c to abort"
}

# Variables used for mysql and hive-site.xml configuration
setvars() {
   MYSQL_NODE=$(nodeset -e @mysql)
   METASTORE_NODE=$(nodeset -e @hivemeta)
   for mhost in $METASTORE_NODE; do
      METASTORE_URI+="thrift://$mhost:9083,"
   done
   # Remove trailing comma
   METASTORE_URI=${METASTORE_URI%,}
   # Set to empty value to use local metastore class
   #METASTORE_URI=''
   HS2_NODE=$(nodeset -e @hs2)
   ZK_NODES=$(nodeset -S, -e @zk)
   # Set up mysql database and user
   ROOT_PASSWORD=mapr
   DATABASE=hive
   USER=hive
   PASSWORD=mapr
}

install_mariadb() {
   #initial mysql configuration
   clush -g mysql "yum install -y mariadb-server"
   clush -g mysql "systemctl enable --now mariadb"
   #set mysql root password
   clush -g mysql "mysqladmin -u root password $ROOT_PASSWORD"
   # Reset mysql root password
   #clush -g mysql "mysqladmin -u root -pmapr password $ROOT_PASSWORD"

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
#TBD: check for errors
#echo -e "[client]\nuser=root\npassword=$ROOT_PASSWORD" > ~/.my.cnf
#chmod 600 ~/.my.cnf
#mysql -uroot -pmapr -sNe"$(mysql -uroot -pmapr -se"SELECT CONCAT('SHOW GRANTS FOR \'',user,'\'@\'',host,'\';') FROM mysql.user;")"
echo Scroll up and check for mysql install errors
read -p "Press enter to continue or ctrl-c to abort"
mysql -uroot -p$ROOT_PASSWORD -e "select user,host,password from mysql.user"
mysql -uroot -p$ROOT_PASSWORD "show grants for 'hive';"
read -p "Press enter to continue or ctrl-c to abort"
}
install_mariadb

install_mysql() {
   #initial mysql configuration
   clush -g mysql "yum install -y mysql-server"
   clush -g mysql "service mysqld start"
   #set mysql root password
   clush -g mysql "mysqladmin -u root password $ROOT_PASSWORD"

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

#TBD: check for errors
mysql -uroot -p"$ROOT_PASSWORD" -sNe"$(mysql -uroot -p"$ROOT_PASSWORD" -se"SELECT CONCAT('SHOW GRANTS FOR \'',user,'\'@\'',host,'\';') FROM mysql.user;")"

#echo -e "[client]\nuser=root\npassword=$ROOT_PASSWORD" > ~/.my.cnf; chmod 600 ~/.my.cnf
#mysql -e "select user,host,password from mysql.user; show grants for 'hive';"
echo Check for mysql install errors
read -p "Press enter to continue or ctrl-c to abort"
}

# The driver for the MySQL JDBC connector (a jar file) is part of the
# MapR distribution under /opt/mapr/lib/. Link file into the Hive lib directory
clush -g mysql "ln -s /opt/mapr/lib/mysql-connector-java-5.1.*-bin.jar $hivepath/lib/"

#create or modify the hive-site.xml
cat > /tmp/hive-site.xml <<EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>

<configuration>
<!-- Hive client, metastore and server configuration all contained in this config file as of Hive 0.13 -->

<!-- Client Configuration ========================  -->
<property>
    <name>hive.metastore.uris</name>
    <value>thrift://$METASTORE_NODE:9083</value>
    <description>Use blank(no value) to enable local metastore,
      use a host:pair to enable a 'remote' metastore.
      Use multiple host:port pairs separated by commas for HA
    </description>
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

<!-- SASL configuration on secure cluster,
     uncomment sasl property and comment out setugi property
-->

<property>
  <name>hive.metastore.sasl.enabled</name>
  <value>true</value>
  <description> Property to enable Hive Metastore SASL on secure cluster
  </description>
</property>

<property>
    <name>hive.metastore.schema.verification</name>
    <value>false</value>
    <description>
      Enforce metastore schema version consistency.
      True: Verify that version information stored in is compatible
      with one from Hive jars.  Also disable automatic
	   schema migration attempt. Users are required to manually
	   migrate schema after Hive upgrade which ensures proper
	   metastore schema migration. (Default)

      False: Warn if the version information stored in metastore
      doesn't match with one from in Hive jars.
    </description>
</property>

<property>
  <name>datanucleus.schema.autoCreateTables</name>
  <value>true</value>
</property>

<property>
  <name>hive.metastore.execute.setugi</name>
  <value>false</value>
  <description> Set this property to true to enable Hive Metastore service
    impersonation in unsecure mode.
    True causes the metastore to execute DFS operations
    using the client's reported user and group permissions.
    Note that this property must be set on
    BOTH the client and server sides.
  </description>
</property>

<!-- Hive Server2 Configuration ========================  -->
<!-- https://cwiki.apache.org/confluence/display/Hive/Configuration+Properties#ConfigurationProperties-HiveServer2 -->
<!-- https://mapr.com/docs/60/Hive/HighAvailability-HiveServer2.html?hl=example%2Chiveserver2%2Chigh%2Cavailability -->
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
  <name>hive.server2.enable.doAs</name>
  <value>true</value>
  <description>Set this property to enable impersonation in Hive Server 2</description>
</property>

<property>
   <name>hive.server2.thrift.port</name>
   <value>10000</value>
   <description>TCP port number for Hive Server to listen on, default 10000, conflicts with webmin</description>
</property>

<property>
  <name>hive.server2.thrift.sasl.qop</name>
  <value>auth-conf</value>
  <description>Added in Hive 2.1 Secure cluster </description>
</property>

<property>
  <name>hive.server2.webui.use.pam</name>
  <value>true</value>
</property>
 
<property>
  <name>hive.server2.webui.use.ssl</name>
  <value>true</value>
</property>
 
<property>
  <name>hive.server2.webui.keystore.path</name>
  <value>/opt/mapr/conf/ssl_keystore</value>
</property>
 
<property>
  <name>hive.server2.webui.keystore.password</name>
  <value>mapr123</value>
</property>

<property>
  <name>hive.server2.support.dynamic.service.discovery</name>
  <value>true</value>
  <description>Set to true to enable HiveServer2 dynamic service discovery
     by its clients. (default is false)
  </description>
</property>

<property>
  <name>hive.server2.zookeeper.namespace</name>
  <value>hiveserver2</value>
  <description>The parent znode in ZooKeeper, which is used by HiveServer2
     when supporting dynamic service discovery.(default value)
  </description>
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
  <description>List of ZooKeeper servers to talk to.
  Used in connection string by JDBC/ODBC clients instead of URI of specific HiveServer2 instance.
  </description>
</property>

<property>
  <name>hive.zookeeper.client.port</name>
  <value>5181</value>
  <description>The Zookeeper client port. The MapR default clientPort is 5181.</description>
</property>

<property>
  <name>hive.zookeeper.session.timeout</name>
  <value>600000</value>
  <description> (600000 is default value) </description>
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

if type xmllint >& /dev/null; then
   xmllint /tmp/hive-site.xml
fi
echo xmldiff /tmp/hive-site.xml with $hivepath/conf/hive-site.xml
read -p "Press enter to continue or ctrl-c to abort"

#su - mapr <<EOF
cat - <<EOF
clush -g all,edge -c /tmp/hive-site.xml --dest $hivepath/conf/hive-site.xml
clush -g all,edge "/opt/mapr/server/configure.sh -R"
export MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket
maprcli node services -name hivemeta -action start -nodes $METASTORE_NODE
maprcli node services -name hs2 -action start -nodes $HS2_NODE
hadoop fs -mkdir /user/hive
hadoop fs -chmod 0777 /user/hive
hadoop fs -mkdir /user/hive/warehouse
#accessible to all but can only delete own files
hadoop fs -chmod 1777 /user/hive/warehouse
hadoop fs -mkdir /tmp
hadoop fs -chmod 1777 /tmp
EOF

echo Run hive-verify.sh as mapr and non-mapr user next.


#!/bin/bash
# jbenninghoff 2013-Jul-22  vi: set ai et sw=3 tabstop=3:

yum -y install mysql-server
service mysqld start
chkconfig mysqld on
cat - <<EOF | mysql -u root
grant all on *.* to 'mapr'@'localhost' identified by "mapr";
grant all on *.* to 'mapr'@'%' identified by "mapr";
source /opt/mapr/bin/setup.sql;
flush privileges;
EOF


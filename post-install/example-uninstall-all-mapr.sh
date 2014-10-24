#!/bin/bash
# jbenninghoff@maprtech.com 2013-Sep-25  vi: set ai et sw=3 tabstop=3:

cat - << 'EOF'
# Assumes clush is installed, available from EPEL repository
# Examine the ps and jps output to insure all MapR Hadoop processes are no longer running
# Edit this script to enable a complete uninstall.  THIS WILL BE DESTRUCTIVE OF ALL DATA!
# After that, comment out the exit command below to execute the full script
EOF
exit

clush -a -B umount /mapr
clush -a -B service mapr-warden stop
clush -a -B service mapr-zookeeper stop
clush -a -B jps
clush -a -B 'ps ax | grep mapr'
# Clean the yum cache on RHEL based servers (in case you want to redeploy the server)
clush -a -B yum clean all
# commands below are destructive and deliberately commented out
#clush -a -B 'rpm -e $(rpm -qa --queryformat "%{NAME}\n"|grep ^mapr)'
#clush -a -B 'rm -rf /opt/mapr'


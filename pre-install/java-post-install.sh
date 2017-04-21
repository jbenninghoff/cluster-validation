#!/bin/bash
# jbenninghoff 2013-Oct-06  vi: set ai et sw=3 tabstop=3:
set -o nounset
set -o errexit

usage() {
cat << EOF
This script sets up the Java default using alternatives.
This can be useful when there are multiple Java versions installed.

There are commented commands in the script that demonstrate using
the CLI to download and install JDK
EOF
}

# Handle script options
while getopts "d" opt; do
  case $opt in
    \?) usage; exit ;;
  esac
done

# Set some global variables
javapath=/usr/java/default #Oracle
#javapath=/usr/lib/jvm/java #OpenJDK
sep=$(printf %80s); sep=${sep// /#} #Substitute all blanks with ######
distro=$(cat /etc/*release 2>&1 |grep -m1 -i -o -e ubuntu -e redhat -e 'red hat' -e centos) || distro=centos
distro=$(echo $distro | tr '[:upper:]' '[:lower:]')
#distro=$(lsb_release -is | tr [[:upper:]] [[:lower:]])

[ -d $javapath ] || { echo $javapath does not exist; exit 1; }
echo $javapath is $(readlink -f $javapath)

for item in java javac javaws jar jps javah keytool; do
  alternatives --install /usr/bin/$item $item $javapath/bin/$item 9
  alternatives --set $item $javapath/bin/$item
done

# Download and install using CLI
#curl -L -C - -b "oraclelicense=accept-securebackup-cookie" -O http://download.oracle.com/otn-pub/java/jdk/7u80-b15/jdk-7u80-linux-x64.rpm
#curl -L -C - -b "oraclelicense=accept-securebackup-cookie" -O http://download.oracle.com/otn-pub/java/jdk/8u121-b13/e9e7ea248e2c4826b92b3f075a80e441/jdk-8u121-linux-x64.rpm
#clush -ab -c /tmp/jdk-7u75-linux-x64.rpm  #Push it out to all the nodes in /tmp/
#clush -ab yum -y localinstall /tmp/jdk-7u75-linux-x64.rpm

## Java Browser (Mozilla) Plugin 32-bit ##
#alternatives --install /usr/lib/mozilla/plugins/libjavaplugin.so libjavaplugin.so /usr/java/jdk1.6.0_32/jre/lib/i386/libnpjp2.so 20000
## Java Browser (Mozilla) Plugin 64-bit ##
#alternatives --install /usr/lib64/mozilla/plugins/libjavaplugin.so libjavaplugin.so.x86_64 /usr/java/jdk1.6.0_32/jre/lib/amd64/libnpjp2.so 20000
 

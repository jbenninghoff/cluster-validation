#!/bin/bash

javapath=/usr/java/jdk1.7.0_51
[ -d $javapath ] && { echo $javapath does not exist; exit 1; }

for item in java javac javaws jar jps javah; do
  alternatives --install /usr/bin/$item $item $javapath/bin/$item 9
  alternatives --set $item $javapath/bin/$item
done

## Java Browser (Mozilla) Plugin 32-bit ##
#alternatives --install /usr/lib/mozilla/plugins/libjavaplugin.so libjavaplugin.so /usr/java/jdk1.6.0_32/jre/lib/i386/libnpjp2.so 20000
## Java Browser (Mozilla) Plugin 64-bit ##
#alternatives --install /usr/lib64/mozilla/plugins/libjavaplugin.so libjavaplugin.so.x86_64 /usr/java/jdk1.6.0_32/jre/lib/amd64/libnpjp2.so 20000
 

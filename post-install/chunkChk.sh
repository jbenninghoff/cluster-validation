#!/bin/bash
# jbenninghoff 2013-Jul-22  vi: set ai et sw=3 tabstop=3:

#TBD: check for non-uniform map-slots or containers
# Check TeraGenerated chunks per node
echo 'Checking /benchmarks/tera/in/part* for chunks per node'
hadoop mfs -ls '/benchmarks/tera/in/part*' |
 grep ':5660' | grep -v -E 'p [0-9]+\.[0-9]+\.[0-9]+' |
 tr -s '[:blank:]' ' ' | cut -d' ' -f 4 |
 sort | uniq -c 
# tr -s '[:blank:]' ' ' | cut -d' ' -f 2 
# sort | uniq | wc -l

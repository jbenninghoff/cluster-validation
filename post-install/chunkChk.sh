#!/bin/bash
# jbenninghoff@maprtech.com 2013-Jul-22  vi: set ai et sw=3 tabstop=3:

# Check TeraGenerated chunks per node
 hadoop mfs -ls '/benchmarks/tera/in/part*' |
 grep ':5660' | grep -v -E 'p [0-9]+\.[0-9]+\.[0-9]+' |
 tr -s '[:blank:]' ' ' | cut -d' ' -f 4 |
 sort | uniq -c 
# tr -s '[:blank:]' ' ' | cut -d' ' -f 2 
# sort | uniq | wc -l

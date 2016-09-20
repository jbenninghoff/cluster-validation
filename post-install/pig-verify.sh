#!/bin/bash

# Script to verify pig works for non-root, non-mapr user
hadoop fs -ls || { echo Pig requires user directory, directory not found; exit 1; }
#sudo hadoop fs -mkdir /user/$(id -un) && sudo hadoop fs -chown $(id -un):$(id -gn) /user/$(id -un)
#sudo hadoop fs -mkdir /tmp
#sudo hadoop fs -chmod 777 /tmp

hadoop fs -copyFromLocal /opt/mapr/pig/pig-0.1?/tutorial/data/excite-small.log /tmp

pig <<-'EOF'
set mapred.map.child.java.opts '-Xmx1g'
lines = load '/tmp/excite-small.log' using TextLoader() as (line:chararray);  -- load a file from hadoop FS
words = foreach lines generate flatten(TOKENIZE(line,' \t')) as word; -- Split each line into words using space and tab as delimiters
uniqwords = group words by word;
wordcount = foreach uniqwords generate group, COUNT(words);
dump wordcount;
EOF
#store wordcount into 'pig-wordcount';

#echo 'Pig website with tutorial: http://pig.apache.org/docs/r0.13.0/start.html'

# Pig code to load hive table
#tab = load 'tablename' using HCatLoader();
#ftab = filter tab by date = '20100819' ;
#...
#store ftab into 'processedevents' using HCatStorer("date=20100819");

#STORE my_processed_data INTO 'tablename2'
#   USING org.apache.hcatalog.pig.HCatStorer();
# https://cwiki.apache.org/confluence/display/Hive/HCatalog+LoadStore#HCatalogLoadStore-HCatStorer

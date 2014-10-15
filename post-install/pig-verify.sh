#!/bin/bash

# Script to verify pig works for non-root, non-mapr user
sudo hadoop fs -mkdir /user/$(id -un) && sudo hadoop fs -chown $(id -un):$(id -gn) /user/$(id -un)
hadoop fs -ls || { echo Pig requires user directory, directory not found; exit 1; }
sudo hadoop fs -mkdir /tmp
sudo hadoop fs -chmod 777 /tmp

hadoop fs -copyFromLocal /opt/mapr/pig/pig-0.12/tutorial/data/excite-small.log /tmp
pig <<-'EOF'
SET mapred.map.child.java.opts '-Xmx1g'
A = LOAD '/tmp/excite-small.log' USING TextLoader() AS (words:chararray);
B = FOREACH A GENERATE FLATTEN(TOKENIZE(*));
C = GROUP B BY $0;
D = FOREACH C GENERATE group, COUNT(B);
STORE D INTO 'wordcount';
EOF

echo 'Pig website with tutorial: http://pig.apache.org/docs/r0.13.0/start.html'

# Pig code to load hive table
#tab = load 'tablename' using HCatLoader();
#ftab = filter tab by date = '20100819' ;
#...
#store ftab into 'processedevents' using HCatStorer("date=20100819");

#STORE my_processed_data INTO 'tablename2'
#   USING org.apache.hcatalog.pig.HCatStorer();
# https://cwiki.apache.org/confluence/display/Hive/HCatalog+LoadStore#HCatalogLoadStore-HCatStorer

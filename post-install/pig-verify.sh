#!/bin/bash

# Script to verify pig works for non-root, non-mapr user
sudo hadoop fs -mkdir /user/$(id -un) && sudo hadoop fs -chown $(id -un):$(id -gn) /user/$(id -un)
hadoop fs -ls || { echo Pig requires user directory, directory not found; exit 1; }
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


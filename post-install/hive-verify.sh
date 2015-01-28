#!/bin/bash

# Script to verify hive works for non-root, non-mapr user
hadoop fs -ls || { echo Hive requires user directory, directory not found; exit 1; }
#sudo hadoop fs -mkdir /user/$(id -un) && sudo hadoop fs -chown $(id -un):$(id -gn) /user/$(id -un)
#sudo hadoop fs -mkdir /user/hive
#sudo hadoop fs -chmod 0777 /user/hive
#sudo hadoop fs -mkdir /user/hive/warehouse
#sudo hadoop fs -chmod 1777 /user/hive/warehouse  #accessible to all but can only delete own files
#sudo hadoop fs -mkdir /tmp
#sudo hadoop fs -chmod 777 /tmp

tmpfile=$(mktemp); trap 'rm $tmpfile' 0 1 2 3 15

cat - > $tmpfile <<EOF1
1320352532	1001	http://www.mapr.com/doc	http://www.mapr.com	192.168.10.1
1320352533	1002	http://www.mapr.com	http://www.example.com	192.168.10.10
1320352546	1001	http://www.mapr.com	http://www.mapr.com/doc	192.168.10.1
EOF1

#set hive.exec.mode.local.auto=true;
hive <<EOF2
set hive.cli.print.header=true;
set mapred.reduce.tasks=2;
DROP TABLE IF EXISTS web_log;
CREATE TABLE web_log(viewTime INT, userid BIGINT, url STRING, referrer STRING, ip STRING) ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t';
LOAD DATA LOCAL INPATH "$tmpfile" INTO TABLE web_log;
SELECT * FROM web_log;
SELECT web_log.* FROM web_log WHERE web_log.url LIKE '%doc';
quit;
EOF2

# Next step would be to run hive-bench to verify performance for the given cluster size


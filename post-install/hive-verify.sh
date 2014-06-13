#!/bin/bash

# Script to verify hive works for non-root, non-mapr user
#hadoop fs -mkdir /user/$(id -un) && hadoop fs -chown $(id -un):$(id -gn) /user/$(id -un)
hadoop fs -ls || { echo Hive requires user directory, directory not found; exit 1; }
#maprcli node cldbmaster # only works if mapr-core was installed

cat - > /tmp/sample-table.txt <<EOF1
1320352532	1001	http://www.mapr.com/doc	http://www.mapr.com	192.168.10.1
1320352533	1002	http://www.mapr.com	http://www.example.com	192.168.10.10
1320352546	1001	http://www.mapr.com	http://www.mapr.com/doc	192.168.10.1
EOF1

hive <<EOF2
set hive.cli.print.header=true;
set mapred.reduce.tasks=2;
DROP TABLE web_log;
CREATE TABLE web_log(viewTime INT, userid BIGINT, url STRING, referrer STRING, ip STRING) ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t';
LOAD DATA LOCAL INPATH '/tmp/sample-table.txt' INTO TABLE web_log;
SELECT * FROM web_log;
SELECT web_log.* FROM web_log WHERE web_log.url LIKE '%doc';
quit;
EOF2

# Next step would be to run hive-bench to verify performance for the given cluster size

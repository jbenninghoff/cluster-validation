#!/bin/bash

# Script to verify hive works for non-root, non-mapr user
srvid=$(awk -F= '/mapr.daemon.user/{ print $2}' /opt/mapr/conf/daemon.conf)
[ $(id -u) -eq 0 ] && { echo This script must be run as non-root; exit 1; }
[ "$srvid" == $(id -u) ] && { echo This script must be run as non-service-account; exit 1; }

hadoop fs -ls || { echo Hive requires user directory, directory not found; exit 1; }
# Use the following to create the maprfs://user/$username folder and chmod
#sudo hadoop fs -mkdir /user/$(id -un) && sudo hadoop fs -chown $(id -un):$(id -gn) /user/$(id -un)

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
DROP TABLE IF EXISTS mapr_web_log;
CREATE TABLE mapr_web_log(viewTime INT, userid BIGINT, url STRING, referrer STRING, ip STRING) ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t';
LOAD DATA LOCAL INPATH "$tmpfile" INTO TABLE mapr_web_log;
SELECT * FROM mapr_web_log;
SELECT mapr_web_log.* FROM mapr_web_log WHERE mapr_web_log.url LIKE '%doc';
quit;
EOF2

# Next step would be to run some hive benchmark to verify performance for the given cluster size
# Might also run beeline


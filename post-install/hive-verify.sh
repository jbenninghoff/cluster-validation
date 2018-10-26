#!/bin/bash
 
# Script to verify hive works for non-root, non-mapr user
[ $(id -u) -eq 0 ] && { echo This script must be run as non-root; exit 1; }

srvid=$(awk -F= '/mapr.daemon.user/{ print $2}' /opt/mapr/conf/daemon.conf)
if [[ "$srvid" == $(id -u) ]]; then
   echo This script should be run as non-service-account
fi
if [[ $# -ne 1 ]]; then
   echo This script requires an HS2 hostname as only argument; exit 2
fi
if ! hadoop fs -ls; then
   echo Hive requires user directory, directory not found; exit 3
fi

tmpfile=$(mktemp); trap 'rm $tmpfile' 0 1 2 3 15
hs2host=$1
hivehome=$(eval echo /opt/mapr/hive/hive-2*)

# Create simple csv table
cat - > $tmpfile <<EOF1
1320352532,1001,http://www.mapr.com/doc,http://www.mapr.com,192.168.10.1
1320352533,1002,http://www.mapr.com,http://www.example.com,192.168.10.10
1320352546,1001,http://www.mapr.com,http://www.mapr.com/doc,192.168.10.1
EOF1
 
# Test with simple hive shell queries, count(*) forces MR job
hive <<EOF2
set hive.cli.print.header=true;
DROP TABLE IF EXISTS mapr_web_log;
CREATE TABLE mapr_web_log(viewTime INT, userid BIGINT, url STRING, \
referrer STRING, ip STRING) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',';
LOAD DATA LOCAL INPATH "$tmpfile" INTO TABLE mapr_web_log;
SELECT * FROM mapr_web_log;
SELECT mapr_web_log.* FROM mapr_web_log WHERE mapr_web_log.url LIKE '%doc';
set mapred.reduce.tasks=2;
SELECT count(*) FROM mapr_web_log;
quit;
EOF2
#set hive.exec.mode.local.auto=true;
 
# Test with beeline
$hivehome/bin/beeline -u "jdbc:hive2://$hs2host:10000/default;auth=maprsasl;saslQop=auth-conf" <<EOF3
SELECT count(*) FROM mapr_web_log;
EOF3
 
# Next step would be to run some hive benchmark to verify performance for the given cluster size

# Use the following to create the maprfs://user/$username folder and chmod
# su - mapr <<EOF
# hadoop fs -mkdir /user/$(id -un)
# hadoop fs -chown $(id -un):$(id -gn) /user/$(id -un)
# EOF
 

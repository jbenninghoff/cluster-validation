#!/bin/bash
# jbenninghoff 2015-May-05 vi: set ai et sw=3 tabstop=3:

[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }

hostname=$(hostname)
clustername=$(awk 'NR==1{print $1}' /opt/mapr/conf/mapr-clusters.conf)
zookeepers=$(maprcli node listzookeepers | sed -n 2p)

# Download Solr 5.1 tarball and place in /mapr/$clustername/tmp/
# curl 'http://mirror.cogentco.com/pub/apache/lucene/solr/5.1.0/solr-5.1.0.tgz' -o /mapr/$clustername/tmp/solr-5.1.0.tgz
tar xzf /mapr/$clustername/tmp/solr-5.1.0.tgz solr-5.1.0/bin/install_solr_service.sh --strip-components=2 #Extract install script
./install_solr_service.sh /mapr/$clustername/tmp/solr-5.1.0.tgz -i /opt -d /var/solr -u mapr -s solr -p 8983 #Use Linux FS

#maprcli volume create -name localvol-$hostname -path /apps/solr/localvol-$hostname -createparent true -localvolumehost $hostname -replication 1 
#./install_solr_service.sh /mapr/$clustername/tmp/solr-5.1.0.tgz -i /opt -d /mapr/$clustername/apps/solr/localvol-$hostname -u mapr -s solr -p 8983 #Use MapR NFS

service solr stop
# add to /var/solr/solr.in.sh
cat - <<EOF >> /var/solr/solr.in.sh
SOLR_MODE=solrcloud
SOLR_HOST="$hostname"
ZK_HOST="$zookeepers/solr"
EOF

/opt/solr/server/scripts/cloud-scripts/zkcli.sh -zkhost $zookeepers/solr -cmd bootstrap -solrhome /var/solr/data

service solr start
service solr status

#!/bin/bash
# jbenninghoff 2015-July-14 vi: set ai et sw=3 tabstop=3:

[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }

#Download Solr 4.4 tarball
#curl "http://mirror.cogentco.com/pub/apache/lucene/solr/4.4.0/solr-4.4.0.tgz" -o /tmp/
pkg=/tmp/solr-4.4.0.tgz #Full path to Solr package
[ -f $pkg ] || { echo $pkg package not found; exit 1; }
serviceacct=${1:-mapr} #Default service account is mapr but alternate account can be provided as arg
su - $serviceacct -c "hadoop fs -stat /apps/solr" || { echo $serviceacct cannot access maprfs, check for ticket; exit 3; }

instance=wf-instance
solr4init=/etc/init.d/solr4
solr4init=/usr/local/bin/solr4 #path to write start/stop/status init script
solr4add=/usr/local/bin/solr4-add-collection.sh #path to write add solr collections script
hostname=$(hostname -s)
clustername=$(awk 'NR==1{print $1}' /opt/mapr/conf/mapr-clusters.conf)
zookeepers=$(su - $serviceacct -c "maprcli node listzookeepers | sed -n '2s/ *$//p'")
bootstrap=$(su - $serviceacct -c "hadoop fs -stat /apps/solr &>/dev/null && echo false || echo true") #If maprfs:/apps/solr does not exist, bootstrap
installdir=/apps/solr/solr-4.4.0 # Use Linux FS
installdir=/mapr/$clustername/apps/solr #Use MapR FS via NFS as install dir
echo Should have already exited; exit
case $installdir in
   /mapr/*)
      if [ ! -d "$installdir" ]; then
         echo Creating Solr4 volume
         maprcli volume create -name solr4-vol -path /${installdir#/*/*/} -createparent true -replication 3 #Create Solr4 volume
      fi
      installdir=$installdir/$hostname; mkdir -p $installdir
      ;;
   *)
      mkdir -p $installdir
      ;;
esac

echo Extracting Solr4 package
cd $installdir; tar xzf $pkg
#create default collection
cd $installdir/solr*; installdir=$PWD; cp -a example $instance; chown -R mapr:mapr $instance
cd $installdir/$instance #bootstrap must be run from here

if [ "$bootstrap" == "true" ]; then
   echo "Use control-c when command has finished sending output and this string is visibile: (live nodes size: 1)"; sleep 3
   echo su - $serviceacct -c \"cd $installdir/$instance\; java -DnumShards=3 -Dbootstrap_confdir=$installdir/$instance/solr/collection1/conf -Dcollection.configName=myconfig -DzkHost=$zookeepers/solr  -jar $installdir/$instance/start.jar\"
   cat - <<-"EOF2" > $solr4add
		#! /bin/bash
		
		if [ $# != 2 ]; then
		   echo "Usage: $0 collection-name number-of-shards"
		   echo "collection-name will be created in installdir/instance/solr/collection-name and loaded into Zookeeper"
		   exit 1
		fi
		
		collection=$1
		nshards=${2:-3}
		
		cp -a installdir/instance/solr/collection1/ installdir/instance/solr/$collection
		sed -i 's/collection1/collection2/' installdir/instance/solr/$collection/core.properties
		installdir/instance/cloud-scripts/zkcli.sh -zkhost zookeepers/solr -cmd upconfig -confdir installdir/instance/solr/$collection/conf -confname ${collection}Conf
		
		sleep 30
		
		curl "localhost:8983/solr/admin/collections?action=CREATE&name=${collection}&numShards=${nshards}&replicationFactor=1&collection.configName=${collection}Conf"
	EOF2

   sed -i "s,installdir,$installdir,g" $solr4add
   sed -i "s,instance,$instance,g" $solr4add
   sed -i "s/zookeepers/$zookeepers/g" $solr4add
   chmod 744 $solr4add

   echo Use $solr4add to add additional document collections to Solr
   su - $serviceacct -c "hadoop fs -mkdir -p /apps/solr"
fi

#make solr4 init script
cat - <<"EOF" > $solr4init
#!/bin/sh
### BEGIN INIT INFO
# Provides:
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start daemon at boot time
# Description:       Control Apache Solr v4.x as an init.d service
### END INIT INFO

dir=installdir
user="mapr"
#cmd="java -Dsolr.solr.home=$dir/solr -DzkHost=$zookeepers/solr -jar $dir/start.jar"
cmd="java -DzkHost=$zookeepers/solr -jar $dir/start.jar"

name=`basename $0`
pid_file="/var/tmp/$name.pid"
stdout_log="/var/tmp/$name.log"
stderr_log="/var/tmp/$name.err"

# Source function library.
. /etc/rc.d/init.d/functions

get_pid() {
    cat "$pid_file"
}

is_running() {
    [ -f "$pid_file" ] && ps `get_pid` > /dev/null 2>&1
}

case "$1" in
    start)
    if is_running; then
        echo "Already started"
    else
        echo "Starting $name"
        cd "$dir"
        runuser -c "$cmd" $user > "$stdout_log" 2> "$stderr_log" &
#        $cmd > "$stdout_log" 2> "$stderr_log" &
#        daemon --user $user $cmd > "$stdout_log" 2> "$stderr_log" &
        echo $! > "$pid_file"; sleep 2
        if ! is_running; then
            echo "Unable to start, see $stdout_log and $stderr_log"
            exit 1
        fi
    fi
    ;;
    stop)
    if is_running; then
        echo -n "Stopping $name.."
        kill `get_pid`
        for i in {1..10}
        do
            if ! is_running; then
                break
            fi

            echo -n "."
            sleep 1
        done
        echo

        if is_running; then
            echo "Not stopped; may still be shutting down or shutdown may have failed"
            exit 1
        else
            echo "Stopped"
            if [ -f "$pid_file" ]; then
                rm "$pid_file"
            fi
        fi
    else
        echo "Not running"
    fi
    ;;
    restart)
    $0 stop
    if is_running; then
        echo "Unable to stop, will not attempt to start"
        exit 1
    fi
    $0 start
    ;;
    status)
    if is_running; then
        echo "Running"
        lsof -i :8983
    else
        echo "Stopped"
        exit 1
    fi
    ;;
    *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac

exit 0
EOF

sed -i.bak "s,dir=installdir,dir=$installdir/$instance,g" $solr4init
sed -i "s/\$zookeepers/$zookeepers/g" $solr4init
chmod 744 $solr4init

#chkconfig --add solr4
#chkconfig solr4 on

#echo Use these commands to start Solr4.x manually or check status
echo $solr4init start
echo $solr4init status


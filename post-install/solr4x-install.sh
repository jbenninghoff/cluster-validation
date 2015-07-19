#!/bin/bash
# jbenninghoff 2015-July-14 vi: set ai et sw=3 tabstop=3:

[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }

hostname=$(hostname)
clustername=$(awk 'NR==1{print $1}' /opt/mapr/conf/mapr-clusters.conf)
zookeepers=$(maprcli node listzookeepers | sed -n 2p)
pkg=solr-4.4.0.tgz
installdir=/apps/solr/solr-4.4.0/DSsolr
installdir=/apps/solr/solr-4.4.0

#Download Solr 4.4 tarball and place in /mapr/$clustername/tmp/
#curl "http://mirror.cogentco.com/pub/apache/lucene/solr/4.4.0/$pkg" -o /mapr/$clustername/tmp/
[ -f /mapr/$clustername/tmp/$pkg ] || { echo $pkg package not found; exit 1; }

#maprcli volume create -name localvol-$hostname -path /apps/solr/localvol-$hostname -createparent true -localvolumehost $hostname -replication 3 
#cd /mapr/$clustername/apps/solr/localvol-$hostname; tar xzf /mapr/$clustername/tmp/$pkg
cd /apps/solr; tar xzf /mapr/$clustername/tmp/$pkg

#create default collection
cd $installdir; cp -a example mycollection

#bootstrap command if first host
echo java -DnumShards=3 -Dbootstrap_confdir=$installdir/mycollection/solr/collection1/conf -Dcollection.configName=mycollection1 -DzkHost=$zookeepers/solr  -jar $installdir//mycollection/start.jar 

#make solr4 init script
cat - <<EOF > /etc/init.d/solr4
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

dir="$installdir/mycollection"
user="root"
cmd="java -Dsolr.solr.home=$installdir/mycollection/solr -DzkHost=$zookeepers/solr -jar $installdir/mycollection/start.jar"

name=`basename $0`
pid_file="/var/run/$name.pid"
stdout_log="/var/log/$name.log"
stderr_log="/var/log/$name.err"

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
        $cmd > "$stdout_log" 2> "$stderr_log" &
#        daemon --user $user $cmd > "$stdout_log" 2> "$stderr_log" &
#        sudo -u "$user" $cmd > "$stdout_log" 2> "$stderr_log" &
#        su -c "$cmd" - $user >> "$stdout_log" 2>> "$stderr_log" &
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

chkconfig solr4 on
echo service solr4 start
echo service solr4 status

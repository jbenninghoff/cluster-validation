#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3

usage() {
cat << EOF
This script probes an installed MapR cluster configuration,
writing all results to stdout.
Assumption is that clush is installed (available from EPEL repository)
and that this script is run by MapR service account (typically 'mapr')
Log stdout/stderr with 'mapr-audit.sh |& tee mapr-audit.log'

Usage: $0 [-d] [-v|-t] [s] [-e] [-a] [-g <clush group name>]
-d option for script debug
-v option for more extensive auditing 
-t option for a quick terse output
-s option to audit the cluster for security
-e option to audit an edge node
-g option to specify a clush group other than all
-a option to audit volume ACEs

EOF
}

verbose=false; terse=false; security=false; edge=false; group=all; volacl=false
while getopts ":dvtsea:g:" opt; do
   case $opt in
      d) dbg=true ;;
      v) verbose=true ;;
      t) terse=true ;;
      s) security=true ;;
      e) edge=true ;;
      g) group=$OPTARG ;;
      a) volacl=true; mntpt=$OPTARG ;;
      :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
      \?) usage >&2; exit ;;
   esac
done

setvars() {
   eval printf -v sep "'#%.0s'" "{1..${COLUMNS:-80}}"
   parg="-b -g ${group:-all}" 
   mrv=$(hadoop version |awk 'NR==1 {printf("%1.1s\n", $2)}')
   #printf -v sep '#%.0s' {1..80} #Set sep to 80 # chars
   #TBD: If edge==true group!=all
   #TBD: clush can use --hostfile <filename> if group cannot be set
}

if [[ -f /opt/mapr/conf/daemon.conf ]]; then
   srvid=$(awk -F= '/mapr.daemon.user/ {print $2}' /opt/mapr/conf/daemon.conf)
else
   srvid=mapr #guess at service acct if not found
fi

maprcli_check() {
   if ( ! type maprcli > /dev/null 2>&1 ); then #If maprcli not on this machine
      node=$(nodeset -I0 -e @$group)
      if [[ -z "$node" ]]; then
         read -e -p 'maprcli not found, enter host name to run maprcli on: ' node
      fi
      if ( ! ssh "$node" "type maprcli > /dev/null 2>&1" ); then
         echo maprcli not found on host "$node", rerun with valid host name; exit
      fi
      node="ssh -qtt $node " #Single node to run maprcli commands from
      #chgu="su -u $srvid -c " # Run as service account
   fi
   #Sudo to mapr on secure cluster
   #node="sudo -u mapr  MAPR_TICKETFILE_LOCATION=/opt/mapr/conf/mapruserticket "
}

sudo_setup() {
   SUDO="sudo -u $srvid -i "
   snode=$(nodeset -I0 -e @$group)
   sscmd="sudo -U $srvid -ln 2>&1 |grep -q 'sudo: a password is required'"
   if (ssh -qtt $snode $sscmd); then
      read -s -e -p 'Enter sudo password: ' mypasswd
      #echo $mypasswd | sudo -S -i dmidecode -t bios || exit
      SUDO="echo $mypasswd | $SUDO -S "
   fi

   clcmd="${SUDO:-} grep -q '^Defaults.*requiretty' /etc/sudoers"
   if (clush $parg -S $clcmd >& /dev/null); then
      parg="-o -qtt $parg" # Add -qtt for sudo tty via ssh/clush
      #To run sudo without a tty use:
      # clush -ab -o -qtt
      # "sudo sed -i.bak '/^Defaults.*requiretty/s/^/#/' /etc/sudoers"
   fi
}

cluster_checks1() {
   echo ==================== MapR audits ================================
   date; echo "$sep"
   if [[ "$mrv" == "1" ]] ; then # MRv1
      msg="Hadoop Jobs Status "; printf "%s%s \\n" "$msg" "${sep:${#msg}}"
      ${node:-} timeout 9 hadoop job -list; echo "$sep"
   elif [[ "$mrv" == "2" ]] ; then # MRv2
      msg="Hadoop Jobs Status "; printf "%s%s \\n" "$msg" "${sep:${#msg}}"
      ${node:-} timeout 9 mapred job -list; echo "$sep"
   fi
   msg="MapR Dashboard "; printf "%s%s \\n" "$msg" "${sep:${#msg}}"
   if (type -p jq >/dev/null); then
      jqcmd='.data[] | {version, cluster,utilization}'
      ${node:-} maprcli dashboard info -json | jq "$jqcmd"
      echo "$sep"
   else
      ${node:-} maprcli dashboard info -json; echo "$sep"
   fi
   msg="MapR Alarms "; printf "%s%s \\n" "$msg" "${sep:${#msg}}"
   ${node:-} maprcli alarm list -summary true; echo "$sep"
   msg="MapR Services "; printf "%s%s \\n" "$msg" "${sep:${#msg}}"
   ${node:-} maprcli node list -columns svc |awk 'NF{--NF};1{printf "%-25s %s\n", $1,$2;}'; echo "$sep"
   #${node:-} maprcli node list -columns svc; echo "$sep"
   msg="Zookeepers: "; printf "%s%s \\n" "$msg" "${sep:${#msg}}"
   ${node:-} maprcli node listzookeepers; echo "$sep"
   msg="Current MapR Version: "; printf "%s%s \\n" "$msg" "${sep:${#msg}}"
   ${node:-} maprcli config load -keys mapr.targetversion
   msg="Current MapR Licenses: "; printf "%s%s \\n" "$msg" "${sep:${#msg}}"
   ${node:-} maprcli license list | grep -i lictype
   echo
}

cluster_checks2() {
   echo ==================== Additional MapR audits ===========================
   msg="MapR System Stats "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   ${node:-} maprcli node list -columns hostname,cpus,mused; echo "$sep"
   msg="Customer Site Specific Volumes "
   printf "%s%s \n" "$msg" "${sep:${#msg}}"
   opts='-filter "[n!=mapr.*] and [n!=*local*]"'
   opts+=' -columns n,numreplicas,mountdir,used,numcontainers,logicalUsed'
   eval ${node:-} maprcli volume list "$opts"; echo "$sep"
   echo
   #clush $parg "echo MapR /etc/shadow access:; ls -l /etc/shadow; id $srvid"
   clush $parg "echo MapR /etc/shadow access:; stat -c '%A %U %G %n'\
      /etc/shadow; id $srvid"
   echo "$sep"
   clush $parg "echo 'MapR SHMEM Segments:'; ${SUDO:-} ipcs -m | uniq -w10"
   echo "$sep"
   clush $parg "echo MapR HostID:; cat /opt/mapr/hostid"; echo "$sep"
   clush $parg "echo MapR Patch; yum --noplugins list installed mapr-patch"
   echo "$sep"
   echo MFS Heap Size:
   clush ${parg/-b/} "pgrep -oaf /opt/mapr/server/mfs" | \
      grep -e '\-m [^ ]*' -e '^[^ ]*'
   echo "$sep"
   clush $parg "echo 'MapR Storage Pools'; \
      ${SUDO:-} /opt/mapr/server/mrconfig sp list -v"
   echo "$sep"
   clush $parg "echo 'Cat mapr-clusters.conf'; \
      cat /opt/mapr/conf/mapr-clusters.conf"
   echo "$sep"
   #TBD: if mapr-clusters.conf has more than one line,
   #look for mirror volumes {maprcli volume list -json |grep mirror???}
   clush $parg "echo 'MapR Env Settings'; grep ^export /opt/mapr/conf/env.sh"
   echo "$sep"
   if [[ "$mrv" == "1" ]] ; then # MRv1
      clush $parg "echo 'Mapred-site.xml Checksum Consistency'; \
                   sum /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml"
   echo "$sep"
      clush $parg "echo 'core-site.xml Checksum Consistency'; sum /opt/mapr/hadoop/hadoop-0.20.2/conf/core-site.xml"; echo "$sep"
      clush $parg "echo 'MapR Central Logging Setting'; grep ROOT_LOGGER /opt/mapr/hadoop/hadoop-0.20.2/conf/hadoop-env.sh"; echo "$sep"
   else
      clush $parg "echo 'MR2 core-site.xml Checksum Consistency'; sum /opt/mapr/hadoop/hadoop-2.*/etc/hadoop/core-site.xml"; echo "$sep"
      clush $parg "echo 'MR2 core-site.xml Property Count: '; awk '/<prop/,/<\/prop/ {if (/\/prop/) count++}; END {print count}' /opt/mapr/hadoop/hadoop-2.*/etc/hadoop/core-site.xml"; echo "$sep"
      clush $parg "echo 'MR2 mapred-site.xml Checksum Consistency'; sum /opt/mapr/hadoop/hadoop-2.*/etc/hadoop/mapred-site.xml"; echo "$sep"
      clush $parg "echo 'MR2 mapred-site.xml Property Count: '; awk '/<prop/,/<\/prop/ {if (/\/prop/) count++}; END {print count}' /opt/mapr/hadoop/hadoop-2.*/etc/hadoop/mapred-site.xml"; echo "$sep"
      clush $parg "echo 'MR2 yarn-site.xml Checksum Consistency'; sum /opt/mapr/hadoop/hadoop-2.*/etc/hadoop/yarn-site.xml"; echo "$sep"
      clush $parg "echo 'MR2 yarn-site.xml Property Count: '; awk '/<prop/,/<\/prop/ {if (/\/prop/) count++}; END {print count}' /opt/mapr/hadoop/hadoop-2.*/etc/hadoop/yarn-site.xml"; echo "$sep"
      hadoop conf-details print-all-effective-properties |grep central-logging
   fi

   msg="MapR Central Configuration Setting"
   clush $parg "echo $msg; grep centralconfig /opt/mapr/conf/warden.conf"
   echo "$sep"
   clush $parg "echo 'MapR Roles Per Host'; ls /opt/mapr/roles"; echo "$sep"
   #cmd="find /opt/mapr -maxdepth 1 -type d |sort"
   #clush $parg "echo 'MapR Directories'; $cmd"; echo "$sep"
   # Strip -mapr-xxxx version from all jar file names and sort for dups
   cmd="find /opt/mapr -name '*mapr-[0-9]*.jar' |sed 's/-mapr-[0-9]*//' |uniq -d"
   clush $parg "echo 'Duplicate jars'; $cmd"; echo "$sep"
   echo
   #if (type -p jq >/dev/null); then
   #TBD: get history server hostname/ip, get 1-3 days history and log it.
   #hist=$(maprcli node list -columns svc |awk '/historyserver/ {print $1}')
   #begin=$(( ($(date +%s) - 86400*3) * 1000 ))
   #url="https://$hist:19890/ws/v1/history/mapreduce/jobs"
   #url+="?startedTimeBegin=$begin"
   #curl -s -u mapr:mapr -k "$url"
   #curl -s -u mapr:mapr -k "$url" |jq
}

edgenode_checks() {
   msg="Edge Node Checking "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg 'echo "MapR packages installed"; rpm -qa |grep mapr- |sort'
   echo "$sep"

   msg="Checking for MySQL Server "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg ${SUDO:-} "service mysqld status 2>/dev/null"
   echo "$sep"

   #TBD: Check Hive config
   #TBD: Check HS2 port and config
   #TBD: Check MetaStore port and config
   msg="Checking Hive Configuration "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clcmd="sed '/<!--.*-->/d' /opt/mapr/hive/hive-2.1/conf/hive-site.xml \
         |sed '/<!--/,/-->/d' |grep '<name>'"
   clush $parg ${SUDO:-} "$clcmd"
   echo "$sep"

   #TBD: Check Hue port and config (hue.ini)
   #TBD: Check Sqoop config (RDBMS jars)
   #TBD: Check Pig config
   #TBD: Check Spark/Yarn config (spark-defaults.conf, web-proxy jar)
}

cluster_checks3() {
   [[ -n "$dbg" ]] && set -x
   msg="Verbose audits "; printf "%s%s \n" "$msg" "${sep:${#msg}}"; echo
   #$node maprcli dump balancerinfo | sort | awk '$1 == prvkey {size += $9}; $1 != prvkey {if (prvkey!="") print size; prvkey=$1; size=$9}'
   #echo MapR disk list per host
   clush $parg 'echo "MapR packages installed"; rpm -qa |grep mapr- |sort'; echo "$sep"
   clush $parg 'echo "MapR Disk List per Host"; maprcli disk list -output terse -system 0 -host $(hostname)'; echo "$sep"
   clush $parg 'echo "MapR Disk Stripe Depth"; ${SUDO:-} /opt/mapr/server/mrconfig dg list | grep -A4 StripeDepth'; echo "$sep"
   #clush $parg 'echo "MapR Disk Stripe Depth"; ${SUDO:-} /opt/mapr/server/mrconfig dg list '; echo "$sep"
   msg="MapR Complete Volume List "; printf "%s%s \n" "$msg" "${sep:${#msg}}" 
   ${node:-} maprcli volume list -columns n,numreplicas,mountdir,used,numcontainers,logicalUsed; echo "$sep"
   msg="MapR Storage Pool Details "; printf "%s%s \n" "$msg" "${sep:${#msg}}" 
   ${node:-} maprcli dump balancerinfo | sort -r; echo "$sep"
   msg="Hadoop Configuration Variable Dump "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   if [[ "$mrv" == "1" ]] ; then # MRv1
      ${node:-} hadoop conf -dump | sort; echo "$sep"
   else
      ${node:-} hadoop conf-details print-all-effective-properties | grep -o '<name>.*</value>' |sed 's/<name>//;s/<\/value>//;s/<\/name><value>/=/'
      echo "$sep"
   fi
   msg="MapR Configuration Variable Dump "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   ${node:-} maprcli config load -json; echo "$sep"
   #msg="List Unique File Owners, Down 4 Levels"; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   #${node:-} find $mntpt -maxdepth 4 -exec stat -c '%U' {} \; |sort -u; echo "$sep" #find uniq owners
   # TBD: check all hadoop* packages installed
   clush -b -g zk -g cldb "echo 'ZK and CLDB nice values'; ps -ocomm,pid,nice $(</opt/mapr/zkdata/zookeeper_server.pid) $(</opt/mapr/pid/cldb.pid)"
   echo "$sep"
   clush $parg "echo 'Guts 6sec snapshot'; /opt/mapr/bin/guts cpu:none rpc:none cache:none db:none cleaner:none time:all dsec:6"; echo "$sep"
   [[ -n "$dbg" ]] && set +x
}

security_checks() {
   msg="MapR Security Checks "; printf "\n%s%s \n\n" "$msg" "${sep:${#msg}}"

   # Edge or Cluster nodes (Linux checks)
   clush $parg "echo -n 'SElinux status: '; ([[ -d /etc/selinux && -f /etc/selinux/config ]] && grep ^SELINUX= /etc/selinux/config) || echo Disabled"; echo
   clush $parg "echo Permissions on /etc/nsswitch.conf; stat -c '%U %G %A %a %n' /etc/nsswitch.conf"
   clush $parg 'echo nsswitch.conf settings; grep -v -e ^# -e ^$ /etc/nsswitch.conf'; echo
   clush $parg "echo Permissions on /tmp; stat -c '%U %G %A %a %n' /tmp"
   clush $parg ${SUDO:-} "service ntpd status|sed 's/(.*)//'"; echo
   clush $parg ${SUDO:-} 'service sssd status|sed "s/(.*)//"; chkconfig --list sssd | grep -e 3:on -e 5:on >/dev/null && wc /etc/sssd/sssd.conf' #TBD: Check sssd settings
   clush $parg ${SUDO:-} "service krb5kbc status |sed 's/(.*)//'; service kadmin status |sed 's/(.*)//'" # Check for Kerberos
   clush $parg ${SUDO:-} "echo Checking for Firewall; service iptables status |sed 's/(.*)//'"
   clush $parg ${SUDO:-} 'echo Checking for LUKS; grep -v -e ^# -e ^$ /etc/crypttab'
   clush $parg ${SUDO:-} 'echo Checking for C and Java Compilers; type gcc; type javac; find /usr/lib -name javac|sort'
   #TBD: clush $parg ${SUDO:-} 'echo Checking MySQL; type mysql && mysql -u root -e "show databases" && echo "Passwordless MySQL access"'
   clush $parg 'echo Checking for Internet Access; { curl -f http://mapr.com/ >/dev/null 2>&1 || curl -f http://54.245.106.105/; } && echo Internet Access Available || echo Internet Access Unavailable'
   clush $parg "echo Checking All TCP/UDP connections; netstat -t -u -p -e --numeric-ports"

   # Cluster nodes only
   if [[ "$edge" == "false" ]]; then
      msg="MapR Secure Mode "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
      ${node:-} maprcli dashboard info -json | grep 'secure.*true,' && maprsecure=true || echo === MapR cluster running non-secure
      msg="MapR Auditing Status "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
      ${node:-} maprcli config load -json | grep "mfs.feature.audit.support" && mapraudit=true || echo === MapR FS Auditing unavailable
      msg="MapR Fast Inode Scan "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
      ${node:-} maprcli config load -json | grep "mfs.feature.fastinodescan.support" && fastinodes=true || echo === MapR Fast Inode Scan not enabled
      # Fast Inode Scan helps mirroring thousands/millions of files/volume
      msg="MapR Cluster Admin ACLs"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
      ${node:-} maprcli acl show -type cluster
      # Check for MapR whitelist: http://doc.mapr.com/display/MapR/Configuring+MapR+Security#ConfiguringMapRSecurity-whitelist
      clush $parg "echo 'MapR MFS Whitelist Defined'; grep mfs.subnets.whitelist /opt/mapr/conf/mfs.conf"
      clush $parg "echo 'MapR YARN Submit ACLs'; awk '/<queue/,/<\/queue>/ {if (/acl|<queue /&&!/<!--/) print}' /opt/mapr/hadoop/hadoop-2*/etc/hadoop/fair-scheduler.xml"
      msg="YARN Queue ACLs"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
      ${node:-} mapred queue -showacls
      grep -q ^zk: /etc/clustershell/groups && garg="-g zk"
      clush $parg ${garg:-} "echo Checking Zookeeper Secure Mode; grep -i ^auth /opt/mapr/zookeeper/zookeeper-*/conf/zoo.cfg"
   fi
   # Edge or Cluster nodes
   clush $parg ${SUDO:-} "service mapr-nfsserver status|sed 's/(.*)//'"
   # NFS Exports should be limited to subnet(s) (whitelist) and squash all root access
   clush $parg ${SUDO:-} 'echo Checking NFS Exports; grep -v -e ^# -e ^$ /opt/mapr/conf/exports /etc/exports'
   clush $parg ${SUDO:-} "echo Checking Current NFS Exports; showmount -e | sed -n '2,\$p'"
   clush $parg ${SUDO:-} "echo Checking Active NFS Mounts; showmount -a | sed -n '2,\$p'"; echo "$sep"
   clush $parg "echo Ownership of /opt/mapr Must Be root; stat -c '%U %G %A %a %n' /opt/mapr"
   clush $parg ${SUDO:-} "echo Find Setuid Executables in /opt/mapr;  find /opt/mapr -type f \( -perm -4100 -o -perm -2010 \) -exec stat -c '%U %G %A %a %n' {} \; |sort"
   #clush $parg ${SUDO:-} "echo Find Setuid Executables in /opt/mapr; find /opt/mapr -perm +6000 -type f -exec stat -c '%U %G %A %a %n' {} \; |sort"
   clush $parg "awk '/^jpamLogin/,/};/' /opt/mapr/conf/mapr.login.conf" # Check MapR JPAM settings
   clush $parg "echo CheckSum of /etc/pam.d files; awk '/^jpamLogin/,/};/' /opt/mapr/conf/mapr.login.conf | awk -F= '/serviceName/{print \$2}' |tr -d \\042  | xargs -i sh -c 'echo -n -e /etc/pam.d/{} \\\t; sum /etc/pam.d/{}'"
   clush $parg "echo 'HiveServer2 Impersonation'; ls /opt/mapr/roles |grep -q hiveserver2 && awk '/<prop/,/<\/prop/ {if (/enable.doAs/) {print;f=1}; if (/value/&&f) {print;f=0}}' /opt/mapr/hive/hive-*/conf/hive-site.xml || echo HiveServer2 not installed"
   clush $parg "echo 'Hive MetaStore Impersonation'; ls /opt/mapr/roles |grep -q metastore && awk '/<prop/,/<\/prop/ {if (/setugi/) {print;f=1}; if (/value/&&f) {print;f=0}}' /opt/mapr/hive/hive-*/conf/hive-site.xml || echo Hive MetaStore not installed"
   clush $parg "echo 'Hive MetaStore Password'; ls /opt/mapr/roles |grep -q metastore && awk '/<prop/,/<\/prop/ {if (/javax.jdo.option.ConnectionPassword/) {print;f=1}; if (/value/&&f) {print;f=0}}' /opt/mapr/hive/hive-*/conf/hive-site.xml"
   clush $parg "echo 'Hadoop Proxy Users'; awk '/<prop/,/<\/prop/ {if (/proxyuser/) {print;f=1}; if (/value/&&f) {print;f=0}}' /opt/mapr/hadoop/hadoop-2.*/etc/hadoop/core-site.xml"
   clush $parg "echo 'MapR Proxy Users'; ls /opt/mapr/conf/proxy"
   clush $parg "echo 'Drill Impersonation'; ls /opt/mapr/roles |grep -q drill && awk '/impersonation/,/}/ {if (/enabled:/) print}' /opt/mapr/drill/drill-1.*/conf/drill-override.conf || echo Drill not installed"
   clush $parg "echo 'Oozie Proxy Settings '; ls /opt/mapr/roles |grep -q oozie && awk '/<prop/,/<\/prop/ {if (/ProxyUserService/) {print;f=1}; if (/value/&&f) {print;f=0}}' /opt/mapr/oozie/oozie-*/conf/oozie-site.xml || echo Oozie not installed"
   #TBD: Find Hue security settings
   echo
   #TBD: Check file permissions on files MapR embeds with passwords at install time, like /opt/mapr/hadoop/hadoop-0.20.2/conf/ssl-server.xml
   if [[ "$verbose" == "true" ]]; then
      clush $parg 'echo Checking for Saved Passwords; find /opt/mapr -type f \( -iname \*.xml\* -o -iname \*.conf\* -o -iname \*.json\* \) -exec grep -Hi -m1 -A1 -e password -e jceks {} \;'
   else
      clush $parg 'echo Checking for Saved Passwords; find /opt/mapr -regex "/opt/mapr/.*conf.old" -prune -o -regex "/opt/mapr/.*conf.new" -prune -o -regex "/opt/mapr/hadoop/hadoop-2.*/share" -prune -o -path /opt/mapr/hadoop/OLD_HADOOP_VERSIONS -prune -o -path /opt/mapr/tmp -o -type f \( -iname \*.xml\* -o -iname \*.conf\* -o -iname \*.json\* \) -exec grep -Hi -m1 -A1 -e password -e jceks {} \;'
   fi
   echo

   #TBD: Find or create firewall rules file containing all MapR Hadoop ports to enable IP tables on all nodes
   #portlist="8443 5181 7222 7221 9083 10000 10020 19888 14000 8002 8888 9001 50030 7443 1111 2049 9997 9998 8040 8041 8042 11000 111 8030 8031 8032 8033 8088 5660 6660"
   #for port in $portlist; do
   #   clush -ab "echo Hosts Connected To Port $port ========; lsof -i :$port | awk '{gsub(\":[0-9]+\",\" \",\$9); print \$9}' |sort -u |fgrep -v -e NAME -e \*"
   #done

   msg="Security Checks Completed"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   echo; echo CIS-CAT audit recommended for thorough Linux level security audit
}

volume_acls() {
   volumep=($(maprcli volume list -filter "[n!=mapr.*] and [n!=*local*]" -columns mountdir |sed -n '2,$p'))
   volumen=($(maprcli volume list -filter "[n!=mapr.*] and [n!=*local*]" -columns n |sed -n '2,$p'))
   mntpt=${mntpt:-/mapr/my.cluster.com}

   for item in "${volumep[@]}"; do
      echo Permissions for Volume Path $item and 2 Levels Down:
      find ${mntpt}${item} -maxdepth 2 -exec stat -c '%U %G %A %a %n' {} \; ; echo
   done
   for item in "${volumen[@]}"; do
      echo MapR ACLs for Volume "$item":
      maprcli acl show -type volume -name "$item"; echo
   done
}

setvars
maprcli_check
[[ "$edge" == "false" ]] && cluster_checks1

if ! type clush &>/dev/null; then 
   echo clush required for advanced options; exit 1
fi
if [[ $(nodeset -c @"${group:-all}") == 0 ]]; then
   echo group: "${group:-all}" does not exist; exit 2
fi
if ! clush $parg -S test -d /opt/mapr; then
   echo MapR not installed in node group "$group"; exit 3
fi
echo "$sep"

[[ "$(id -un)" != "$srvid" ]] && sudo_setup
[[ "$edge" == "false" && "$terse" == "false" ]] && cluster_checks2
[[ "$edge" == "false" && "$verbose" == "true" ]] && cluster_checks3
[[ "$edge" == "false" && "$volacl" == "true" ]] && volume_acls
[[ "$edge" == "true" ]] && edgenode_checks
[[ "$security" == "true" ]] && security_checks

echo "Extract cluster summary from the captured output log with awk: "
awkcmd='FNR==1 {print FILENAME}; /[ \t]+\"version\":/; '
awkcmd+='/[ \t]+\"cluster\":/,/},/'
echo "awk '$awkcmd' mapr-audit-*.log"

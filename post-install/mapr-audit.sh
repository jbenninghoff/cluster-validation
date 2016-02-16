#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

# A script to probe an installed MapR system configuration
# Assumes clush is installed, available from EPEL repository
# Log stdout/stderr with 'mapr-audit.sh |& tee mapr-audit.log'

verbose=false; terse=false; security=false; edge=false; group=all volacl=false
while getopts ":vtseag:" opt; do
   case $opt in
      v) verbose=true ;;
      t) terse=true ;;
      s) security=true ;;
      e) edge=true ;;
      g) group=$OPTARG ;;
      a) volacl=true; mntpt=$OPTARG ;;
      :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
      \?) echo "Invalid option: -$OPTARG" >&2; exit ;;
   esac
done

type clush >/dev/null 2>&1 || { echo clush required for this script; exit 1; }
parg="-b -g ${group:-all}" # Assuming clush group 'all' is configured
if [ ! -d /opt/mapr ]; then
   echo MapR not installed locally!
   clush $parg -S test -d /opt/mapr ||{ echo MapR not installed in group; exit; }
fi
sep='====================================================================='
mrv=$(hadoop version |awk 'NR==1 {printf("%1.1s\n", $2)}')
srvid=$(awk -F= '/mapr.daemon.user/ {print $2}' /opt/mapr/conf/daemon.conf)
if [ $(id -u) -ne 0 -a $(id -un) != "$srvid" ]; then
   echo You must run this script as the MapR service account or root
   exit
fi
if [ $(id -u) -ne 0 ]; then
   SUDO="sudo"
   parg="-o -qtt $parg" # Add -qtt for sudo via ssh/clush
   ${node:-} $SUDO -ln | grep 'sudo: a password is required' && exit
   #TBD: Support password sudo using -S -i
   #read -s -e -p 'Enter sudo password: ' mypasswd
   #echo $mypasswd | sudo -S -i dmidecode -t bios || exit
   #SUDO="echo $mypasswd | sudo -S -i "
fi

# Function definitions, overall function flow executed at end of script

maprcli_check() {
   if ( ! type maprcli > /dev/null 2>&1 ); then #If maprcli not on this machine
      node=''; #node=$(nodeset -I0 -e $group)
      [ -z "$node" ] && read -e -p 'maprcli not found, enter host name that can run maprcli: ' node
      if ( ! ssh $node "type maprcli > /dev/null 2>&1" ); then
         echo maprcli not found on host $node, rerun with valid host name; exit
      fi
      node="ssh -qtt $node" #Single node to run maprcli commands from
   fi
}

cluster_checks1() {
   echo ==================== MapR audits ================================
   date; echo $sep
   if [ "$mrv" == "1" ] ; then # MRv1
      msg="Hadoop Jobs Status "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
      ${node:-} hadoop job -list; echo $sep
   else
      msg="Hadoop Jobs Status "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
      ${node:-} mapred job -list; echo $sep
   fi
   msg="MapR Dashboard "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   ${node:-} ${SUDO:-} maprcli dashboard info -json; echo $sep
   msg="MapR Alarms "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   ${node:-} ${SUDO:-} maprcli alarm list -summary true; echo $sep
   msg="MapR Services "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   ${node:-} ${SUDO:-} maprcli node list -columns hostname,svc; echo $sep
   msg="Zookeepers: "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   ${node:-} ${SUDO:-} maprcli node listzookeepers; echo $sep
   msg="MapR System Stats "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   ${node:-} ${SUDO:-} maprcli node list -columns hostname,cpus,mused; echo $sep
   echo
}

cluster_checks2() {
   msg="MapR Storage Pools "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg ${SUDO:-} /opt/mapr/server/mrconfig sp list -v; echo $sep
   #awk '/^MapR Storage/,/^=======/' mapr-audit.log |egrep -o '^SP.*:|disks .*$|^<hostprefix>.*' >SPdisks.log
   msg="MapR Site Specific Volumes "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   ${node:-} ${SUDO:-} maprcli volume list -filter "[n!=mapr.*] and [n!=*local*]" -columns n,numreplicas,mountdir,used,numcontainers,logicalUsed; echo $sep
   msg="Cat mapr-clusters.conf, Checking for MapR Mirror enabling "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg ${SUDO:-} cat /opt/mapr/conf/mapr-clusters.conf; echo $sep
   #TBD: if mapr-clusters.conf has more than one line, look for mirror volumes {maprcli volume list -json |grep mirror???}
   msg="MapR Env Settings "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg ${SUDO:-} grep ^export /opt/mapr/conf/env.sh; echo $sep
   msg="Mapred-site.xml Checksum Consistency "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg ${SUDO:-} sum /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml; echo $sep
   msg="MapR Central Configuration Setting "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg ${SUDO:-} grep centralconfig /opt/mapr/conf/warden.conf; echo $sep
   msg="MapR Central Logging Setting "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg ${SUDO:-} grep ROOT_LOGGER /opt/mapr/hadoop/hadoop-0.20.2/conf/hadoop-env.sh; echo $sep
   msg="MapR Roles Per Host "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg ${SUDO:-} ls /opt/mapr/roles; echo $sep
   #msg="MapR Directories "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   #clush $parg ${SUDO:-} "find /opt/mapr -maxdepth 1 -type d |sort"; echo $sep
   echo
}

edgenode_checks() {
   :
}

anynode_checks() {
   if [ "$edge" == "true" ]; then
      msg="Edge Node Checking "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
      echo
   fi
   msg="MapR packages installed "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg ${SUDO:-} 'rpm -qa |grep mapr- |sort'; echo $sep
}

indepth_checks() {
   msg="Verbose audits "; printf "%s%s \n" "$msg" "${sep:${#msg}}"; echo
   #$node maprcli dump balancerinfo | sort | awk '$1 == prvkey {size += $9}; $1 != prvkey {if (prvkey!="") print size; prvkey=$1; size=$9}'
   #echo MapR disk list per host
   msg="MapR Disk List per Host "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   clush $parg ${SUDO:-} 'maprcli disk list -output terse -system 0 -host $(hostname)'; echo $sep
   msg="MapR Disk Stripe Depth "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   clush $parg ${SUDO:-} '/opt/mapr/server/mrconfig dg list | grep -A4 StripeDepth'; echo $sep
   msg="MapR Complete Volume List "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   ${node:-} ${SUDO:-} maprcli volume list -columns n,numreplicas,mountdir,used,numcontainers,logicalUsed; echo $sep
   msg="MapR Storage Pool Details "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   ${node:-} ${SUDO:-} maprcli dump balancerinfo | sort -r; echo $sep
   msg="Hadoop Configuration Variable Dump "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   ${node:-} ${SUDO:-} hadoop conf -dump | sort; echo $sep
   msg="MapR Configuration Variable Dump "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   ${node:-} ${SUDO:-} maprcli config load -json; echo $sep
   #msg="List Unique File Owners, Down 4 Levels"; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   #${node:-} ${SUDO:-} find /shared/hdfs -maxdepth 4 -exec stat -c '%U' {} \; |sort -u; echo $sep #loopbackmnt=/shared/hdfs or /mapr/cluster #find uniq owners
   # TBD: check all hadoop* packages installed
}

security_checks() {
   msg="MapR Security Checks "; printf "%s%s \n" "$msg" "${sep:${#msg}}"; echo

   # Edge or Cluster nodes (Linux checks)
   msg="SElinux Status "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   clush $parg ${SUDO:-} "echo -n 'SElinux status: '; ([ -d /etc/selinux -a -f /etc/selinux/config ] && grep ^SELINUX= /etc/selinux/config) || echo Disabled"; echo
   msg="Nsswitch.conf Permissions and Settings "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
   clush $parg ${SUDO:-} "echo Checking Permissions on /etc/nsswitch.conf; stat -c '%U %G %A %a %n' /etc/nsswitch.conf"
   clush $parg ${SUDO:-} 'echo Checking for nsswitch.conf settings; grep -v -e ^# -e ^$ /etc/nsswitch.conf'; echo
   clush $parg ${SUDO:-} "echo Checking Permissions on /tmp; stat -c '%U %G %A %a %n' /tmp"
   clush $parg ${SUDO:-} "service ntpd status|sed 's/(.*)//'"
   clush $parg ${SUDO:-} 'service sssd status|sed "s/(.*)//"; wc /etc/sssd/sssd.conf' #TBD: Check sssd settings
   clush $parg ${SUDO:-} "service krb5kbc status |sed 's/(.*)//'; service kadmin status |sed 's/(.*)//'" # Check for Kerberos
   clush $parg ${SUDO:-} "echo Checking for Firewall; service iptables status |sed 's/(.*)//'"
   clush $parg ${SUDO:-} 'echo Checking for LUKS; grep -v -e ^# -e ^$ /etc/crypttab'
   clush $parg ${SUDO:-} 'echo Checking for C and Java Compilers; type gcc; type javac; find /usr/lib -name javac|sort'
   #TBD: clush $parg ${SUDO:-} 'echo Checking MySQL; type mysql && mysql -u root -e "show databases" && echo "Passwordless MySQL access"'
   clush $parg ${SUDO:-} 'echo Checking for Internet Access; { curl -f http://mapr.com/ 2>/dev/null >/dev/null || curl -f http://54.245.106.105/; } && echo Internet Access Available || echo Internet Access Denied'
   clush $parg ${SUDO:-} "echo Checking TCP/UDP Listening Sockets; netstat -tpe"
   clush $parg ${SUDO:-} "echo Checking All TCP/UDP connections; netstat -t -u --numeric-ports"

   # Cluster nodes only
   if [ "$edge" == "false" ]; then
      msg="MapR Secure Mode "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
      ${node:-} ${SUDO:-} maprcli dashboard info -json | grep secure
      msg="MapR Auditing Enabled "; printf "%s%s \n" "$msg" "${sep:${#msg}}"
      ${node:-} ${SUDO:-} maprcli config load -json | grep "mfs.feature.audit.support" #TBD:If true, set secure-cluster flag
      msg="MapR Cluster Admin ACLs"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
      ${node:-} ${SUDO:-} maprcli acl show -type cluster
      # Check for MapR whitelist: http://doc.mapr.com/display/MapR/Configuring+MapR+Security#ConfiguringMapRSecurity-whitelist
      msg="MapR MFS Whitelist Defined "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
      clush $parg ${SUDO:-} grep mfs.subnets.whitelist /opt/mapr/conf/mfs.conf
      msg="MapR YARN Submit ACLs "; printf "%s%s \n" "$msg" "${sep:${#msg}}"             
      clush $parg ${SUDO:-} "awk '/<queue/,/<\/queue>/ {if (/acl|<queue /&&!/<!--/) print}' /opt/mapr/hadoop/hadoop-2*/etc/hadoop/fair-scheduler.xml"
      clush $parg ${SUDO:-} "echo Checking Zookeeper Secure Mode; grep -i ^auth /opt/mapr/zookeeper/zookeeper-*/conf/zoo.cfg"
   fi
   # Edge or Cluster nodes
   clush $parg ${SUDO:-} "service mapr-nfsserver status|sed 's/(.*)//'"
   # NFS Exports should be limited to subnet(s) (whitelist) and squash all root access
   clush $parg ${SUDO:-} 'echo Checking NFS Exports; grep -v -e ^# -e ^$ /opt/mapr/conf/exports /etc/exports'
   clush $parg ${SUDO:-} 'echo Checking Active NFS Exports; showmount -e'
   clush $parg ${SUDO:-} 'echo Checking Active NFS Mounts; showmount -a'
   #clush $parg ${SUDO:-} "echo Is MapR Patch Installed?; yum list mapr-patch"
   clush $parg ${SUDO:-} "echo Ownership of /opt/mapr Must Be root; stat -c '%U %G %A %a %n' /opt/mapr"
   clush $parg ${SUDO:-} "echo Find Setuid Executables in /opt/mapr;  find /opt/mapr -type f \( -perm -4100 -o -perm -2010 \) -exec stat -c '%U %G %A %a %n' {} \; |sort"
   #clush $parg ${SUDO:-} "echo Find Setuid Executables in /opt/mapr; find /opt/mapr -perm +6000 -type f -exec stat -c '%U %G %A %a %n' {} \; |sort"
   clush $parg ${SUDO:-} "awk '/^jpamLogin/,/};/' /opt/mapr/conf/mapr.login.conf" # Check MapR JPAM settings
   clush $parg ${SUDO:-} "echo CheckSum of /etc/pam.d files; awk '/^jpamLogin/,/};/' /opt/mapr/conf/mapr.login.conf | awk -F= '/serviceName/{print \$2}' |tr -d \\042  | xargs -i sh -c 'echo -n -e /etc/pam.d/{} \\\t; sum /etc/pam.d/{}'"; echo
   clush $parg ${SUDO:-} 'echo Checking for Saved Passwords; find /opt/mapr -type f \( -iname \*.xml\* -o -iname \*.conf\* -o -iname \*.json\* \) -exec grep -Hi -m1 -A1 -e password -e jceks {} \;'; echo

   #portlist="8443 5181 7222 7221 9083 10000 10020 19888 14000 8002 8888 9001 50030 7443 1111 2049 9997 9998 8040 8041 8042 11000 111 8030 8031 8032 8033 8088 5660 6660"
   #for port in $portlist; do
   #   clush -ab "echo Hosts Connected To Port $port ========; lsof -i :$port | awk '{gsub(\":[0-9]+\",\" \",\$9); print \$9}' |sort -u |fgrep -v -e NAME -e \*"
   #done

   msg="Security Checks Completed"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   echo; echo CIS-CAT recommended for thorough Linux level security audit
}

volume_acls() {
   volumep=($(maprcli volume list -filter "[n!=mapr.*] and [n!=*local*]" -columns mountdir |sed -n '2,$p'))
   volumen=($(maprcli volume list -filter "[n!=mapr.*] and [n!=*local*]" -columns n |sed -n '2,$p'))
   mntpt=/mapr/my.cluster.com

   for item in "${volumep[@]}"; do
      find ${mntpt}${item} -maxdepth 2 -exec stat -c '%U %G %A %a %n' {} \; echo
   done
   for item in "${volumen[@]}"; do
      maprcli acl show -type volume -name ${item}; echo
   done
}

[ "$edge" == "false" ] && maprcli_check
[ "$edge" == "false" ] && cluster_checks1
[ "$edge" == "false" -a "$terse" == "false" ] && cluster_checks2
[ "$terse" == "false" ] && anynode_checks
[ "$verbose" == "true" -a "$edge" == "false" ] && indepth_checks
[ "$security" == "true" ] && security_checks
[ "$volacl" == "true" ] && volume_acls

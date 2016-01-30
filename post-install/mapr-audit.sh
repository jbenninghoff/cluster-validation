#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

# A sequence of maprcli commands to probe installed system configuration
# Assumes clush is installed, available from EPEL repository
# Log stdout/stderr with 'mapr-audit.sh |& tee mapr-audit.log'

if ( ! type maprcli > /dev/null 2>&1 ); then #If maprcli not on this machine
   node=''
   [ -z "$node" ] && read -e -p 'maprcli not found, enter host name that can run maprcli: ' node
   if ( ! ssh $node "type maprcli > /dev/null 2>&1" ); then
      echo maprcli not found on host $node, rerun with valid host name; exit
   fi
   node="ssh -qtt $node" #Single node to run maprcli commands from
fi

parg='-b -g all' # Assuming clush group 'all' is configured to reach all nodes
sep='====================================================================='
MRV=$(${node:-} hadoop version | awk 'NR==1{printf("%1.1s\n",$2)}')
srvid=$(awk -F= '/mapr.daemon.user/{ print $2}' /opt/mapr/conf/daemon.conf)
[ $(id -un) != $srvid -a $(id -u) -ne 0 ] && { echo You mus#t be logged in as the MapR service account or root to run this script; exit; }
[ $(id -u) -ne 0 ] && { SUDO="-o -qtt sudo"; }
#TBD check for $srvid sudo capability, needed for security option

verbose=false; terse=false; security=false
while getopts ":vts" opt; do
   case $opt in
      v) verbose=true ;;
      t) terse=true ;;
      s) security=true ;;
      \?) echo "Invalid option: -$OPTARG" >&2; exit ;;
   esac
done

echo ==================== MapR audits ================================
date; echo $sep
if [ "$MRV" == "1" ] ; then # MRv1
   msg="Hadoop Jobs Status"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   ${node:-} hadoop job -list; echo $sep
else
   msg="Hadoop Jobs Status"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   ${node:-} mapred job -list; echo $sep
fi
msg="MapR Dashboard"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
${node:-} ${SUDO:-} maprcli dashboard info -json; echo $sep
msg="MapR Alarms"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
${node:-} ${SUDO:-} maprcli alarm list -summary true; echo $sep
msg="MapR Services"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
${node:-} ${SUDO:-} maprcli node list -columns hostname,svc
msg="Zookeepers:"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
${node:-} ${SUDO:-} maprcli node listzookeepers; echo $sep
msg="MapR system stats"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
${node:-} ${SUDO:-} maprcli node list -columns hostname,cpus,mused; echo $sep
[ "$terse" == "true" ] && exit

msg="MapR Storage Pools"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
clush $parg ${SUDO:-} /opt/mapr/server/mrconfig sp list -v; echo $sep
msg="MapR Volumes"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
${node:-} ${SUDO:-} maprcli volume list -filter "[n!=mapr.*] and [n!=*local*]" -columns n,numreplicas,mountdir,used,numcontainers,logicalUsed; echo $sep
msg="MapR env settings"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
clush $parg ${SUDO:-} grep ^export /opt/mapr/conf/env.sh
msg="mapred-site.xml checksum consistency"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
clush $parg ${SUDO:-} sum /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml; echo $sep
msg="MapR Central Configuration setting"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
clush $parg ${SUDO:-} grep centralconfig /opt/mapr/conf/warden.conf
msg="MapR Central Logging setting"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
clush $parg ${SUDO:-} grep ROOT_LOGGER /opt/mapr/hadoop/hadoop-0.20.2/conf/hadoop-env.sh
msg="MapR roles per host"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
clush $parg ${SUDO:-} ls /opt/mapr/roles
msg="MapR packages installed"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
clush $parg ${SUDO:-} 'rpm -qa | grep mapr-'
# clush $parg ${SUDO:-} 'dpkg-query --list 'mapr-*''  # for Ubuntu

if [ "$verbose" == "true" ]; then
   msg="Verbose audits"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   #$node maprcli dump balancerinfo | sort | awk '$1 == prvkey {size += $9}; $1 != prvkey {if (prvkey!="") print size; prvkey=$1; size=$9}'
   #echo MapR disk list per host
   clush $parg ${SUDO:-} 'maprcli disk list -output terse -system 0 -host $(hostname)'
   clush $parg ${SUDO:-} '/opt/mapr/server/mrconfig dg list | grep -A4 StripeDepth'
   ${node:-} ${SUDO:-} maprcli volume list -columns numreplicas,mountdir,used,numcontainers,logicalUsed; echo $sep
   ${node:-} ${SUDO:-} maprcli dump balancerinfo | sort -r; echo $sep
   ${node:-} ${SUDO:-} hadoop conf -dump | sort; echo $sep
   ${node:-} ${SUDO:-} maprcli config load -json; echo $sep
   # TBD: check all hadoop* packages installed
fi

if [ "$security" == "true" ]; then
   msg="MapR security checks using clush and maprcli"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg ${SUDO:-} "echo -n 'SElinux status: '; ([ -d /etc/selinux -a -f /etc/selinux/config ] && grep ^SELINUX= /etc/selinux/config) || echo Disabled"
   clush $parg ${SUDO:-} 'echo Checking for nsswitch.conf settings; grep -v -e ^# -e ^$ /etc/nsswitch.conf'
   clush $parg ${SUDO:-} "echo Checking Permissions on /tmp; stat -c '%U %G %A %a %n' /tmp"
   clush $parg ${SUDO:-} "service ntpd status|sed 's/(.*)//'"
   clush $parg ${SUDO:-} 'service sssd status|sed "s/(.*)//"; wc /etc/sssd/sssd.conf' #TBD: Check sssd settings
   clush $parg ${SUDO:-} "service krb5kbc status |sed 's/(.*)//'; service kadmin status |sed 's/(.*)//'" # Check for Kerberos
   clush $parg ${SUDO:-} "echo Checking for Firewall; service iptables status |sed 's/(.*)//'"
   clush $parg ${SUDO:-} 'echo Checking for LUKS; grep -v -e ^# -e ^$ /etc/crypttab'
   clush $parg ${SUDO:-} 'echo Checking for C and Java Compilers; type gcc; type javac; find /usr/lib -name javac|sort' # Check for compilers

   clush $parg ${SUDO:-} "service mapr-nfsserver status|sed 's/(.*)//'"
   # NFS Exports should be limited to subnet(s) (whitelist) and squash all root access
   clush $parg ${SUDO:-} 'echo Checking NFS Exports; grep -v -e ^# -e ^$ /opt/mapr/conf/exports /etc/exports' #Check NFS exports
   ${SUDO:-} maprcli dashboard info -json | grep secure
   ${SUDO:-} maprcli config load -json | grep "mfs.feature.audit.support" #TBD:If true, set flag
   clush $parg -B ${SUDO:-} "echo Is MapR Patch Installed?; yum list mapr-patch"
   clush $parg ${SUDO:-} "echo Ownership of /opt/mapr Must Be root; stat -c '%U %G %A %a %n' /opt/mapr"
   clush $parg ${SUDO:-} "echo Find Setuid Executables in /opt/mapr; find /opt/mapr -perm +6000 -type f -exec stat -c '%U %G %A %a %n' {} \; |sort"
   # Check for MapR whitelist: http://doc.mapr.com/display/MapR/Configuring+MapR+Security#ConfiguringMapRSecurity-whitelist
   clush $parg ${SUDO:-} grep mfs.subnets.whitelist /opt/mapr/conf/mfs.conf
   clush $parg ${SUDO:-} "awk '/^jpamLogin/,/};/' /opt/mapr/conf/mapr.login.conf" # Check MapR JPAM settings
   clush $parg ${SUDO:-} "echo Check Sum of /etc/pam.d files; awk '/^jpamLogin/,/};/' /opt/mapr/conf/mapr.login.conf | awk -F= '/serviceName/{print \$2}' |tr -d \\042  | xargs -i sum /etc/pam.d/{}"
   clush $parg ${SUDO:-} "echo Checking for Zookeeper Secure Mode; grep -i ^auth /opt/mapr/zookeeper/zookeeper-*/conf/zoo.cfg"
   clush $parg ${SUDO:-} 'echo Checking for Saved Passwords; find /opt/mapr -type f \( -iname \*.xml\* -o -iname \*.conf\* -o -iname \*.json\* \) -exec grep -Hi -m1 -A2 -e password -e jceks {} \;'
   echo; echo ; echo Check for MapR specific ports
   portlist="8443 5181 7222 7221 9083 10000 10020 19888 14000 8002 8888 9001 50030 7443 1111 2049 9997 9998 8040 8041 8042 11000 111 8030 8031 8032 8033 8088 5660 6660"
   for port in $portlist; do
      clush -ab "echo Hosts Connected To Port $port ========; lsof -i :$port | awk '{gsub(\":[0-9]+\",\" \",\$9); print \$9}' |sort -u |fgrep -v -e NAME -e \*"
   done

   echo Grep this log for unique hostnames connecting to MapR like this:
   echo "grep -o '\->.*' mapr-audit-security2.log| sort -u |fgrep -v '</'"

   echo CIS-CAT recommended for thorough Linux level security audit
   exit
   echo
   echo Check for accounts with access
   echo Check for accounts with admin or root access
   echo Check for reliability?  HA, NIC bonding, SPs, etc

   echo Linux security checks ==============================
   echo CIS-CAT recommended for thorough Linux level security audit
fi


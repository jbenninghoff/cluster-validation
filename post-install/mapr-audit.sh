#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:

# A sequence of maprcli commands to probe installed system configuration
# Assumes clush is installed, available from EPEL repository
# Log stdout/stderr with 'mapr-audit.sh |& tee mapr-audit.log'

if ( ! type maprcli > /dev/null 2>&1 ); then
   node=''
   [ -z "$node" ] && read -e -p 'maprcli not found, enter host name that can run maprcli: ' node
   if ( ! ssh $node "type maprcli > /dev/null 2>&1" ); then
      echo maprcli not found on host $node, rerun with valid host name; exit
   fi
   node="ssh -qtt $node" #Single node to run maprcli commands from
fi

parg='-B -g all' # Assuming clush group 'all' is configured to reach all nodes
[ $(id -u) -ne 0 ] && SUDO=sudo
sep='====================================================================='
MRV=$(${node:-} hadoop version | awk 'NR==1{printf("%1.1s\n",$2)}')

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
${node:-} ${SUDO:-} maprcli volume list -columns numreplicas,mountdir,used,numcontainers,logicalUsed; echo $sep
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
   ${node:-} ${SUDO:-} maprcli dump balancerinfo | sort -r; echo $sep
   ${node:-} ${SUDO:-} hadoop conf -dump | sort; echo $sep
   ${node:-} ${SUDO:-} maprcli config load -json; echo $sep
   # TBD: check all hadoop* packages installed
fi

if [ "$security" == "true" ]; then
   msg="MapR security checks"; printf "%s%s \n" "$msg" "${sep:${#msg}}"
   clush $parg ${SUDO:-} ls -ld /opt/mapr
   clush $parg ${SUDO:-} find /opt/mapr -perm +6000 -type f -exec ls -ld {} \;
   echo Check for mapr-patch installation and version
   echo Check for Data encryption over the wire (secure cluster)
   echo Check for passwords in files like hive-site.xml
   echo Check /etc/exports and /opt/mapr/conf/exports
   echo Check for Sqoop password or keystore{java}
   echo Check for Data encryption at rest
   echo Check for MFS auditing
   echo Check PAM settings
   echo Check sssd settings
   echo Check for Kerberos
   echo Check for compilers
   echo Check for zookeeper secure mode
   echo Check for accounts with access
   echo Check for accounts with admin or root access
   echo Check for reliability?  HA, NIC bonding, SPs, etc

   echo Linux security checks ==============================
   echo Recommend CIS-CAT for thorough Linux level security audit
   clush $parg ${SUDO:-} ls -ld /tmp
   clush $parg ${SUDO:-} stat -c %a /tmp | grep -q 1777
fi

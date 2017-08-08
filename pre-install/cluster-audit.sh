#!/bin/bash
# jbenninghoff 2013-Oct-06  vi: set ai et sw=3 tabstop=3:
#set -o nounset
#set -o errexit

usage() {
cat << EOF
Usage: $0 -g -d -l
-g To specify clush group other than "all"
-d To enable debug output
-l To specify clush/ssh user other than $USER

This script is a sequence of parallel shell commands probing for
current system configuration and highlighting differences between
the nodes in a cluster.

The script requires that the clush utility (a parallel ssh tool)
be installed and configured using passwordless ssh connectivity for root to
all the nodes under test.  Or passwordless sudo for a non-root account.
Use -l mapr for example if mapr account has passwordless sudo rights.

EOF
}

# Handle script options
DBG=""; group=all; cluser=""
while getopts "dl:g:" opt; do
  case $opt in
    d) DBG=true ;;
    g) group=$OPTARG ;;
    l) cluser="-l $OPTARG" ;;
    \?) usage; exit ;;
  esac
done
[ -n "$DBG" ] && set -x

# Set some global variables
sep=$(printf %80s); sep=${sep// /#} #Substitute all blanks with ######
distro=$(cat /etc/*release 2>&1 |grep -m1 -i -o -e ubuntu -e redhat -e 'red hat' -e centos -e sles) || distro=centos
distro=$(echo $distro | tr '[:upper:]' '[:lower:]')
#distro=$(lsb_release -is | tr [[:upper:]] [[:lower:]])

# Check for clush and provide alt if not found
if type clush >& /dev/null; then
   [ $(nodeset -c @${group:-all}) -gt 0 ] || { echo group: ${group:-all} does not exist; exit 2; } && { echo NodeSet: $(nodeset -e @${group:-all}); }
   echo $sep
   echo All the groups currently defined for clush:; $(nodeset -l); echo groups zk, cldb, rm, and hist should be defined for clush install
   echo $sep
   #clush specific arguments
   parg="${cluser} -b -g ${group:-all}"
   parg1="-S"
   parg2="-B"
   parg3="-u 30"
   parg4="-qNS -g ${group:-all}"
   node=$(nodeset -I0 -e @${group:-all})
   narg="-w $node -o -qtt"
   #echo Use: "(umask 0077 && sed -i -e '/^StrictHostKeyChecking/{s/.*/StrictHostKeyChecking no/;:a;n;ba;q}' -e '$aStrictHostKeyChecking no' $HOME/.ssh/config)" To remove ssh noise
   #(umask 0077 && printf "ServerAliveInterval 99\nStrictHostKeyChecking no\nLogLevel ERROR\n" >> $HOME/.ssh/config)
   # Common arguments to pass in to clush execution
   #clcnt=$(nodeset -c @all)
   #parg="$parg -f $clcnt" #fanout set to cluster node count
   #parg="-o '-oLogLevel=ERROR' $parg"
else
   echo clush not found, doing a single node inspection without ssh
   clush() { eval "$@"; } #clush becomes no-op, all commands run locally doing a single node inspection
   #clush() { for h in $(<~/host.list); do; ssh $h $@; done; } #ssh in for loop
fi
[ -n "$DBG" ] && { clush $parg $parg1 ${parg3/0 /} date || { echo clush failed; usage; exit 3; }; }

# Locate or guess MapR Service Account
if [ -f /opt/mapr/conf/daemon.conf ]; then
   serviceacct=$(awk -F= '/mapr.daemon.user/ {print $2}' /opt/mapr/conf/daemon.conf)
   [ -z "$serviceacct" ] && serviceacct=mapr #guess
else
   serviceacct=mapr #guess
fi

# Define Sudo options if available
if [[ $(id -u) -ne 0 && "$cluser" != "-l root" ]]; then
   if (clush $narg sudo -ln 2>&1 | grep -q 'sudo: a password is required'); then
      read -s -e -p 'Enter sudo password: ' mypasswd
      #echo $mypasswd | sudo -S -i dmidecode -t bios || exit
      SUDO="echo $mypasswd | sudo -S -i "
   else
      SUDO='sudo PATH=/sbin:/usr/sbin:$PATH '
   fi
   if (clush $narg $parg1 "${SUDO:-} grep -q '^Defaults.*requiretty' /etc/sudoers" >& /dev/null); then
      parg="-o -qtt $parg" # Add -qtt for sudo tty via ssh/clush
      #echo Use: clush -ab -o -qtt "sudo sed -i.bak '/^Defaults.*requiretty/s/^/#/' /etc/sudoers"  To run sudo without a tty
   fi
fi

# Check for systemd and basic RPMs
sysd=$(clush $parg4 "[ -f /etc/systemd/system.conf ]" && echo true || echo false )
case $distro in
   redhat|centos|red*|sles)
   if ! clush $parg $parg1 "rpm -q bind-utils pciutils dmidecode net-tools ethtool"; then
      echo RPMs required for audit not installed!
      echo "Install packages on all nodes with clush: clush -ab 'yum -y install bind-utils pciutils dmidecode net-tools ethtool'"
      exit
   fi
   ;;
   ubuntu)
   if ! clush $parg $parg1 "dpkg -l bind9utils pciutils dmidecode net-tools ethtool"; then
      echo Packages required for audit not installed!
      echo "Install packages on all nodes with clush: clush -ab 'apt-get -y install bind9utils pciutils dmidecode net-tools ethtool'"
      exit
   fi
   ;;
esac

[ -n "$DBG" ] && { echo sysd: $sysd; echo serviceacct: $serviceacct; echo SUDO: $SUDO; echo parg: $parg; echo node: $node; }
[ -n "$DBG" ] && exit


echo;echo "#################### Hardware audits ################################"
date; echo $sep
# probe for system info ###############
clush $parg "echo DMI Sys Info:; ${SUDO:-} dmidecode | grep -A2 '^System Information'"; echo $sep
clush $parg "echo DMI BIOS:; ${SUDO:-} dmidecode | grep -A3 '^BIOS I'"; echo $sep

# probe for cpu info ###############
clush $parg "grep '^model name' /proc/cpuinfo | sort -u"; echo $sep
clush $parg "lscpu | grep -v -e op-mode -e ^Vendor -e family -e Model: -e Stepping: -e BogoMIPS -e Virtual -e ^Byte -e '^NUMA node(s)' | awk '/^CPU MHz:/{sub(\$3,sprintf(\"%0.0f\",\$3))};{print}'"; echo $sep
clush $parg "lscpu | grep -e ^Thread"; echo $sep
#TBD: grep '^model name' /proc/cpuinfo | sed 's/.*CPU[ ]*\(.*\)[ ]*@.*/\1/'
#TBD: curl -s -L 'http://ark.intel.com/search?q=E5-2420%20v2' | grep -A2 -e 'Memory Channels' -e 'Max Memory Bandwidth'

# probe for mem/dimm info ###############
clush $parg "cat /proc/meminfo | grep -i ^memt | uniq"; echo $sep
clush $parg "echo -n 'DIMM slots: '; ${SUDO:-} dmidecode -t memory |grep -c '^[[:space:]]*Locator:'"; echo $sep
clush $parg "echo -n 'DIMM count is: '; ${SUDO:-} dmidecode -t memory | grep -c '^[[:space:]]Size: [0-9][0-9]*'"; echo $sep
clush $parg "echo DIMM Details; ${SUDO:-} dmidecode -t memory | awk '/Memory Device$/,/^$/ {print}' | grep -e '^Mem' -e Size: -e Speed: -e Part | sort -u | grep -v -e 'NO DIMM' -e 'No Module Installed' -e 'Not Specified'"; echo $sep

# probe for nic info ###############
#clush $parg "ifconfig | grep -o ^eth.| xargs -l ${SUDO:-} /usr/sbin/ethtool | grep -e ^Settings -e Speed -e detected" 
#clush $parg "ifconfig | awk '/^[^ ]/ && \$1 !~ /lo/{print \$1}' | xargs -l ${SUDO:-} /usr/sbin/ethtool | grep -e ^Settings -e Speed" 
clush $parg "${SUDO:-} lspci | grep -i ether"
clush $parg ${SUDO:-} "ip link show | sed '/ lo: /,+1d' | awk '/UP/{sub(\":\",\"\",\$2);print \$2}' | xargs -l /sbin/ethtool | grep -e ^Settings -e Speed -e Link"
#TBD: fix SUDO to find ethtool, not /sbin/ethtool
#clush $parg "echo -n 'Nic Speed: '; /sbin/ip link show | sed '/ lo: /,+1d' | awk '/UP/{sub(\":\",\"\",\$2);print \$2}' | xargs -l -I % cat /sys/class/net/%/speed"
echo $sep
[ -n "$DBG" ] && exit

# probe for disk info ###############
#TBD: Probe disk controller settings, needs storcli64 binary, won't work on HP which needs smartarray tool
#/opt/MegaRAID/storcli/storcli64 /c0 /eall /sall show | awk '$3 == "UGood"{print $1}'; exit 
#./MegaCli64 -cfgeachdskraid0 WT RA cached NoCachedBadBBU –strpsz256 -a0
clush $parg "echo 'Storage Controller: '; ${SUDO:-} lspci | grep -i -e ide -e raid -e storage -e lsi"; echo $sep
clush $parg "echo 'SCSI RAID devices in dmesg: '; ${SUDO:-} dmesg | grep -i raid | grep -i -o 'scsi.*$' |uniq"; echo $sep
case $distro in
   ubuntu)
   clush $parg "${SUDO:-} fdisk -l | grep '^Disk /.*:' |sort"; echo $sep
   ;;
   redhat|centos|red*|sles)
   clush $parg "echo 'Block Devices: '; lsblk -id -o NAME,SIZE,TYPE,MOUNTPOINT |grep -v ^sr0"; echo $sep
   ;;
   *) echo Unknown Linux distro! $distro; exit ;;
esac
clush $parg "echo 'Udev rules: '; ${SUDO:-} ls /etc/udev/rules.d"; echo $sep
#clush $parg "echo 'Storage Drive(s): '; fdisk -l 2>/dev/null | grep '^Disk /dev/.*: ' | sort | grep mapper"
#clush $parg "echo 'Storage Drive(s): '; fdisk -l 2>/dev/null | grep '^Disk /dev/.*: ' | sort | grep -v mapper"

echo
echo "#################### Linux audits ################################"
#clush $parg "cat /etc/*release | uniq"; echo $sep
clush $parg "[ -f /etc/system-release ] && cat /etc/system-release || cat /etc/os-release | uniq"; echo $sep
clush $parg "uname -a | fmt"; echo $sep
clush $parg "echo Time Sync Check: ; date"; echo $sep

case $distro in
   ubuntu)
      # Ubuntu SElinux tools not so good.
      clush $parg "echo 'NTP status '; ${SUDO:-} service ntpd status"; echo $sep
      clush $parg "${SUDO:-} apparmor_status | sed 's/([0-9]*)//'"; echo $sep
      clush $parg "echo -n 'SElinux status: '; ([ -d /etc/selinux -a -f /etc/selinux/config ] && grep ^SELINUX= /etc/selinux/config) || echo Disabled"
      echo $sep
      clush $parg "echo 'Firewall status: '; ${SUDO:-} service ufw status | head -10"; echo $sep
      clush $parg "echo 'IPtables status: '; ${SUDO:-} iptables -L | head -10"; echo $sep
      clush $parg "echo 'NFS packages installed '; dpkg -l '*nfs*' | grep ^i"; echo $sep
   ;;
   redhat|centos|red*|sles)
      if [[ "$distro" != "sles" ]]; then
         clush $parg 'echo "MapR Repos Check "; yum --noplugins repolist | grep -i mapr && yum -q info mapr-core mapr-spark mapr-patch';echo $sep
         #clush $parg 'echo "MapR Repos Check "; grep -li mapr /etc/yum.repos.d/* |xargs -l grep -Hi baseurl && yum -q info mapr-core mapr-spark mapr-patch';echo $sep
      else
         clush $parg 'echo "MapR Repos Check "; zypper repos | grep -i mapr && zypper -q info mapr-core mapr-spark mapr-patch';echo $sep
         #clush $parg 'echo "MapR Repos Check "; grep -li mapr /etc/zypp/repos.d/* |xargs -l grep -Hi baseurl && zypper -q info mapr-core mapr-spark mapr-patch';echo $sep
      fi
      clush $parg 'echo "NFS packages installed "; rpm -qa | grep -i nfs |sort' ; echo $sep
      pkgs="dmidecode bind-utils irqbalance syslinux hdparm sdparm rpcbind nfs-utils redhat-lsb-core ntp" #TBD: SLES should have lsb5-core
      clush $parg "echo Required RPMs: ; rpm -q $pkgs | grep 'is not installed' || echo All Required Installed"; echo $sep
      pkgs="patch nc dstat xml2 jq git tmux zsh vim nmap mysql mysql-server tuned smartmontools pciutils lsof lvm2 iftop ntop iotop atop ftop htop ntpdate tree net-tools ethtool"
      clush $parg "echo Optional  RPMs: ; rpm -q $pkgs | grep 'is not installed' |sort" ; echo $sep
      clush $parg "echo -n 'SElinux status: '; grep ^SELINUX= /etc/selinux/config; ${SUDO:-} getenforce" ; echo $sep
      #TBD suggest: setenforce Permissive and sed -i.bak 's/enforcing/permissive/' /etc/selinux/config
      case $sysd in
         true)
            clush $parg "ntpstat | head -1" ; echo $sep
            clush $parg "${SUDO:-} systemctl list-dependencies iptables"; echo $sep
            clush $parg "${SUDO:-} systemctl status iptables"; echo $sep
            clush $parg "${SUDO:-} systemctl status firewalld"; echo $sep
            clush $parg "${SUDO:-} systemctl status cpuspeed"; echo $sep
         ;;
         false)
            clush $parg "echo 'NTP status '; ${SUDO:-} service ntpd status |sed 's/(.*)//'"; echo $sep
            clush $parg "${SUDO:-} chkconfig --list iptables" ; echo $sep
            clush $parg "${SUDO:-} service iptables status | head -10"; echo $sep
            clush $parg "echo -n 'CPUspeed Service: '; ${SUDO:-} service cpuspeed status"; echo $sep
            clush $parg "${SUDO:-} service sssd status|sed 's/(.*)//' && chkconfig --list sssd | grep -e 3:on -e 5:on >/dev/null"
            clush $parg "${SUDO:-} wc /etc/sssd/sssd.conf" #TBD: Check sssd settings and add sysd checks
            #clush $parg "/sbin/service iptables status | grep -m 3 -e ^Table -e ^Chain" 
            #clush $parg "echo -n 'Frequency Governor: '; for dev in /sys/devices/system/cpu/cpu[0-9]*; do cat \$dev/cpufreq/scaling_governor; done | uniq -c" 
            #clush $parg "echo -n 'CPUspeed Service: '; ${SUDO:-} chkconfig --list cpuspeed"; echo $sep
         ;;
      esac
   ;;
   *) echo Unknown Linux distro! $distro; exit ;;
      #clush $parg 'echo "MapR Repos Check "; zypper repos |grep -i mapr && yum -q info mapr-core mapr-spark mapr-patch';echo $sep
esac

# See https://www.percona.com/blog/2014/04/28/oom-relation-vm-swappiness0-new-kernel/
clush $parg "echo 'Sysctl Values: '; ${SUDO:-} sysctl vm.swappiness net.ipv4.tcp_retries2 vm.overcommit_memory"; echo $sep
echo -e "/etc/sysctl.conf values should be:\nvm.swappiness = 1\nnet.ipv4.tcp_retries2 = 5\nvm.overcommit_memory = 0"; echo $sep
#clush $parg "grep AUTOCONF /etc/sysconfig/network" ; echo $sep
clush $parg "echo -n 'Transparent Huge Pages: '; cat /sys/kernel/mm/transparent_hugepage/enabled" ; echo $sep
clush $parg ${SUDO:-} 'echo Checking for LUKS; grep -v -e ^# -e ^$ /etc/crypttab'
clush $parg 'echo "Disk Controller Max Transfer Size:"; files=$(ls /sys/block/{sd,xvd,vd}*/queue/max_hw_sectors_kb 2>/dev/null); for each in $files; do printf "%s: %s\n" $each $(cat $each); done |uniq -c -f1'; echo $sep
clush $parg 'echo "Disk Controller Configured Transfer Size:"; files=$(ls /sys/block/{sd,xvd,vd}*/queue/max_sectors_kb 2>/dev/null); for each in $files; do printf "%s: %s\n" $each $(cat $each); done |uniq -c -f1'; echo $sep
echo Check Mounted FS
case $sysd in
   true)
      clush $parg $parg3 "df -h --output=fstype,size,pcent,target -x tmpfs -x devtmpfs"; echo $sep ;;
   false)
      clush $parg $parg3 "df -hT | cut -c22-28,39- | grep -e '  *' | grep -v -e /dev"; echo $sep ;;
esac
echo Check for nosuid and noexec mounts
clush $parg $parg3 "mount | grep -e noexec -e nosuid | grep -v tmpfs |grep -v 'type cgroup'"; echo $sep
echo Check for /tmp permission 
clush $parg "stat -c %a /tmp | grep 1777 || echo /tmp permissions not 1777" ; echo $sep
echo Check for tmpwatch on NM local dir
clush $parg $parg2 "grep -H /tmp/hadoop-mapr/nm-local-dir /etc/cron.daily/tmpwatch || echo Not in tmpwatch: /tmp/hadoop-mapr/nm-local-dir"; echo $sep
#FIX: clush -l root -ab "echo '/usr/sbin/tmpwatch \"\$flags\" -x /tmp/hadoop-mapr/nm-local-dir' >> /etc/cron.daily/tmpwatch" 
#TBD: systemd-tmpfiles 'tmpfiles.d' man page.  Configuration 
#in /usr/lib/tmpfiles.d/tmp.conf, and in /etc/tmpfiles.d/*.conf.

echo Java Version
clush $parg $parg2 'java -version || echo See java-post-install.sh'
if [[ "$distro" != "sles" ]]; then
   clush $parg $parg2 'yum list installed \*jdk\* \*java\*'
else
   clush $parg $parg2 'zypper -i search java jdk'
fi
clush $parg $parg2 'javadir=$(dirname $(readlink -f /usr/bin/java)); test -x $javadir/jps || { test -x $javadir/../../bin/jps || echo JDK not installed; }'
echo $sep
echo Hostname IP addresses
if [[ "$distro" != "sles" ]]; then
   clush ${parg/-b /} 'hostname -I'; echo $sep
else
   clush ${parg/-b /} 'hostname -i'; echo $sep
fi
echo DNS lookup
clush ${parg/-b /} 'host $(hostname -f)'; echo $sep
echo Reverse DNS lookup
clush ${parg/-b /} 'host $(hostname -i)'; echo $sep
echo Check for system wide nproc and nofile limits
clush $parg "${SUDO:-} grep -e nproc -e nofile /etc/security/limits.d/*.conf /etc/security/limits.conf |grep -v ':#' "; echo $sep
echo Check for root ownership of /opt/mapr  
clush $parg $parg2 'stat --printf="%U:%G %A %n\n" $(readlink -f /opt/mapr)'; echo $sep
echo "Check for $serviceacct login"
clush $parg $parg1 "echo '$serviceacct account for MapR Hadoop '; getent passwd $serviceacct" || { echo "$serviceacct user NOT found!"; exit 2; }
echo $sep

if [[ $(id -u) -eq 0 || "$parg" =~ root || "$SUDO" =~ sudo ]]; then
   #TBD check umask for root and mapr
   echo Check for $serviceacct user specific open file and process limits
   clush $parg "echo -n 'Open process limit(should be >=32K): '; ${SUDO:-} su - $serviceacct -c 'ulimit -u'"
   clush $parg "echo -n 'Open file limit(should be >=32K): '; ${SUDO:-} su - $serviceacct -c 'ulimit -n'"; echo $sep
   echo Check for $serviceacct users java exec permission and version
   clush $parg $parg2 "echo -n 'Java version: '; ${SUDO:-} su - $serviceacct -c 'java -version'"; echo $sep
   clush $parg $parg2 "echo -n 'Locale setting(must be en_US): '; ${SUDO:-} su - $serviceacct -c 'locale |grep LANG'"; echo $sep
   echo "Check for $serviceacct passwordless ssh (only for MapR v3.x)"
   clush $parg "${SUDO:-} ls ~$serviceacct/.ssh/authorized_keys"; echo $sep
elif [[ $(id -un) == $serviceacct ]]; then
   echo Check for $serviceacct user specific open file and process limits
   clush $parg "echo -n 'Open process limit(should be >=32K): '; ulimit -u"
   clush $parg "echo -n 'Open file limit(should be >=32K): '; ulimit -n"; echo $sep
   echo Check for $serviceacct users java exec permission and version
   clush $parg $parg2 "echo -n 'Java version: '; java -version"; echo $sep
   echo "Check for $serviceacct passwordless ssh (only for MapR v3.x)"
   clush $parg "ls ~$serviceacct/.ssh/authorized_keys\*"; echo $sep
else
   echo Must have root access or sudo rights to check $serviceacct limits
fi
#echo 'Check for root user login and passwordless ssh (not needed for MapR, just easy for clush)'
#clush $parg "echo 'Root login '; getent passwd root && { ${SUDO:-} echo ~root/.ssh; ${SUDO:-} ls ~root/.ssh; }"; echo $sep

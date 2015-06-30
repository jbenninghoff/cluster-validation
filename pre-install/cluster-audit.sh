#!/bin/bash
# jbenninghoff 2013-Oct-06  vi: set ai et sw=3 tabstop=3:

# A sequence of parallel shell commands looking for system configuration
# differences between the nodes in a cluster.
#
# The script requires that the clush utility (a parallel execution shell)
# be installed and configured for passwordless ssh connectivity to
# all the nodes under test.  Or passwordless sudo for a non-root account.

sep='====================================================================='
scriptdir="$(cd "$(dirname "$0")"; pwd -P)"
distro=$(cat /etc/*release | grep -m1 -i -o -e ubuntu -e redhat -e 'red hat' -e centos) || distro=centos
[ $(id -u) -ne 0 ] && SUDO=sudo
shopt -s nocasematch

# Common arguments to pass in to clush execution
clcnt=$(nodeset -c @all)
parg="-b -a -f $clcnt" #fanout set to cluster node count
parg2="$parg -o -qtt"

echo ==================== Hardware audits ================================
date; echo $sep
# probe for system info ###############
clush $parg2 "${SUDO:-} dmidecode | grep -A2 '^System Information'" 2> /dev/null; echo $sep
clush $parg2 "${SUDO:-} dmidecode | grep -A3 '^BIOS I'"; echo $sep

# probe for cpu info ###############
clush $parg "grep '^model name' /proc/cpuinfo | sort -u"; echo $sep
clush $parg "lscpu | grep -v -e op-mode -e ^Vendor -e family -e Model: -e Stepping: -e BogoMIPS -e Virtual -e ^Byte -e '^NUMA node(s)' | awk '/^CPU MHz:/{sub(\$3,sprintf(\"%0.0f\",\$3))};{print}'"; echo $sep

# probe for mem/dimm info ###############
clush $parg "cat /proc/meminfo | grep -i ^memt | uniq"; echo $sep
clush $parg2 "echo -n 'DIMM slots: '; ${SUDO:-} dmidecode |grep -c '^[[:space:]]*Locator:'"; echo $sep
clush $parg2 "echo -n 'DIMM count is: '; ${SUDO:-} dmidecode | grep -c '^[[:space:]]Size: [0-9]* MB'"; echo $sep
clush $parg2 "${SUDO:-} dmidecode | awk '/Memory Device$/,/^$/ {print}' | grep -e '^Mem' -e Size: -e Speed: -e Part | sort -u | grep -v -e 'NO DIMM' -e 'No Module Installed' -e Unknown"; echo $sep

# probe for nic info ###############
#clush $parg "ifconfig | grep -o ^eth.| xargs -l ${SUDO:-} /usr/sbin/ethtool | grep -e ^Settings -e Speed" 
#clush $parg "ifconfig | awk '/^[^ ]/ && \$1 !~ /lo/{print \$1}' | xargs -l ${SUDO:-} /usr/sbin/ethtool | grep -e ^Settings -e Speed" 
clush $parg2 "${SUDO:-} lspci | grep -i ether"
clush $parg2 "${SUDO:-} ip link show | sed '/ lo: /,+1d' | awk '/UP/{sub(\":\",\"\",\$2);print \$2}' | xargs -l ${SUDO:-} ethtool | grep -e ^Settings -e Speed"
#clush $parg "echo -n 'Nic Speed: '; /sbin/ip link show | sed '/ lo: /,+1d' | awk '/UP/{sub(\":\",\"\",\$2);print \$2}' | xargs -l -I % cat /sys/class/net/%/speed"
echo $sep

# probe for disk info ###############
clush $parg2 "echo 'Storage Controller: '; ${SUDO:-} lspci | grep -i -e raid -e storage -e lsi"; echo $sep
clush $parg "dmesg | grep -i raid | grep -i scsi"; echo $sep
case $distro in
   ubuntu)
	clush $parg2 "${SUDO:-} fdisk -l | grep '^Disk /.*:'"; echo $sep
   ;;
   redhat|centos|red*)
	clush $parg "lsblk -id | awk '{print \$1,\$4}'|sort | nl"; echo $sep
   ;;
   *) echo Unknown Linux distro! $distro; exit ;;
esac
#clush $parg "echo 'Storage Drive(s): '; fdisk -l 2>/dev/null | grep '^Disk /dev/.*: ' | sort | grep mapper"
#clush $parg "echo 'Storage Drive(s): '; fdisk -l 2>/dev/null | grep '^Disk /dev/.*: ' | sort | grep -v mapper"

echo ==================== Linux audits ================================
echo $sep
clush $parg "cat /etc/*release | uniq"; echo $sep
clush $parg "uname -srvm | fmt"; echo $sep
clush $parg date; echo $sep
clush $parg2 "${SUDO:-} sysctl vm.swappiness net.ipv4.tcp_retries2 vm.overcommit_memory"; echo $sep
echo -e "/etc/sysctl.conf values should be:\nvm.swappiness = 0\nnet.ipv4.tcp_retries2 = 5\nvm.overcommit_memory = 0"
echo $sep

case $distro in
   ubuntu)
      # Ubuntu SElinux tools not so good.
      clush $parg2 "${SUDO:-} apparmor_status | sed 's/([0-9]*)//'"; echo $sep
      clush $parg "echo -n 'SElinux status: '; ([ -d /etc/selinux -a -f /etc/selinux/config ] && grep ^SELINUX= /etc/selinux/config) || echo Disabled"; echo $sep
      clush $parg2 "echo 'Firewall status: '; ${SUDO:-} service ufw status | head -10"; echo $sep
      clush $parg2 "echo 'IPtables status: '; ${SUDO:-} iptables -L | head -10"; echo $sep
      clush $parg2 'echo "NTP status "; ${SUDO:-} service ntp status'; echo $sep
      clush $parg "echo 'NFS packages installed '; dpkg -l '*nfs*' | grep ^i"; echo $sep
   ;;
   redhat|centos|red*)
      clush $parg "ntpstat | head -1" ; echo $sep
      clush $parg "echo -n 'SElinux status: '; grep ^SELINUX= /etc/selinux/config" ; echo $sep
      clush $parg2 "${SUDO:-} chkconfig --list iptables" ; echo $sep
      #clush $parg "/sbin/service iptables status | grep -m 3 -e ^Table -e ^Chain" 
      clush $parg2 "${SUDO:-} service iptables status | head -10"; echo $sep
      #clush $parg "echo -n 'Frequency Governor: '; for dev in /sys/devices/system/cpu/cpu[0-9]*; do cat \$dev/cpufreq/scaling_governor; done | uniq -c" 
      clush $parg2 "echo -n 'CPUspeed Service: '; ${SUDO:-} service cpuspeed status" 
      clush $parg2 "echo -n 'CPUspeed Service: '; ${SUDO:-} chkconfig --list cpuspeed"; echo $sep
      clush $parg 'echo "NFS packages installed "; rpm -qa | grep -i nfs |sort' ; echo $sep
      clush $parg 'echo Missing RPMs: ; for each in make patch redhat-lsb irqbalance syslinux hdparm sdparm dmidecode nc rpcbind nfs-utils dstat redhat-lsb-core git gcc openjdk-devel; do rpm -q $each | grep "is not installed"; done' ; echo $sep
   ;;
   *) echo Unknown Linux distro! $distro; exit ;;
esac
shopt -u nocasematch

#clush $parg "grep AUTOCONF /etc/sysconfig/network" ; echo $sep
clush $parg "echo -n 'Transparent Huge Pages: '; cat /sys/kernel/mm/transparent_hugepage/enabled" ; echo $sep
clush $parg2 'for each in  /sys/block/sd*/queue/max_hw_sectors_kb; do printf "%s: %s\n" $each $(cat $each); done'; echo $sep
clush $parg2 'for each in  /sys/block/sd*/queue/max_sectors_kb; do printf "%s: %s\n" $each $(cat $each); done'; echo $sep
clush $parg -u 30 "df -hT | cut -c23-28,39- | grep -e '  *' | grep -v -e /dev"; echo $sep
echo Check for nosuid mounts #TBD add noexec check
clush $parg -u 30 "mount | grep nosuid"; echo $sep
echo Check for /tmp permission and tmpwatch on NM local dir
clush $parg "stat -c %a /tmp | grep -q 1777 || echo /tmp permissions not 1777" ; echo $sep
clush $parg "grep /tmp/hadoop-mapr/nm-local-dir /etc/cron.daily/tmpwatch"; echo $sep
clush $parg 'echo JAVA_HOME is ${JAVA_HOME:-Not Defined!}'; echo $sep
clush $parg 'java -XX:+PrintFlagsFinal -version |& grep MaxHeapSize'; echo $sep
echo Hostname lookup
clush $parg 'hostname -I'; echo $sep
echo DNS lookup
clush $parg 'host $(hostname -f)'; echo $sep
echo Reverse DNS lookup
clush $parg 'host $(hostname -i)'; echo $sep
echo Check for existing MapR install
clush $parg "ls -d /opt/mapr/* | head" ; echo $sep
echo Check for root ownership of /opt/mapr  
clush $parg 'ls -ld $(readlink -f /opt/mapr)'
clush $parg 'ls -ld $(readlink -f /opt/mapr) | awk "\$3!=\"root\" || \$4!=\"root\" {print \"/opt/mapr not owned by root:root!!\"}"'
echo Check for nproc limit
clush $parg2 "grep -h nproc /etc/security/limits.d/*nproc.conf"; echo $sep
clush $parg2 "echo -n 'Open process limit(should be >=32K): '; ${SUDO:-} su - mapr -c 'ulimit -u'" ; echo $sep
echo Check for mapr user open file limit
clush $parg2 "echo -n 'Open file limit(should be >=32K): '; ${SUDO:-} su - mapr -c 'ulimit -n'" ; echo $sep
echo Check for mapr users java exec permission and version
clush $parg2 "echo -n 'Jave version: '; ${SUDO:-} su - mapr -c 'java -version'"; echo $sep
echo "Check for mapr user login and passwordless ssh (only for MapR v3.x)"
clush $parg2 "echo 'mapr login for Hadoop '; getent passwd mapr || echo 'mapr user NOT found!'"
clush $parg2 "echo 'mapr login for Hadoop '; getent passwd mapr && { ${SUDO:-} echo ~mapr/.ssh; ${SUDO:-} ls ~mapr/.ssh; }"; echo $sep
echo "Check for root user login and passwordless ssh (not needed for MapR, just easy for clush)"
clush $parg2 "echo 'Root login '; getent passwd root && { ${SUDO:-} echo ~root/.ssh; ${SUDO:-} ls ~root/.ssh; }"; echo $sep

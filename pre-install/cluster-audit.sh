#!/bin/bash
# jbenninghoff@maprtech.com 2013-Oct-06  vi: set ai et sw=3 tabstop=3:

# A sequence of parallel shell commands looking for system configuration
# differences between all the nodes in a cluster
# Requires clush, a parallel shell which requires passwordless ssh using an identity file

sep='====================================================================='
D=$(dirname "$0")
abspath=$(cd "$D" 2>/dev/null && pwd || echo "$D")
eval enpath=$(echo /sys/kernel/mm/*transparent_hugepage/enabled)

#parg="-a -x rhel11,rhel16"
parg="-aB"
parg2='-aB -o -qtt'

date; echo $sep
# probe for system info ###############
clush $parg2 "sudo dmidecode |grep -A2 '^System Information'"; echo $sep
clush $parg2 "sudo dmidecode | grep -A3 '^BIOS I'"; echo $sep
# probe for mem/dimm info ###############
clush $parg "cat /proc/meminfo | grep -i ^memt | uniq"; echo $sep
clush $parg2 "echo -n 'DIMM slots: '; sudo dmidecode |grep -c '^[[:space:]]*Locator:'"; echo $sep
clush $parg2 "echo -n 'DIMM count is: '; sudo dmidecode | grep -c '^[[:space:]]Size: [0-9]* MB'"; echo $sep
clush $parg2 "sudo dmidecode | awk '/Memory Device$/,/^$/ {print}' | grep -e '^Mem' -e Size: -e Speed: -e Part | sort -u | grep -v -e 'NO DIMM' -e 'No Module Installed' -e Unknown"; echo $sep
# probe for cpu info ###############
clush $parg "grep '^model name' /proc/cpuinfo | sort -u"; echo $sep
#clush $parg "$abspath/id_cpu_x64 -L | grep -e ' bus freq=' -e 'microcode signature=' -e 'DPL (Stride)' -e 'L2 Streamer' -e 'DCU prefetcher' -e 'Sticky thermal status=' -e 'Stepping' -e 'This system has' -e prefetch | uniq -s 6" 
clush $parg "lscpu | grep -v -e op-mode -e ^Vendor -e family -e Model: -e Stepping: -e BogoMIPS -e Virtual -e ^Byte -e '^NUMA node(s)' | awk '/^CPU MHz:/{sub(\$3,sprintf(\"%0.0f\",\$3))};{print}'"; echo $sep
# probe for nic info ###############
#clush $parg "ifconfig | grep -o ^eth.| xargs -l sudo /usr/sbin/ethtool | grep -e ^Settings -e Speed" 
#clush $parg "ifconfig | awk '/^[^ ]/ && \$1 !~ /lo/{print \$1}' | xargs -l sudo /usr/sbin/ethtool | grep -e ^Settings -e Speed" 
clush $parg "/sbin/lspci | grep -i ether"
clush $parg "/sbin/ip link show | sed '/ lo: /,+1d' | awk '/UP/{sub(\":\",\"\",\$2);print \$2}' | xargs -l sudo /usr/sbin/ethtool | grep -e ^Settings -e Speed"
clush $parg "echo -n 'Nic Speed: '; /sbin/ip link show | sed '/ lo: /,+1d' | awk '/UP/{sub(\":\",\"\",\$2);print \$2}' | xargs -l -I % cat /sys/class/net/%/speed"
echo $sep
# probe for disk info ###############
clush $parg "echo 'Storage Controller: '; /sbin/lspci | grep -i -e raid -e storage -e lsi"; echo $sep
clush $parg "dmesg | grep -i raid | grep -i scsi"; echo $sep
clush $parg "lsblk -id | awk '{print \$1,\$4}'|sort | nl"; echo $sep
#clush $parg "echo 'Storage Drive(s): '; fdisk -l 2>/dev/null | grep '^Disk /dev/.*: ' | sort | grep mapper"
#clush $parg "echo 'Storage Drive(s): '; fdisk -l 2>/dev/null | grep '^Disk /dev/.*: ' | sort | grep -v mapper"

echo ==================== Software audits ================================
echo $sep
clush $parg "cat /etc/*release | uniq"; echo $sep
clush $parg "uname -srvm | fmt"; echo $sep
clush $parg date; echo $sep

distro=$(cat /etc/*release | grep -m1 -i -o -e ubuntu -e redhat -e centos)
shopt -s nocasematch
case $distro in
   ubuntu)
      # Ubuntu SElinux tools not so good.
      clush $parg "echo -n 'SElinux status: '; ([ -d /etc/selinux -a -f /etc/selinux/config ] && grep ^SELINUX= /etc/selinux/config) || echo Disabled" ; echo $sep
      clush $parg "echo 'Firewall status: '; /sbin/service ufw status | head -10" ; echo $sep
      clush $parg 'echo "NTP status "; /sbin/service ntp status'  ; echo $sep
      clush $parg "echo 'NFS packages installed '; dpkg-query -W -f='${PackageSpec} ${Version}\t${Maintainer}\n' | grep -i nfs"  ; echo $sep
   ;;
   redhat|centos)
      clush $parg "ntpstat | head -1" ; echo $sep
      clush $parg "echo -n 'SElinux status: '; grep ^SELINUX= /etc/selinux/config" ; echo $sep
      clush $parg "/sbin/chkconfig --list iptables" ; echo $sep
      #clush $parg "/sbin/service iptables status | grep -m 3 -e ^Table -e ^Chain" 
      clush $parg "/sbin/service iptables status | head -10"; echo $sep
      #clush $parg "echo -n 'Frequency Governor: '; for dev in /sys/devices/system/cpu/cpu[0-9]*; do cat \$dev/cpufreq/scaling_governor; done | uniq -c" 
      clush $parg "echo -n 'CPUspeed Service: '; /sbin/service cpuspeed status" 
      clush $parg "echo -n 'CPUspeed Service: '; /sbin/chkconfig --list cpuspeed"; echo $sep
      clush $parg 'echo "NFS packages installed "; rpm -qa | grep -i nfs |sort' ; echo $sep
      clush $parg 'echo Missing RPMs: ; for each in make patch redhat-lsb irqbalance syslinux hdparm sdparm dmidecode nc; do rpm -q $each | grep "is not installed"; done' ; echo $sep
   ;;
   *) echo Unknown Linux distro!; exit ;;
esac
shopt -u nocasematch

#clush $parg "grep AUTOCONF /etc/sysconfig/network" ; echo $sep
clush $parg "echo -n 'Transparent Huge Pages: '; cat $enpath" 
#clush $parg "echo Check Permissions; ls -ld / /tmp | awk '{print \$1,\$3,\$4,\$9}'" ; echo $sep
clush $parg "stat -c %a /tmp | grep -q 1777 || echo /tmp permissions not 1777" ; echo $sep
clush $parg 'java -version; echo JAVA_HOME is ${JAVA_HOME:-Not Defined!}'; echo $sep
clush $parg 'java -XX:+PrintFlagsFinal -version |& grep MaxHeapSize'; echo $sep
echo Hostname lookup
clush $parg 'hostname -I'; echo $sep
#clush $parg 'echo Hostname lookup; hostname -i; hostname -f' ; echo $sep
clush $parg "ls -d /opt/mapr/* | head" ; echo $sep
clush $parg 'echo -n "Open file limit(should be >32K): "; ulimit -n' ; echo $sep
clush $parg 'echo "mapr login for Hadoop "; getent passwd mapr && { echo ~mapr/.ssh; ls ~mapr/.ssh; }' 
echo $sep
clush $parg 'echo "Root login "; getent passwd root && { echo ~root/.ssh; ls ~root/.ssh; }'; echo $sep

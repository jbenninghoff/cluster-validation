#!/bin/bash
# A sequence of parallel shell commands looking for system configuration
# differences between all the nodes in a cluster
# Requires a parallel shell such as clush or pdsh
shopt -s expand_aliases

sep='====================================================================='
D=$(dirname "$0")
abspath=$(cd "$D" 2>/dev/null && pwd || echo "$D")
eval enpath=$(echo /sys/kernel/mm/*transparent_hugepage/enabled)

unalias psh
if (type clush > /dev/null); then
  alias psh=clush
  alias dshbak=clubak
elif (type pdsh > /dev/null); then
  alias psh=pdsh
fi
#parg="-a -x rhel11,rhel16"
parg="-a"

date; echo $sep
psh $parg "dmidecode |grep -A2 '^System Information'" | dshbak -c
echo $sep
psh $parg "dmidecode | grep -A3 '^BIOS I'" | dshbak -c
echo $sep
# probe for mem/dimm info ###############
psh $parg "cat /proc/meminfo | grep -i ^memt | uniq" | dshbak -c
echo $sep
psh $parg "echo -n 'DIMM slots: '; dmidecode |grep -c '^[[:space:]]*Locator:'" | dshbak -c
echo $sep
psh $parg "echo -n 'DIMM count is: '; dmidecode | grep -c '	Size: [0-9]* MB'" | dshbak -c
echo $sep
psh $parg "dmidecode | awk '/Memory Device$/,/^$/ {print}' | grep -e '^Mem' -e Size: -e Speed: -e Part | sort -u | grep -v -e 'NO DIMM' -e 'No Module Installed' -e Unknown" | dshbak -c
echo $sep
# probe for cpu info ###############
psh $parg "grep '^model name' /proc/cpuinfo | sort -u" | dshbak -c
#echo $sep
#psh $parg "$abspath/id_cpu_x64 -L | grep -e ' bus freq=' -e 'microcode signature=' -e 'DPL (Stride)' -e 'L2 Streamer' -e 'DCU prefetcher' -e 'Sticky thermal status=' -e 'Stepping' -e 'This system has' -e prefetch | uniq -s 6" | dshbak -c
echo $sep
psh $parg "lscpu | grep -v -e op-mode -e ^Vendor -e family -e Model: -e Stepping: -e BogoMIPS -e Virtual -e ^Byte -e '^NUMA node(s)' | awk '/^ CPU MHz:/{sub(\$3,sprintf(\"%0.0f\",\$3))};{print}'" | dshbak -c
echo $sep
# probe for nic info ###############
#psh $parg "ifconfig | grep -A1 \^eth | fmt" | dshbak -c
#psh $parg "ifconfig | grep -o ^eth.| xargs -l ethtool | grep -e ^Settings -e Speed" | dshbak -c
#psh $parg "ifconfig | awk '/^[^ ]/ && \$1 !~ /lo/{print \$1}' | xargs -l ethtool | grep -e ^Settings -e Speed" | dshbak -c
psh $parg "lspci | grep -i ether" | dshbak -c
psh $parg "ip link show | sed '/ lo: /,+1d' | awk '/UP/{sub(\":\",\"\",\$2);print \$2}' | xargs -l ethtool | grep -e ^Settings -e Speed" | dshbak -c
echo $sep
# probe for disk info ###############
psh $parg "echo 'Storage Controller: '; lspci | grep -i -e raid -e storage -e lsi" | dshbak -c
psh $parg "dmesg | grep -i raid | grep -i scsi" | dshbak -c
echo $sep
psh $parg "lsblk -id | awk '{print \$1,\$4}'|sort | nl" | dshbak -c
echo $sep
#psh $parg "echo 'Storage Drive(s): '; fdisk -l 2>/dev/null | grep '^Disk /dev/.*: ' | sort | grep mapper" | dshbak -c
#psh $parg "echo 'Storage Drive(s): '; fdisk -l 2>/dev/null | grep '^Disk /dev/.*: ' | sort | grep -v mapper" | dshbak -c

echo ==================== Software audits ================================
echo $sep
psh $parg "cat /etc/*release | uniq" | dshbak -c
echo $sep
psh $parg "uname -srvm | fmt" | dshbak -c
echo $sep
psh $parg date | dshbak -c
echo $sep
psh $parg "ntpstat | head -1" | dshbak -c
echo $sep
psh $parg "echo -n 'SElinux status: '; grep ^SELINUX= /etc/selinux/config" | dshbak -c
echo $sep
psh $parg "chkconfig --list iptables" | dshbak -c
echo $sep
psh $parg "service iptables status | head -10" | dshbak -c
echo $sep
#psh $parg "grep AUTOCONF /etc/sysconfig/network" | dshbak -c; echo $sep
psh $parg "echo -n 'Transparent Huge Pages: '; cat $enpath" | dshbak -c
echo $sep
psh $parg "echo -n 'CPUspeed Service: '; service cpuspeed status" |dshbak -c
psh $parg "echo -n 'CPUspeed Service: '; chkconfig --list cpuspeed" |dshbak -c
#psh $parg "echo -n 'Frequency Governor: '; for dev in /sys/devices/system/cpu/cpu[0-9]*; do cat \$dev/cpufreq/scaling_governor; done | uniq -c" | dshbak -c
echo $sep
#psh $parg "echo Check Permissions; ls -ld / /tmp | awk '{print \$1,\$3,\$4,\$9}'" | dshbak -c; echo $sep
psh $parg "stat -c %a /tmp | grep -q 1777 || echo /tmp permissions not 1777" | dshbak -c; echo $sep
psh $parg 'java -version; echo JAVA_HOME is ${JAVA_HOME:-Not Defined!}' |& dshbak -c; echo $sep
psh $parg 'java -XX:+PrintFlagsFinal -version |& grep MaxHeapSize' |& dshbak -c; echo $sep
echo Hostname lookup
psh $parg 'hostname -I'; echo $sep
#psh $parg 'echo Hostname lookup; hostname -i; hostname -f' | dshbak -c; echo $sep
psh $parg 'rpm -qa | grep -i nfs |sort' | dshbak -c; echo $sep
psh $parg 'echo Missing RPMs: ; for each in make patch redhat-lsb irqbalance syslinux hdparm sdparm dmidecode nc; do rpm -q $each | grep "is not installed"; done' | dshbak -c; echo $sep
psh $parg "ls -d /opt/mapr/* | head" | dshbak -c; echo $sep
psh $parg 'echo -n "Open file limit(should be >32K): "; ulimit -n' | dshbak -c; echo $sep
psh $parg 'echo "mapr login for Hadoop "; getent passwd mapr && { echo ~mapr/.ssh; ls ~mapr/.ssh; }' | dshbak -c
echo $sep
psh $parg 'echo "Root login "; getent passwd root && { echo ~root/.ssh; ls ~root/.ssh; }' | dshbak -c; echo $sep


exit

if type -t lscpu > /dev/null; then
  grep Xeon /proc/cpuinfo | sort -u
  lscpu | grep -v -e op-mode -e ^Vendor -e family -e Model: -e Stepping: -e BogoMIPS -e Virtual -e ^Byte -e '^NUMA node(s)'; echo $sep
else
  echo -n "CPU count is: "
  grep -c ^processor /proc/cpuinfo
  cat /proc/cpuinfo | grep -i 'cpu mhz' | uniq
  cat /proc/cpuinfo | grep -i 'cache ' | uniq
  echo $sep
  if [ -e /proc/pal/cpu0/cache_info ]; then
    cat /proc/pal/cpu0/cache_info
    echo $sep
  fi
fi

#lsblk
#fdisk -l | grep '^Disk /dev.*:.*'
#parted /dev/sda print | head -3
#sfdisk -l /dev/sda
#fdisk -l /dev/sda
#hdparm -i /dev/sda
#smartctl -i /dev/sda

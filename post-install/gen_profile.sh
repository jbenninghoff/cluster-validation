#!/bin/bash
# dgomerman@maprtech.com 2014-Mar-25
OUTPUT="/tmp/node_profile.sh"
SUDO=""
[ $(id -u) -ne 0 ] && SUDO=sudo

# OS
distro=$(cat /etc/*release | grep -m1 -i -o -e ubuntu -e redhat -e centos)
if [ ! -n "$distro" ] ; then
    distro="unknown"
fi
# Manufacturer
manufacturer=$($SUDO dmidecode |grep -A2 '^System Information' |grep -i "Manufacturer" |sed -e 's/^.*: //')
if [ ! -n "$manufacturer" ] ; then
    manufacturer="unknown"
fi
product=$($SUDO dmidecode |grep -A2 '^System Information' |grep -i "Product" |sed -e 's/[^0-9]*//g')
if [ ! -n "$product" ] ; then
    product="unknown"
fi
# Memory DIMS
memoryDims=$($SUDO dmidecode | grep -c '^[[:space:]]Size: [0-9]* MB')
if [ ! -n "$memoryDims" ] ; then
    memoryDims="0"
fi
# Memory Total
memoryTotal=$(cat /proc/meminfo | grep -i ^memt | uniq |sed -e 's/[^0-9]*//g')
if [ ! -n "$memoryTotal" ] ; then
    memoryTotal="0"
fi
# Core Count
coreCount=$(lscpu | grep -v -e op-mode -e ^Vendor -e family -e Model: -e Stepping: -e BogoMIPS -e Virtual -e ^Byte -e '^NUMA node(s)' | awk '/^CPU MHz:/{sub($3,sprintf("%0.0f",$3))};{print}' |grep '^CPU(s)' |sed -e 's/[^0-9]*//g')
if [ ! -n "$coreCount" ] ; then
    coreCount="0"
fi
# Core Speed
cpuMhz=$(lscpu | grep -v -e op-mode -e ^Vendor -e family -e Model: -e Stepping: -e BogoMIPS -e Virtual -e ^Byte -e '^NUMA node(s)' | awk '/^CPU MHz:/{sub($3,sprintf("%0.0f",$3))};{print}' |grep '^CPU MHz' |sed -e 's/[^0-9]*//g')
if [ ! -n "$cpuMhz" ] ; then
    cpuMhz="0"
fi
# NIC Count & Speed
which ethtool >/dev/null 2>&1
ethExists=$?
if [ $ethExists -eq 0 ] ; then
    nicSpeeds=$(/sbin/ip link show | sed '/ lo: /,+1d' | awk '/UP/{sub(":","",$2);print $2}' | xargs -l $SUDO ethtool | grep -e ^Settings -e Speed |grep "Speed" |sed -e 's/[^0-9]//g')
else
    nicSpeeds=$(/sbin/ip link show | sed '/ lo: /,+1d' | awk '/UP/{sub(":","",$2);print $2}' | xargs -l $SUDO mii-tool|sed -e 's/^.*negotiated//' -e 's/[^0-9]//g')
fi
if [ ! -n "$nicSpeeds" ] ; then
    nicSpeeds="1000"
fi

avgSpeed=0
aggSpeed=0
nicCount=0
for speed in $nicSpeeds ; do
    let aggSpeed+=$speed
    let nicCount+=1
done
let avgSpeed=$aggSpeed/$nicCount
# Disk count
diskCount=$(cat /opt/mapr/conf/disktab |grep '^\/' |wc --lines)
if [ ! -n "$diskCount" ] ; then
    nicSpeeds="0"
fi

# Save Profile
cat <<EOF > $OUTPUT
#!/bin/bash
# OS
export DISTRO="$distro"
# Manufacturer
export MANUFACTURER="$manufacturer"
export PRODUCT="$product"
# Memory DIMS
export MEMORY_DIMS="$memoryDims"
# Memory Total
export MEMORY_TOTAL="$memoryTotal"
# Core Count
export CORE_COUNT="$coreCount"
# Core Speed
export CPU_MHZ="$cpuMhz"
# NIC Count & Speed
export NIC_SPEEDS="$nicSpeeds"
export AVG_NIC_SPEED="$avgSpeed"
export AGG_NIC_SPEED="$aggSpeed"
export NIC_COUNT="$nicCount"
# Disk count
export DISK_COUNT="$diskCount"
EOF

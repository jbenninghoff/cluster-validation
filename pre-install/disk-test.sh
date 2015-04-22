#!/bin/bash
# jbenninghoff 2013-Jan-06  vi: set ai et sw=3 tabstop=3:

find_unused_disks() {
   disks=""
   for d in `fdisk -l 2>/dev/null | grep -e "^Disk .* bytes$" | awk '{print $2}' |sort`; do
      dev=${d%:}
      [[ $dev == /dev/md* ]] && mdisks="$mdisks $(mdadm --detail $dev | grep -o '/dev/[^0-9 ]*' | grep -v /dev/md)"
      mount | grep -q -w -e $dev -e ${dev}1 -e ${dev}2 && continue #if mounted skip device
      swapon -s | grep -q -w $dev && continue #if swap partition skip device
      type pvdisplay &> /dev/null && pvdisplay $dev &> /dev/null && continue #if physical volume is part of LVM (swap vol TBD)
      [[ $dev == *swap* ]] && continue #device name appears to be LVM swap device
      lsblk -nl $(readlink -f $dev) | grep -i swap && continue

      disks="$disks $dev"
   done
   for d in $mdisks; do #Remove devices used by /dev/md*
      echo MDisk: $d
      disks=${disks/$d/}
   done
}

[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }

cat - << 'EOF'
# Parallel IOzone tests to stress/measure disk controller
# These tests are destructive therefore the must be run BEFORE 
# formatting the devices for the MapR filesystem (disksetup -F ..)
# Run iozone command once on a single device to verify iozone command
#
#  NOTE: logs are created in the current working directory
EOF

D=$(dirname "$0")
abspath=$(unset CDPATH; cd "$D" 2>/dev/null && pwd || echo "$D")

while getopts ":v" opt; do
  case $opt in
    v) # disks=$(lsblk -id | grep -o ^sd. | grep -v ^sda |sort); echo $disks
       echo -e "All disks: \n $(fdisk -l 2>/dev/null | grep -e '^Disk .* bytes$' | awk '{print $2}' |sort)"
       ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit ;;
  esac
done

# Set list of device names for the 'for' loop
find_unused_disks
echo "Unused disks: $disks"
diskqty=$(echo $disks | wc -w)
# HP DL380 P420i default settings example for /dev/sdb
#[root@tmz2mpr001 ~]# cat /sys/block/sdb/queue/max_sectors_kb
#512
#[root@tmz2mpr001 ~]# cat /sys/block/sdb/queue/max_hw_sectors_kb 
#4096

if (( diskqty > 48 )); then # See /opt/mapr/conf/mfs.conf: mfs.max.disks
   echo 'MapR FS currently only supports a maximum of 48 disk devices!'
   echo Select 48 or fewer disks from the list above for MapR disksetup 
fi
echo Scrutinize this list carefully!!; exit #Comment out exit after list is vetted
echo $disks | tr ' ' '\n' > /tmp/disk.list; exit
#read -p "Press enter to continue or ctrl-c to abort"

#read-only dd test, possible even after MFS is in place
#for i in $disks; do dd of=/dev/null if=$i iflag=direct bs=1M count=1000 & done; exit

set -x
for disk in $disks; do
   iozlog=`basename $disk`-iozone.log
   $abspath/iozone -I -r 1M -s 4G -+n -i 0 -i 1 -i 2 -f $disk > $iozlog  &
   sleep 3 #Some controllers seem to lockup without a sleep
done
set +x

echo ""
echo "Waiting for all iozone to finish"

wait


#!/bin/bash
# jbenninghoff@fastmail.fm 2013-Jan-06  vi: set ai et sw=3 tabstop=3:

cat - << 'EOF'
# Parallel IOzone tests to stress/measure disk controller
# These tests are destructive therefore
# Tests must be run BEFORE MapR filesystem is formatted (disksetup -F ..)
# Run iozone command once on a single device to verify iozone command
EOF

D=$(dirname "$0")
abspath=$(cd "$D" 2>/dev/null && pwd || echo "$D")

# run iozone with -h option for usage
# Set list of device names for the 'for' loop
disks=$(lsblk -id | grep -o ^sd. | grep -v ^sda |sort); echo $disks
diskqty=$(echo $disks | wc -w)
if (( diskqty > 48 )); then
  echo 'MapR FS currently only supports a maximum of 48 disk devices!'
  echo Select 48 or fewer disks from the list above for MapR disksetup 
fi
echo Scrutinize this list carefully!!; exit #Comment out exit after list is vetted

#read-only dd test, possible even after MFS is in place
#for i in $disks; do dd of=/dev/null if=/dev/$i iflag=direct bs=1M count=1000 & done; exit

set -x
for disk in $disks; do
   $abspath/iozone -I -r 1M -s 4G -i 0 -i 1 -i 2 -f /dev/$disk > $disk-iozone.log&
   sleep 3 #Some controllers seem to lockup without a sleep
done

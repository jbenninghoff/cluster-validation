#!/bin/bash
# jbenninghoff@fastmail.fm 2013-Jan-06  vi: set ai et sw=3 tabstop=3:

find_unused_disks() {
    disks=""
    for d in `fdisk -l 2>/dev/null | grep -e "^Disk .* bytes$" | awk '{print $2}' `; do
        dev=${d%:}
        mount | grep -q -w -e $dev -e ${dev}1 -e ${dev}2 && continue #if mounted skip device
        swapon -s | grep -q -w $dev && continue #if swap partition skip device
        type pvdisplay &> /dev/null && pvdisplay $dev &> /dev/null && continue #if physical volume is part of LVM (swap vol TBD)

        disks="$disks $dev"
    done
    export MAPR_DISKS="$disks"
}

cat - << 'EOF'
# Parallel IOzone tests to stress/measure disk controller
# These tests are destructive therefore the must be run BEFORE 
# formatting the devices for the MapR filesystem (disksetup -F ..)
# Run iozone command once on a single device to verify iozone command
#
#	NOTE: logs are created in the current working directory
EOF

D=$(dirname "$0")
abspath=$(unset CDPATH; cd "$D" 2>/dev/null && pwd || echo "$D")

# Set list of device names for the 'for' loop
# 	disks=$(lsblk -id | grep -o ^sd. | grep -v ^sda |sort); echo $disks
#	diskqty=$(echo $disks | wc -w)
find_unused_disks
disks=$MAPR_DISKS
diskqty=$(echo $disks | wc -w)
echo "Unused disks: $disks"

if (( diskqty > 48 )); then
  echo 'MapR FS currently only supports a maximum of 48 disk devices!'
  echo Select 48 or fewer disks from the list above for MapR disksetup 
fi
echo Scrutinize this list carefully!!; exit #Comment out exit after list is vetted

#read-only dd test, possible even after MFS is in place
#for i in $disks; do dd of=/dev/null if=/dev/$i iflag=direct bs=1M count=1000 & done; exit

set -x
for disk in $disks; do
	iozlog=`basename $disk`-iozone.log
	$abspath/iozone -I -r 1M -s 4G -i 0 -i 1 -i 2 -f $disk > $iozlog  &
	sleep 3 #Some controllers seem to lockup without a sleep
done
set +x

echo ""
echo "Waiting for all iozone to finish"

wait


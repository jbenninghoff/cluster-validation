#!/bin/bash
# jbenninghoff 2013-Jan-06  vi: set ai et sw=3 tabstop=3:
# updated by nestrada 2015-June-15 

[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }

cat - << 'EOF'

Parallel IOzone tests to stress/measure disk controller
These tests are destructive therefore they must be run BEFORE 
formatting the devices for the MapR filesystem (disksetup -F ..)

When run with no arguments, this script outputs a list of 
unused disks.  After carefully examining this list, run again
with --destroy as the argument ('disk-test.sh --destroy') to
run the destructive IOzone tests on all unused disks.

NOTE: logs are created in the current working directory

EOF
#Usage:  disk-test.sh [--unusedDisks] [--allDisks] [--destroy]

D=$(dirname "$0")
abspath=$(unset CDPATH; cd "$D" 2>/dev/null && pwd || echo "$D")

find_unused_disks() {
   disks=""
   for d in `fdisk -l 2>/dev/null | grep -e "^Disk .* bytes$" | awk '{print $2}' |sort`; do
      dev=${d%:}
      [[ $dev == /dev/md* ]] && { mdisks="$mdisks $(mdadm --detail $dev | grep -o '/dev/[^0-9 ]*' | grep -v /dev/md)"; continue; }
      mount | grep -q -w -e $dev -e ${dev}1 -e ${dev}2 && continue #if mounted skip device
      swapon -s | grep -q -w $dev && continue #if swap partition skip device
      type pvdisplay &> /dev/null && pvdisplay $dev &> /dev/null && continue #if physical volume is part of LVM (swap vol TBD)
      [[ $dev == *swap* ]] && continue #device name appears to be LVM swap device
      lsblk -nl $(readlink -f $dev) | grep -i swap && continue

      disks="$disks $dev"
   done
   for d in $mdisks; do #Remove devices used by /dev/md*
      echo Removing MDisk: $d
      disks=${disks/$d/}
   done
   pvsdisks=$(pvs | awk '$1 ~ /\/dev/{sub("[0-9]+$","",$1); print $1}')
   for d in $pvsdisks; do #Remove devices used by VG
      echo Removing VG disk: $d
      disks=${disks/$d/}
   done
}

#########################################################################################################


# Variables used for getops
ALLDISKS=false
DISKS=false
DESTROY=false

# Give list of unsued disks if no option is provided
if [ $# -eq 0 ]; then
	DISKS=true
fi

# getopts: three options - allDisks, unusedDisks (same as using script without option), and destroy
optspec=":a-:"
while getopts "$optspec" optchar; do
    case "${optchar}" in
        -)
            case "${OPTARG}" in
                allDisks) ALLDISKS=true ;;
                unusedDisks) DISKS=true ;;
                destroy) DESTROY=true ;;
                *)
                   echo "Invalid option --${OPTARG}" >&2
                   echo "Please run script either with --allDisks, --destroy, or no arguments"
                   ;;
            esac;;
        a) ALLDISKS=true ;;
        *)
          echo "Invalid option -${OPTARG}" >&2
          echo "Please run script either with --allDisks, --destroy, or no arguments"
          ;;
    esac
done

# Based on the getops loop one of the below will be executed.

if [ "$ALLDISKS" == true ]; then
   disks=$(fdisk -l 2>/dev/null | grep -e "^Disk .* bytes$" | awk '{print $2}' | sed 's/://' |sort)
	#disks=$(lsblk -id | grep -o ^sd. | grep -v ^sda |sort)
   echo -e "All disks: " $disks
	echo " "
	exit 0
fi

find_unused_disks
diskqty=$(echo $disks | wc -w)
if (( diskqty > 48 )); then # See /opt/mapr/conf/mfs.conf: mfs.max.disks
   echo 'MapR FS currently only supports a maximum of 48 disk devices!'
   echo Select 48 or fewer disks from the list above for MapR disksetup 
fi

if [ "$DISKS" == true ]; then
   echo " "
   echo "Unused disks: $disks"
   echo Scrutinize this list carefully!!
   echo $disks | tr ' ' '\n' > /tmp/disk.list # write disk list to file for MapR install
   echo " "
#read-only dd test, possible even after MFS is in place
#for i in $disks; do dd of=/dev/null if=$i iflag=direct bs=1M count=1000 &> $(basename $i)-dd.log & done
#echo; echo "Waiting for dd to finish"; wait; sleep 3; exit
   exit 0
fi

if [ "$DESTROY" == true ]; then
	echo " "
	set -x
   for disk in $disks; do
      iozlog=`basename $disk`-iozone.log
      $abspath/iozone -I -r 1M -s 4G -+n -i 0 -i 1 -i 2 -f $disk > $iozlog  & #remove ampersand to run sequential test on drives
      sleep 2 #Some controllers seem to lockup without a delay
   done
   set +x
   echo " "
   echo "Waiting for all iozone to finish"
   wait
   echo " "
   exit 0
fi

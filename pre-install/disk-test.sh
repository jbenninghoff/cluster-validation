#!/bin/bash
# jbenninghoff 2013-Jan-06  vi: set ai et sw=3 tabstop=3:

usage() {
cat << EOF

This script uses iozone to measure disk and disk controller bandwidth.
These tests are DESTRUCTIVE therefore they must be run BEFORE 
formatting the devices for the MapR filesystem (disksetup -F ...)

When run with no arguments, this script outputs a list of unused
disks and exits without running iozone.  Run the script first without
arguments and after carefully examining this list, run the script
again with --destroy as the argument ('disk-test.sh --destroy') to
run the destructive IOzone tests on all unused disks.

NOTE: iozone outuput logs are created in the current directory,
which is usually the home directory of root, typically /root.
Use summIOzone.sh to gather up a summary of the iozone output logs.

Options:
-a: List all disks, used and unused
-s: Run iozone tests sequentially to tests disks individually
-z: Specify test size in Gigabytes (default is 4 (4GB), quick test)
-r: Run read-only dd based test
-d: Enable debug statements

EOF
exit
}

disks=unused; seq=false; size=4; DBG=''
while getopts "asdrz:-:" opt; do
  case $opt in
    -) case "$OPTARG" in
         all) disks=all ;; #Show all disks, not just umounted/unused disks
         destroy) disks=destroy ;; #Run iozone on all unused disks, destroying data
         *) echo "Invalid option --$OPTARG" >&2; usage ;;
       esac;;
    a) disks=all ;;
    s) seq=true ;;
    r) disks=readtest ;;
    z) [[ "$OPTARG" =~ ^[0-9.]+$ ]] && size=$OPTARG || { echo $OPTARG is not an number; exit; } ;;
    d) DBG=true ;; # Enable debug statements
    *) usage ;;
  esac
done
[ -n "$DBG" ] && read -p "Press enter to continue or ctrl-c to abort"

[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }
scriptdir="$(cd "$(dirname "$0")"; pwd -P)" #absolute path to this script dir

find_unused_disks() {
   [ -n "$DBG" ] && set -x
   disklist=""
   fdisks=$(fdisk -l | awk '/^Disk .* bytes/{print $2}' |sort)
   for d in $fdisks; do
      dev=${d%:} #strip colon off the dev path string
      [ -n "$DBG" ] && echo Checking Device: $dev
      [[ $dev == /dev/md* ]] && { mdisks="$mdisks $(mdadm --detail $dev | grep -o '/dev/[^0-9 ]*' | grep -v /dev/md)"; continue; }
      mount | grep -q -w -e $dev -e ${dev}1 -e ${dev}2 && continue #if mounted skip device
      swapon -s | grep -q -w $dev && continue #if swap partition skip device
      type pvdisplay &> /dev/null && pvdisplay $dev &> /dev/null && continue #if physical volume is part of LVM, skip device
      [[ $dev == *swap* ]] && continue #device name appears to be LVM swap device, skip device
      lsblk -nl $(readlink -f $dev) | grep -i swap && continue #Looks like might be swap device
      if [ "$disks" != "readtest" ]; then
         grep $dev /opt/mapr/conf/disktab &>/dev/null && continue #Looks like part of MapR disk set already
         lsof $dev && continue #Looks like something has device open
      fi
      disklist="$disklist $dev" #Survived all filters, add it to the list of unused disks
   done

   [ -n "$DBG" ] && echo MD check loop
   for d in $mdisks; do #Remove devices used by /dev/md*
      echo Removing MDisk from list: $d
      disklist=${disklist/$d/}
   done

   [ -n "$DBG" ] && echo VG check loop
   pvsdisks=$(pvs | awk '$1 ~ /\/dev/{sub("[0-9]+$","",$1); print $1}')
   for d in $pvsdisks; do #Remove devices used by VG
      echo Removing VG disk from list: $d
      disklist=${disklist/$d/}
   done
   [ -n "$DBG" ] && set +x
}

##############################################################################
pgrep iozone && { echo 'iozone appears to be running, kill all iozones running (e.g. pkill iozone)'; exit; }
files=$(ls *-{dd,iozone}.log 2>/dev/null)
[ -n "$files" ] && { tar czf disk-tests-$(date "+%Y-%m-%dT%H-%M%z").tgz $files; rm -f $files; } #tar up previous log files
find_unused_disks #Sets $disklist
echo $disklist | tr ' ' '\n' >/tmp/disk.list #write disk list for MapR install
[ -n "$DBG" ] && cat /tmp/disk.list
[ -n "$DBG" ] && read -p "Press enter to continue or ctrl-c to abort"

case "$disks" in
   all)
      disklist=$(fdisk -l 2>/dev/null | awk '/^Disk .* bytes$/ {gsub(":","",$2); print $2}' |sort)
      echo -e "All disks: " $disklist; echo
      ;;
   unused)
      #diskqty=$(echo $disklist | wc -w) #See /opt/mapr/conf/mfs.conf: mfs.max.disks
      if [ -n "$disklist" ]; then
         echo; echo "Unused disks: $disklist"
         echo Scrutinize this list carefully!!;  echo
      else
         echo; echo "No Unused disks!"; echo; exit 1
      fi
      ;;
   readtest)
      [ -n "$DBG" ] && set -x
      #read-only dd test, possible even after MFS is in place
      if [ $seq == "true" ]; then
         for i in $disklist; do dd of=/dev/null if=$i iflag=direct bs=1M count=$[$size*1000] &> $(basename $i)-dd.log ; done
      else
         for i in $disklist; do dd of=/dev/null if=$i iflag=direct bs=1M count=$[$size*1000] &> $(basename $i)-dd.log & done
      fi
      [ $seq == "false" ] && { echo; echo "Waiting for dd to finish"; wait; sleep 3; echo; }
      for i in $disklist; do echo $(basename $i)-dd.log; cat $(basename $i)-dd.log; echo; done
      ;;
   destroy)
      echo
      [ -n "$DBG" ] && set -x
      service mapr-warden status && { echo 'MapR warden appears to be running, stop warden (e.g. service mapr-warden stop)'; exit; }
      for disk in $disklist; do
         iozlog=$(basename $disk)-iozone.log
         if [ $seq == "true" ]; then
            $scriptdir/iozone -I -r 1M -s ${size}G -+n -i 0 -i 1 -i 2 -f $disk > $iozlog #sequential iozone if disk controller suspected
         else
            $scriptdir/iozone -I -r 1M -s ${size}G -+n -i 0 -i 1 -i 2 -f $disk > $iozlog& #concurrent iozone on all disks
            sleep 2 #Some disk controllers lockup without a delay
         fi
      done

      [ $seq == "false" ] && { echo; echo "Waiting for all iozone to finish"; wait; sleep 3; echo; }
      ;;
esac

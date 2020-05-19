#!/bin/bash
# jbenninghoff 2013-Jan-06  vi: set ai et sw=3 tabstop=3:
# shellcheck disable=SC2086,SC2162,SC2016

# Absolute path to this script dir which contains iozone binary
scriptdir="$(cd "$(dirname "$0")" ||exit; pwd -P)"

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
which is usually the home directory of root, typically /root,
when run via clush.
Use summIOzone.sh via clush to gather up a summary of the iozone output logs.

Options:
-a: List all disks, used and unused
-s: Run iozone tests sequentially to tests disks individually
-z: Specify test size in Gigabytes (default is 4 (4GB), quick test)
-r: Run read-only dd based test
-p: Use previously existing /tmp/disk.list file
-d: Enable debug statements

EOF
exit
}

testtype=none; diskset=unused; seq=false; size=4; preserve=false; DBG=''
while getopts "pasdrz:-:" opt; do
  case $opt in
    -) case "$OPTARG" in
         all) diskset=all ;; #Show all disks, not just umounted/unused disks
         destroy) testtype=destroy ;; #Run iozone on all unused disks
         *) echo "Invalid option --$OPTARG" >&2; usage ;;
       esac;;
    a) diskset=all ;;
    s) seq=true ;;
    r) testtype=readtest ;;
    p) preserve=true ;;
    z) [[ "$OPTARG" =~ ^[0-9.]+$ ]] && size=$OPTARG
       [[ "$OPTARG" =~ ^[0-9.]+$ ]] || { echo $OPTARG is not a number;exit; } ;;
    d) DBG=true ;; # Enable debug statements
    *) usage ;;
  esac
#TBD: add disk detail option, -i
done
[[ -n "$DBG" ]] && echo Options set: diskset: $diskset, seq: $seq, size: $size 
[[ -n "$DBG" ]] && read -p "Press enter to continue or ctrl-c to abort"

[[ $(id -u) != 0 ]] && { echo This script must be run as root; exit 1; }

find_unused_disks() {
   [[ -n "$DBG" ]] && set -x
   disklist=""
   fdisks=$(fdisk -l 2>/dev/null | awk '/^Disk .* bytes/{print $2}' |sort)
   for d in $fdisks; do
      [[ -n "$DBG" ]] && echo Fdisk list loop, Checking Device: $dev
      dev=${d%:} # Strip colon off the dev path string
      # If mounted, skip device
      mount | grep -q -w -e $dev -e ${dev}1 -e ${dev}2 && continue
      # If swap partition, skip device
      swapon -s | grep -q -w $dev && continue
      # If physical volume is part of LVM, skip device
      type pvdisplay &> /dev/null && pvdisplay $dev &> /dev/null && continue
      # If device name appears to be LVM swap device, skip device
      [[ $dev == *swap* ]] && continue
      # Looks like might be swap device
      lsblk -nl "$(readlink -f $dev)" | grep -i swap && continue
      # If device is part of encrypted partition, skip device
      type cryptsetup >& /dev/null && cryptsetup isLuks $dev && continue
      if [[ $dev == /dev/md* ]]; then
         mdisks+="$(mdadm -D $dev |grep -o '/dev/[^0-9 ]*' |grep -v /dev/md) "
         continue
      fi
      if [[ "$testtype" != "readtest" ]]; then
         #Looks like part of MapR disk set already
         grep $dev /opt/mapr/conf/disktab &>/dev/null && continue
         #Looks like something has device open
         lsof $dev && continue
      fi
      ## Survived all filters, add device to the list of unused disks!!
      disklist="$disklist $dev "
   done

   for d in $mdisks; do #Remove devices used by /dev/md*
      echo Removing MDisk from list: $d
      disklist=${disklist/$d }
   done

   #Remove devices used by LVM or mounted partitions
   [[ -n "$DBG" ]] && echo LVM checks
   awkcmd='$2=="lvm" {print "/dev/"$3; print "/dev/mapper/"$1}; '
   awkcmd+=' $2=="part" {print "/dev/"$3; print "/dev/"$1}'
   lvmdisks=$(lsblk -ln -o NAME,TYPE,PKNAME,MOUNTPOINT |awk "$awkcmd" |sort -u)
   for d in $lvmdisks; do
      echo Removing LVM disk from list: $d
      disklist=${disklist/$d }
   done

   # Remove /dev/mapper duplicates from $disklist
   for i in $disklist; do
      [[ "$i" != /dev/mapper* ]] && continue
      [[ -n "$DBG" ]] && echo Disk is mapper: $i
      #/dev/mapper underlying device
      dupdev=$(lsblk |grep -B2 "$(basename $i)" |awk '/disk/{print "/dev/"$1}')
      #strip underlying device used by mapper from disklist
      disklist=${disklist/$dupdev }
      #disklist=${disklist/$i } #strip mapper device
   done

   # Remove /dev/secvm/dev duplicates from $disklist (Vormetric)
   for i in $disklist; do
      [[ "$i" != /dev/secvm/dev/* ]] && continue
      [[ -n "$DBG" ]] && echo Disk is Vormetric: $i
      #/dev/secvm/dev underlying device
      dupdev=$(lsblk |grep -B2 "$(basename $i)" |awk '/disk/{print "/dev/"$1}')
      #strip underlying device used by secvm(Vormetric) from disklist
      disklist=${disklist/$dupdev }
      #disklist=${disklist/$i } #strip secvm(Vormetric) device
   done
   [[ -n "$DBG" ]] && { set +x; echo DiskList: $disklist; }
   [[ -n "$DBG" ]] && read -p "Press enter to continue or ctrl-c to abort"
}

# Report on unused or all disks found
case "$diskset" in
   all)
      disklist=$(fdisk -l 2>/dev/null | awk '/^Disk \// {print $2}' |sort)
      echo -e "All disks: " $disklist; echo; exit
      ;;
   unused)
      if [[ $preserve == true ]]; then
         [[ -f /tmp/disk.list ]] || { echo /tmp/disk.list does not exist; exit; }
         # Re-use /tmp/disk.list
         disklist=$(</tmp/disk.list)
      else
         # Find unused disks and set $disklist
         find_unused_disks
         # Log the disk list for mapr-install.sh
         echo $disklist | tr ' ' '\n' >/tmp/disk.list
      fi
      [[ -n "$DBG" ]] && cat /tmp/disk.list
      [[ -n "$DBG" ]] && read -p "Press enter to continue or ctrl-c to abort"
      if [[ -n "$disklist" ]]; then
         echo; echo "Unused disks: $disklist"
         [[ -t 1 ]] && { tput -S <<< $'setab 3\nsetaf 0'; }
         echo -n Scrutinize this list carefully!!
         [[ -t 1 ]] && tput op
         echo
         #echo -e "\033[33;5;7mScrutinize this list carefully!!\033[0m"
      else
         echo; echo "No Unused disks!"; echo; exit 1
      fi
: << '--BLOCK-COMMENT--'
      diskqty=$(echo $disklist | wc -w)
      #See /opt/mapr/conf/mfs.conf: mfs.max.disks
      #TBD: add smartctl disk detail probes
      if type smartctl >& /dev/null; then
         grepopts='-e ^Vendor -e ^Product -e Capacity -e ^Rotation '
         grepopts+=' -e ^Form -e ^Transport'
         smartctl -d megaraid,0 -a /dev/sdf | grep $grepopts
      elif [[ -f /opt/MegaRAID/MegaCLI ]]; then
         /opt/MegaRAID/MegaCLI ...
      fi
--BLOCK-COMMENT--
      ;;
esac

# Run read-only or read-write (destructive) tests
case "$testtype" in
   readtest)
      [[ -n "$DBG" ]] && set -x
      #read-only dd test, possible even after MFS is in place
      ddopts="of=/dev/null iflag=direct bs=1M count=$((size*1000))"
      if [[ $seq == "false" ]]; then
         [[ -n "$DBG" ]] && echo Concurrent dd disklist: $disklist
         for i in $disklist; do
            dd if=$i $ddopts |& tee "$(basename $i)-dd.log" &
         done
         echo; echo "Waiting for dd to finish"
         wait
         echo
      else
         for i in $disklist; do
            dd if=$i $ddopts |& tee "$(basename $i)-seq-dd.log"
         done
      fi
      sleep 3
      for i in $disklist; do grep -H MB/s "$(basename $i)*-dd.log"; done
      ;;
   destroy)
      [[ -n "$DBG" ]] && set -x
      if service mapr-warden status; then
         echo 'MapR warden appears to be running'
         echo 'Stop warden (e.g. service mapr-warden stop)'
         exit
      fi
      if pgrep iozone; then
         echo 'iozone appears to be running'
         echo 'kill all iozones running (e.g. pkill iozone)'
         exit
      fi
      #tar up previous log files
      files=$(ls ./*-{dd,iozone}.log 2>/dev/null)
      if [[ -n "$files" ]]; then
         tar czf disk-tests-"$(date "+%FT%T" |tr : .)".tgz $files
         rm -f $files
      fi
      #TBD: add sync option.  Async IO (-k) by default
      iozopts="-I -r 1M -s ${size}G -k 10 -+n -i 0 -i 1 -i 2"
      if [[ $seq == "false" ]]; then # Benchmark all disks concurrently
         for disk in $disklist; do
            iozlog=$(basename $disk)-iozone.log
            $scriptdir/iozone $iozopts -f $disk > $iozlog &
            sleep 2 #Some disk controllers lockup without a delay
         done
         echo; echo "Waiting for iozone to finish"; wait; echo
      else # Sequence through the disk list, one by one
         for disk in $disklist; do
            iozlog=$(basename $disk)-seq-iozone.log
            $scriptdir/iozone $iozopts -f $disk > $iozlog
         done
         echo; echo "IOzone sequential testing done"; echo
      fi
      #write dd test
      #dd if=/dev/urandom of=/dev/sdX oflag=direct bs=1M count=4000
      ;;
   none)
      echo No test requested
      ;;
esac

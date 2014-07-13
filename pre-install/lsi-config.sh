#!/bin/bash
# jbenninghoff@maprtech.com 2013-Mar-10  vi: set ai et sw=3 tabstop=3:

#Strip Size: 256K (1MB when firmware and OS driver allow, TBD)
#Cache Policy: cached
#Read Policy: read ahead
#Write Policy: write thru
#Disk Cache Policy: enabled

echo These are the key LSI controller settings affecting disk IO performance
cd /opt/MegaRAID/MegaCli/
./MegaCli64 -ldinfo -lall -aall | grep -e ^Strip -e '^Virtual Drive:' -e '^Current Cache Policy:' -e '^Disk Cache Policy:'
echo Edit this script carefully to use LSI megacli to configure the virtual drives optimally for MapR
exit

# Linux device handle to LSI drive ID mapping, ID is 2nd to last digit
#jbenning@fusion1 zsh%0 ls -l /sys/block/sd*/device                              
#lrwxrwxrwx 1 root root 0 May 16 14:35 /sys/block/sda/device -> ../../../2:0:0:0
#lrwxrwxrwx 1 root root 0 May 16 14:23 /sys/block/sdb/device -> ../../../2:0:1:0
#lrwxrwxrwx 1 root root 0 May 16 14:35 /sys/block/sdc/device -> ../../../2:0:2:0
#lrwxrwxrwx 1 root root 0 May 16 14:36 /sys/block/sdd/device -> ../../../2:0:3:0
# Last component is a 4 part digit grouped: controllerID:channelID:DRIVEid:LUN

#==================================================================
# Unconfigure all drives except ID 0 (/dev/sda) via the command line using LSI MegaCli64
# This assumes the OS is on /dev/sda and that /dev/sda maps to LSI drive ID 0(zero)
# This must be done BEFORE MapR FS is installed and configured (configure.sh)
#===================================================================
#dsks=$(/opt/MegaCli/MegaCli64 -ldgetprop) #Grep someting to get LSI disk count
dsks=24
for i in $(seq 1 $dsks);  do
    # skips ID 0, assumes it is /dev/sda which is assumed to be OS drive.  Check assumptions in your system
    ./MegaCli64 -cfglddel -l$i -a0 # This is destructive to data on $i drives
done
 
# This command applies the configuration to all UNCONFIGURED devices
# The for loop above removes the configuration from all drives except ID 0 (/dev/sda)
./MegaCli64 -cfgeachdskraid0 WT RA cached NoCachedBadBBU –strpsz256 -a0
 
# Enables on disk cache, not suitable for production environment
#for i in `seq 1 40`;  do
#    ./MegaCli64 -ldsetprop endskcache -l$i -a0
#done

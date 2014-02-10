#!/bin/bash

#Stripe Size: 256K (1MB when firmware and OS driver allow, TBD)
#Cache Policy: cached
#Read Policy: read ahead
#Write Policy: write thru
#Disk Cache Policy: enabled

echo These are the key LSI controller settings affecting disk IO performance
/opt/MegaCli/MegaCli64 -ldpdinfo -aall | grep -e 'Read Ahead' -e …..
/opt/MegaCli/MegaCli64 -ldinfo -lall -aall | egrep 'Sector|Current Cache Policy|Disk Cache Policy'
echo Edit this script carefully to use LSI megacli to configure the virtual drives optimally for MapR
exit

#==================================================================
 
#Here is how we accomplish this via the command line using LSI MegaCli64 tool:
#===================================================================
for i in `seq 1 40`;  do
    cd /opt/MegaCli/
    /opt/MegaCli/MegaCli64 -cfglddel -l$i -a0 # This is destructive to data on $i drives
done
 
/opt/MegaCli/MegaCli64 -cfgeachdskraid0 WT RA cached NoCachedBadBBU –strpsz256 -a0
 
for i in `seq 1 40`;  do
    cd /opt/MegaCli/
    /opt/MegaCli/MegaCli64 -ldsetprop endskcache -l$i -a0
done

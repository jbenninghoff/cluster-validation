#!/bin/bash
# jbenninghoff 2013-Jan-06  vi: set ai et sw=3 tabstop=3:

[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }

if type storcli >& /dev/null; then
   :
elif [ -x /opt/MegaRAID/storcli/storcli64 ]; then
   storcli() { /opt/MegaRAID/storcli/storcli64; }
else
   echo storcli command not found; exit 2
fi

echo -e "Unused disks before storcli: \n$(echo $disks | tr ' ' '\n'| sort)"
storcli /c0 /eall /sall show | awk '$3 == "UGood"{print $1}'; exit 
#storcli /c0 /v1 set wrcache=wb rdcache=ra iopolicy=cached pdcache=off strip=1024 #strip size probably cannot be changed

# Loop over all UGood drives and create RAID0 single disk virtual drive (vd)
#storcli /c0 /eall /sall show | awk '$3 == "UGood"{print $1}' | xargs -i sudo storcli /c0 add vd drives={} type=r0 strip=1024 ra wb cached pdcache=off

#assuming drive 17:7 is UGood.  1024 strip needs recent LSI/Avago and 7.x RHEL
#sudo storcli /c0 add vd drives=17:7 type=r0 strip=1024 ra wb cached pdcache=off

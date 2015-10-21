#!/bin/bash
# jbenninghoff 2014-Oct-16  vi: set ai et sw=3 tabstop=3:

[ $(id -u) -ne 0 ] && { echo This script must be run as root; exit 1; }

tmpfile=$(mktemp); trap 'rm $tmpfile' 1 2 3 15

# Define the set of disk devices that will be taken offline and then
# merged into new Storage Pool.  All data on these drives will be lost.
# Assumes the disks in this list form at least one Storage Pool
disklist='/dev/sdh /dev/sdi /dev/sdj /dev/sdk'
disklist='' #Set to null for safety, script must be edited to define disks
echo These disks will be reformatted and all data lost: $disklist
read -p "Press enter to continue or ctrl-c to abort"

# Configure re-replication to start in 1 minute after SP goes offline,
# rather than default 60 min.  Assumes cluster is otherwise quiet.
maprcli config save -values '{"cldb.fs.mark.rereplicate.sec":"60"}'
maprcli config save -values '{"cldb.replication.max.in.transit.containers.per.sp":"8"}'

/opt/mapr/server/mrconfig sp list -v

# Iterate over each disk, allowing the data on each disk to be re-replicated
# before going to the next disk
# Minimal risk since script can be interrupted and SPs brought back online
for dsk in $disklist; do
  echo Taking $dsk offline
  /opt/mapr/server/mrconfig sp offline $dsk || { echo $dsk not an SP; continue; } # If $dsk fails to offline must not be SP
  date; echo Waiting 180 seconds for rereplication to start; sleep 180
  # Now wait until rereplication stops
  until (maprcli dump rereplicationinfo | grep 'No active rereplications'); do
	echo -n 'Still Replicating '; sleep 120
  done
  date; echo rereplication for $dsk is done, next disk
done

echo $disklist All offline and data rereplicated
maprcli dump rereplicationinfo

echo Initial MapR Disktab
cat /opt/mapr/conf/disktab

echo Removing $disklist from MapR FS, SPs cannot be brought back now
maprcli disk remove -host $(hostname) -disks ${disklist// /,} -force true

>$tmpfile
for dsk in $disklist; do
  echo $dsk >> $tmpfile
done
cat $tmpfile

/opt/mapr/server/disksetup -W ${#disklist[@]} -F $tmpfile
echo New disktab ================
cat /opt/mapr/conf/disktab

/opt/mapr/server/mrconfig sp list -v
maprcli config save -values '{"cldb.fs.mark.rereplicate.sec":"3600"}'  #Reset
maprcli config save -values '{"cldb.replication.max.in.transit.containers.per.sp":"4"}'
echo Restart the warden: service mapr-warden restart


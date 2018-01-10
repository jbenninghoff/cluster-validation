#!/bin/bash
# jbenninghoff 2015-Jun-29  vi: set ai et sw=3 tabstop=3 retab:

# Usage
usage() {
  echo "Usage: $0 new-user-name <optional uid>"
  echo group name and gid will match user-name and uid
  echo optional uid will be checked for availability and used if available
  exit 1
}
[[ $# -lt 1 ]] && usage
[[ $(id -u) -ne 0 ]] && { echo This script must be run as root; exit 1; }
type clush >& /dev/null || { echo clush required for this script; exit 2; }

pw=${3:-password}
# Check if current host in clush group all and define exception
nodeset -e @all | grep $(hostname -s) && xprimenode="-x $(hostname -s)"

# Check for existing uid and gid
if [[ $# -gt 1 ]]; then
   clush -S -b -g all $xprimenode "getent passwd $2" && { echo $2 is in use already; exit 1; }
   clush -S -b -g all $xprimenode "getent group $2" && { echo $2 in use already; exit 1; }
   adduid="-u $2"
   addgid="-g $2"
fi

# Create new Linux user on all cluster nodes
prep-linux-user() {
   groupadd $addgid $1
   useradd -m -c 'MapR user account' -g $1 $adduid $1
   # set password for user
   echo -e "$pw\n$pw" | passwd $1
   # Get system generated uid/gid
   uid=$(getent passwd $1| awk -F: '{print $3}')
   gid=$(getent group $1| awk -F: '{print $3}')
   adduid="-g $uid"; printf "UID: $uid\n"
   addgid="-g $gid"; printf "GID: $gid\n"

   # Create group on all nodes
   clush -b -g all $xprimenode "groupadd $addgid $1"
   # Create user on all nodes
   clush -b -g all $xprimenode "useradd -m -c 'MapR user account' -g $1 $adduid $1"
   # Set password for user on all nodes
   clush -b -g all $xprimenode "echo -e '$pw\n$pw' | passwd $1"
   # Set secondary group membership as needed, modify and uncomment
   # clush -b -g all $xprimenode usermod -G wheel,project1 $1
   # Verify consistent id
   clush -b -g all "id $1"
done

# Set up MapR folder and proxy for the specified user
prep-mapr-user() {
   clush -a touch /opt/mapr/conf/proxy/$1
   clush -a chown mapr:mapr /opt/mapr/conf/proxy/$1
   #TBD: run as mapr and define ticket location
   hadoop fs -mkdir /user/$1
   hadoop fs -chown $1:$1 /user/$1
}

if getent passwd $1; do
   echo $1 is in use already
   clush -b -g all "id $1"
   echo Adding $1 to MapR cluster
   prep-mapr-user
else
   prep-linux-user
   prep-mapr-user
done


#!/bin/bash
# jbenninghoff 2015-Jun-29  vi: set ai et sw=3 tabstop=3 retab:

# Usage
usage() {
  echo "Usage: $0 new-user-name <optional uid>"
  echo group name and gid will match user-name and uid
  echo optional uid will be checked for availability and used if available
  exit 1
}
[ $# -gt 0 ] || usage
getent passwd $1| awk -F: '{print $1}' | grep "^$1$" && { echo $1 is in use already; exit 1; }
if [ $# -gt 1 ]; then
  getent passwd $2 && { echo $2 is in use already; exit 1; }
  getent group $2 && { echo $2 is in use already; exit 1; }
  adduid="-u $2"
  addgid="-g $2"
fi

# add group
groupadd $addgid $1
# add user
useradd -m -c 'MapR user account' -g $1 $adduid $1
# set password for user
echo -e "password\npassword" | passwd $1
# Generate keys?
# Set secondary group membership as needed
# usermod -G wheel,project1 $1
# Get uid/gid
uid=$(getent passwd $1| awk -F: '{print $3}')
gid=$(getent group $1| awk -F: '{print $3}')
printf "UID: $uid\n"
printf "GID: $gid\n"

# Check if current host in clush group all
nodeset -e @all | grep $(hostname -s) && xprimenode="-x $(hostname -s)"

# Check for existing user name, uid and gid
clush -S -b -g all $xprimenode "getent passwd $1" && { echo $1 is in use already; exit 1; }
clush -S -b -g all $xprimenode "getent passwd $uid" && { echo $uid in use already; exit 1; }
clush -S -b -g all $xprimenode "getent passwd $gid" && { echo $gid in use already; exit 1; }

# Create group on all nodes
clush -b -g all $xprimenode "groupadd $addgid $1"
# Create user on all nodes
clush -b -g all $xprimenode "useradd -m -c 'MapR user account' -g $1 $adduid $1"
# Set password for user on all nodes
clush -b -g all $xprimenode "echo -e 'password\npassword' | passwd $1"
# Set secondary group membership as needed
# clush -b -g all $xprimenode usermod -G wheel,project1 $1
# Verify consistent id
clush -b -g all "id $1"

hadoop fs -mkdir /user/$1
hadoop fs -chown $1:$1 /user/$1


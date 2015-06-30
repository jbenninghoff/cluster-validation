#!/bin/bash
# jbenninghoff 2015-Jun-29  vi: set ai et sw=3 tabstop=3 retab:

# Usage

# getopts: three options - allDisks, unusedDisks (same as using script without option), and destroy
optspec=":a-:"
while getopts "$optspec" optchar; do
    case "${optchar}" in
      -)
         case "${OPTARG}" in
            allDisks) ALLDISKS=true ;;
            unusedDisks) DISKS=true ;;
            destroy) DESTROY=true ;;
            *) echo "Invalid option --${OPTARG}" >&2
               echo "Please run script either with --allDisks, --destroy, or no arguments" ;;
         esac
      a) ALLDISKS=true ;;
      *) echo "Invalid option -${OPTARG}" >&2
         echo "Please run script either with --allDisks, --destroy, or no arguments" ;;
    esac
done

# Check uid/gid

# Check if current host in clush group all
# add group
# add user
# set password for user
# Generate keys?

# Create group on all nodes

# Create user on all nodes

# Set password for user on all nodes
# Verify id


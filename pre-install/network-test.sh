#!/bin/bash
# jbenninghoff@maprtech.com 2013-Jun-07  vi: set ai et sw=3 tabstop=3:
# TBD: generate IP list with clush, pad list if length of list is odd, split list in half
# The list of all IP addresses can be retrieved with this clush command:  clush -aN hostname -i | sort -n

cat - << 'EOF'
# Use MapR rpctest to validate network bandwidth for worst case, bisection.
# One half of nodes (clients) send load to other half (servers) and 
# the throughput is measured.  MapR rpctest is a client/server binary, 
# use 'rpctest --help' to see options.
#
# Copy the rpctest binary to all nodes into the directory containing
# this script (or ensure that it is in the path).
# Edit this script and redefine half1 and half2 bash arrays with the
# target IP addresses.
# After that, comment out the exit command below to execute the full script
EOF

concurrent=false; runiperf=false
while getopts ":ci" opt; do
  case $opt in
    c) concurrent=true ;;
    i) runiperf=true ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit ;;
  esac
done

scriptdir="$(cd "$(dirname "$0")"; pwd -P)" #absolute path to this script's directory

#############################################################
# Define array of server hosts (half of all hosts in cluster)
#  NOTE: use IP addresses to ensure specific NIC utilization
half1=(10.10.100.165 10.10.100.166 10.10.100.167)

for node in "${half1[@]}"; do
  case $runiperf in
    true)
      ssh -n $node $scriptdir/iperf -s -i3 &  # iperf alternative test, requires iperf binary pushed out to all nodes like rpctest
      ;;
    false)
      ssh -n $node $scriptdir/rpctest -server &
      ;;
  esac
  #ssh $node 'echo $[4*1024] $[1024*1024] $[4*1024*1024] | tee /proc/sys/net/ipv4/tcp_wmem > /proc/sys/net/ipv4/tcp_rmem'
done
echo Servers have been launched
sleep 9 # let the servers stabilize

#############################################################
# Define 2nd array of client hosts (other half of all hosts in cluster)
#  NOTE: use IP addresses to ensure specific NIC utilization
half2=(10.10.100.168 10.10.100.169)

i=0 # index into array
for node in "${half2[@]}"; do
  case $concurrent in
     true)
       if [ $runiperf == "true" ]; then
         ssh -n $node "$scriptdir/iperf -c ${half1[$i]} -t 30 -i3 -w 16K > ${half1[$i]}-iperf.log" & # 16K socket buffer/window size MapR uses
       else
         ssh -n $node "$scriptdir/rpctest -client 5000 ${half1[$i]} > ${half1[$i]}-rpctest.log" &
       fi
       ;;
     false) #Sequential mode can be used to help isolate NIC and cable issues versus switch overload issues
       if [ $runiperf == "true" ]; then
         ssh -n $node "$scriptdir/iperf -c ${half1[$i]} -t 30 -i3 -w 16K > ${half1[$i]}-iperf.log" # 16K socket buffer/window size MapR uses
       else
         ssh -n $node "$scriptdir/rpctest -client 5000 ${half1[$i]} > ${half1[$i]}-rpctest.log"
       fi
       ;;
  esac
  ((i++))
  #ssh $node 'echo $[4*1024] $[1024*1024] $[4*1024*1024] | tee /proc/sys/net/ipv4/tcp_wmem > /proc/sys/net/ipv4/tcp_rmem'
done
echo Clients have been launched
[ $concurrent == "true" ] && wait $! 
sleep 5

tmp=${half2[@]}
[ $concurrent == "true" ] && echo Concurrent network throughput results || echo Sequential network throughput results
[ $runiperf == "true" ] &&  clush -w ${tmp// /,} grep -i -H -e ^Rate -e error \*-iperf.log # Print the measured bandwidth (string TBD)
[ $runiperf == "false" ] &&  clush -w ${tmp// /,} grep -i -H -e ^Rate -e error \*-rpctest.log #Print the network bandwidth (mb/s is MB/sec), 1GbE=125MB/s, 10GbE=1250MB/s
clush -w ${tmp// /,} 'tar czf network-tests-$(date "+%Y-%m-%dT%H-%M%z").tgz *-rpctest.log *-iperf.log; rm *-rpctest.log' # Tar up the log files

tmp=${half1[@]}
clush -w ${tmp// /,} pkill rpctest #Kill the servers

# Unlike most Linux commands, option order is important for rpctest, -port must be used before other options
#[root@rhel1 ~]# /opt/mapr/server/tools/rpctest --help
#usage: rpctest [-port port (def:5555)]  -server
#usage: rpctest [-port port (def:5555)]  -client mb-to-xfer (prefix - to fetch, + for bi-dir)  ip ip ip ... 


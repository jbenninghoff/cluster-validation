#!/bin/bash
# jbenninghoff 2013-Jun-07  vi: set ai et sw=3 tabstop=3:

usage() {
cat << EOF

This script runs the iperf benchmark to validate network bandwidth
using a cluster bisection strategy.  One half of the nodes act as
clients by sending load to other half of the nodes acting as servers.
The throughput between each pair of nodes is reported.  When run
concurrently (the default case), load is also applied to the network
switch(s).

Use -m option to run tests on multiple server NICs
Use -s option to run tests in seqential mode
Use -c option to run MapR rpctest instead of iperf
Use -x option to run 4 flows/streams from each client to measure bonding/teaming NICs
Use -z option to specify size of test in MB (default=5000)
Use -r option to specify reverse sort order of IP addresses, good check for firewall blockage
Use -R option to specify random sort order of IP addresses, good check for firewall blockage
Use -g option to specify a clush group (default is group all)
Use -d option to enable debug output

EOF
}

concurrent=true; runiperf=true; multinic=false; size=5000; sortopt=''; DBG=''; xtra=1; group=all
while getopts "xdscmrRg:z:" opt; do
  case $opt in
    d) DBG=true ;;
    g) group=$OPTARG ;;
    s) concurrent=false ;;
    c) runiperf=false ;;
    x) xtra=4 ;;
    m) multinic=true ;;
    r) sortopt="-$opt" ;; #Reverse order
    R) sortopt="-$opt" ;; #Random order
    z) [[ "$OPTARG" =~ ^[0-9]+$ ]] && size=$OPTARG || { echo $OPTARG is not an integer; usage >&2; exit; } ;;
    \?) usage >&2; exit ;;
  esac
done

scriptdir="$(cd "$(dirname "$0")"; pwd -P)" #absolute path to this script dir
iperfbin=iperf #Installed iperf version
iperfbin=iperf3 #Installed iperf3 {uses same options}
iperfbin=$scriptdir/iperf #Packaged version
rpctestbin=/opt/mapr/server/tools/rpctest #Installed version
rpctestbin=$scriptdir/rpctest #Packaged version
#tmpfile=$(mktemp); trap "rm $tmpfile; echo EXIT sigspec: $?; exit" EXIT
#ssh() { /usr/bin/ssh -l root $@; }

# Generate a host list array
if type nodeset >& /dev/null; then
   hostlist=( $(nodeset -e @${group}) ) #Host list in bash array
elif [[ -f ~/host.list ]]; then
   hostlist=( $(< ~/host.list) )
else
   echo 'This test requires a host list via clush/nodeset or $HOME/host.list file, one host per line' >&2; exit
fi
[[ -n "$DBG" ]] && echo hostlist: ${hostlist[@]}

# Convert host list into  an ip list array
for host in ${hostlist[@]}; do
   iplist+=( $(ssh $host hostname -i | awk '{print $1}') )
done
[[ -n "$DBG" ]] && echo iplist: ${iplist[@]}

# Capture multiple NIC addrs on servers
if [[ $multinic == "true" ]]; then
   for host in ${hostlist[@]}; do
      iplist2+=( $(ssh $host "hostname -I |sed 's/ /,/g'") )
   done #comma sep pair in bash array
   len=${#iplist2[@]}; ((len=len/2)); ((len--))
   multinics=( ${iplist2[@]:0:$len} ) #extract first half of array (servers for rpctest)
   [[ -n "$DBG" ]] && echo multinics: ${multinics[@]}
fi

# Generate the 2 bash arrays with IP address values using array extraction
len=${#iplist[@]}; ((len=len/2))
half1=( ${iplist[@]:0:$len} ) #extract first half of array (servers)
half2=( ${iplist[@]:$len} ) #extract second half of array (clients)
[[ -n "$DBG" ]] && echo half1: ${half1[@]}
[[ -n "$DBG" ]] && echo half2: ${half2[@]}

# Tar up old log files
for host in ${half2[@]}; do
   ssh $host 'files=$(ls *-{rpctest,iperf}.log 2>/dev/null); [[ -n "$files" ]] && { tar czf network-tests-$(date "+%Y-%m-%dT%H-%M%z").tgz $files; rm -f $files; echo "$(hostname -s): Previous run results archived into: $PWD/network-tests-*.tgz"; }'
done
echo

# Sort client list
if [[ -n $sortopt ]]; then
   readarray -t sortlist < <(printf '%s\n' "${half2[@]}" | sort $sortopt)
   half2=( "${sortlist[@]}" )
   echo Sorted half2: ${half2[@]}
fi

# Handle uneven total host count, save and strip last element
len=${#iplist[@]} #list of 3 hosts is special case and the reason why length of half2 can't be used
if [[ $(($len & 1)) -eq 1 ]]; then
   echo Uneven IP address count, removing extra client IP
   len=${#half2[@]} #recalc length of client array, to be used to modify client array
   (( len-- ))
   extraip=${half2[$len]}; echo extraip: $extraip
   #(( len-- )); echo len: $len
   half2=( ${half2[@]:0:$len} )
   [[ -n "$DBG" ]] && echo half2: ${half2[@]}
fi
[[ -n "$DBG" ]] && read -p "$DBG: Press enter to continue or ctrl-c to abort"

##### Servers ###############################################
# Its possible but not recommended to manually define the array of server hosts
# half1=(10.10.100.165 10.10.100.166 10.10.100.167)
# NOTE: use IP addresses to ensure specific NIC utilization

for node in "${half1[@]}"; do
  if [[ $runiperf == "true" ]]; then
     ssh -n $node "$iperfbin -s > /dev/null" &  # iperf alternative test, requires iperf binary on all nodes
  else
     ssh -n $node $rpctestbin -server &
  fi
  #ssh $node 'echo $[4*1024] $[1024*1024] $[4*1024*1024] | tee /proc/sys/net/ipv4/tcp_wmem > /proc/sys/net/ipv4/tcp_rmem'
done
echo ${#half1[@]} Servers have been launched
sleep 5 # let the servers stabilize
[[ -n "$DBG" ]] && read -p "$DBG: Press enter to continue or ctrl-c to abort"

##### Clients ###############################################
# Its possible but not recommended to manually define the array of client hosts
# half2=(10.10.100.168 10.10.100.169 10.10.100.169)
# NOTE: use IP addresses to ensure specific NIC utilization

i=0 # index into the server array
for node in "${half2[@]}"; do #Loop over all clients
  [[ -n "$DBG" ]] && echo client-node: $node, server-node: ${half1[$i]}
  if [[ $concurrent == "true" ]]; then
    if [[ $runiperf == "true" ]]; then
      #ssh -n $node "$iperfbin -c ${half1[$i]} -t 30 -w 16K > ${half1[$i]}---$node-iperf.log" & #16K window size MapR uses
      ssh -n $node "$iperfbin -c ${half1[$i]} -n ${size}M -P$xtra > ${half1[$i]}---$node-iperf.log" &  #increase -n value 10x for better test
      clients+=" $!" #catch this client PID
    else
      if [[ $multinic == "true" ]]; then
         ssh -n $node "$rpctestbin -client -b 32 $size ${multinics[$i]} > ${half1[$i]}---$node-rpctest.log" &
         clients+=" $!" #catch this client PID
      else
         #increase $size value 10x for better test
         ssh -n $node "$rpctestbin -client -b 32 $size ${half1[$i]} > ${half1[$i]}---$node-rpctest.log" &
         clients+=" $!" #catch this client PID
         [[ $xtra -eq 4 ]] && { ssh -n $node "$rpctestbin -client -b 32 $size ${half1[$i]} > ${half1[$i]}---$node-2-rpctest.log" & clients="$clients $!"; }
         [[ -n "$DBG" ]] && ssh -n $node "pgrep -lf $rpctestbin"
         [[ -n "$DBG" ]] && { jobs -l; jobs -p; }
      fi
    fi
     [[ -n "$DBG" ]] && echo clients: "$clients $!"
  else #Sequential mode can be used to help isolate NIC and cable issues
    if [[ $runiperf == "true" ]]; then
      ssh -n $node "$iperfbin -c ${half1[$i]} -n ${size}M -i3 -P$xtra > ${half1[$i]}---$node-iperf.log" #use 10x -n value for better test
    else
      if [[ $multinic == "true" ]]; then
        ssh -n $node "$rpctestbin -client -b 32 $size ${multinics[$i]} > ${half1[$i]}---$node-rpctest.log"
      else
        [[ $xtra -eq 4 ]] && ssh -n $node "$rpctestbin -client -b 32 $size ${half1[$i]} > ${half1[$i]}---$node-2-rpctest.log" &
        ssh -n $node "$rpctestbin -client -b 32 $size ${half1[$i]} > ${half1[$i]}---$node-rpctest.log"
      fi
    fi
    ssh $node "arp -na | awk '{print \$NF}' | sort -u | xargs -l ethtool | grep -e ^Settings -e Speed: "
    ssh $node "arp -na | awk '{print \$NF}' | sort -u | xargs -l ifconfig | grep -e HWaddr -e errors -e 'inet addr:' "
    echo
  fi
  ((i++))
  #ssh $node 'echo $[4*1024] $[1024*1024] $[4*1024*1024] | tee /proc/sys/net/ipv4/tcp_wmem > /proc/sys/net/ipv4/tcp_rmem'
done

[[ $concurrent == "true" ]] && echo ${#half2[@]} Clients have been launched
[[ $concurrent == "true" ]] && { echo Waiting for client PIDS: $clients; wait $clients; } #Wait for all clients to finish in concurrent run
echo Wait over, post processing
sleep 3

# Handle the odd numbered node count case (extra node)
if [[ -n "$extraip" ]]; then
[[ -n "$DBG" ]] && set -x
   echo Measuring extra IP address
   ((i--)) #decrement to reuse last server in server list $half1
   if [[ $runiperf == "true" ]]; then
      ssh -n $extraip "$iperfbin -c ${half1[$i]} -n ${size}M -i3 -P$xtra > ${half1[$i]}---$extraip-iperf.log" #Small initial test, increase size for better test
   else
      ssh -n $extraip "$rpctestbin -client -b 32 $size ${half1[$i]} > ${half1[$i]}---$extraip-rpctest.log"
   fi
   echo Extra IP address $extraip done.
[[ -n "$DBG" ]] && set +x
fi

# Define list of client nodes to collect results from
tmp=${half2[@]}
[[ -n "$extraip" ]] && tmp="$tmp $extraip"
[[ -n "$DBG" ]] && echo Clients: $tmp

[[ -n "$DBG" ]] && read -p "$DBG: Press enter to continue or ctrl-c to abort"
echo
[[ $concurrent == "true" ]] && echo Concurrent network throughput results || echo Sequential network throughput results
if [[ $runiperf == "true" ]]; then
   for host in $tmp; do ssh $host 'grep -i -h -e ^ *-iperf.log'; done # Print the measured bandwidth (string TBD)
   for host in ${half1[@]}; do ssh $host pkill iperf; done #Kill the servers
else
   for host in $tmp; do ssh $host 'grep -i -H -e ^Rate -e error *-rpctest.log'; done #Print the network bandwidth
   echo
   echo "(mb/s is MB/sec), Theoretical Max: 1GbE=125MB/s, 10GbE=1250MB/s, expect 90-94% best case"
   echo "e.g. Expect 1125-1175 MB/sec on all pairs for 10GbE links"
   for host in ${half1[@]}; do ssh $host pkill rpctest; done #Kill the servers
fi

# Unlike most Linux commands, option order is important for rpctest, -port must be used before other options
#[root@rhel1 ~]# /opt/mapr/server/tools/rpctest --help
#usage: rpctest [-port port (def:5555)] -server
#usage: rpctest [-port port (def:5555)] -client mb-to-xfer (prefix - to fetch, + for bi-dir) ip ip ip ...


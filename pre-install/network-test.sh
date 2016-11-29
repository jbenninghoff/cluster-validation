#!/bin/bash
# jbenninghoff 2013-Jun-07  vi: set ai et sw=3 tabstop=3:

>&2 cat << EOF
MapR rpc test to validate network bandwidth using cluster bisection strategy
One half of the nodes act as clients by sending load to other half of the nodes acting as servers.
The throughput between each pair of nodes is reported.
When run concurrently (the default case), load is also applied to the network switch(s).
Use -m option to run tests on multiple server NICs
Use -s option to run tests in seqential mode
Use -i option to run iperf test instead of rpctest
Use -x option to run 2nd stream from client to measure bonding/teaming NICs
Use -z option to specify size of test in MB (default==5000)
Use -r option to specify reverse sort order of IP addresses, good check for firewall blockage
Use -R option to specify random sort order of IP addresses, good check for firewall blockage
EOF
read -p "Press enter to continue or ctrl-c to abort"

concurrent=true; runiperf=false; multinic=false; size=5000; sortopt=''; DBG=''; xtra=false
while getopts "xdsimrRz:" opt; do
  case $opt in
    d) DBG=true ;;
    s) concurrent=false ;;
    i) runiperf=true ;;
    x) xtra=true ;;
    m) multinic=true ;;
    r) sortopt="-$opt" ;; #Reverse order
    R) sortopt="-$opt" ;; #Random order
    z) [[ "$OPTARG" =~ ^[0-9]+$ ]] && size=$OPTARG || { echo $OPTARG is not an integer; exit; } ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit ;;
  esac
done

scriptdir="$(cd "$(dirname "$0")"; pwd -P)" #absolute path to this script dir
iperfbin=iperf #Installed iperf version
iperfbin=iperf3 #Installed iperf3 {uses same options}
iperfbin=$scriptdir/iperf #Packaged version
rpctestbin=/opt/mapr/server/tools/rpctest #Installed version
rpctestbin=$scriptdir/rpctest #Packaged version
tmpfile=$(mktemp); trap 'rm $tmpfile' 0 1 2 3 15
#ssh() { /usr/bin/ssh -l root $@; }

# Generate a host list array
if type nodeset >& /dev/null; then
   hostlist=( $(nodeset -e @all) ) #Host list in bash array
elif [ -f ~/host.list ]; then
   hostlist=( $(< ~/host.list) )
else
   echo "This test requires a host list via clush/nodeset or ~/host.list " >&2; exit
fi
#echo hostlist: ${hostlist[@]}

# Generate an ip list array
for host in ${hostlist[@]}; do
   iplist+=( $(ssh $host hostname -i) )
done
[ -n "$DBG" ] && echo iplist: ${iplist[@]}

# Capture multiple NIC addrs on servers
if [ $multinic == "true" ]; then
   for host in ${hostlist[@]}; do
      iplist2+=( $(ssh $host "hostname -I |sed 's/ /,/g'") )
   done #comma sep pair in bash array
   len=${#iplist2[@]}; ((len=len/2)); ((len--))
   multinics=( ${iplist2[@]:0:$len} ) #extract first half of array (servers for rpctest)
   [ -n "$DBG" ] && echo multinics: ${multinics[@]}
fi

# Generate the 2 bash arrays with IP address values using array extraction
len=${#iplist[@]}; ((len=len/2))
half1=( ${iplist[@]:0:$len} ) #extract first half of array (servers)
half2=( ${iplist[@]:$len} ) #extract second half of array (clients)
[ -n "$DBG" ] && echo half1: ${half1[@]}
[ -n "$DBG" ] && echo half2: ${half2[@]}

# Tar up old log files
for host in ${half2[@]}; do
   ssh $host 'files=$(ls *-{rpctest,iperf}.log 2>/dev/null); [ -n "$files" ] && { tar czf network-tests-$(date "+%Y-%m-%dT%H-%M%z").tgz $files; rm -f $files; }'
done

# Sort client list
if [ -n $sortopt ]; then
   readarray -t sortlist < <(printf '%s\n' "${half2[@]}" | sort $sortopt)
   half2=( "${sortlist[@]}" )
   echo Sorted half2: ${half2[@]}
fi

# Handle uneven total host count, save and strip last element
len=${#iplist[@]} #list of 3 hosts is special case and the reason why length of half2 can't be used
if [ $(($len & 1)) -eq 1 ]; then 
   echo Uneven IP address count, removing extra client IP
   len=${#half2[@]} #recalc length of client array, to be used to modify client array
   (( len-- ))
   extraip=${half2[$len]}; echo extraip: $extraip
   #(( len-- )); echo len: $len
   half2=( ${half2[@]:0:$len} )
   [ -n "$DBG" ] && echo half2: ${half2[@]}
fi

##### Servers ###############################################
# Its possible but not recommended to manually define the array of server hosts
# half1=(10.10.100.165 10.10.100.166 10.10.100.167)
# NOTE: use IP addresses to ensure specific NIC utilization

for node in "${half1[@]}"; do
  if [ $runiperf == "true" ]; then
     ssh -n $node "$iperfbin -s > /dev/null" &  # iperf alternative test, requires iperf binary on all nodes
  else
     ssh -n $node $rpctestbin -server &
  fi
  #ssh $node 'echo $[4*1024] $[1024*1024] $[4*1024*1024] | tee /proc/sys/net/ipv4/tcp_wmem > /proc/sys/net/ipv4/tcp_rmem'
done
echo Servers have been launched
sleep 5 # let the servers stabilize

##### Clients ###############################################
# Its possible but not recommended to manually define the array of client hosts
# half2=(10.10.100.168 10.10.100.169 10.10.100.169)
# NOTE: use IP addresses to ensure specific NIC utilization

i=0 # index into array
for node in "${half2[@]}"; do
   [ -n "$DBG" ] && echo node: $node, half1-i: ${half1[$i]}
  case $concurrent in #TBD: convert case block to if/else block
     true)
       if [ $runiperf == "true" ]; then
         #ssh -n $node "$iperfbin -c ${half1[$i]} -t 30 -w 16K > ${half1[$i]}---$node-iperf.log" & #16K window size MapR uses
         ssh -n $node "$iperfbin -c ${half1[$i]} -n ${size}M > ${half1[$i]}---$node-iperf.log" &  #increase -n value 10x for better test
       else
         if [ $multinic == "true" ]; then
            ssh -n $node "$rpctestbin -client -b 32 $size ${multinics[$i]} > ${half1[$i]}---$node-rpctest.log" &
         else
            ssh -n $node "$rpctestbin -client -b 32 $size ${half1[$i]} > ${half1[$i]}---$node-rpctest.log" & #increase -n value 10x for better test
            [ $xtra == true ] && ssh -n $node "$rpctestbin -client -b 32 $size ${half1[$i]} > ${half1[$i]}---$node-2-rpctest.log" &
         fi
       fi
       clients="$clients $!" #catch all client PIDs ($!)
       ;;
     false) #Sequential mode can be used to help isolate NIC and cable issues
       if [ $runiperf == "true" ]; then
         [ $xtra == true ] && ssh -n $node "$iperfbin -c ${half1[$i]} -n ${size}M -i3 > ${half1[$i]}---$node-s2-iperf.log" &
         ssh -n $node "$iperfbin -c ${half1[$i]} -n ${size}M -i3 > ${half1[$i]}---$node-iperf.log" #increase -n value 10x for better test
       else
         if [ $multinic == "true" ]; then
            ssh -n $node "$rpctestbin -client -b 32 $size ${multinics[$i]} > ${half1[$i]}---$node-rpctest.log"
         else
            [ $xtra == true ] && ssh -n $node "$rpctestbin -client -b 32 $size ${half1[$i]} > ${half1[$i]}---$node-2-rpctest.log" &
            ssh -n $node "$rpctestbin -client -b 32 $size ${half1[$i]} > ${half1[$i]}---$node-rpctest.log"
         fi
       fi

       ssh $node "arp -na | awk '{print \$NF}' | sort -u | xargs -l ethtool | grep -e ^Settings -e Speed:"
       ssh $node "arp -na | awk '{print \$NF}' | sort -u | xargs -l ifconfig | grep errors"
       echo
       ;;
  esac
  ((i++))
  #ssh $node 'echo $[4*1024] $[1024*1024] $[4*1024*1024] | tee /proc/sys/net/ipv4/tcp_wmem > /proc/sys/net/ipv4/tcp_rmem'
done
[ $concurrent == "true" ] && echo Clients have been launched
[ $concurrent == "true" ] && { echo Waiting for PIDS: $clients; wait $clients; } #Wait for all clients to finish in concurrent run
echo Wait over
sleep 5

# Handle the odd numbered node count case (extra node)
if [ -n "$extraip" ]; then 
   echo Measuring extra IP address
   ((i--)) #decrement to reuse last server in server list $half1
   if [ $runiperf == "true" ]; then
      ssh -n $extraip "$iperfbin -c ${half1[$i]} -n ${size}M > ${half1[$i]}---$extraip-iperf.log" #Small initial test, increase size for better test
   else
      ssh -n $extraip "$rpctestbin -client -b 32 $size ${half1[$i]} > ${half1[$i]}---$extraip-rpctest.log"
   fi
fi

# Define list of client nodes to collect results from
tmp=${half2[@]}
[ -n "$extraip" ] && tmp="$tmp $extraip"

echo
[ $concurrent == "true" ] && echo Concurrent network throughput results || echo Sequential network throughput results
if [ $runiperf == "true" ]; then
   for host in $tmp; do ssh $host 'grep -i -h -e ^ *-iperf.log'; done # Print the measured bandwidth (string TBD)
   for host in ${half1[@]}; do ssh $host pkill iperf; done #Kill the servers
else
   for host in $tmp; do ssh $host 'grep -i -H -e ^Rate -e error *-rpctest.log'; done #Print the network bandwidth
   echo "(mb/s is MB/sec), Theoretical Max: 1GbE=125MB/s, 10GbE=1250MB/s, expect 90-94% best case"
   for host in ${half1[@]}; do ssh $host pkill rpctest; done #Kill the servers
fi

# Unlike most Linux commands, option order is important for rpctest, -port must be used before other options
#[root@rhel1 ~]# /opt/mapr/server/tools/rpctest --help
#usage: rpctest [-port port (def:5555)] -server
#usage: rpctest [-port port (def:5555)] -client mb-to-xfer (prefix - to fetch, + for bi-dir) ip ip ip ...


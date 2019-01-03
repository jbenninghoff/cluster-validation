#!/bin/bash
# jbenninghoff 2013-Jun-07  vi: set ai et sw=3 tabstop=3:

usage() {
cat << EOF >&2

This script runs the iperf benchmark to validate network bandwidth
using a cluster bisection strategy.  One half of the nodes act as
clients by sending load to other half of the nodes acting as servers.
The throughput between each pair of nodes is reported.  When run
concurrently (the default case), load is also applied to the network
switch(s).

Use -s option to run tests in seqential mode
Use -c option to run MapR rpctest instead of iperf
Use -x <integer> option to run multiple flows/streams from each
    client to measure bonding/teaming NICs (default 1)
Use -X option to run 2 processes on servers and clients to measure
    bonding/teaming NICs
Use -z <integer> option to specify size of test in MB (default=5000)
Use -r option to specify reverse sort order of IP addresses, good
    test of any firewall blockage
Use -R option to specify random sort order of IP addresses, good
    test of any firewall blockage
Use -g <group name> option to specify a clush group (default is group all)
Use -m option to run tests on multiple server NIC IP addresses
Use -d option to enable debug output

EOF
exit
}

concurrent=true; runiperf=true; multinic=false; size=5000; sortopt=''
DBG=''; xtra=1; group=all; procs=1
while getopts "XdscmrRg:z:x:" opt; do
   msg="$OPTARG is not an integer"
   case $opt in
      d) DBG=true ;;
      g) group=$OPTARG ;;
      s) concurrent=false ;;
      c) runiperf=false ;;
      x) [[ "$OPTARG" =~ ^[0-9]+$ ]] && xtra=$OPTARG || { echo $msg; usage; };;
      X) procs=2 ;;
      m) multinic=true ;;
      r) sortopt="-$opt" ;; #Reverse order
      R) sortopt="-$opt" ;; #Random order
      z) [[ "$OPTARG" =~ ^[0-9]+$ ]] && size=$OPTARG || { echo $msg; usage; };;
      \?) usage >&2; exit ;;
   esac
done

setvars() {
   scriptdir="$(cd "$(dirname "$0")"; pwd -P)" #absolute path to script dir
   iperfbin=iperf3 #Installed iperf3 {uses same options}
   iperfbin=$scriptdir/iperf #Packaged version
   iperfbin=iperf #Installed iperf version
   rpctestbin=/opt/mapr/server/tools/rpctest #Installed version
   rpctestbin=$scriptdir/rpctest #Packaged version
   port2=5002
   #Uncomment next 3 vars to enable NUMA taskset, check nodes with numactl -H
   #numanode0="0-13,28-41"
   #numanode1="14-27,42-55"
   #taskset="taskset -c "
   #tmpfile=$(mktemp); trap "rm $tmpfile; echo EXIT sigspec: $?; exit" EXIT
   if [[ $(id -u) != 0 ]]; then
      ssh() { /usr/bin/ssh -l root $@; }
   fi
}
setvars

if [[ -n "$DBG" ]]; then
   echo concurrent: $concurrent
   echo runiperf: $runiperf
   echo multinic: $multinic
   echo size: $size
   echo sortopt: $sortopt
   echo xtra: $xtra
   echo group: $group
   echo procs: $procs
   read -p "DBG: Press enter to continue or ctrl-c to abort"
fi

# Generate a host list array
if type nodeset >& /dev/null; then
   hostlist=( $(nodeset -e @${group}) ) #Host list in bash array
elif [[ -f ~/host.list ]]; then
   hostlist=( $(< ~/host.list) )
else
   echo 'This test requires a host list via clush/nodeset or ' >&2
   echo "$HOME/host.list file, one host per line" >&2
   exit
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
   #extract first half of array (servers for rpctest)
   multinics=( ${iplist2[@]:0:$len} )
   [[ -n "$DBG" ]] && echo multinics: ${multinics[@]}
fi

# Generate the 2 bash arrays with IP address values using array extraction
len=${#iplist[@]}; ((len=len/2))
half1=( ${iplist[@]:0:$len} ) #extract first half of array (servers)
half2=( ${iplist[@]:$len} ) #extract second half of array (clients)
[[ -n "$DBG" ]] && echo half1: ${half1[@]}
[[ -n "$DBG" ]] && echo half2: ${half2[@]}

# Tar up old log files on the server hosts
for host in ${half2[@]}; do
   p1='files=$(ls *-{rpctest,iperf}.log 2>/dev/null); '
   p1+='[[ -n "$files" ]] && '
   p1+='{ tar czf network-tests-$(date "+%FT%T" |tr : .).tgz $files; '
   p1+='rm -f $files; echo "$(hostname -s): '
   p1+='Previous run results archived into: $PWD/network-tests-*.tgz"; }'
   [[ -n "$DBG" ]] && echo ssh $host "$p1"
   [[ -n "$DBG" ]] && echo ssh $host 'ls *-{rpctest,iperf}.log 2>/dev/null'
   ssh $host "$p1"
done
echo

# Sort client list
if [[ -n $sortopt ]]; then
   readarray -t sortlist < <(printf '%s\n' "${half2[@]}" | sort $sortopt)
   half2=( "${sortlist[@]}" )
   echo Sorted half2: ${half2[@]}
fi

# Handle uneven total host count, save and strip last element
len=${#iplist[@]} #list of 3 hosts is special case, reason half2/2 can't be used
if [[ $(($len & 1)) -eq 1 ]]; then
   echo Uneven IP address count, removing extra client IP
   #recalc length of client array, to be used to modify client array
   len=${#half2[@]}
   (( len-- ))
   extraip=${half2[$len]}; echo extraip: $extraip
   #(( len-- )); echo len: $len
   half2=( ${half2[@]:0:$len} )
   [[ -n "$DBG" ]] && echo half2: ${half2[@]}
fi
[[ -n "$DBG" ]] && read -p "DBG: Press enter to continue or ctrl-c to abort"

##### Servers ###############################################
# Its possible but not recommended to manually define the array of server hosts
# half1=(10.10.100.165 10.10.100.166 10.10.100.167)
# NOTE: use IP addresses to ensure specific NIC utilization
for node in "${half1[@]}"; do
  if [[ $runiperf == "true" ]]; then
     ssh -n $node "$taskset $numanode0 $iperfbin -s > /dev/null" &  
     if [[ $procs -gt 1 ]]; then
        ssh -n $node "$taskset $numanode1 $iperfbin -s -p $port2 >/dev/null" & 
        echo 2nd server process on port $port2
     fi
  else
     ssh -n $node $rpctestbin -server &
  fi
  #ssh $node 'echo $[4*1024] $[1024*1024] $[4*1024*1024] | \
  #tee /proc/sys/net/ipv4/tcp_wmem > /proc/sys/net/ipv4/tcp_rmem'
done
echo ${#half1[@]} Servers have been launched
[[ $procs -gt 1 ]] && echo $procs processes per server launched
sleep 5 # let the servers stabilize
[[ -n "$DBG" ]] && read -p "DBG: Press enter to continue or ctrl-c to abort"

##### Clients ###############################################
# Its possible but not recommended to manually define the array of client hosts
# half2=(10.10.100.168 10.10.100.169 10.10.100.169)
# NOTE: use IP addresses to ensure specific NIC utilization
i=0 # Index into the server array
for node in "${half2[@]}"; do #Loop over all clients
   [[ -n "$DBG" ]] && echo client-node: $node, server-node: ${half1[$i]}
   log="${half1[$i]}--$node-iperf.log"
   if [[ $concurrent == "true" ]]; then
      if [[ $runiperf == "true" ]]; then
         #$iperfbin -w 16K #16K window size MapR uses
         cmd="$taskset $numanode0 $iperfbin -c ${half1[$i]} -t 30 -P$xtra"
         ssh -n $node "$cmd > $log" & 
         clients+=" $!" #catch PID
         if [[ $procs -gt 1 ]]; then
            cmd="$taskset $numanode1 $iperfbin -c ${half1[$i]} -t 30 -P$xtra"
            ssh -n $node "$cmd -p $port2 > ${log/iperf/$port2-iperf/}" &
            clients+=" $!" #catch PID
         fi
      else
         log="${half1[$i]}--$node-rpctest.log"
         if [[ $multinic == "true" ]]; then
            cmd="$rpctestbin -client -b 32 $size ${multinics[$i]}"
            ssh -n $node "$cmd > $log" &
            clients+=" $!" #catch this client PID
         else
            #increase $size value 10x for better test
            cmd="$rpctestbin -client -b 32 $size ${half1[$i]}"
            ssh -n $node "$cmd > $log" &
            clients+=" $!" #catch this client PID
            if [[ $procs -gt 1 ]]; then
               ssh -n $node "$cmd > ${log/rpctest/2-rpctest}" &
               clients+=" $!" #catch this client PID
            fi
            [[ -n "$DBG" ]] && { jobs -l; jobs -p; }
         fi
      fi
      [[ -n "$DBG" ]] && echo clients: "$clients $!"
   else #Sequential mode can be used to help isolate NIC and cable issues
      if [[ $runiperf == "true" ]]; then
         #$iperfbin -w 16K #16K window size MapR uses
         if [[ $procs -gt 1 ]]; then
            cmd="$taskset $numanode1 $iperfbin -c ${half1[$i]} -t 30 -P$xtra"
            ssh -n $node "$cmd -p $port2 > ${log/iperf/$port2-iperf}" &
            echo 2nd client process to port $port2
            echo logging to ${log/iperf/$port2-iperf}
         fi
         cmd="$taskset $numanode0 $iperfbin -c ${half1[$i]} -t 30 -P$xtra"
         ssh $node "$cmd > $log"
      else
         log="${half1[$i]}--$node-rpctest.log"
         if [[ $multinic == "true" ]]; then
            cmd="$rpctestbin -client -b 32 $size ${multinics[$i]}"
            ssh -n $node "$cmd > $log"
         else
            cmd="$rpctestbin -client -b 32 $size ${half1[$i]}"
            if [[ $procs -gt 1 ]]; then
               ssh -n $node "$cmd > ${log/rpctest/2-rpctest}" &
            fi
            ssh -n $node "$cmd > $log"
         fi
      fi
      echo; echo "Test from $node to ${half1[$i]} complete"
      # Get NIC stats when running sequential tests
      echo >> $log; echo >> $log
      if type ip >& /dev/null; then
         nics=$(ssh $node ip neigh |awk '{print $3}' |sort -u)
         for inic in $nics; do
            ssh $node "ethtool $inic |grep -e ^Settings -e Speed: >> $log"
            ssh $node "ip -s link show dev $inic  >> $log"
         done
      else
         gs="-e HWaddr -e errors -e 'inet addr:'"
         nics=$(ssh $node arp -na |awk '{print $NF}' |sort -u)
         for inic in $nics; do
            ssh $node "ethtool $inic |grep -e ^Settings -e Speed: >> $log"
            ssh $node "ifconfig $inic |grep $gs  >> $log"
         done
      fi
   fi
   ((i++))
done

if [[ $concurrent == "true" ]]; then
   echo ${#half2[@]} Clients have been launched
   [[ $procs -gt 1 ]] && echo $procs processes per client launched
   echo Waiting for client PIDS: $clients
   wait $clients
   echo Wait over, post processing; sleep 3
fi

# Handle the odd numbered node count case (extra node)
if [[ -n "$extraip" ]]; then
   [[ -n "$DBG" ]] && set -x
   echo
   echo Measuring extra IP address, NOT a concurrent measurement
   ((i--)) #decrement to reuse last server in server list $half1
   if [[ $runiperf == "true" ]]; then
      iargs="-c ${half1[$i]} -t30 -P$xtra"
      ilog="${half1[$i]}--$extraip"
      if [[ $procs -gt 1 ]]; then
         ssh -n $extraip "$iperfbin $iargs -p $port2 > $ilog-$port2-iperf.log" &
      fi
      ssh -n $extraip "$iperfbin $iargs > $ilog-iperf.log"
   else
      rargs="-client -b 32 $size ${half1[$i]}"
      rlog="${half1[$i]}--$extraip"
      ssh -n $extraip "$rpctestbin $rargs > $rlog-rpctest.log"
   fi
   echo Extra IP address $extraip done.
   [[ -n "$DBG" ]] && set +x
fi

# Define list of client nodes to collect results from
half2+=("$extraip")
[[ -n "$DBG" ]] && echo Clients: ${half2[@]}
[[ -n "$DBG" ]] && read -p "DBG: Press enter to continue or ctrl-c to abort"
echo

if [[ $concurrent == "true" ]]; then
   echo Concurrent network throughput results 
else
   echo Sequential network throughput results
fi

if [[ $runiperf == "true" ]]; then
   # Print the measured bandwidth (string TBD)
   for host in ${half2[@]}; do ssh $host 'grep -i -h -e ^ *-iperf.log'; done
   echo
   echo "Theoretical Max: 1GbE=125MB/s, 10GbE=1250MB/s"
   echo "Expect 90-94% best case, 1125-1175 MB/sec on all pairs for 10GbE"
   #Kill the servers
   for host in ${half1[@]}; do ssh $host pkill iperf; done
else
   #Print the network bandwidth
   for host in ${half2[@]}; do
      ssh $host 'grep -i -H -e ^Rate -e error *-rpctest.log'
   done
   echo
   echo "(mb/s is MB/sec), Theoretical Max: 1GbE=125MB/s, 10GbE=1250MB/s"
   echo "expect 90-94% best case"
   echo "e.g. Expect 1125-1175 MB/sec on all pairs for 10GbE links"
   #Kill the servers
   for host in ${half1[@]}; do ssh $host pkill rpctest; done
fi

# Unlike most Linux commands, option order is important for rpctest,
# -port must be used before other options
#[root@rhel1 ~]# /opt/mapr/server/tools/rpctest --help
#usage: rpctest [-port port (def:5555)] -server
#usage: rpctest [-port port (def:5555)] -client mb-to-xfer
#(prefix - to fetch, + for bi-dir) ip ip ip ...

#ssh $node 'echo $[4*1024] $[1024*1024] $[4*1024*1024] | \
#tee /proc/sys/net/ipv4/tcp_wmem > /proc/sys/net/ipv4/tcp_rmem'

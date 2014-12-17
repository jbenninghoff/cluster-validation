#!/bin/bash
# dgomerman@maprtech.com 2014-Mar-25
DATE="`date +%Y-%m-%d-%H:%M`"
YARN="false"
MRV=$(maprcli cluster mapreduce get |tail -1 |awk '{print $1}')
if [ "$MRV" == "yarn" ] ; then
    YARN="true"
fi
EXECUTABLE="./runTeraSort.sh"
RUN_LOG="teraTune-$DATE-$$.log"
TMP_LOG="/tmp/teraTuneTmp-$$.log"
CYCLES=1


if [ "$YARN" == "false" ] ; then # MRv1
    REDUCE_CAPACITY="`maprcli dashboard info -json |grep '\"reduce_task_capacity\"' |sed -e 's/[^0-9]*//g'`"
    NODES=$(maprcli node list -columns hostname,cpus,ttReduceSlots | awk '/^[1-9]/{if ($2>0) count++};END{print count}')
else # MRv2 Yarn
    REDUCE_CAPACITY="`maprcli node list -columns hostname,cpus,service,disks |grep nodemanager | awk '/^[1-9]/{count+=$4}; END{print count}'`"
    NODES=$(maprcli node list -columns hostname,cpus,service |grep nodemanager |wc --lines)
fi

MAX_REDUCE=$REDUCE_CAPACITY
if [ -n "$REDUCE_CAPACITY" -a -n "$NODES" -a $NODES -gt 0 ] ; then
    if [ $NODES -gt $REDUCE_CAPACITY ] ; then
        MAX_REDUCE=1
    else
        let MAX_REDUCE=$REDUCE_CAPACITY/$NODES
    fi
fi

# Change RUN_LOG path if $1 specified
if [ -n "$1" ] ; then
    out_dir=$(dirname $1)
    if [ ! -d "$out_dir" ] ; then
        echo "$out_dir log directory missing. Exiting."
        exit 1
    fi
    RUN_LOG="$1"
fi

# DEBUG ONLY - START #
DEBUG=0
if [ $DEBUG -eq 1 ] ; then
    MAX_REDUCE=99999
    run[0]=410
    run[1]=386
    run[2]=380
    run[3]=377
    run[4]=433
    run[5]=388
    run[6]=383
    run[7]=380
    run[8]=394
    run[9]=384
    run[10]=381
    run[11]=386
    run[12]=394
    run[13]=391
fi
# DEBUG ONLY - END #

time_to_sec() {
    local time="$1"
    local time_arr=(${my_time//,/ })
    local h=0
    local m=0
    local s=0
    for el in ${time_arr[*]} ; do
        echo "$el" |grep "hrs" > /dev/null 2>&1
        if [ $? -eq 0 ] ; then
            h="`echo \"$el\" |sed -e 's/[^0-9 ]*//g'`"
        fi
        echo "$el" |grep "mins" > /dev/null 2>&1
        if [ $? -eq 0 ] ; then
            m="`echo \"$el\" |sed -e 's/[^0-9 ]*//g'`"
        fi
        echo "$el" |grep "sec" > /dev/null 2>&1
        if [ $? -eq 0 ] ; then
            s="`echo \"$el\" |sed -e 's/[^0-9 ]*//g'`"
        fi
    done
    local duration
    let duration=$h*60*60+$m*60+$s
    echo -ne $duration
}
sec_to_time() {
    local s="$1"
    local h m
    let h=$s/3600
    let s=$s%3600
    let m=$s/60
    let s=$s%60
    echo -ne "${h}hrs ${m}mins ${s}sec"
}
print_ln() {
    echo "================================================================================"
}
do_log() {
    local to_log="$1"
    echo -ne "$to_log" |tee -a $RUN_LOG
}
do_run() {
    local cyc="$1"
    local test_count="$2"
    local my_rtasks="$3"
    do_log "$cyc\t$test_count\t$my_rtasks\t"

    if [ $DEBUG -eq 1 ] ; then # DEBUG
        my_fd=${run[$test_count]}
    else # NORMAL
        $EXECUTABLE $my_rtasks > $TMP_LOG 2>&1
        my_time="`grep \"^Finished At:\" $TMP_LOG |sed -e 's/^.*(//' -e 's/).*//g'`"
        #echo "TIME: $my_time"
        rm "$TMP_LOG"
        my_fd="`time_to_sec $my_time`"
        if [ $my_fd -eq 0 ] ; then
            echo -ne "\nERROR: Received invalid time for test run. Exiting.\n"
            exit 1
        fi
    fi
    do_log "$my_fd\n"
}

start_time="`date +%s`"

print_ln
for cyc in `seq $CYCLES` ; do
    fast_duration=0
    test_count=0
    my_fd=0

    a=0
    b=0
    let c=2**2
    if [ $c -gt $MAX_REDUCE ] ; then
        c=$MAX_REDUCE
    fi
    while [ 1 ] ; do
        do_run "$cyc" "$test_count" "$c"
        #echo -ne "$a\t$b\t$c\t$my_fd\n"
        if [ $a -eq 0 ] ; then # First run
            fast_duration=$my_fd
            if [ $c -lt $MAX_REDUCE ] ; then # Shouldn't set a to MAX on first run, otherwise next while loop cycle is cut short
                a=$c
            fi
        elif [ $b -eq 0 ] ; then # Second run
            if [ $my_fd -gt $fast_duration ] ; then # Already slower
                b=$a
                a=0
                break
            else
                fast_duration=$my_fd
                b=$c
            fi
        else # Future runs
            if [ $my_fd -lt $fast_duration ] ; then # Faster
                fast_duration=$my_fd
                a=$b
                b=$c
            else # Slower, found max
                break
            fi
        fi
        if [ $c -ge $MAX_REDUCE ] ; then # If c is already maxed, no point running with it AGAIN, break
            c=$MAX_REDUCE
            if [ $b -eq 0 ] ; then
                b=$c
            fi
            break
        fi
        let c*=2
        if [ $c -gt $MAX_REDUCE ] ; then # No point having more reducers than reduce slots
            c=$MAX_REDUCE
        fi
        let test_count+=1
    done

    x=0
    fin=0
    let test_count+=1
    while [ 1 ] ; do
        if [ $fin -eq 1 ] ; then # Check if last test was run
            break
        fi
        let x='('$a+$c')'/2

        let to_fin=$c-$a
        if [ $to_fin -le 3 ] ; then # Back to middle
            let x=$a+1
            let z=$x+1 # Special case for 3 Reducers max, where c=3, 1 & 2 need to be tested
            if [ $z -ge $b ] ; then
                fin=1
            fi
            if [ $x -eq $b ] ; then
                let x+=1
            fi
            if [ $x -eq $c ] ; then # Special case for 3 Reducers max, where c=3, 1 & 2 need to be tested
                break
            fi
        fi

        if [ $x -ge $MAX_REDUCE ] ; then # No point running more than MAX_REDUCE capacity and MAX has already been tested above
            break
        fi
        do_run "$cyc" "$test_count" "$x"
        #echo -ne "$a\t$b\t$c\t$x\t$my_fd\n"
        if [ $my_fd -lt $fast_duration ] ; then # Faster
            if [ $x -gt $b ] ; then # Properly constrict range
                a=$b
            else
                c=$x
            fi
            b=$x
            fast_duration=$my_fd
        elif [ $my_fd -ge $fast_duration ] ; then # Slower, count = as slower
            if [ $x -gt $b ] ; then
                c=$x
            else
                a=$x
            fi
        fi
        let test_count+=1
    done

    fast_time="`sec_to_time $fast_duration`"
cat <<EOF
Tuned Reducers for test: $b
Duration for $b reducers: $fast_time
Tests executed: $test_count
EOF
    print_ln
done

end_time="`date +%s`"
let total_dur_sec=$end_time-$start_time
total_dur="`sec_to_time $total_dur_sec`"
echo "Total duration: $total_dur"
echo "Log file: $RUN_LOG"


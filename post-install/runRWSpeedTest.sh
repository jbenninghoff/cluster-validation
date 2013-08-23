#!/bin/bash
#
# Simple script to run the MapR RWSpeedTest.  Best suited for testing
# MapR FS performance on a single node within a cluster (so the "local" 
# topology is the default).
#
#	usage: runRWSpeedTest [ <topology> | local ] 
#
#		If a topology is provided, a "diagnostics" volume will be 
#		created there. The keyword "local" will force the creation
#		of a unique "diag_<host>" volume (allowingn for parallel
#		testing).
#
#		If no topology is specified, the local topology will be used
#		(just the node on which the driver is running).
#
#	NOTE: RWSpeedTest is NOT like DFSIO ... it is not a MapReduce job.
#		Thus, the client driver is more likely to be the performance
#		bottleneck.
#

# set -x

MAPR_HOME=${MAPR_HOME:-/opt/mapr}
MAPR_BUILD=`cat $MAPR_HOME/MapRBuildVersion`
MAPR_VERSION=${MAPR_BUILD%.*.GA}

TVOL=diagnostics
btopology=${1:-local}

if [ $btopology = "local" ] ; then
	TVOL=diag_`cat $MAPR_HOME/hostname`
fi
	# TBD : Make sure the topology exists if it's specified
	# (though maprcli volume create will fail if the topology is absent)


#	Recreate the target volume if necessary ... with specific
#	settings for replication, compression, and chunksize
#		NOTE Let's be smart enough to check if it's on the
#		topology we want ... and recreate if necessary

	# maprcli has a bug ... it doesn't print the full topology for
	# the standard listing.  A temporary workaround is to use the 
	# -json output if we see the volume already existing.
maprcli volume list -filter "[volumename==$TVOL]" \
	-columns rackpath,volumename -noheader 2> /dev/null | read btopo bvol
if [ -n "${btopo}" ] ; then
	btopo=`maprcli volume list -filter "[volumename==$TVOL]" -json 2> /dev/null | python -c "import sys,json; jobj=json.load(sys.stdin); print jobj['data'][0]['rackpath']"`
	[ `basename ${btopo}` = `cat $MAPR_HOME/hostname` ] && btopo="local"
fi
if [ "${bvol:-}" != "$TVOL"  -o  "${btopo:-}" != $btopology ] ; then
	maprcli volume unmount -name $TVOL 2> /dev/null
	maprcli volume remove -name $TVOL 2> /dev/null

	if [ "$btopology" = "local" ] ; then
		TARG="-localvolumehost `cat $MAPR_HOME/hostname`"
	elif [ -n "${btopology}" ] ; then
		TARG="-topology $btopology"
	fi

	echo "Creating $TVOL volume on $btopology topology"
	echo ""
	maprcli volume create -name $TVOL -path /$TVOL \
		-replication 1 $TARG
	if [ $? -ne 0 ] ; then
		echo ""
		echo "Aborting $0"
		exit 1
	fi

	hadoop mfs -setcompression off /$TVOL
fi


# There should only be one of these jars ... let's hope :)
MFS_TEST_JAR=`find $MAPR_HOME/lib -name maprfs-diagnostic-tools-\*.jar`

if [ ! -r $MFS_TEST_JAR ] ; then
	echo "RWSpeedTest failed: could not find $MFS_TEST_JAR"
	exit 1
fi

# Figure out how many nodes are supporting the topology 
# (default to entire cluster)
if [ $btopology = "local" ] ; then
	nnodes=1
else
	nnodes=`maprcli node list -noheader -filter "[racktopo==${btopology}*] 2> /dev/null | wc -l"`
fi
[ ${nnodes:-0} -le 0 ] && nnodes=`maprcli node list -noheader | wc -l`
ncpu=`grep -c ^processor /proc/cpuinfo`
coresPerCPU=`grep "^cpu cores" /proc/cpuinfo | head -1 | awk '{print $NF}'`
siblingsPerCPU=`grep "^siblings" /proc/cpuinfo | head -1 | awk '{print $NF}'`

# Leave 2 CPU's (4 threads) for MFS ... the rest for our testing
if [ $siblingsPerCPU -eq $coresPerCPU ] ; then
	if [ $ncpu -gt 4 ] ; then
		ndrivers=$[ncpu-2]
	else
		ndrivers=1
	fi
else	# HyperThreading enabled ... 1 driver per actual core 
	ndrivers=$[ncpu*$coresPerCPU/$siblingsPerCPU]
fi

# Now compute the total data to write/read based on the number of nodes
# in the cluster.
fsize=4096	# I/O size per driver (should be greater than MFS cache)
fsize=$[fsize*$nnodes]

# Testing writing (fsize is positive) and reading (fsize is negative)
echo "RWSpeedTest: $[ndrivers*$fsize] MB across the ${btopology} volume"
echo ""

for i in `seq $ndrivers` ; do
	hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest \
		/$TVOL/RWTest${i} $fsize maprfs:/// 2> /dev/null  &
done
wait

for i in `seq $ndrivers` ; do
	hadoop jar $MFS_TEST_JAR com.mapr.fs.RWSpeedTest \
		/$TVOL/RWTest${i} -$fsize maprfs:/// 2> /dev/null  &
done
wait



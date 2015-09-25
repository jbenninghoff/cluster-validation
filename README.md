Cluster Validation
==================

Before installing MapR Hadoop it is invaluable to validate the hardware and
software that MapR will be dependent on.  Doing so will verify that items like
disks and DIMMs are performing as expected and with a known benchmark metric.
Doing so will also verify that many of the basic OS configurations and
packages are in the required state and that state is also recorded in the
output log.

Please use the steps below to test CPU/RAM, disk, and networking
performance as well as to verify that your cluster meets MapR
installation requirements. Pre-install tests should be run before
installing MapR.  Post-install tests should be run after installing
the MapR software and configuring a cluster.  Post-install tests 
help assure that the cluster is in good working order and ready 
to hand over to your production team.

Install clustershell (rpm provided, also available via EPEL) on a machine
with passwordless ssh to all other cluster nodes.  If using a
non-root account, then non-root account must have passwordless
sudo rights configured in /etc/sudoers.  Update the file
`/etc/clustershell/groups` to include an entry for "all" matching a
pattern or patterns of host names in your cluster.  For example;

    all: node[0-10]
Verify clush works correctly by running:
    "clush -a date"
Compare results with:
    "clush -ab date"

Download and extract the cluster-validation package with a command like this:

    curl -L -o cluster-validation.tgz http://github.com/jbenninghoff/cluster-validation/tarball/master
Extract with tar in /root or your home folder and rename the top level folder like this:  

    mv jbenninghoff-cluster-validation-* cluster-validation
    or
    mv cluster-validation-* cluster-validation

Copy the cluster-validation folder to all nodes in the cluster.  The
clush command simplifies this:

    clush -a --copy /path.../cluster-validation
    clush -Ba ls /path.../cluster-validation	# confirm that all nodes have the utilties

Step 1 : Gather Base Audit Information
--------------------------------------
Use cluster-audit.sh to verify that you have met the MapR installation
requirements.  Run:

    /root/cluster-validation/pre-install/cluster-audit.sh | tee cluster-audit.log
on the node where clush has been installed and configured to access
all cluster nodes.  Examine the log for inconsistency among any nodes.  
Do not proceed until all inconsistencies have been resolved and all 
requirements such as missing rpms, Java version, etc. have been met.
Please send the output of the cluster-audit.log back to us.

	NOTE: cluster-audit.sh is designed for physical servers.   
	Virtual Instances in cloud environments (eg Amazon, Google, or
	OpenStack) may generate confusing responses to some specific
	commands (eg dmidecode).  In most cases, these anomolies are
	irrelevant.

Step 2 : Evaluate Network Interconnect Bandwidth
------------------------------------------------
Use the network test to validate network bandwidth.  This will take
about two minutes or so to run and produce output so be patient.
The script will use clush to collect the IP addresses of all the
nodes and split the set in half, using first half as servers and
the second half as clients.  The half1 and half2 arrays in the
network-test.sh script can be manually defined as well.  There are
command line options for sequential mode and to run iperf as well.
Run:

    /root/cluster-validation/pre-install/network-test.sh | tee network-test.log
on the node where clush has been installed and configured.
Expect about 90% of peak bandwidth for either 1GbE or 10GbE
networks:

	1 GbE  ==>  ~115 MB/sec 
	10 GbE ==> ~1150 MB/sec

Step 3 : Evaluate Raw Memory Performance
----------------------------------------
Use the stream59 benchmark to test memory performance.  This test will take 
about a minute or so to run.  It can be executed in parallel on all
the cluster nodes with the command:

    clush -Ba '/root/cluster-validation/pre-install/memory-test.sh | grep ^Triad' | tee memory-test.log
Memory bandwidth is determined by speed of DIMMs, number of memory
channels and to a lesser degree by CPU frequency.  Current generation
Xeon based servers with eight or more 1600MHz DIMMs can deliver
70-80GB/sec Triad results. Previous generation Xeon cpus (Westmere)
can deliver ~40GB/sec Triad results.

Step 4 : Evaluate Raw Disk Performance
--------------------------------------
Use the iozone benchmark to test disk performance. This process 
is destructive to disks that are tested, so make sure that 
you have not installed MapR nor have any needed data on those 
spindles. The script as shipped will ONLY list out the disks to
be tested. When run with no arguments, this script outputs a 
list of unused disks.  After carefully examining this list, run 
again with --destroy as the argument ('disk-test.sh --destroy') 
to run the destructive IOzone tests on all unused disks.

The test can be run in parallel on all nodes with:

    clush -ab /root/cluster-validation/pre-install/disk-test.sh

Current generation (2012+) 7200 rpm SATA drives can produce 
100-145 MB/sec sequential read and write performance.
By default, the disk test only uses a 4GB data set size to finish
quickly.  Consider using an additional larger size to measure
streaming throughput more thoroughly.
For large numbers of nodes and disks there is a summIOzone.sh script
that can help provide a summary of disk-test.sh output using clush.

    clush -ab /root/cluster-validation/pre-install/summIOzone.sh

Complete Pre-Installation Checks
--------------------------------
When all subsystem tests have passed and met expectations,
there is an example install script in the pre-install folder that
can be modified and used for a scripted install.  Otherwise, follow
the instructions from the doc.mapr.com web site for cluster installation.

Post Installation tests
--------------------------------
Post install tests are in the post-install folder.  The primary 
tests are RWSpeedTest and TeraSort.  Scripts to run each are 
provided in the folder.  Read the scripts for additional info.  

A script to create a benchmarks volume `mkBMvol.sh` is provided.
Additionally, `runTeraGen.sh` script is provided to to generate the terabyte
of data necessary for the TeraSort benchmark.  Be sure to create the 
benchmarks volume before running any of the post install benchmarks.

    NOTE: The TeraSort benchmark (executed by runTeraSort.sh) will likely
    require tuning for each specific cluster.  At a minimum, pass integer
    arguments in powers of 2 (e.g. 4, 8, etc) to the script to increase the
    number of reduce tasks per node up to the maximum reduce slots available on
    your cluster.  Experiment with the -D options as needed.

The post-install folder contains a mapr-audit.sh script which can
be run to provide an audit snapshot of the MapR configuration.  The
script is a useful set of example maprcli commands. There are also
example install, upgrade and uninstall scripts.  None of those will
run without editing, so read the scripts carefully to understand
how to edit them with site specific info.

/John Benninghoff

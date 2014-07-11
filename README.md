==================
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
    "clush -ab date".

Download and extract the cluster-validation package with a command like this:

    curl -L -o cluster-validation.tgz http://github.com/jbenninghoff/cluster-validation/tarball/master
Extract with tar in /root or your home folder and rename the top level folder like this:  

    mv jbenninghoff-cluster-validation-* cluster-validation

Copy the cluster-validation folder to all nodes in the cluster.  The
clush commmand simplifies this:

    clush -a --copy /path.../cluster-validation --dest /path.../cluster-validation
    clush -Ba ls /path.../cluster-validation	# confirm that all nodes have the utilties

Step 1 : Gather Base Audit Information
--------------------------------------
Use cluster-audit.sh to verify that you have met the MapR installation
requirements.  Run:

    /root/pre-install/cluster-audit.sh | tee cluster-audit.log
on the node where clush has been installed and configured to access
all cluster nodes.  Examine the log for inconsistency among any nodes.  
Do not proceed until all inconsistencies have been resolved and all 
requirements such as missing rpms, java version, etc have been met.
Please send the output of the cluster-audit.log back to us.

	NOTE: cluster-audit.sh is designed for physical servers.   
	Virtual Instances in cloud environments (eg Amazon, Google, or
	OpenStack) may generate confusing responses to some specific
	commands (eg dmidecode).  In most cases, these anomolies are
	irrelevant.

Step 2 : Evaluate Network Interconnect Bandwidth
------------------------------------------------
Use the RPC test to validate network bandwidth.  This will take
about two minutes or so to run and produce output so please be
patient.  Update the half1 and half2 arrays in the network-test.sh
script to include the first and second half of the IP addresses of
your cluster nodes.  Delete the exit command also.  Run:

    /root/pre-install/network-test.sh | tee network-test.log
on the node where clush has been installed and configured.
Expect about 90% of peak bandwidth for either 1GbE or 10GbE
networks:

	1 GbE  ==>  ~115 MB/sec 
	10 GbE ==> ~1100 MB/sec

Step 3 : Evaluate Raw Memory Performance
----------------------------------------
Use the stream59 utility to test memory performance.  This test will take 
about a minute or so to run.  It can be executed in parallel on all
the cluster nodes with the command:

    clush -Ba '/root/pre-install/memory-test.sh | grep ^Triad' | tee memory-test.log
Memory bandwidth is determined by speed of DIMMs, number of memory
channels and to a lesser degree by CPU frequency.  Current generation
Xeon based servers with eight or more 1600MHz DIMMs can deliver
70-80GB/sec Triad results. Previous generation Xeon cpus (Westmere)
can deliver ~40GB/sec Triad results.

Step 4 : Evaluate Raw Disk Performance
--------------------------------------
Use the iozone utility to test disk performance.  This process 
is destructive to disks that are tested, so make sure that 
sure that you have not installed MapR nor have any needed data on
those spindles.  The script as shipped will ONLY list out the 
disks to be tested.   You MUST edit the script once you have
verified that the list of spindles to test is correct.

The test can be run in parallel on all nodes with:

    clush -ab /root/pre-install/disk-test.sh

Current generation (2012+) 7200 rpm SATA drives can produce 
100-145 MB/sec sequential read and write performance.
For larger numbers of disks there is a summIOzone.sh script that can help
provide a summary of disk-test.sh output.

Complete Pre-Installation Checks
--------------------------------
When all subsystem tests have passed and met expectations,
there is an example install script in the pre-install folder that
can be modified and used for a scripted install.  Otherwise, follow
the instructions from the doc.mapr.com web site for cluster installation.

Post install tests are in the post-install folder.  The primary 
tests are RWSpeedTest and TeraSort.  Scripts to run each are 
provided in the folder.  Read the scripts for additional info.  

A script to create a benchmarks volume (mkBMvol.sh) is provided.
Additionally, runTeraGen.sh is provided to to generate the terabyte
of data necessary for the TeraSort benchmark.  Be sure to create the 
benchmarks volume before running any of the post install benchmarks.

	NOTE: The TeraSort benchmark (executed by runTeraSort.sh) 
	will likely require tuning for each specific cluster.
	Experiment with the -D options as needed.

There is also a mapr-audit.sh script which can be run to provide
an audit snapshot of the MapR configuration.  The script is a
useful set of example maprcli commands. There are also example install,
upgrade and uninstall scripts.  None of those will run without editing, so
read the scripts carefully to understand how to edit them with site specific
info.

/John Benninghoff

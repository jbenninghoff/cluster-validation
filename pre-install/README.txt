Cluster Validation

Please use the steps below to test CPU/RAM, disk, and networking
performance as well as to verify that your cluster meets MapR
installation requirements. Pre-install tests must be run before
installing MapR.  Post-install tests must be run after installing
MapR.  Post-install tests help assure that the cluster is in good
working order and ready to hand over to production.

Install clush (rpm provided, also available via EPEL) on a machine
with passwordless ssh to all other cluster nodes.  Update the file
/etc/clushtershell/groups to include an entry for "all" matching a
pattern or patterns of host names.  For example, "all: node[0-10]".
Verify clush works correctly by running "clush -a date".  Compare
results with "clush -ab date".

Copy the /root/pre-install folder to all nodes in the cluster via
clush.  For example, run:
clush -a -c /root/pre-install

Use cluster-audit.sh to verify that you have met the MapR installation
requirements.  Run:
/root/pre-install/cluster-audit.sh | tee cluster-audit.log
on the node that runs clush.  Examine the log
for inconsistency among any nodes.  Do not proceed until all
inconsistencies have been resolved and all requirements such as 
missing rpms, java version, etc have been met.
Please send the output of the cluster-audit.log back to us.

Use the RPC test to validate network bandwidth.  This will take
about two minutes or so to run and produce output so please be
patient.  Update the half1 and half2 arrays in the network-test.sh
script to include the first and second half of the IP addresses of
your cluster nodes.  Delete the exit command also.  Run:
/root/pre-install/network-test.sh | tee network-test.log
on the node that runs clush.  Expect about 90% of peak bandwidth
for either 1GbE or 10GbE, which means ~115MB/sec or ~1100 MB/sec
respectively.

Run memory-test.sh This test will take about a minute or so to run.
Run:
clush -ab '/root/pre-install/memory-test.sh | grep ^Triad' | tee memory-test.log
Memory bandwidth is determined by speed of DIMMs, number of memory
channels and to a lesser degree by CPU frequency.  Current generation
Xeon based servers with eight or more 1600MHz DIMMs can deliver
70-80GB/sec Triad results. Previous generation Xeon cpus (Westmere)
can deliver ~40GB/sec Triad results.

Run disk-test.sh to validate disk and disk controller bandwidth.
The process is destructive to disks except /dev/sda so please make
sure that you have not installed MapR nor have any needed data on
any disk except /dev/sda.
Run:
clush -ab /root/pre-install/disk-test.sh
Current generation 7200 rpm SATA drives can produce 100-145 MB/sec
sequential read and write results.
For larger numbers of disks there is a summIOzone.sh script that can help
provide a summary of disk-test.sh output.

When all three subsystem tests have passed and met expectations,
there is an example install script in the pre-install folder that
can be modified and used for a scripted install.  This script assumes
the yum repos are configured and ready to go.  Read the script
carefully to understand how a simple scripted install works.  The
script MUST be modified to work in an actual cluster deployment.

Post install tests are RWSpeedTest, TestDFSIO and TeraSort.  Scripts
to run each are provided in the post-install folder.  Read the
scripts for additional info.  A script to create a benchmarks volume
(mkBMvol.sh) is provided as well as a script to generate the terabyte
of data, runTeraGen.sh.  runTeraSort.sh needs to be tuned to each
specific cluster.  Experiment with the -D options as needed.
There is also a mapr-audit.sh script which can be run to provide
an audit snapshot of the MapR configuration.  The script is a
useful set of example maprcli commands.

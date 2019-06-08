#!/bin/bash
# jbenninghoff 2013-Mar-20  vi: set ai et sw=3 tabstop=3:
set -o nounset
set -o errexit

usage() {
cat <<-EOF
This script sets up MapR repos using clush.

EOF
}

# Handle script options
while getopts "d" opt; do
  case $opt in
    \?) usage; exit ;;
  esac
done

#Use sudo, assuming account has passwordless sudo  (sudo -i)?
[ "$(id -u)" -ne 0 ] && { SUDO='sudo -i '; clargs=' -l root'; }
[ "$(id -u)" -ne 0 ] && SUDO='sudo -i '
clargs='-o -qtt'
#printf -v sep '#%.0s' {1..80} #Set sep to 80 # chars
grepopts=" -m1 -i -o -e ubuntu -e redhat -e 'red hat'   -e centos"
distro=$(cat /etc/*release 2>&1 |grep "$grepopts") || distro=centos
distro=$(echo $distro | tr '[:upper:]' '[:lower:]')
reponame=/etc/yum.repos.d/mapr.repo

if clush "$clargs" -S -B -g all 'grep -qi mapr /etc/yum.repos.d/*'; then
   echo MapR repos found; exit 1
fi
if clush "$clargs" -S -B -g all 'grep -qi -m1 epel /etc/yum.repos.d/*'; then
   echo Warning, EPEL repo not found
fi

#Create 6.x repos on all nodes
cat <<EOF2 | clush "$clargs" -Nq -g all "${SUDO:-} dd status=none of=$reponame"
[mapr-core]
name=MapR Technologies
baseurl=http://package.mapr.com/releases/v6.1.0/redhat/
enabled=1
gpgcheck=0
protect=1

[mapr-eco]
name=MapR Technologies
baseurl=http://package.mapr.com/releases/MEP/MEP-6.0/redhat/
enabled=1
gpgcheck=0
protect=1
EOF2

clush "$clargs" -g all 'rpm --import http://package.mapr.com/releases/pub/maprgpg.key'
clush "$clargs" -g all 'yum --noplugins makecache fast'
clush "$clargs" -g all 'yum --noplugins clean all'

mkgrps() {
   #Define these groups in /etc/clustershell/groups for use by the automated install script
   #Replace the text in angle brackets, including brackets, with site specific host names
   cat <<-EOF1 | ${SUDO:-} tee -a /etc/clustershell/groups >/dev/null
	clstr: @all
	zk: <replace this with 3 node names to run Zookeeper on>
	cldb: <replace this with 3 node names to run CLDB on, can also just be @dzk>
	rm: <replace this with 2 or 3 node names to run Resource Manager on. Use nodes other than CLDB and ZK nodes>
	hist: <replace this with 1 node name to run Yarn History service on. Use nodes other than CLDB and ZK nodes>
	EOF1
}

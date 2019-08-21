#!/bin/bash
# updated to work with AWS
# 20171020 R.Itäpuro initialize valsum variable to get correct CV values

usage() {
cat << EOF

This script summarizes iozone results on a set of disks
iozone results presumed to be in current folder in .log files
Use -c option to output a csv format
Use -C option to output a csv format with header line
Use clush -aLN summIOzone.sh -c to gather all disk-test.sh results in csv.

EOF
exit
}

csv=false; hdr=false DBG=''
while getopts "Ccd" opt; do
   case $opt in
      c) csv=true ;;
      C) csv=true hdr=true;;
      d) DBG=true ;; # Enable debug statements
      *) usage ;;
   esac
done
[[ -n "$DBG" ]] && echo Options set: csv: $csv
[[ -n "$DBG" ]] && read -rp "Press enter to continue or ctrl-c to abort"

files=$(ls ./*-iozone.log 2>/dev/null)
[[ -n "$files" ]] || { echo No iozone.log files found; exit 1; }

if [[ $csv = "true" ]]; then
   gawk -v OFS=, -v HOST="$(hostname -s)" -v HDR=$hdr '
      BEGIN {
         hdr="Host,Disk,DataSize,RecordSize,SeqWrite,SeqRead,"
         hdr=hdr"RandRead,RandWrite"
         if ( HDR == "true" ) print hdr
      }
      /KB  reclen +write/ {
         getline
         print HOST, substr(FILENAME,0,3), $1, $2, $3, $5, $7, $8
      }
   ' ./*-iozone.log
   exit
fi

cat ./*-iozone.log | gawk '
   BEGIN {
      # Initialize seq & rand, min and max values
      swmin=6000000; srmin=swmin; rrmin=swmin; rwmin=swmin
   }

   # For all input files,
   # Match header of IOzone output line,
   # Get next line, read and store data fields
   /KB  reclen +write/ {
     getline
     # err chk if NF < 8
     count++
     fsize = $1
     swtotal += $3
     srtotal += $5
     rrtotal += $7
     rwtotal += $8
     swvals[count] = $3
     srvals[count] = $5
     rrvals[count] = $7
     rwvals[count] = $8
     if ($3 < swmin) swmin = $3; if ($3 > swmax) swmax = $3
     if ($5 < srmin) srmin = $5; if ($5 > srmax) srmax = $5
     if ($7 < rrmin) rrmin = $7; if ($7 > rrmax) rrmax = $7
     if ($8 < rwmin) rwmin = $8; if ($8 > rwmax) rwmax = $8
   }

   END {
     printf "%-7s %1.2f%s\n", "File size:", fsize/(1024*1024), "GB"
     printf "%-7s %6d\n", "Disk count:", count
     print ""

     print "IOzone Sequential Write Summary(KB/sec)"
     swavg = swtotal/count
     printf "%-7s %1.2f%s\n", "aggregate:", swtotal/(1024*1024), "GB/sec"
     printf "%-7s %6d\n", "mean:", swavg
     printf "%-7s %6d\n", "min:", swmin
     printf "%-7s %6d\n", "max:", swmax
     valsum = 0
     for (val in swvals) {
       valsum += (swvals[val] - swavg) ** 2
     }
#     print "stdev: ", sqrt(valsum/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(valsum/count) / swavg)
     print ""

     print "IOzone Sequential Read Summary(KB/sec)"
     sravg = srtotal/count
     printf "%-7s %1.2f%s\n", "aggregate:", srtotal/(1024*1024), "GB/sec"
     printf "%-7s %6d\n", "mean:", sravg
     printf "%-7s %6d\n", "min:", srmin
     printf "%-7s %6d\n", "max:", srmax
     valsum = 0
     for (val in srvals) {
       valsum += (srvals[val] - sravg) ** 2
     }
#     print "stdev: ", sqrt(valsum/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(valsum/count) / sravg)
     print ""

     print "IOzone Random Write Summary(KB/sec)"
     rwavg = rwtotal/count
     printf "%-7s %1.2f%s\n", "aggregate:", rwtotal/(1024*1024), "GB/sec"
     printf "%-7s %6d\n", "mean:", rwavg
     printf "%-7s %6d\n", "min:", rwmin
     printf "%-7s %6d\n", "max:", rwmax
     valsum = 0
     for (val in rwvals) {
       valsum += (rwvals[val] - rwavg) ** 2
     }
#     print "stdev: ", sqrt(valsum/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(valsum/count) / rwavg)
     print ""

     print "IOzone Random Read Summary(KB/sec)"
     rravg = rrtotal/count
     printf "%-7s %1.2f%s\n", "aggregate:", rrtotal/(1024*1024), "GB/sec"
     printf "%-7s %6d\n", "mean:", rravg
     printf "%-7s %6d\n", "min:", rrmin
     printf "%-7s %6d\n", "max:", rrmax
     valsum = 0
     for (val in rrvals) {
       valsum += (rrvals[val] - rravg) ** 2
     }
#     print "stdev: ", sqrt(valsum/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(valsum/count) / rravg)
     print ""
   }
'
# jbenninghoff 2012-Aug-31  vim: set ai et sw=3 tabstop=3: 

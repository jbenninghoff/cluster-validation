#!/bin/bash
# jbenninghoff@maprtech.com 2012-Aug-31  vi: set ai et sw=3 tabstop=3:
# script which summarizes iozone results on a set of disks
# iozone results must be concatenated to a single log file like this:
# cat sd*iozone.log > tmp.log; ./summIOzone.sh tmp.log

cat sd*iozone.log | gawk '
   BEGIN {
     swmin=6000000; srmin=swmin; rrmin=swmin; rwmin=swmin
   }

# Match begining of IOzone output line and capture data fields
   /         4194304    1024/ {
     # err chk if argc < 8
     count++
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
     print "IOzone Sequential Write Summary(KB/sec)"
     swavg = swtotal/count
     printf "%-7s %6d\n", "count:", count
     printf "%-7s %6d\n", "min:", swmin
     printf "%-7s %6d\n", "max:", swmax
     printf "%-7s %6d\n", "mean:", swavg
     for (val in swvals) {
       svals += (swvals[val] - swavg) ** 2
     }
#     print "stdev: ", sqrt(svals/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(svals/count) / swavg)

     print "IOzone Sequential Read Summary(KB/sec)"
     sravg = srtotal/count
     printf "%-7s %6d\n", "count:", count
     printf "%-7s %6d\n", "min:", srmin
     printf "%-7s %6d\n", "max:", srmax
     printf "%-7s %6d\n", "mean:", sravg
     for (val in srvals) {
       svals += (srvals[val] - sravg) ** 2
     }
#     print "stdev: ", sqrt(svals/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(svals/count) / sravg)

     print "IOzone Random Write Summary(KB/sec)"
     rwavg = rwtotal/count
     printf "%-7s %6d\n", "count:", count
     printf "%-7s %6d\n", "min:", rwmin
     printf "%-7s %6d\n", "max:", rwmax
     printf "%-7s %6d\n", "mean:", rwavg
     for (val in rwvals) {
       svals += (rwvals[val] - rwavg) ** 2
     }
#     print "stdev: ", sqrt(svals/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(svals/count) / rwavg)

     print "IOzone Random Read Summary(KB/sec)"
     rravg = rrtotal/count
     printf "%-7s %6d\n", "count:", count
     printf "%-7s %6d\n", "min:", rrmin
     printf "%-7s %6d\n", "max:", rrmax
     printf "%-7s %6d\n", "mean:", rravg
     for (val in rrvals) {
       svals += (rrvals[val] - rravg) ** 2
     }
#     print "stdev: ", sqrt(svals/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(svals/count) / rravg)
   }
'


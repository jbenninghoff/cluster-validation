#!/bin/bash
# jbenninghoff@maprtech.com 2012-Aug-31  vi: set ai et sw=3 tabstop=3:
# script which summarizes iozone results on a set of disks
# iozone results must be concatenated to a single log file like this:
# cat sd*iozone.log > tmp.log; ./summIOzone.sh tmp.log

gawk '
   BEGIN {
     min=600000
   }

# Match begining of IOzone output line
   /         4194304    1024/ {
     count++
     total += $3
     vals[count] = $3
     if ($3 < min) min = $3
     if ($3 > max) max = $3
   }

   END {
     print "IOzone Sequential Write Summary(KB/sec)"
     avg = total/count
     printf "%-7s %6d\n", "count:", count
     printf "%-7s %6d\n", "min:", min
     printf "%-7s %6d\n", "max:", max
     printf "%-7s %6d\n", "mean:", avg
     for (val in vals) {
       svals += (vals[val] - avg) ** 2
     }
#     print "stdev: ", sqrt(svals/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(svals/count) / avg)
   }
' $1

gawk '
   BEGIN {
     min=600000
   }

# Match begining of IOzone output line
   /         4194304    1024/ {
     count++
     vals[count] = $5
     total += $5
     if ($5 < min) min = $5
     if ($5 > max) max = $5
   }

   END {
     avg = total/count
     print "IOzone Sequential Read Summary(KB/sec)"
     printf "%-7s %6d\n", "count:", count
     printf "%-7s %6d\n", "min:", min
     printf "%-7s %6d\n", "max:", max
     printf "%-7s %6d\n", "mean:", avg
     for (val in vals) {
       svals += (vals[val] - avg) ** 2
     }
#     print "stdev: ", sqrt(svals/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(svals/count) / avg)
   }
' $1

gawk '
   BEGIN {
     min=600000
   }

# Match begining of IOzone output line
   /         4194304    1024/ {
     count++
     vals[count] = $7
     total += $7
     if ($7 < min) min = $7
     if ($7 > max) max = $7
   }

   END {
     avg = total/count
     print "IOzone Random Read Summary(KB/sec)"
     printf "%-7s %6d\n", "count:", count
     printf "%-7s %6d\n", "min:", min
     printf "%-7s %6d\n", "max:", max
     printf "%-7s %6d\n", "mean:", avg
     for (val in vals) {
       svals += (vals[val] - avg) ** 2
     }
#     print "stdev: ", sqrt(svals/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(svals/count) / avg)
   }
' $1

gawk '
   BEGIN {
     min=600000
   }

# Match begining of IOzone output line
   /         4194304    1024/ {
     count++
     vals[count] = $8
     total += $8
     if ($8 < min) min = $8
     if ($8 > max) max = $8
   }

   END {
     avg = total/count
     print "IOzone Random Write Summary(KB/sec)"
     printf "%-7s %6d\n", "count:", count
     printf "%-7s %6d\n", "min:", min
     printf "%-7s %6d\n", "max:", max
     printf "%-7s %6d\n", "mean:", avg
     for (val in vals) {
       svals += (vals[val] - avg) ** 2
     }
#     print "stdev: ", sqrt(svals/count)
     printf "CV: %00.1f%%\n", 100*(sqrt(svals/count) / avg)
   }
' $1

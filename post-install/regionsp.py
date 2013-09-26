#!/usr/bin/python
#
# Show distribution of regions(tablets) for a MapR table across storage pools
#
# Requirements:
#   maprcli is in PATH
#   passwordless ssh to cluster nodes to run mrconfig
#
# Usage: regionsp.py <path to table>
#

import sys
import subprocess
import re
import json
import locale
from collections import defaultdict

locale.setlocale(locale.LC_ALL, 'en_US')
progname=sys.argv[0]

def usage(*ustring):
  print 'Usage: '+ progname + ' tablepath'
  if len(ustring) > 0:
    print "       ",ustring[0]
  exit(1)

def errexit(estring, err):
  print estring,": ",err
  exit(1)

def execCmd(cmdlist):
  process = subprocess.Popen(cmdlist, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
  out, err = process.communicate()
  return out,err

def getSpDict(node):
  # Create a storage pool dictionary. 
  #   Key	: SP Name
  #   Value	: List of Containers
  spContainerDict = defaultdict(list)

  # Get a storage pool listing for node
  spls, errout = execCmd(["ssh", "-o", "StrictHostKeyChecking=no", node, "/opt/mapr/server/mrconfig sp list"])
  #if errout: 
  #  errexit(node + " mrconfig sp list", errout)
  splines = spls.split('\n')

  # For each storage pool, extract name and first disk device
  for spline in splines:
#    splineRe=re.compile('^SP .+name (.+?),.*path (.+?)\s*\Z')
    splineRe=re.compile('^SP .+name (.+?), (.+?),.*path (.+?)\s*\Z')
    if not splineRe.match(spline):
      continue
    matches = splineRe.search(spline).groups()
    spName=matches[0]
    spStatus=matches[1]
    spDev=matches[2]

    if spStatus == "Offline":
      continue

    # For the given storage pool (first disk device), get RW container list
    spcntr, errout = execCmd(["ssh", "-o", "StrictHostKeyChecking=no", node, "/opt/mapr/server/mrconfig info containers rw " + spDev])
    spcntrRe=re.compile('^RW containers: (.*)')
    matches = spcntrRe.search(spcntr).groups()
    cntrlist = matches[0].split()
  
    # put the list in the dictionary and return
    spContainerDict[spName].extend(cntrlist)

  return spContainerDict

def getRegionInfo(tablepath):
  regionInfo, errout = execCmd(["/opt/mapr/bin/maprcli", "table", "region", "list", "-path", tablepath, "-json"])
  regionInfoJson=json.loads(regionInfo)
  return regionInfoJson

def isValidRegionJson(regionInfoJson):
  # region info JSON should always have a status
  desc = "NOT_OK"
  status = "NOT_OK"
  if "status" in regionInfoJson:
    desc = status = regionInfoJson["status"]
  if "errors" in regionInfoJson:
    desc = regionInfoJson["errors"][0]["desc"]
  return status, desc

def kStr(i):
  # return number as a string with comma separated thousands
  if isinstance(i, (int,long)):
    return locale.format("%ld", i, grouping=True)
  else:
    return i

#def printfields(field1, sp, regionCnt, rowCnt, size, fidList):
#    print field1.ljust(16), sp.ljust(8), ":", kStr(regionCnt).rjust(4), "regions", kStr(rowCnt).rjust(14), "rows", kStr(size).rjust(17), "bytes  ", fidList
  

def printfields(field1, sp, regionCnt, containerCnt, rowCnt, size, cList):
    print field1.ljust(17), sp.ljust(6), kStr(regionCnt).rjust(8), kStr(containerCnt).rjust(6), kStr(rowCnt).rjust(16), kStr(size).rjust(19), " ", cList
  
def main():

  if len(sys.argv) != 2:
    usage()
  
  tablepath=sys.argv[1]

  regionInfoJson = getRegionInfo(tablepath)
  status, description = isValidRegionJson(regionInfoJson)
  if status != "OK":
    usage(description)
    
  nodeList=[]
  tableContainerDict = defaultdict(list)
  # Create a table container dictionary
  #   Key	: Node
  #   Value	: List of Region Dicts

  ''' 
  Each region dictionary looks like this.  One per region.
  {
	"primarynode":"se-node11.se.lab",
	"secondarynodes":"se-node10.se.lab, se-node13.se.lab",
	"startkey":"user1987445486054028621",
	"endkey":"user24927076355330151",
	"lastheartbeat":0,
	"fid":"3058.32.131224",
	"physicalsize":5983674368,
	"logicalsize":5983674368,
	"numberofrows":4869428
  }

  '''

  regionList=regionInfoJson["data"] # This is a list of region dicts

  # Create a list of nodes that hold a container for the table
  for regionDict in regionList:
    node=regionDict["primarynode"]
    tableContainerDict[node].append(regionDict)
    if node not in nodeList:
      nodeList.append(node)
  nodeList.sort()

  # Loop through nodes printing out region info for each SP.
  # Note that a given container may contain more than one region (fid) for the table
  tableCntTotal=0
  tableSizeTotal=0
  tableRowsTotal=0
  tableContainersTotal=0
  for node in nodeList:
    spTableFidDict = defaultdict(list)	# for each SP, the table FIDs in that SP
    nodeCntTotal=0
    nodeSizeTotal=0
    nodeRowsTotal=0
    nodeContainersTotal=0
    nodeContainerList=[]
    printfields(node, "SP", "Regions", "Cntnrs", "Rows", "Bytes", "Container IDs")
    spRegionCntDict=defaultdict(int)
    spRegionSzDict=defaultdict(long)
    spRegionRowsDict=defaultdict(long)
    spContainerDict=getSpDict(node) # For specified node, SPName:list of containers
    for regionDict in tableContainerDict[node]:
      regionContainer=regionDict["fid"].split('.')[0]
      #print "regionContainer = ", regionContainer
      for sp in spContainerDict:
        if regionContainer in spContainerDict[sp]:
	  spTableFidDict[sp].append(str(regionDict["fid"])) # Add FID to this SP's list of FIDs
	  spRegionCntDict[sp] += 1
	  spRegionSzDict[sp] += regionDict["physicalsize"]
	  spRegionRowsDict[sp] += regionDict["numberofrows"]
    # Need to print out 0 for SPs that don't have anything
    for sp in sorted(spRegionCntDict.iterkeys()):
      #print "  ", sp, "\t", spRegionCntDict[sp]
      size=spRegionSzDict[sp]
      sizeMB=spRegionSzDict[sp]/(1024*1024)
      rowCnt=spRegionRowsDict[sp]
      #print "  ", sp.ljust(8), ":", kStr(spRegionCntDict[sp]).rjust(4), "regions", kStr(rowCnt).rjust(14), "rows", kStr(sizeMB).rjust(10), "MB"
      spTableFidDict[sp].sort()
      containerList = [fid.split('.')[0] for fid in spTableFidDict[sp]]
      containerList=list(set(containerList))
      containerCnt = len(set(containerList))
      printfields(" ", sp, spRegionCntDict[sp], containerCnt, rowCnt, size, ' '.join(containerList)) # spTableFidDict[sp])
      #print "  ", sp.ljust(8), ":", kStr(spRegionCntDict[sp]).rjust(4), "regions", kStr(rowCnt).rjust(14), "rows", kStr(size).rjust(17), "bytes  ", spTableFidDict[sp]
      nodeCntTotal += spRegionCntDict[sp]
      #nodeSizeTotal += sizeMB
      nodeSizeTotal += size
      nodeRowsTotal += rowCnt
      nodeContainersTotal += containerCnt
      nodeContainerList.extend(containerList)
      nodeContainerList.sort()
    #print "  ", "TOTAL".ljust(8), ":", kStr(nodeCntTotal).rjust(4), "regions", kStr(nodeRowsTotal).rjust(14), "rows", kStr(nodeSizeTotal).rjust(10), "MB"
    printfields("TOTAL".rjust(17), "", nodeCntTotal, nodeContainersTotal, nodeRowsTotal, nodeSizeTotal, ' '.join(nodeContainerList))
    print " "
    tableCntTotal += nodeCntTotal
    tableSizeTotal += nodeSizeTotal
    tableRowsTotal += nodeRowsTotal
    tableContainersTotal += nodeContainersTotal
  #print "TABLE TOTAL", ":", kStr(tableCntTotal).rjust(4), "regions", kStr(tableRowsTotal).rjust(14), "rows", kStr(tableSizeTotal).rjust(17), "bytes"
  printfields("TABLE TOTAL:", "", tableCntTotal, tableContainersTotal, tableRowsTotal, tableSizeTotal, "")
  
if __name__ == "__main__":
   main()

exit(0)


#!/bin/bash
#
log=/tmp/Kreek15PV_$(date '+%Y%m%d').log
# Only one >, we only store the last log output (not really useful to store every 5min anyway)
#/usr/local/bin/sbfspot.3/SBFspot -v0 -ad0 -am0 -ae0 > $log

# Don't log anymore, working OK
/home/pi/workers/sbfspot/SBFspot -v0 -ad0 -am0 -ae0  >> $log
# Push to influxdb
/home/pi/workers/sbfspot/SBFspot2influxdb.sh

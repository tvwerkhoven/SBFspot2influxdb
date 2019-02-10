#!/bin/bash

# Get monthly data
#log=/var/log/sbfspot.3/Kreek15PV_$(date '+%Y%m').log
#/usr/local/bin/sbfspot.3/SBFspot -v -sp0 -ad0 -am1 -ae1 -finq >>$log

# Don't log anymore, stuff is working
/home/pi/workers/sbfspot/SBFspot -v -sp0 -nocsv -ad31 -am2 -ae2 -finq 

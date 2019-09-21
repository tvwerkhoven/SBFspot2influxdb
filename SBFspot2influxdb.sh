#!/usr/bin/env bash
# SBFspot2influxdb.sh
# Call this script after running SBFspot to push updated CSV files to influxdb

# From https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash

show_help () {
	echo "${0} -h -f <DATAFILE> -c <SBFspot.cfg path> -i <influx URI>"
}

### Default configuration
SBFCFG=/home/pi/workers/sbfspot/SBFspot.cfg
# TODO: get this from the CSV file (might not always work?)
DATASEP=";"
INFLUXDBURI="http://localhost:8086/write?db=smarthome&precision=s"

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
output_file=""
verbose=0

while getopts "h?vf:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    c)  SBFCFG=$OPTARG
        ;;
    i)  INFLUXDBURI=$OPTARG
        ;;
    f)  DATAFILE=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))
[ "${1:-}" = "--" ] && shift

# If datafile not given as argument, find ourselves
if [ -z ${DATAFILE} ]; then
	echo "Finding data file"
	# Get output path from config. Use tail to skip any duplicate entries, use 
	# cut to select actual value after =, use f2- to select all fields after =, 
	# in case dirname contains =, remove trailing newline/carriage return
	CFGOUTPUTPATH=$(grep ^OutputPath= ${SBFCFG} | tail -n1 | cut -f2- -d= | tr -d '\n\r')
	CFGPLANTNAME=$(grep ^Plantname= ${SBFCFG} | tail -n1 | cut -f2- -d= | tr -d '\n\r')
	CFGCSV_Export=$(grep ^CSV_Export= ${SBFCFG} | tail -n1 | cut -f2- -d= | tr -d '\n\r')

	# CSV export must be enabled. Add 0 to variable in case it's empty
	if [[ $(($CFGCSV_Export+0)) -ne 1 ]]; then
		echo "This script only works with CSV export, aborting"
		exit
	fi

	# Fill in date in path dynamically using date
	OUTPATH=$(date +${CFGOUTPUTPATH} )

	# Find file, abort if it does not exist
	DATAFILE=${OUTPATH}/${CFGPLANTNAME}-Spot-$(date "+%Y%m%d").csv
fi

if [[ ! -e ${DATAFILE} ]]; then
	echo "Datafile for today does not exist, nothing to update, aborting"
	exit
fi

# Check which fields we need
# https://superuser.com/questions/1001973/bash-find-string-index-position-of-substring
# https://stackoverflow.com/questions/229551/how-to-check-if-a-string-contains-a-substring-in-bash#229585
# https://stackoverflow.com/questions/16679369/count-occurrences-of-a-char-in-a-string-using-bash#16679640
# String until desired field: ${HEADERS%%EToday*}
# Strip everything except $DATASEP: ${${HEADERS%%EToday*}//[^$DATASEP]}
HEADERS="dd/MM/yyyy HH:mm:ss;DeviceName;DeviceType;Serial;Pdc1;Pdc2;Idc1;Idc2;Udc1;Udc2;Pac1;Pac2;Pac3;Iac1;Iac2;Iac3;Uac1;Uac2;Uac3;PdcTot;PacTot;Efficiency;EToday;ETotal;Frequency;OperatingTime;FeedInTime;BT_Signal;Condition;GridRelay;Temperature"

# dd/MM/yyyy HH:mm:ss	11/11/2018 12:06:29
# DeviceName	SN: 2120000000
# DeviceType	SB 2000HF-30
# Serial	2120000000
# Pdc1	152
# Pdc2	0
# Idc1	0.61
# Idc2	0
# Udc1	250.37
# Udc2	0
# Pac1	120
# Pac2	0
# Pac3	0
# Iac1	0.521
# Iac2	0
# Iac3	0
# Uac1	230.67
# Uac2	0
# Uac3	0
# PdcTot	152
# PacTot	120
# Efficiency	0
# EToday	0.353
# ETotal	4783.638
# Frequency	49.98
# OperatingTime	13109.604
# FeedInTime	12128.906
# BT_Signal	67.059
# Condition	Ok
# GridRelay	Closed
# Temperature	30.54

PdcTot_field1=${HEADERS%%PdcTot*}
PdcTot_field2=${PdcTot_field1//[^$DATASEP]}
PdcTot_field=$((${#PdcTot_field2}+1))

PacTot_field1=${HEADERS%%PacTot*}
PacTot_field2=${PacTot_field1//[^$DATASEP]}
PacTot_field=$((${#PacTot_field2}+1))

ETotal_field1=${HEADERS%%ETotal*}
ETotal_field2=${ETotal_field1//[^$DATASEP]}
ETotal_field=$((${#ETotal_field2}+1))

EToday_field1=${HEADERS%%EToday*}
EToday_field2=${EToday_field1//[^$DATASEP]}
EToday_field=$((${#EToday_field2}+1))

Temperature_field1=${HEADERS%%Temperature*}
Temperature_field2=${Temperature_field1//[^$DATASEP]}
Temperature_field=$((${#Temperature_field2}+1))

# Get latest entries, query file only once (tail) to prevent race 
# conditions/unique dataset. Replace commas by period for lua/influxdb
LASTDATA=$(tail -n 1 ${DATAFILE} | tr ',' '.')
Datadate=$(echo ${LASTDATA} | cut -f 1 -d ${DATASEP})
PdcTot=$(echo ${LASTDATA} | cut -f ${PdcTot_field} -d ${DATASEP})
PacTot=$(echo ${LASTDATA} | cut -f ${PacTot_field} -d ${DATASEP})
# Multiply ETotal and EToday with 1000*3600 to convert kWh to Joule (SI)
# Use lua as it's quite portable, see https://unix.stackexchange.com/a/40787
ETotal=$(lua -e "print($(echo ${LASTDATA} | cut -f ${ETotal_field} -d ${DATASEP}) * 1000 * 3600)")
EToday=$(lua -e "print($(echo ${LASTDATA} | cut -f ${EToday_field} -d ${DATASEP}) * 1000*3600)")
Temperature=$(echo ${LASTDATA} | cut -f ${Temperature_field} -d ${DATASEP})

# Convert date to epoch (in UTC) for influxdb. We need this in case there was no
# new data added to the file (e.g SBFspot failed), adding the timestamp will
# silently overwrite the previous datapoint.
#
# - We use only the time of the datetime stamp in the file so date(1) will add
#   the date itself. This is done because date(1) assumes MM/DD/YYYY date 
#   formats incompatible with SBFspot log files. Alternative: use 
#   dateutils.strptime -i "%d/%M/%Y %H:%M:%S" ${Datadate} or something similar
# - We don't need to add --utc as %s already converts to seconds since Epoch 
#   UTC.
# - We use second precision (not ms/ns) which is the same resolution as 
#   source data
#
# TODO: detect SBFspot failure such that we don't need this time.
#Datadate="11/11/2018 12:06:29"
Datadatens=$(date -d "${Datadate##* }" +%s)

# Post to influxdb, add explicit timestamp to each measurement
# https://docs.influxdata.com/influxdb/v1.7/tools/api/
# curl --max-time 5 -i -XPOST ${INFLUXDBURI} --data-binary "energy,type=elec,device=sma value=${ETotal} ${Datadatens}
# power,type=elec,device=sma value=${PacTot} ${Datadatens}
# power,type=elec,device=sma,subtype=dc value=${PdcTot} ${Datadatens}
# temperature,type=device,device=sma value=${Temperature} ${Datadatens}"

# New data architecture
# curl --max-time 5 -i -XPOST ${INFLUXDBURI} --data-binary "energyv2 sma=${ETotal} ${Datadatens}
# powerv2 sma_ac=${PacTot} ${Datadatens}
# powerv2 sma_dc=${PdcTot} ${Datadatens}
# systemv2 sma=${Temperature} ${Datadatens}"

# No need for power, we calculate it ourselves
curl --max-time 5 -i -XPOST ${INFLUXDBURI} --data-binary "energyv2 sma=${ETotal} ${Datadatens}
systemv2 sma_temp=${Temperature} ${Datadatens}"


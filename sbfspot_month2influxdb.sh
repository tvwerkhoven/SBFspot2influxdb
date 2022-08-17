#!/usr/bin/env bash
# SBFspot2influxdb.sh
# Call this script after running SBFspot to push updated month-data CSV files to InfluxDB
#
# Layout
# 
# - read command line parms or config file
# -- check if config file exists
# - reconstruct filenaming (e.g. /var/lib/sbfspot/2022/Kreek15PV-20220701.csv)
# -- OutputPath --> complete with date()
# -- Plantname
# - for last X days, read files, push to influxdb per line or batch?
# -- date(OutputPath)/Plantname-YYYYMMDD.csv
# -- 

# From https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash

show_help () {
	echo "Push updated SBFspot month-data CSV files to InfluxDB"
	echo "${0} -h -c [SBFspot.cfg path] -i [influx URI] [querydate in YYYMMDD (today)]"
}

### Default configuration
SCRIPTNAME=$(basename $0)
# Location of SBFspot configuration file (for reading some settings)
SBFCFG=/usr/local/bin/sbfspot.3/SBFspot.cfg
# TODO: get this from the CSV file (might not always work?)
DATASEP=";"
# InfluxDB URI where we should post to
INFLUXDBURI="http://localhost:8086/write?db=smarthomev3&precision=s"
# Date to query (default: today)
QUERYDATE=$(date "+%Y%m%d")

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

while getopts "h?cfi:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    c)  SBFCFG=$OPTARG
        ;;
    i)  INFLUXDBURI=$OPTARG
        ;;
    f)  DATAFILEBASE=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))
[ "${1:-}" = "--" ] && shift

[ -n "${1}" ] && QUERYDATE=${1}

# If datafile not given as argument, find ourselves
if [ -z "${DATAFILEBASE}" ]; then
	/usr/bin/logger -t ${SCRIPTNAME} -p user.debug "Finding data file"
	# Get output path from config. Use tail to skip any duplicate entries, use 
	# cut to select actual value after =, use f2- to select all fields after =, 
	# in case dirname contains =, remove trailing newline/carriage return
	CFGOUTPUTPATH=$(grep ^OutputPath= "${SBFCFG}" | tail -n1 | cut -f2- -d= | tr -d '\n\r')
	CFGPLANTNAME=$(grep ^Plantname= "${SBFCFG}" | tail -n1 | cut -f2- -d= | tr -d '\n\r')
	CFGCSV_Export=$(grep ^CSV_Export= "${SBFCFG}" | tail -n1 | cut -f2- -d= | tr -d '\n\r')

	# CSV export must be enabled. Add 0 to variable in case it's empty
	if [[ $((CFGCSV_Export+0)) -ne 1 ]]; then
		/usr/bin/logger -t ${SCRIPTNAME} -p user.error "This script only works with CSV export, aborting"
		exit
	fi

	# Fill in date in path dynamically using date
	OUTPATH=$(date +"${CFGOUTPUTPATH}" )

	# Find file, abort if it does not exist
	DATAFILEBASE=${OUTPATH}/${CFGPLANTNAME}-
fi

DATAFILE1=${DATAFILEBASE}$(date "+%Y%m%d" --date "${QUERYDATE}").csv

if [[ ! -e "${DATAFILE1}" ]]; then
	/usr/bin/logger -t ${SCRIPTNAME} -p user.error "Datafile for yesterday does not exist, is syntax or config correct? Aborting."
	exit
fi

echo "Running ${0} on ${DATAFILE1}"

# Loop over lines in file
INFLUXQUERY=""
while read dataline; do
	# Split dataline into array
	IFS=${DATASEP} read -ra linearr <<< "$dataline"
	
	# Lines must have three elements, else break
	if [[ "${#linearr[@]}" -ne 3 ]]; then
		echo "${0} syntax mismatch - lines should have 3 elements split by ${DATASEP}"
		break
	fi

	datestr=${linearr[0]}
	ETotal=${linearr[1]}
	PTotal=${linearr[2]}

	# datestring must be non-zero length, kWh string must be float, else break
	if ! [[ -n "$datestr"  && "${ETotal}"  =~ ^[0-9\.]+$ ]]; then
		echo "${0} syntax mismatch - date should be set and kWh should be numerical"
		break
	fi

	# Calculate total energy in Joule (from kWh) via lua
	ETotal=$(lua -e "print(${ETotal} * 1000 * 3600)")

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
	#Datadate="11/11/2018 12:06:29"
	# datestr="31/01/2022 03:00:00"
	read DD MM YYYY hh mm ss <<< ${datestr//[\/:]/ }
	Datadatens=$(date -d "${YYYY}-${MM}-${DD} ${hh}:${mm}:${ss}" +%s)
	THISLINE="energyv3,quantity=electricity,type=production,source=sma value=${ETotal} ${Datadatens}
"
	INFLUXQUERY="${INFLUXQUERY}${THISLINE}"
done <<< "$(tail -n +10 ${DATAFILE1})"

# Push to InfluxDB
curl --max-time 5 -i -XPOST "http://localhost:8086/write?db=smarthomev3&precision=s" --data-binary "${INFLUXQUERY}"

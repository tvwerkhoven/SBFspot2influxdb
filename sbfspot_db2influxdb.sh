#!/usr/bin/env bash
# Push DayData table from SBFspot.db to influxdb

# From https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
show_help () {
	echo "Push SBFspot database (of last N days) to InfluxDB"
	echo "${0} -h -d [path to SBFspot.db] -i [influx URI] [days to push (default=all)]"
}

### Default configuration
SCRIPTNAME=$(basename $0)
# Location of SBFspot configuration file (for reading some settings)
SBFSPOTDB=/var/lib/sbfspot/SBFspot.db
# InfluxDB URI where we should post to
INFLUXDBURI="http://localhost:8086/write?db=smarthomev3&precision=s"

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

while getopts "h?cfi:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    d)  SBFSPOTDB=$OPTARG
        ;;
    i)  INFLUXDBURI=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))
[ "${1:-}" = "--" ] && shift

# Check starting time, default is 0 (all data since epoch), else number of days since today.
STARTTIME=0
[ -n "${1}" ] && NDAYS=${1} && shift
STARTTIME=$(date +"%s" --date "${NDAYS} day ago")

# Loop over lines in file
INFLUXQUERY=""
LOOPCOUNT=0
while read dataline; do
	# Put data in query format. Note that $dataline is already in the right format thanks to sqlite
	THISLINE="energyv3,quantity=electricity,type=production,source=sma value=${dataline}
"
	INFLUXQUERY="${INFLUXQUERY}${THISLINE}"
	LOOPCOUNT=$(( ${LOOPCOUNT} + 1 ))

	# Push to influxdb every 200 lines, reset collection and continue
	if [[ ${LOOPCOUNT} -gt 200 ]]; then
		curl --max-time 5 -i -XPOST ${INFLUXDBURI} --data-binary "${INFLUXQUERY}"
		LOOPCOUNT=0
		INFLUXQUERY=""
	fi
# Query database, convert TotalYield from Wh to Joule, prepare in right format, i.e. ${ETotal} ${Datadatens}
done <<< "$(sqlite3 -list -separator ' ' ${SBFSPOTDB} "SELECT TotalYield*3600,TimeStamp FROM DayData WHERE TimeStamp > ${STARTTIME};")"


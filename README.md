# sbfspot2influxdb

Convert SBFspot data (of various formats) to InfluxDB line protocol and insert to database so I can collect my home automation data in InfluxDB.

*N.B.* Your InfluxDB architecture (measurements/tags/units etc) is likely different, so you'll have to edit these scripts to adjust for this. Also, `precision=s` is required in the InfluxDB call since timestamps are given in seconds.

# All data from SBFspot.db

This script reads the TotalYield field from DayData from `SBFspot.db` and pushes it to influxdb in batches of 200 lines. It's probably the most versatile and fastest if you want to edit something that suits your needs.

Syntax (using command line params):

	  ./sbfspot_db2influxdb.sh -d /var/lib/sbfspot/SBFspot.db -i http://localhost:8086/write?db=yourdatabase&precision=s

Syntax (using embedded defaults):

	./sbfspot_db2influxdb.sh


# Latest data from spot csv files

This script reads the newest `<plant>-Spot-YYYYMMDD.csv` file and pushes the newest measurement in that file to InfluxDB. Can be used for live updating, i.e. run SBFspot first, then this script.

Syntax (get datafile from config file):

	./sbfspot_day2influxdb.sh -c /usr/local/bin/sbfspot.3/SBFspot.cfg -i http://localhost:8086/write?db=yourdatabase&precision=s

Syntax (get datafile directly):

	./sbfspot_day2influxdb.sh -f ${OUTPATH}/${CFGPLANTNAME}-Spot-$(date "+%Y%m%d").csv -i http://localhost:8086/write?db=yourdatabase&precision=s

# All data from regular csv files

This script reads `<plant>-YYYYMMDD.csv` files and pushes all entries to InfluxDB. You can loop this script to push multiple dates.

Syntax:

	./sbfspot_day2influxdb.sh -c /usr/local/bin/sbfspot.3/SBFspot.cfg -i http://localhost:8086/write?db=yourdatabase&precision=s 20220817

Syntax (as loop, to push the last 100 days to InfluxDB, using embedded defaults):

	for d in $(seq -1 -1 -100); do time ./sbfspot_month2influxdb.sh -- "${d} days"; done
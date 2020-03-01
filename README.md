# sbfspot2influxdb

Convert sbfspot data to influxdb line protocol and insert to database

# Repair from csv history file

Given Kreek15PV-202002\*csv files, read, fix date format to ISO, convert kWh to
Joule, then push to influxdb. Can be used in case regular sbfspot script 
failed to back-insert historical data.

	_lastenergyjoule=0
	for _file in Kreek15PV-202002{19..24}.csv; do
	 tail -n +10 "${_file}" | while read -r _line; do
	  IFS=';' read -ra _lineel <<< "${_line}"
	  _energyjoule=$(lua -e "print(${_lineel[1]} * 1000*3600)")
	  if [[ ( "${_line:11:8}" != "00:00:00" ) && ( "${_energyjoule}" -ne "${_lastenergyjoule}" ) ]]; then
	  	_dateiso="${_line:6:4}/${_line:3:2}/${_line:0:2} ${_line:11:8}"
	  	_datestr=$(date -d "${_dateiso}" +%s)
	    #echo ${_file} - ${_datestr} - ${_lineel[1]} - ${_energyjoule}
	    echo energyv3,quantity=electricity,type=production,source=sma value=${_energyjoule} ${_datestr}
	  fi
	  _lastenergyjoule=${_energyjoule}
	 done
	done > 20200301_influxdb_fix.txt

	INFLUXDBURI="http://localhost:8086/write?db=smarthomev3&precision=s"
	curl -i -XPOST ${INFLUXDBURI} --data-binary @20200301_influxdb_fix.txt

Read line, split by ;

	IFS=';' read -ra _lineel <<< "${_line}"
Convert kWh to Joule using lua

	_energyjoule=$(lua -e "print(${_lineel[1]} * 1000*3600)")

Only update if not first measurment of day (time = 00:00:00) and new value

	if [[ ( "${_line:11:8}" != "00:00:00" ) && ( "${_energyjoule}" -ne "${_lastenergyjoule}" ) ]]; then
Convert date from

	"24/02/2020 23:55:00"
to 

	"2020/02/24 23:55:00"
using

	${_line:6:4}/${_line:3:2}/${_line:0:2}

then convert to datetime with date
	
	_datestr=$(date -d "${_dateiso}" +%s)

#/usr/bin/env python3.7
#
# Push SBFspot data to influxdb
#
# TODO
# - Insert Spot data into MySQL DB 
# From ➜  sbfspot-tim git:(master) ✗ gdate --date=@1541859248 Sat Nov 10 15:14:08 CET 2018 
# To ➜  sbfspot-tim git:(master) ✗ gdate --date=@1543709362 Sun Dec  2 01:09:22 CET 2018
# 
# 

import argparse
import requests
import sqlite3

# Fields in SQLite databases MonthData and SpotData
MONTHFIELDS = "TimeStamp,Serial,TotalYield,DayYield"
SPOTFIELDS = "TimeStamp,Serial,Pdc1,Pdc2,Idc1,Idc2,Udc1,Udc2,Pac1,Pac2,Pac3,Iac1,Iac2,Iac3,Uac1,Uac2,Uac3,EToday,ETotal,Frequency,OperatingTime,FeedInTime,BT_Signal,Status,GridRelay,Temperature"

def read_sbfspot_cfg(sbfcfg):
	"""
	Read SBFspot configuration file located in sbfcfg, return 
	"""
	# https://stackoverflow.com/a/25493615
	# https://stackoverflow.com/a/28563058
	with open(sbfcfg, 'r') as f:
	    config_string = '[sbf]\n' + f.read().replace('%', '%%')

	import configparser
	sbfconfig = configparser.ConfigParser()
	sbfconfig.read_string(config_string)
	return sbfconfig

def read_sbfspot_db(sbfdb, influxquery, influxhost, influxdb, includezero=False, unit="native", sbfformat='month', dry=False):
	"""
	Read data from SBFspot database
	"""

	# default sbfformat is "month"
	database = "MonthData"
	fields = MONTHFIELDS
	if (sbfformat == "spot"):
		database = "SpotData"
		fields = SPOTFIELDS

	# Build list of keys from fields string for dict building lateron
	fields_keys = fields.split(",")

	# default unit is 'native' which has multiplication factors 1
	conv_factor = [1] * len(fields_keys)
	if (unit == "SI"):
		if (sbfformat == "month"):
			# Find fields TotalYield and DayYield and set conversion factor to 
			# 3600 for Wh to J
			conv_factor[fields_keys.index("TotalYield")] = 3600
			conv_factor[fields_keys.index("DayYield")] = 3600
		elif (sbfformat == "spot"):
			# Find fields EToday and ETotal and set conversion factor to 
			# 3600 for Wh to J
			conv_factor[fields_keys.index("EToday")] = 3600
			conv_factor[fields_keys.index("ETotal")] = 3600

	# Connect and query database
	conn = sqlite3.connect(sbfdb)
	c = conn.cursor()
	
	query = "SELECT {fields} FROM {database} ORDER BY TimeStamp ASC".format(fields=fields, database=database)
	rows = c.execute(query)

	post_data = ""
	lastTotalYield = 0
	for idx, r in enumerate(rows):

		# Store totalyield to check changes since last measurement
		if (sbfformat == "month"):
			thisTotalYield = r[fields_keys.index("TotalYield")]
		elif (sbfformat == "spot"):
			thisTotalYield = r[fields_keys.index("ETotal")]

		# Check if this data row is new
		if (lastTotalYield == thisTotalYield and includezero == False):
			continue

		# Convert rows into dict by adding keys from field names
		dictrow = {key:val*f for key, val, f in zip(fields_keys, r, conv_factor)}
		# Construct line protocol string based on query template
		post_data_line = influxquery.format(**dictrow)
		post_data += post_data_line

		# Post data in chunked way to influxdb as not to overflow. 
		# https://docs.influxdata.com/influxdb/v1.7/tools/api recommends 
		# 5000-10000 points.
		if (idx % 5000 == 0 and idx > 0):
			push_influx_data(post_data, influxhost, influxdb)
			post_data = ""

def push_influx_data(post_data, influxhost, influxdb):
	# Post data to influxdb, check for obvious errors
	req_url = influxhost+"/write?db="+influxdb+"&precision=s"

	try:
		httpresponse = requests.post(req_url, data=post_data, verify=False, timeout=10)
		if (httpresponse.status_code != 204):
			raise Exception("Push to influxdb failed: " + str(httpresponse.status_code) + " - " + str(httpresponse.text))
	except requests.exceptions.Timeout as e:
		raise requests.exceptions.Timeout("Update failed due to timeout. Is influxdb running?")
	except requests.exceptions.ConnectionError:
		raise requests.exceptions.ConnectionError("Update failed due to refused connection. Is influxdb running?")


def test_influxquery(influxquery, sbfformat):
	"""
	Test if query format is OK and fields are correct
	"""
	if sbfformat == 'month':
		fields = MONTHFIELDS
	else:
		fields = SPOTFIELDS

	fields_keys = fields.split(",")
	dictrow = {key:val for key, val in zip(fields_keys, range(len(fields_keys)))}
	try:
		query_test = influxquery.format(**dictrow)
	except KeyError as e:
		print("influxquery {} not valid, please check sbfformat supports requested fields: {}".format(influxquery, e))
		exit()

# Parse commandline arguments
parser = argparse.ArgumentParser(description="SBFspot2influxdb pushes SBFspot \
	data to influxdb")
# group = parser.add_mutually_exclusive_group(required=True)
# group.add_argument("--last", action='store_true',
# 	help="push only last reading to influxdb (useful for cron jobs)")
# group.add_argument("--all", action='store_true',
# 	help="push all data to influxdb (useful for one-time import")
parser.add_argument("--unit", choices=("native", "SI"), default="native",
	help="units to use either native (kWh/kW etc) or SI (Joule/W). \
	Advantage of SI is easier comparison with other meters (e.g. heat).")
parser.add_argument("--includezero", action="store_true",
	help="Also include entries with no change in power/yield. By default \
	only data with changes since previous measurement are included.")

parser.add_argument("--sbfformat", choices=("spot", "month"), default="month",
	help="choose format to read: month or spot format. Month format supports \
	{} Spot format supports {}".format(MONTHFIELDS, SPOTFIELDS))
parser.add_argument('--sbfcfg', type=str, metavar="SBFspot.cfg", default=None,
	help='SBFspot configuration file')
parser.add_argument('--sbfdb', type=str, metavar="path", default=None, 
	required=True, help='SBFspot SQLite database file to read from')

parser.add_argument('--influxdb', type=str, metavar=("URI", "db"),
	default=("http://localhost:8086", "smarthome"),
	nargs=2, help="URI should point to influxdb, e.g. \
	[http/https]://<ip>:<port>. Database: e.g. smarthome.")
parser.add_argument('--influxquery', type=str, metavar="query",
	default="energy,device=sma energy={TotalYield} {TimeStamp}",
	help='query string template to push data to influxdb, you \
	can use the variables determined by the --sbfformat setting. Example: \
	"energy,device=sma energy={TotalYield} {TimeStamp}')

args = parser.parse_args()

#sbfconfig = read_sbfspot_cfg(args.sbfcfg)
test_influxquery(args.influxquery, args.sbfformat)

# Add newline for influxdb, difficult to enter via command line
args.influxquery += "\n"
sbfdata = read_sbfspot_db(args.sbfdb, args.influxquery, args.influxdb[0], args.influxdb[1], includezero=args.includezero, unit=args.unit, sbfformat=args.sbfformat)

# CFGOUTPUTPATH=$(grep ^OutputPath= ${SBFCFG} | tail -n1 | cut -f2- -d= | tr -d '\n\r')
# CFGPLANTNAME=$(grep ^Plantname= ${SBFCFG} | tail -n1 | cut -f2- -d= | tr -d '\n\r')
# CFGCSV_Export=$(grep ^CSV_Export= ${SBFCFG} | tail -n1 | cut -f2- -d= | tr -d '\n\r')

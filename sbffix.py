#/usr/bin/env python3.7
#
# Fix gap in SBFspot nosql database SpotData table from CSV files
#
# Manually, concatenate csv files to one (using zsh for range expansion)
#for f in MySolarPV-Spot-20181<110->.csv; do
#	tail -n +6 $f >> sbffix.csv
#done

# We have: dd/MM/yyyy HH:mm:ss;DeviceName;DeviceType;Serial;Pdc1;Pdc2;Idc1;Idc2;Udc1;Udc2;Pac1;Pac2;Pac3;Iac1;Iac2;Iac3;Uac1;Uac2;Uac3;PdcTot;PacTot;Efficiency;EToday;ETotal;Frequency;OperatingTime;FeedInTime;BT_Signal;Condition;GridRelay;Temperature
# We need: TimeStamp								,Serial,Pdc1,Pdc2,Idc1,Idc2,Udc1,Udc2,Pac1,Pac2,Pac3,Iac1,Iac2,Iac3,Uac1,Uac2,Uac3,							EToday,ETotal,Frequency,OperatingTime,FeedInTime,BT_Signal,Status,	GridRelay,Temperature
# We drop: 
import sqlite3
import datetime as dt

csvfile="sbffix.csv"
dbfile="SBFspot-fix.db"
csvfields="dd/MM/yyyy HH:mm:ss;DeviceName;DeviceType;Serial;Pdc1;Pdc2;Idc1;Idc2;Udc1;Udc2;Pac1;Pac2;Pac3;Iac1;Iac2;Iac3;Uac1;Uac2;Uac3;PdcTot;PacTot;Efficiency;EToday;ETotal;Frequency;OperatingTime;FeedInTime;BT_Signal;Condition;GridRelay;Temperature".split(";")
dbfields="Timestamp,Serial,Pdc1,Pdc2,Idc1,Idc2,Udc1,Udc2,Pac1,Pac2,Pac3,Iac1,Iac2,Iac3,Uac1,Uac2,Uac3,EToday,ETotal,Frequency,OperatingTime,FeedInTime,BT_Signal,Status,GridRelay,Temperature".split(",")

conn = sqlite3.connect(dbfile)
c = conn.cursor()

with open(csvfile, 'r') as fd:
	for idx, row in enumerate(fd):
		rows = row.strip().split(";")
		# For pop debugging:
		# for el, key in zip(rows, csvfields):
		# 	print(key, el)

		# Pop fields that csv file has but DB has not
		rows.pop(csvfields.index("Efficiency"))
		rows.pop(csvfields.index("PacTot"))
		rows.pop(csvfields.index("PdcTot"))
		rows.pop(csvfields.index("DeviceType"))
		rows.pop(csvfields.index("DeviceName"))

		# CSV stored is kWh, we need Wh (Power is in W in both formats)
		rows[dbfields.index("ETotal")] = int(float(rows[dbfields.index("ETotal")])*1000)
		rows[dbfields.index("EToday")] = int(float(rows[dbfields.index("EToday")])*1000)

		# For pop debugging:
		# for el, key in zip(rows, dbfields):
		# 	print(key, el)

		# Fix timestamp by converting to datetime object
		rows[0] = dt.datetime.strptime(rows[0], "%d/%m/%Y %H:%M:%S").timestamp()

		# Insert this row into nosql, but only after a certain time
		if (rows[0] <= 1541859248):
			continue
		print( rows[0])
		c.execute('INSERT INTO SpotData VALUES (?'+',?'*(len(rows)-1)+')', rows)

# Save (commit) the changes
conn.commit()

# We can also close the connection if we are done with it.
# Just be sure any changes have been committed or they will be lost.
conn.close()

exit()

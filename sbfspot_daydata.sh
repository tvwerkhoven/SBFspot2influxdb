#!/usr/bin/env bash
#
# Wrap sbfspot to catch and repair some errors
# 
# 1. Run sbfspot
# 2a. If OK: happy & continue
# 2b. If not OK, reset bluetooth, wait for 5min, then continue
#
# Implemented as:
# 1. Check if pidfile exists
# 2a. If older than 5min: kill process (if still running), delete and continue
# 2b. else: warn & quit
# 3. Run SBFspot
# 4a. If OK: delete pidfile
# 4b. If NOK: warn, reset bluetooth & keep pidfile
#
# Do not store pid (via --use-pid) as this will break the 5-min wait mechanism 
# because the lock file is invalid if the PID process is gone.


SCRIPTNAME=$(basename "$0")
# Run only if no others run
# https://stackoverflow.com/questions/1715137/what-is-the-best-way-to-ensure-only-one-instance-of-a-bash-script-is-running
# Using PID can be confusing if testing from shell scripts
# https://stackoverflow.com/questions/20089797/lockfile-create-does-not-work-in-bash-script
PIDFILE=/var/lock/sbfspot.pid
# lockfile-check --use-pid --lock-name ${PIDFILE}
# if [[ $? -eq 0 ]]; then
if lockfile-check --lock-name ${PIDFILE}; then
	/usr/bin/logger -t "${SCRIPTNAME}" -p user.warning "Lockfile ${PIDFILE} already exists, quitting"
	exit
fi

if ! lockfile-create --retry 0 --lock-name ${PIDFILE}; then
	/usr/bin/logger -t "${SCRIPTNAME}" -p user.warning "Could not create lock on ${PIDFILE}, quitting"
	exit
fi

# -ad0: no daily data -am0/ae0: no month/event history -q: quiet
# stop process after 35s/kill after 45s to prevent run-away stuff
RET=$(timeout --kill-after 45 35 /usr/local/bin/sbfspot.3/SBFspot -ad0 -am0 -ae0  2>&1)
STATUS=$?
# Return codes
# 250 for CRITICAL: Failed to initialize communication with inverter --> try again in 1min
# 255 for CRITICAL: bthConnect() returned -1
if [[ ${STATUS} -eq 255 ]]; then
	/usr/bin/logger -t "${SCRIPTNAME}" -p user.err "Error: ${STATUS} ${RET}"
	# Allow non-root to run hciconfig
	# sudo setcap 'cap_net_raw,cap_net_admin+eip' /usr/bin/hciconfig
	# Source: https://unix.stackexchange.com/questions/96106/bluetooth-le-scan-as-non-root
	# Source: https://stackoverflow.com/questions/413807/is-there-a-way-for-non-root-processes-to-bind-to-privileged-ports-on-linux
	# 
	# To remove again:
	# https://unix.stackexchange.com/questions/303423/unset-setcap-additional-capabilities-on-excutable

	# Restart bluetooth in case of failure, we get CRITICAL: bthConnect() returned -1
	# regularly and this seems to fix it (no idea why)
	/usr/bin/logger -t "${SCRIPTNAME}" -p user.err "SBFspot failed, resetting bluetooth and quitting so we pause for 5min"
	hciconfig hci0 reset
	# Also restart bluetooth service
	# (Ensure to allow user to restart service - https://unix.stackexchange.com/questions/192706/)
	/usr/bin/systemctl restart bluetooth.service
	exit
	/usr/bin/logger -t "${SCRIPTNAME}" -p user.err "SBFspot connection failed, will retry next run."
elif [[ ${STATUS} -ne 0 ]]; then
	# Other less fatal error occured: report, clean up, and try again later
	/usr/bin/logger -t "${SCRIPTNAME}" -p user.err "Error: ${STATUS} ${RET}"
else
	# Everything OK, push to influxdb if we have data
	/home/tim/workers/SBFspot2influxdb/SBFspot2influxdb.sh
fi


if ! lockfile-remove --lock-name ${PIDFILE}; then
	/usr/bin/logger -t "${SCRIPTNAME}" -p user.warning "Could not remove lock on ${PIDFILE}, quitting"
	exit
fi


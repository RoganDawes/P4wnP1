#!/bin/bash

# this script tries to fingerprint the target OS by analyzing DNS requests and
# filtering for domains which are used by OS specific conectivity tests
#	www.msftncsi.com 		= Win 7
#	www.msftconnecttest.com 	= Win 10
#	...
#
# The DNS requests are grabed from a Logfile of Responder (acting as DNS spoofer)
# on every change (Logfile change monitored with inotifywait)
#
# This method gives only a rough idea on the target OS (no distinguishing between 
# architectures, no build version etc.) but should be enough to know how to keyboard
# interact with the target (e.g. which key combinations have to be used to unlock or
# start something)
#
# Needs /bin/bash as builtin $SECONDS is used to check for timeout


# After $timeout seconds are reached without capturing a DNS request, target OS is considered unknown
timeout=30

target_os="undetected"
while [ "$target_os" == "undetected" ]; do
	remaining=$(($timeout - $SECONDS))
	#echo "remain: $remaining"

	# set target_os to unknown if timeout reached
	if [ $remaining -le 0 ]; then
		# timeout reached
		echo "OS detection timeout reached, OS unkown" 1>&2
		target_os="UNKNOWN"
		break
	fi

	# check for request to www.msftncsi.com
	grep -q "www.msftncsi.com" /tmp/Poisoners-Session.log
	if [ $? -eq 0 ]; then
		target_os="WIN7"
		break
	fi

	# check for request to www.msftncsi.com
	grep -q "www.msftconnecttest.com" /tmp/Poisoners-Session.log
	if [ $? -eq 0 ]; then
		target_os="WIN10"
		break
	fi

	# wait till log file has been modified again (max timeout)
	inotifywait -qq -t $remaining -e modify /tmp/Poisoners-Session.log
done

echo "$target_os"

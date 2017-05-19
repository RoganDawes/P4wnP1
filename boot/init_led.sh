#!/bin/sh
#
# Start LED controller script and provide funtion to set blink count

# ====================
# LED init
# ====================

# start LED control in background
python $wdir/ledtool/ledtool.py&

ledtrigger="/tmp/blink_count"
# led blink function
function led_blink()
{
	if [ "$1" ] 
	then
		echo "$1" > $ledtrigger
	fi
}

# disable LED for now
led_blink 0

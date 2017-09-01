#!/bin/sh
#
# Start LED controller script and provide funtion to set blink count

# ====================
# LED init
# ====================

# create control file and change owner (otherwise it would be created by ledtool.py
# with owner root, and thus not writable by user pi)
ledtrigger="/tmp/blink_count"
echo 255 > $ledtrigger
chown pi:pi $ledtrigger

# start LED control in background
python $wdir/ledtool/ledtool.py&

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

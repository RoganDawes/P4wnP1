#!/bin/sh


#    This file is part of P4wnP1.
#
#    Copyright (c) 2017, Marcus Mengs. 
#
#    P4wnP1 is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    P4wnP1 is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with P4wnP1.  If not, see <http://www.gnu.org/licenses/>.


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

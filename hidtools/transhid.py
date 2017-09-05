#!/usr/bin/python


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


# Transform raw input to match output for the HID report descriptor in use
# Author: MaMe82 aka.  Marcus Mengs

import sys
import time


data = sys.stdin.read()
with open("/dev/hidg0","wb") as f:
	for i in range(0, len(data), 2):
		out = ""
		key = ord(data[i:i+1])
		if len(data[i+1:i+2]) == 0:
			continue
		mod = ord(data[i+1:i+2])
		if (key == 0):
			# delay code
			d = float(mod)/1000.0
			time.sleep(d)
		out = chr(mod) + '\x00' + chr(key) + '\x00\x00\x00\x00\x00' + '\x00\x00\x00\x00\x00\x00\x00\x00'
		f.write(out)
		f.flush()
		# no delay between keypresses (hanfled by HID gadget)
		#time.sleep(0.01)

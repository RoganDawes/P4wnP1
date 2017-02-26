#!/usr/bin/python

# Transform raw input to match output for the HID report descriptor in use
# AUthor: MaMe82 aka.  Marcus Mengs

import sys
import time


data = sys.stdin.read()
with open("/dev/hidg0","wb") as f:
	for i in range(0, len(data), 2):
		out = ""
		key = ord(data[i:i+1])
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

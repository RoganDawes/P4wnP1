#!/usr/bin/python

# Transform raw input to match output for the HID report descriptor in use
# AUthor: MaMe82 aka.  Marcus Mengs

import sys
import time

data = sys.stdin.read()
for i in range(0, len(data), 2):
	out = ""
	key = ord(data[i:i+1])
	mod = ord(data[i+1:i+2])
	if (key == "\x00"):
		# delay code
		sleep(float(ord(mod))/1000.0)
	out = chr(mod) + '\x00' + chr(key) + '\x00\x00\x00\x00\x00' + '\x00\x00\x00\x00\x00\x00\x00\x00'
	sys.stdout.write(out)

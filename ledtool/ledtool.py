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

import os
import pwd
import grp
import time

filepath = "/tmp/blink_count"
uid="pi"
gid="pi"
ledpath = "/sys/class/leds/led0/"
DELAY_PAUSE = 0.5
DELAY_BLINK = 0.2

def prepare():
	# create control file if necessary
	if not os.path.exists(filepath):
		f = file(filepath, "w")
		f.write("255") # continous lit
		f.close()

		# fix ownership
		os.chown(filepath, pwd.getpwnam(uid).pw_uid, grp.getgrnam(gid).gr_gid)

	# setup manual led control
	with open(ledpath + "trigger", "w") as trigger:
		trigger.write("none")
		
	# disable LED
	with open(ledpath + "brightness", "w") as brightness:
		brightness.write("1")


def blink(count, delay_off, delay_on):
	with open(ledpath + "brightness", "w") as brightness:
		# if count is 255, LED should be turned on continuosly
		if count >= 255:
			brightness.write("0")
			brightness.seek(0)
		elif count == 0:
			brightness.write("1")
			brightness.seek(0)
		else:
			for i in range(count):
				brightness.write("0")
				brightness.seek(0)
				time.sleep(delay_on)
				brightness.write("1")
				brightness.seek(0)
				time.sleep(delay_off)


	

prepare()

with open(filepath, "r") as f:
	while True:
		value = f.read().split("\n")[0] # we read the whole file to prevent caching and split the needed value
		f.seek(0)
		count = 0
		try:
			count = int(value)
		except ValueError:
			count = 255 # failover if integer conversion not possible			

		#print "File contains {0}".format(count)
		#print repr(value)
		
		blink(count, DELAY_BLINK, DELAY_BLINK)
		time.sleep(DELAY_PAUSE)

		

#!/usr/bin/python
import os
import time

filepath = "/tmp/blink_count"
ledpath = "/sys/class/leds/led0/"
DELAY_PAUSE = 0.5
DELAY_BLINK = 0.2

def prepare():
	# create control file if necessary
	if not os.path.exists(filepath):
		f = file(filepath, "w")
		f.write("255") # continous lit
		f.close()
		print "LED control file created"
	else:
		print "LED control file exists"

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

		

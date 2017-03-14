#!/usr/bin/python
from datetime import datetime
import sys

DEBUG=False

class WatchHIDLed:
	LED={"NUMLOCK": 1, "CAPSLOCK": 2, "SCROLLLOCK": 4}
	KEY_NUMLOCK = 0
	KEY_CAPSLOCK = 1
	KEY_SCROLLLOCK = 2
	KEYS = {"NUMLOCK": KEY_NUMLOCK, "CAPSLOCK": KEY_CAPSLOCK, "SCROLLLOCK": KEY_SCROLLLOCK}

	def __init__(self, timeout=800):
		self.timeout=timeout # timeout in milliseconds to decide if count has to be increased on LED state change
		self.state=[2, 2, 2] # [NUM, CAPS, SCROLL] 0 = LED off, 1 = LED on, 2 = not initialized
		self.laststate=[2, 2, 2] # [NUM, CAPS, SCROLL] 0 = LED off, 1 = LED on, 2 = not initialized
		self.last_change=[0, 0, 0] # [NUM, CAPS, SCROLL] milliseconds passed since last state change
		self.count_change=[0, 0, 0] # [NUM, CAPS, SCROLL] count of state changes, gets reset after timeout 
		self.triggers=[]
		self.timesaved = None


	def statechange(self, ledbyte):
		LED = WatchHIDLed.LED
		KEYS = WatchHIDLed.KEYS

		# calculate delay in ms since last call (last LED state change)
		if (self.timesaved == None):
			self.timesaved = datetime.now()
			delayms=0		
		else:	
			lasttime = self.timesaved
			self.timesaved = datetime.now()
			delayms = int((self.timesaved - lasttime).total_seconds() * 1000)

		# process LED state

		# check if last_state has been initialized
		if self.laststate[0] == 2:
			# no, use current state
			self.laststate = [(ledbyte & LED["NUMLOCK"]) / LED["NUMLOCK"], (ledbyte & LED["CAPSLOCK"]) / LED["CAPSLOCK"], (ledbyte & LED["SCROLLLOCK"]) / LED["SCROLLLOCK"]]
			self.state = self.laststate
		else:
			# yes, backup current state
			self.laststate = self.state
			self.state = [(ledbyte & LED["NUMLOCK"]) / LED["NUMLOCK"], (ledbyte & LED["CAPSLOCK"]) / LED["CAPSLOCK"], (ledbyte & LED["SCROLLLOCK"]) / LED["SCROLLLOCK"]]

		# check if state change
		statechange = [self.state[i] ^ self.laststate[i] for i in range(len(self.state))]



		# set state changed timers
		for i in range(len(statechange)):
			# LED state unchanged, increase timer
			self.last_change[i] += delayms

			# state changed
			if statechange[i] == 1:
				# check if timer was smaller than timeout
				if self.last_change[i] < self.timeout:
					# raise state change counter
					self.count_change[i] += 1
				else:
					# reset state change counter to 0 (restart)
					self.count_change[i] = 0
				# reset change timer
				self.last_change[i] = 0

		if DEBUG:
			print "Delay since last global state change"
			print delayms
			print "Current LED state"
			print self.state
			print "Last LED state"
			print self.laststate
			print "LED state changed since last event"
			print statechange
			print "LED state change timer (reset after state change)"
			print self.last_change
			print "LED state change counter (increased if state change before timeout)"
			print self.count_change
			print "======================================"

		# check if triggers have hit
		for trigger in self.triggers:
			keyname = trigger[0]
			hitcount = trigger[1]
			exitcode = trigger[2]
			key_pos = KEYS[keyname]
			if self.count_change[key_pos] >= hitcount:
				# trigger has fired, so reset count
				self.count_change[key_pos] = 0
				if DEBUG:
					print "Trigger fired " + keyname + " pressed more than " + str(hitcount) + " times in short sequence, exitting with exit code " + str(exitcode)
				sys.exit(exitcode)

	# trigger: 
	#	key		Which key should trigger (NUM LOCK, CAPS LOCK, SCROLL LOCK)
	#	press_count	How often has the key to be pressed until the trigger fires
	#			The delay betwenn keypresses has to be smaller than global timeout
	#			which is set on creation of a class instance (default 800 ms)
	#	exit_code	If the key triggers, the script exits with the given exit code
	#			This could be used to distinguish between triggers, if multiple
	#			triggers are added (only the first hit is regarded, as the script exits
	#			if the trigger fires).
	def add_trigger(self, key, press_count, exit_code):
		KEYS = WatchHIDLed.KEYS

		if key in KEYS:
			trigger = [key, press_count, exit_code]
			self.triggers.append(trigger)
		else:
			print "Unknown key " + key

	def use_default_triggers(self):
		if len(self.triggers) == 0:
			# trigger after 5 changes to one of the LED driving keys
			# use different EXIT CODE for every key
			self.add_trigger("CAPSLOCK", 5, 1)
			self.add_trigger("NUMLOCK", 5, 2)
			self.add_trigger("SCROLLLOCK", 5, 3)

		

	def start_LED_monitoring(self):
		with open("/dev/hidg0","rb") as f:
			while True:
				data = f.read(1)
				self.statechange(ord(data))

	def send_receive_check(self, attempts = 5, testkey = "NUMLOCK"):
		#KEYS = {"NUMLOCK": 0x83, "CAPSLOCK": 0x82, "SCROLLLOCK": 0x84}
		KEYS = {"NUMLOCK": 0x53, "CAPSLOCK": 0x39, "SCROLLLOCK": 0x47}
		if not testkey in KEYS:
			return

		# return exitcode 0 after attempts time changing the LED state for the key given by 
		# testkey
		self.add_trigger(testkey, attempts, 0)

		with open("/dev/hidg0","r+b") as f:
			while True:
				for i in range(attempts):
					# send_key
					out = '\x00\x00' + chr(KEYS[testkey]) + '\x00\x00\x00\x00\x00' + '\x00\x00\x00\x00\x00\x00\x00\x00'
					f.write(out)
					f.flush()					
					# check LED
					data = f.read(1)
					self.statechange(ord(data))
		

	@staticmethod
	def check_HID_availability():
		t = WatchHIDLed()
		t.send_receive_check()
		

	@staticmethod
	def createDefaultTrigger():
		t = WatchHIDLed()
		t.use_default_triggers()
		t.start_LED_monitoring()



# main
if __name__ == "__main__":
	# only simplified error checking for parameter count
	# we assure correct usage on calling
	# exiting with different error codes on success is part of the core mechanism
	# of this script, so it can't be used on exit
	# we return with error code 255 if something went wrong, this has to be handled by the caller
		
	argc = len(sys.argv[1:])
	if argc < 1:
		sys.exit(255)

	method = sys.argv[1]
	

	
	if method == "check":
		# check if HID keyboard is working by triggering LED
		if argc == 1:
			# no trigger detail given, use default 
			# NUMLOCK is pressed until 5 LED state changes have been seen
			WatchHIDLed.check_HID_availability()
		else:
			pass
	elif method == "trigger":
		# block execution till trigger occurs (trigger key, count of keypresses, exitcode)
		if argc == 1:
			# no trigger detail given, use default (5 presses of NUMLOCK, CAPSLOCK or SCROLLLOCK)
			# exitcode 1 = CAPSLOCK, 2 = NUMLOCK, 3 = SCROLLLOCK pressed 5 times
			WatchHIDLed.createDefaultTrigger()
		else:
			# check of enough arguments for trigger definition
			pass
	else:
		sys.exit(255)

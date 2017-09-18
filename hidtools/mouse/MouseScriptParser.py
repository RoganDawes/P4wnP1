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

from hid_mouse import hid_mouse
import time
import sys

class MouseScriptParser:
	def __init__(self):
		# stores valid commands + minimum argument count
		self.valid_commands = {"BUTTONS": 3, "MOVE": 2, "MOVESTEPS": 3, "MOVESTEPPED": 2, "MOVETO": 2, "DELAY": 1, "CLICK": 3, "DOUBLECLICK": 3, "UPDATEDELAYED": 1, "REPEAT": 1, "UPDATE": 0}
		devfile = ""
		try:
			with open("/tmp/device_hid_mouse", "rb") as f:
				devfile = f.readline().replace("\n", "")
		except IOError:
			print "/tmp/device_hid_mouse missing, mouse seems to be disabled!"
			sys.exit()
		self.mouse = hid_mouse(False, devfile)

	def extract_command(self, line):
		# try to split into command + args

#		print "line: " + line
		line = line.strip() # remove trailing and leading spaces
		line = line.replace("\t", " ") # replace tabs by single space
		first_word = line.split(" ", 1)[0]
		if first_word.upper() in self.valid_commands:
			# remove linebreaks
			line = line.replace("\r\n","").replace("\n","")
			# remove comments
			line = line.split("#")[0]
			line = line.split("//")[0]
			# trim down spaces
			line = line.strip()

			# split command from args
			argv = []
			parts = line.split(" ")

#			print "Parts {0}".format(parts)

			# store command uppercase
			cmd = parts[0].strip().upper()
			# if command includes args, trim down each arg (avoid interpreting multi-space as arguments)
			for part in parts[1:]:
				part = part.strip()
				if len(part) > 0:
					argv.append(part)

			return cmd, argv
		else:
			return None


	def dispatch_command(self, cmd, argv):
		method_name =  "DO_" + cmd
		try:
			method = getattr(self, method_name)
		except AttributeError:
			print "Error: Missing implementation for {0}, commans '{1}' ignored".format(method_name, cmd)
			return
		method(argv)


	def DO_BUTTONS(self, argv):
		#print "BUTTONS method {0}".format(argv)
		if len(argv) < 3:
			#print "BUTTON command takes 3 values"
			return

		if argv[0] == "0":
			self.mouse.button1 = False
		else:
			self.mouse.button1 = True

		if argv[1] == "0":
			self.mouse.button2 = False
		else:
			self.mouse.button2 = True

		if argv[2] == "0":
			self.mouse.button3 = False
		else:
			self.mouse.button3 = True

		self._sendMouseReport()

	def _sendMouseReport(self):
		self.mouse.fire_report()
			
	def DO_MOVE(self, argv):
		# ToDo: Command could be extended to support 3rd relative axis for mousewheel (implementation in hid_mouse.py + change of HID descriptor)
		#print "MOVE method {0}".format(argv)
		x = int(float(argv[0])) # be sure to convert float to int
		x = min(127, max(-127, x))
		y = int(float(argv[1])) # be sure to convert float to int
		y = min(127, max(-127, y))

		self.mouse.x_rel = x
		self.mouse.y_rel = y
		
		self._sendMouseReport()
		
		# reset relative position, to avoid sending it again when a report for button press is generated
		self.mouse.x_rel = 0
		self.mouse.y_rel = 0
		
	def DO_MOVESTEPPED(self, argv):
		x = int(float(argv[0])) # be sure to convert float to int
		y = int(float(argv[1])) # be sure to convert float to int
		steps = max(abs(x), abs(y))
		
		argv.append(str(steps))
		self.DO_MOVESTEPS(argv)
		
	def DO_MOVESTEPS(self, argv):
		# ToDo: Command could be extended to support 3rd relative axis for mousewheel (implementation in hid_mouse.py + change of HID descriptor)
		#print "MOVESTEPS method {0}".format(argv)
		x = int(float(argv[0])) # be sure to convert float to int
		#x = min(127, max(-127, x))
		y = int(float(argv[1])) # be sure to convert float to int
		#y = min(127, max(-127, y))

		steps = int(float(argv[2]))
		if steps < 1:
			steps = 1

		dx = float(x) / float(steps)
		dy = float(y) / float(steps)
		
		cur_x = 0
		cur_y = 0
		
		for cur_step in range(1, steps+1):
			desired_x = int(round(dx * cur_step))
			desired_y = int(round(dy * cur_step))
			step_x = desired_x - cur_x
			step_y = desired_y - cur_y
			self.mouse.x_rel = step_x
			self.mouse.y_rel = step_y
			self._sendMouseReport()
			cur_x += step_x
			cur_y += step_y
		
		# reset relative position, to avoid sending it again when a report for button press is generated
		self.mouse.x_rel = 0
		self.mouse.y_rel = 0

	def DO_MOVETO(self, argv):
		#print "MOVETO method {0}".format(argv)
		x = float(argv[0])
		y = float(argv[1])

		self.mouse.x_abs = x
		self.mouse.y_abs = y
		
		self._sendMouseReport()

	def DO_DELAY(self, argv):
		#print "DELAY method {0}".format(argv)
		time.sleep(float(argv[0]) / 1000.0)

	def DO_UPDATE(self, argv):
		#print "UPDATE method {0}".format(argv)
		self._sendMouseReport()

	def DO_CLICK(self, argv):
		#print "CLICK method {0}".format(argv)
		# clear button state
		self.DO_BUTTONS(['0', '0', '0']) # more correct: only button which have to be clicked should be released here
		#self._sendMouseReport()
		# press buttons
		self.DO_BUTTONS(argv)
		#self._sendMouseReport()

		# NOTE: Seems there's no delay needed between pressing and releasing, otherwise it has to be placed here

		# releas buttons again
		self.DO_BUTTONS(['0', '0', '0']) # more correct: only button which have been clicked should be released here
		#self._sendMouseReport()


	def DO_DOUBLECLICK(self, argv):
		#print "DOUBLECLICK method {0}".format(argv)
		self.DO_CLICK(argv)
		# NOTE: Seems there's no delay needed between two CLICKS, otherwise it has to be placed here
		self.DO_CLICK(argv)


	def DO_UPDATEDELAYED(self, argv):
		#print "UPDATEDELAYED method {0}".format(argv)
		self.DO_UPDATE(argv)
		self.DO_DELAY(argv)
		
	def executeScript(self, script):
		if len(script) > 0:
			commands = []
			for l in script:
				extracted = self.extract_command(l)
				if extracted:
					commands.append(extracted)

			for command in commands:
				cmd, argv = command
				self.dispatch_command(cmd, argv)		

def main(args):
	p = MouseScriptParser()

	source = []
	for line in sys.stdin:
		source.append(line)

	p.executeScript(source)


if __name__ == "__main__":
        main(sys.argv[1:])


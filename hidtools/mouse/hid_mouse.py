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

import struct
import sys

class hid_mouse(object)	:
	def __init__(self, absolute=False, outfile="/dev/hidg2"):
		self.button1 = False
		self.button2 = False
		self.button3 = False
		self._x_abs = 0.0
		self._y_abs = 0.0
		self.outf = outfile
		self._abs = absolute
		self.bleft = 0
		self.bright = 32767
		self.btop = 0
		self.bbottom = 32767
		self._x_abs_short = self.bleft
		self._y_abs_short = self.btop
		self._x_rel = 0
		self._y_rel = 0

	@property
	def x_rel(self):
		return self._x_rel

	@x_rel.setter
	def x_rel(self, value):
		# in case the last coordinate change was relative, we disable absolute mode
		self._abs = False

		self._x_rel = value

	@property
	def y_rel(self):
		return self._y_rel

	@y_rel.setter
	def y_rel(self, value):
		# in case the last coordinate change was relative, we disable absolute mode
		self._abs = False

		self._y_rel = value

	@property
	def x_abs(self):
		return self._x_abs

	@x_abs.setter
	def x_abs(self, value):
		# in case the last coordinate change was absolute, we enable absolute mode
		self._abs = True

		self._x_abs = self.clamp_float(value)
		self._x_abs_short = self.scaled_short(self._x_abs, self.bleft, self.bright)

	@property
	def y_abs(self):
		return self._y_abs

	@y_abs.setter
	def y_abs(self, value):
		# in case the last coordinate change was absolute, we enable absolute mode
		self._abs = True

		self._y_abs = self.clamp_float(value)
		self._y_abs_short = self.scaled_short(self._y_abs, self.btop, self.bbottom)

	def clamp_float(self, val):
		return min(max(0.0, val), 1.0)

	def scaled_short(self, val, lower, upper):
		#print "val {0}".format(val)
		lower = min(max(-32768, lower), 32767)
		upper = min(max(-32768, upper), 32767)
		val = self.clamp_float(val)

		dim = upper - lower

		#print "dim {0}".format(dim)
		scaled = int(lower + val*dim)
		#print "clamped val {0} scaled {1}".format(val, scaled)
		return scaled

	def gen_out_report_abs(self):
		#xout = hid_mouse.convert_pos_short(self._x_abs)
		xout = struct.pack("<h", int(self._x_abs_short)) # signed short, little endian

		#yout = hid_mouse.convert_pos_short(self._y_abs)
		yout = struct.pack("<h", int(self._y_abs_short)) # signed short, little endian

		btnout = hid_mouse.convert_btn_byte(self.button1, self.button2, self.button3)
		return "\x02" + btnout + xout + yout

	def gen_out_report_rel(self):
		#xout = hid_mouse.convert_pos_short(self._x_abs)
		xout = struct.pack("<b", int(self._x_rel)) # signed short, little endian

		#yout = hid_mouse.convert_pos_short(self._y_abs)
		yout = struct.pack("<b", int(self._y_rel)) # signed short, little endian

		btnout = hid_mouse.convert_btn_byte(self.button1, self.button2, self.button3)
		return "\x01" + btnout + xout + yout + "\x00\x00"

	def fire_report(self):
		with open(self.outf, "wb") as f:
			if self._abs:
				#print "absolute x: {0} ({1})\ty: {2} ({3})".format(self._x_abs, self._x_abs_short, self._y_abs, self._y_abs_short)
				f.write(self.gen_out_report_abs())
			else:
				#print "relative x: {0} \ty: {1}".format(self.x_rel, self.y_rel)
				f.write(self.gen_out_report_rel())
			f.flush()


	@staticmethod
	def convert_btn_byte(btn1=False, btn2=False, btn3=False):
		res = 0x00
		if btn1:
			res += 0x01
		if btn2:
			res += 0x02
		if btn3:
			res += 0x04

		return struct.pack("<B", res)

	@staticmethod
	def convert_pos_short(val):
		# clamp val
		valf = max(min(val, 1.0), 0.0)

		valx = valf * 0x7FFF # scale to 0x7FFF
#		valx = valf * 10000 + 1 # scale from 0x0001 to 0x7FFF
		res = struct.pack("<h", int(valx)) # signed short, little endian
		return res

	@staticmethod
	def convert_pos_short(val):
		# clamp val
		valf = max(min(val, 1.0), 0.0)

		valx = valf * 0x7FFE + 1 # scale from 0x0001 to 0x7FFF
#		valx = valf * 10000 + 1 # scale from 0x0001 to 0x7FFF
		res = struct.pack("<h", int(valx)) # signed short, little endian
		return res

	@staticmethod
	def bytes2hexstr(bytes):
		return "\\x"+"\\x".join("{:02x}".format(ord(c)) for c in bytes)

	@staticmethod
	def convert_pos_str(val):
		res = hid_mouse.convert_pos_short(val)
		res_str = hid_mouse.bytes2hexstr(res)
		return res_str



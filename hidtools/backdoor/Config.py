
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


class Config:
	def __init__(self, configfile):
		self.conf = Config.conf_to_dict(configfile)

	@staticmethod
	def conf_to_dict(filename):
		result_dict={}
		lines=[]
		with open(filename,"r") as f:
			lines= f.readlines()
		for l in lines:
			# remove comment from line
			l=l.split("#")[0]
			# remove line breaks
			l=l.strip().replace("\r\n","").replace("\n","")

			# skip empty lines
			if len(l) == 0:
				continue

			splitted = l.split("=", 1)
			key = splitted[0].strip()
			val = splitted[1].strip()
			result_dict[key]=val

		return result_dict


#test = Config("config.txt")
#for item in  test:
#	print item

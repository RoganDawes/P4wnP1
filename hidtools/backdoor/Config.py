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

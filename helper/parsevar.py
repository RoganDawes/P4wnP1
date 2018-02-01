#!/usr/bin/python3
import re, ast
import os
import sys

file="/home/pi/P4wnP1/defaults.conf"
#file="/tmp/vars.sh"

def parsevars(filename):
	re_bashvars = re.compile(r"^\s*[a-zA-Z_][0-9a-zA-Z_]*=\S.*", re.M)
	re_varname = re.compile(r"^\s*([a-zA-Z_][0-9a-zA-Z_]*)=\S.*")
	re_varvalue = re.compile(r"^\s*[a-zA-Z_][0-9a-zA-Z_]*=(\S.*)")
	re_delcomments = re.compile(r"\s*#.*")
	re_delmarks = re.compile(r"(^['\"])(.*)(['\"]\s*$)")
	

	ret={}

	with open(filename, "r") as f:
		res = re_bashvars.findall(f.read())
		for m in res:
			#print("\npure")
			print(m)
			
			name=re_varname.match(m).group(1) # extract variable name
			val=re_varvalue.match(m).group(1) # extract value
			val=re_delcomments.sub("", val) # delete comments and leading whitespaces to comments
			
			# if the remaining value is a string (starts with " or ') we evaluate it (in a safe way)
			if (val[0] == '"') or (val[0] == "'"):
				val=ast.literal_eval(val) # remove comments and unescape string, where needed
			
			#print("parsed")
			#print(name)
			#print(val)
		
			ret[name]=val
	return ret
	
def writeoption(name, value):
	# set correct umask
	oldmask = os.umask(0o000) #rwxrwxrwx
	with open("/dev/shm/"+name, "w") as f:
		f.write(value)
	os.umask(oldmask)

def populate_options_from_file(file):
	vars=parsevars(file)
	for name,val in vars.items():
		# print("Setting name '{0}' to '{1}'".format(name, val))
		writeoption(name, val)

if __name__ == "__main__":
	if len(sys.argv) < 2:
		print("Too few arguments for parsevar.py")
	else:
		populate_options_from_file(sys.argv[1])
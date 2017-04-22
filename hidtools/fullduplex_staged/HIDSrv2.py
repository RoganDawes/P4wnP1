#!/usr/bin/python
from LinkLayer import LinkLayer
import time
import struct

STREAM_TYPE_STAGE2_REQUEST = 1
STREAM_TYPE_STAGE2_RESPONSE = 1
STREAM_TYPE_ECHO_REQUEST = 2
STREAM_TYPE_ECHO_RESPONSE = 2


def handle_stage2_request(LinkLayer):
	print "Stage2 request received"	
	stage2test="#This is a test for stage 2, which should exceed the size of a single report to test for proper reassembling\nGet-Date"
	# send back stage2
	response = struct.pack("<I", STREAM_TYPE_STAGE2_RESPONSE)
	response += stage2test
	LinkLayer.state["qout"].put(response)

def handle_echo_request(LinkLayer, request):
#	print "Echo request received"	
	response = struct.pack("<I", STREAM_TYPE_ECHO_RESPONSE)
	response += request
	LinkLayer.state["qout"].put(response)

if __name__ == "__main__":

	# !!! Caution !!! two seperate file descriptors (for read and write) have to be used to reach full speed
	HIDin = open("/dev/hidg1", "rb")
	HIDout = open("/dev/hidg1", "wb")

	# initialize link layer
	ll = LinkLayer(HIDin, HIDout)

	# we open a try block to bring cleanup methods into finally block
	# this is used to cleanup on keyboard interrupt
	try:

		# start LinkLayer
		ll.start()
	

		starttime=0
		while True:
			bytes_rcvd = ll.state["payload_bytes_received"]
			streams_rcvd = ll.state["qin"].qsize() # frequentl acces is expensive for LinkLayer threads, as the Queues are synchronized

			while ll.state["qin"].qsize() > 0:
				stream = ll.state["qin"].get()
				
				# unpack type from stream
				stream_type = struct.unpack("<I", stream[0:4])[0]
				#print "Stream received " + str(stream_type)

				if stream_type == STREAM_TYPE_STAGE2_REQUEST:
					handle_stage2_request(ll)
				elif stream_type == STREAM_TYPE_ECHO_REQUEST:
					handle_echo_request(ll, stream[4:])
				else:
					print "Unknown Stream Type " + str(stream_type)

	finally:

		print "Cleaning Up..."

		ll.stop() # send stop event to read and write loop of link layer
		#devfile.close()
		HIDout.close()
		HIDin.close()

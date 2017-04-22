#!/usr/bin/python
import struct
from threading import Thread
from threading import Event
import time
import os
import struct
import Queue
import time
from select import select

class LinkLayer:
	def __init__(self, devfile_in, devfile_out, on_connect_callback=None):
		self.state={}
		self.state["qout"] = Queue.Queue()
		self.state["qin"] = Queue.Queue()
		self.state["MAX_OUT_QUEUE"]=32 # how many packets are allowed to be pening in output queue (without ACK received)
	
		self.state["last_seq_used"]=-1 # placeholder, gets overwritten on syncing
		self.state["last_valid_ack_rcvd"]=-1  # placeholder, gets overwritten on syncing
		self.state["resend_request_rcvd"]=False
		self.state["peer_state_changed"]=False
		self.state["PAYLOAD_MAX_SIZE"]=62
		self.state["EVENT_STOP_WRITE"]=Event()
		self.state["EVENT_STOP_READ"]=Event()
		self.fin = devfile_in
		self.fout = devfile_out
		self.state["connectCallback"] = on_connect_callback # unused at the moment, callback mustn't be processed in LinkLayer threads
		self.state["payload_bytes_received"] = 0

	def stop(self):
		self.state["EVENT_STOP_WRITE"].set()
		self.state["EVENT_STOP_READ"].set()
		rt = self.state["read_thread"]
		wt = self.state["write_thread"]
		print "Waiting for read thread to terminate .."
		rt.join()
		print "Read thread terminated"
		print "Waiting for write thread to terminate .."
		wt.join()
		print "Write thread terminated"
		

	def start(self):
		#sync linklayer (Send with SEQ till correct ACK received)
		self.__sync_link()

		# start write thread
		#thread.start_new_thread(self.write_rep, ( ))
		self.state["write_thread"] = Thread(target = self.write_rep, args = ( ))
		self.state["write_thread"].start()

		# start read thread
		#thread.start_new_thread(self.read_rep, ( ) )
		self.state["read_thread"] = Thread(target = self.read_rep, args = ( ))
		self.state["read_thread"].start()



	def write_rep(self):
		print "Starting write thread"

		DEBUG=False
	
		PAYLOAD_MAX_SIZE=self.state["PAYLOAD_MAX_SIZE"]
		MAX_SEQ = self.state["MAX_OUT_QUEUE"] # length of output buffer (32)
		next_seq = 0 # holding next sequence number to use
		qout = self.state["qout"] # reference to outbound queue
		outbuf = [None]*MAX_SEQ # output buffer array
		last_seq_used = self.state["last_seq_used"]
		stop = self.state["EVENT_STOP_WRITE"]

		current_stream = "" # outbound data larger than PAYLOAD_MAX_SIZE is handled as stream and split into chhunks
		
		# fill outbuf with empty heartbeat reports (to have a valid initial state)
		for i in range(MAX_SEQ):
			# fill initial output buffer with heartbeat packets
			SEQ = i
			payload = ""
			outbuf[i] = struct.pack('!BB62s', len(payload), SEQ, payload )
	

		# start write loop
		while not stop.isSet():
#			time.sleep(0.5) # test delay, to slow down thread (try to produce errors)

			next_seq = last_seq_used + 1
			# cap sequence number to maximum (avoid modulo)
			if next_seq >= MAX_SEQ:
				next_seq -= MAX_SEQ
			last_valid_ack_rcvd = self.state["last_valid_ack_rcvd"]


			is_resend = self.state["resend_request_rcvd"]


			#print "Windows peer state changed " + str(self.state["peer_state_changed"])
			if self.state["peer_state_changed"]:
				self.state["peer_state_changed"] = False # state changed is handled one time here
			else:
				continue # CPU consuming "do nothing"			


			# calculate outbuf start / ebd, fill region start/end and (re)send start/end
			outbuf_start = last_valid_ack_rcvd + 1
			if outbuf_start >= MAX_SEQ:
				outbuf_start -= MAX_SEQ
			outbuf_end = outbuf_start + MAX_SEQ - 1

			outbuf_fill_start = last_seq_used + 1
			if outbuf_fill_start < outbuf_start:
				outbuf_fill_start += MAX_SEQ
			elif  outbuf_fill_start > outbuf_end:
				outbuf_fill_start -= MAX_SEQ
			outbuf_fill_end = outbuf_end 
			# corner case, if resend of whole buffer is requested it mustn't be refilled
			if is_resend and (next_seq == outbuf_fill_start):
				outbuf_fill_start = outbuf_fill_end

			outbuf_send_start = outbuf_fill_start
			if is_resend:
				outbuf_send_start = outbuf_start
			outbuf_send_end = outbuf_end

			usable_send_slots = outbuf_fill_end - outbuf_fill_start

			if DEBUG:
				print "===================== Writer stats ===================================================="
				print "Writer: Last valid ACK " + str(last_valid_ack_rcvd)
				print "Writer: Last SEQ used " + str(last_seq_used)
				if is_resend:
					print "Writer: Answering RESEND "
				print "Writer: OUTBUF position from " + str(outbuf_start) + " to " + str(outbuf_end)
				print "Writer: OUTBUF fill position from " + str(outbuf_fill_start) + " to " + str(outbuf_fill_end)
				print "Writer: OUTBUF send position from " + str(outbuf_send_start) + " to " + str(outbuf_send_end)
				print "Writer: OUTBUF usable send slots " + str(usable_send_slots)
				print "Qout stream count " + str(qout.qsize())
				print "======================================================================================="


			# fill usable send slots in outbuf
			for seq in range(outbuf_fill_start, outbuf_fill_end):
				# sequence number to use in slot
				current_seq = seq
				# clamp sequence number to valid range
				if current_seq >= MAX_SEQ:
					current_seq -= MAX_SEQ

				#print "Writer: Setting outbuf slot " + str(current_seq)

				###########
				# fragment oversized output data (stream) into multiple payloads (fitting into single report)
				###########
				payload = None
				FIN = True # Last report in current stream
				if len(current_stream) == 0:
					# no more data in stream
					# check if pending data in out queue
					if qout.qsize() > 0:
						current_stream = qout.get()			
				payload = current_stream[:PAYLOAD_MAX_SIZE] # grab chunk
				current_stream = current_stream[PAYLOAD_MAX_SIZE:] # remove chunk from stream
				if len(current_stream) > 0:
					# unsent data in stream, so remove FIN bit
					FIN = False
				# Note: If no data has been in qout this leads to a payload of length 0 with 
				#	FIN bit set. This again leads to sending an empty report, which is ignored 
				#	by the peer (could be seen as heartbeat or carrier without data)
				#	SEQ numbers are continuosly counted up, even on empty reports. This
				#	Thus the other payer has to acknowledge received reports with a valid
				#	ACK number (and of course the answer report is allowed to contain payload, if there's
				#	pending output on the other end)
				
				####
				# end fragment
				###


				# combine FIN bit into LEN field
				LEN_FIN = len(payload)
				if FIN:
					LEN_FIN += 128 # encode FIN bit into header

				# create report to fit into outbuf
				report = struct.pack('!BB62s', LEN_FIN, current_seq, payload )



				#print "Payload: " + payload
					
				# put report into current slot in outbuf
				outbuf[current_seq] = report

			# process pre-filled outbuf slots which should to be (re)send
			for seq in range(outbuf_send_start, outbuf_send_end):
				# sequence number to use in slot
				current_seq = seq
				# clamp sequence number to valid range
				if current_seq >= MAX_SEQ:
					current_seq -= MAX_SEQ


				# write reports marked for sending from outbuf to HID device
				written = self.fout.write(outbuf[current_seq])

				# update state to correct last sequence number used
				last_seq_used = current_seq
					
				#print "Writer: Written with seq " + str(current_seq) + " payload " + outbuf[current_seq][4:]

			self.fout.flush() # push written data to device file
			
#			print "Last SEQ used after write loop finish " + str(last_seq_used)

			self.state["resend_request_rcvd"] = False # disable resend if it was set

	# used initernally to handle reconnect requests
	def __on_reconnect(self):
		print "Handling reconnect..."
		print "Stop Write thread..."

		# stop write thread (we want to write from this thread on connection establishment)
		self.state["EVENT_STOP_WRITE"].set() # set stop event for write thread

		# wait for write thread to terminate
		self.state["write_thread"].join() # wait for current write thread to terminate
		print "Write thread terminated"
				
		# empty queues with old data
		print "Clearing input and output queues..."
		self.state["qout"].queue.clear()
		self.state["qin"].queue.clear()


		# write empty report in order to terminate the blocking read on other end 
		# (peer is waiting for incoming report after sending reconnect request, which is never
		# sent after the write thread has been terminated)
		outbytes = struct.pack('!BB62s', 0, 0, "" )
		self.fout.write(outbytes)
		self.fout.flush()
				
		# resync connection (sync SEQ to ACK before restarting write thread)
		self.__sync_link()

		# restart write thread
		print "Restarting write thread..."
		self.state["EVENT_STOP_WRITE"].clear()
		self.state["write_thread"] = Thread(target = self.write_rep, args = ( ))
		self.state["write_thread"].start()


	def read_rep(self):
		print "Starting read thread"

		MAX_OUT_QUEUE = self.state["MAX_OUT_QUEUE"]

		# state values to detect SENDER state changes across repeated reports
		last_BYTE1_BIT7_FIN = 0	
		last_BYTE1_BIT6_RESEND = 0
		last_ACK = -1
	
		qin = self.state["qin"] # reference to inbound queue
		stop = self.state["EVENT_STOP_READ"]

		stream = "" # used to concat fragmented reports to full stream
	
		while not stop.isSet():
#			time.sleep(1.5) # slow down loop, try to produce errors


			# the read call to the device file blocks forever if there's no data and would prevent stopping this thread
			# (if stopping is needed), thus we introduce a select with timeout, to check for readable data before calling read
			#
			# note: the additional select lowers transfer rate about 500 Byte/s
			res = select([self.fin.fileno()], [], [], 0.1) # 1 ms timeout
			if len(res[0]) == 0:
				# no data to read, restart loop (and check stop condition)
				continue

			inbytes = self.fin.read(64)


			report = struct.unpack('!BB62s', inbytes)
			
			BYTE1_BIT7_FIN = report[0] & 128
			BYTE1_BIT6_RESEND = report[0] & 64
			BYTE2_BIT7_CONNECT = report[1] & 128 # (re)establish connection
			LENGTH = report[0] & 63
			ACK = report[1] & 63

			# print "Reader: Report received: Length " + str(LENGTH) + " FIN bit " + str(BYTE1_BIT7_FIN/128)

			# handle (re) connect bit
			if (BYTE2_BIT7_CONNECT):
				print "Reconnect request (ACK " +str(ACK) +" has CONNECT BIT set)"
				self.__on_reconnect()
				# abort this loop iteration
				continue


#			# if length > 0 (no heartbeat) process
#			if LENGTH > 0:
#				qin.put(report[2][:LENGTH]) # trim to length given by header

			# if length > 0 (no heartbeat) process
			if LENGTH > 0:
				# concat stream
				stream += report[2][:LENGTH]
				if BYTE1_BIT7_FIN:
					# if FIN bit set, push stream to input queue
					qin.put(stream) # trim to length given by header
					stream = "" # reset stream
				self.state["payload_bytes_received"] += LENGTH # sums the payload bytes received, only debug state (bytes mustn't necessarily be enqueued if incomplete stream)
				self.state["payload_bytes_received"] &= 0x7FFFFFFF # cap to max of 32 bit (signed)

			# as state change of the other peer is detected by comparing header fields from the last received report to the current received
			# as reports are flowing coninuosly (with or without payload), the same state could be reported by the other peer repetively
			# Example: 	The other peer misses a packet (out-of-order HID input report SEQ number)
			#		this would lead to a situation, where the other peer continuosly sends RESEND REQUEST
			#		till a packet with a valid sequence number is received.
			#		The resend should take place only once, thus follow up resend requests have to be ignored.
			#		This is achieved by tracking the peer sate, based on received HID output report headers (ACK field and flags)
			#		to detect changes. Only a change in these fields will result in an action taken by this endpoint.
			#		So the first request readen here, carrying a RESEND REQUEST will enable the "peer_state_changed" state.
			#		The writer thread (creating input reports) disables "peer_state_changed" again, after the needed action
			#		has been performed (in this example RESENDING of the packets missed).
			#
			# The "peer_sate_change" has to be enabled by this thread if needed, but mustn't be disable by this thread (task of the writer thread
			# after taking needed action)

			# This isn't an optimal solution, because if the same packet is lost two times, the receiver peer would answer with the
			# same RESEND request, although the action has already been taken by this peer (writing the missed HID inpurt reports again)
			# Thus the writer thread, which is responsible for disabeling the "peer_state_change" request, should reset last_* variables
			# to some initial values, to force a new state change if something goes wrong (not implemented, re-occuring report loss is unlikely
			# as the maximum number of pending reports written, should be less than the reports cachable on the input buffer of the other peer)
			
			if last_BYTE1_BIT7_FIN != BYTE1_BIT7_FIN or last_BYTE1_BIT6_RESEND != BYTE1_BIT6_RESEND or last_ACK != ACK:
				self.state["peer_state_changed"] = True
				last_BYTE1_BIT7_FIN = BYTE1_BIT7_FIN
				last_BYTE1_BIT6_RESEND = BYTE1_BIT6_RESEND 
				last_ACK = ACK
		
			if (BYTE1_BIT6_RESEND):
				#print "Reader: received resend request, starting from SEQ " + str(ACK) + " len " + str(report[0]) 

				self.state["resend_request_rcvd"] = True
				ACK=ACK-1 # ACKs ar valid up to predecessor report of resend request
				if ACK < 0:
					ACK += MAX_OUT_QUEUE # clamp to valid range
				self.state["last_valid_ack_rcvd"]=ACK
			else:
				#print "Reader: received ACK " + str(ACK)
				self.state["last_valid_ack_rcvd"]=ACK
				self.state["resend_request_rcvd"] = False


			
	# This synchronization method is used when the LinkLayer is started the first time
	# (because communication has to be started by the peer) and when the peer sends a report
	# with CONNECT BIT set (= reconnect request).
	#
	# The purpose of the method is to bring SEQ numbers send from this server in sync with ACK numbers
	# send by the peer. This is needed on communication start, because the peer is supposed to start sending.
	# As no report with a valid SEQ number has the peer at this point, the peer couldn't know a valid ACK
	# to start with. So synchronization of ACK/SEQ has to be done, before link layer communication starts.
	def __sync_link(self):
		MAX_OUT_QUEUE = self.state["MAX_OUT_QUEUE"]

		SEQ = 10 # start sequence number for syncing to ACK (random start SEQ between 0 and MAX_OUT_QUEUE)
		payload_byte1 = 0
		print "Trying to sync link layer..."
		while True:
			inbytes = self.fin.read(64) # if this is the first read, the client shouldn't have a valid ack
			report = struct.unpack('!BB62s', inbytes)

			# check if CONNECT BIT is set,
			CONNECT_BIT = report[1] & 128
			ACK = report[1] & 63
			if CONNECT_BIT:
				print "ACK " + str(ACK) + " with CONNECT BIT received"
				# check if ACK fits our initial SEQ
				if SEQ == ACK:
					# we are in sync and could continue with FULL DUPLEX communication
					break
			else:
				# We land here, if initial communication seen from the peer doesn't start
				# with a connection request (CONNECT BIT set)
				# Such traffic is considere invalid and thus ignored
				print "Connection Establishment: Received  ACK " + str(ACK) + " without CONNECT BIT."
				print "Peer has to sync connection before trying to communicate the first time"

			# set CONNECT BIT to notify peer that the ACK belongs to a connection request
			# (and isn't old outbound traffic already sent to the wire)
			BYTE2 = SEQ + 128 # set CONNECT BIT
			outbytes = struct.pack('!BB62s', 0, BYTE2, "" )
			self.fout.write(outbytes)
			self.fout.flush()


		# if we are here, we are in sync, next valid sequence number is in SEQ
		print "Sync done, last valid SEQ " + str(SEQ) + " + last valid ACK " + str(ACK)
		self.state["last_valid_ack_rcvd"]=ACK # set correct ACK into state
		self.state["last_seq_used"] = SEQ # set last SEQ into state
		self.state["peer_state_changed"] = True



if __name__ == "__main__":
	##############
	## test of link layer
	########

	# Test function to enque output
	#  q_stream_out:	output queue to use
	#  stream_size:		size to use for single stream which gets enqueued
	#  max_bytes:		max bytes to enqueue at all
	def TEST_enqueue_output(q_stream_out, stream_size, max_bytes):
		# Fill outbound queue with test data
		print "Enqueue " + str(max_bytes) + " Bytes output data split into streams of " + str(stream_size) + " bytes, each..."
	
		for i in range((int) (max_bytes / stream_size)):
			payload = "Stream number " + str(i) + " of size " + str(stream_size) + " filled up with As... "
			# fill up payload to consume 
			fill = "A" * (stream_size - len(payload))
			payload += fill
			q_stream_out.put(payload)

		print "... done pushing data into queue"


	# open device file read/write binary
	#devfile=open("/dev/hidg1", "r+b")
	#HIDin = devfile
	#HIDout = devfile

	# !!! Caution !!! open the output and input files with a single FD as shown in the code above, halves the speed (caused by synchronization on file ?)
	HIDin = open("/dev/hidg1", "rb")
	HIDout = open("/dev/hidg1", "wb")


	ll = LinkLayer(HIDin, HIDout)

	# fetch handle to output report queue
	#q_stream_out = ll.state["qout"]
	# fetch handle to output report queue
	#q_stream_in = ll.state["qin"]

	# Fill outbound queue with test data (streams of 620 bytes each, up to 1 MB)
	stream_size = ll.state["PAYLOAD_MAX_SIZE"] * 100 # size of a single data stream enqueued
	max_bytes = 1024*1024 + stream_size # maximum of bytes to put to outbound queue
	TEST_enqueue_output(ll.state["qout"], stream_size, max_bytes)


	BYTES_TO_FETCH = 896*1024 # don't capture all data (1 MB is sent), as PowerShell process terminates after receiving without sending further data

	try:

		# start LinkLayer
		ll.start()
	

		# test loop printing out every input received
		#i = 0
		starttime=0
		no_data_rcvd = True # only for time measuring
		while True:
			bytes_rcvd = ll.state["payload_bytes_received"]
			streams_rcvd = ll.state["qin"].qsize() # frequentl acces is expensive for LinkLayer threads, as the Queues are synchronized

			if bytes_rcvd and no_data_rcvd:
				no_data_rcvd = False
				starttime = time.time() # start stopwatch

			if bytes_rcvd < BYTES_TO_FETCH:
				print "Full streams received " + str(streams_rcvd) + ". Raw payload bytes received " + str(bytes_rcvd)
				time.sleep(0.05) # 50 ms sleep to lower load
			else:
				ttaken = time.time() - starttime

				print "Received " + str(bytes_rcvd) + " bytes of data in " + str(ttaken) + " seconds"
				print "Pending input streams: " + str(streams_rcvd)
				print "Printing out (only first 100 bytes of each stream)..."

				# if max_bytes received, print out all comleted streams from input queue
				while ll.state["qin"].qsize() > 0:
					#print q_stream_in.get()
					print ll.state["qin"].get()[:100] + "...snip..."

				throughput_in = bytes_rcvd / ttaken
				print "Received " + str(bytes_rcvd) + " bytes of data in " + str(ttaken) + " seconds"
				print "Throughput " + str(throughput_in) + " Bytes/s"
			
				break

		# second test loop continuosly sending / reading, 1 second interval
		starttime = time.time()
		while True:
			if ll.state["payload_bytes_received"] > BYTES_TO_FETCH:
				# reset counter
				bytes_rcvd = ll.state["payload_bytes_received"]
				ll.state["payload_bytes_received"] = 0
				endtime = time.time()
				ttaken = endtime - starttime
				starttime = endtime
				tp = bytes_rcvd / ttaken
				print str(bytes_rcvd) + " bytes in " + str(ttaken) + " seconds (" + str(tp) + " bytes/s)"

			# keep main thread running
			time.sleep(1.0) # 1000 ms sleep

		
			# go on processing inbound data
			while ll.state["qin"].qsize() > 0:
				#print q_stream_in.get()
				stream = ll.state["qin"].get()
	#			print stream[:100] + "...snip..."

			# enqueue output
			stream_size = ll.state["PAYLOAD_MAX_SIZE"] * 100 # size of a single data stream enqueued
			max_bytes = 9*6200 # maximum of bytes to put to outbound queue
			q_stream_out = ll.state["qout"]
			TEST_enqueue_output(q_stream_out, stream_size, max_bytes)


	finally:

		print "Cleaning Up..."

		ll.stop() # send stop event to read and write loop of link layer
		#devfile.close()
		HIDout.close()
		HIDin.close()

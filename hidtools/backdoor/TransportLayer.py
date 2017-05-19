#!/usr/bin/python
from pydispatch import dispatcher
from LinkLayer import LinkLayer
from threading import current_thread
import Queue

class TransportLayer():
	"""
	Interfaces with LinkLayer via pydispatcher
	"""

	DEBUG=False

        SIGNAL_LINKLAYER_STARTED = "LinkLayerStarted"
        SIGNAL_LINKLAYER_SYNCING = "LinkLayerSyncing"
        SIGNAL_LINKLAYER_SYNCED = "LinkLayerSynced"
        SIGNAL_LINKLAYER_CONNECTION_RESET = "LinkLayerConnectionReset"
        SIGNAL_LINKLAYER_CONNECTION_ESTABLISHED = "LinkLayerConnectionEstablished"
        SIGNAL_LINKLAYER_STOPPING = "LinkLayerStopping"
        SIGNAL_LINKLAYER_STOPPED = "LinkLayerStopped"
        SIGNAL_LINKLAYER_STREAM_ENQUEUED = "LinkLayerStreamEnqueued"

        TRANSPORTLAYER_SENDER_NAME = "TransportLayer"
        SIGNAL_TRANSPORTLAYER_SEND_STREAM = "TransportLayerSendStream"

	def __init__(self):
		# create queue for incoming streams to decouple processing from link layer reader thread
		self.stream_in_queue = Queue.Queue()

		# register Listener for LinkLayer signals
		dispatcher.connect(self.handle_link_layer, sender="LinkLayer")

	def write_stream(self, stream):
		self.__write_raw_stream(stream)

	def __write_raw_stream(self, stream):
		# should keep track of LinkLayer's output queue size (needs additional dispatcher messages)
		dispatcher.send(data = stream, signal = TransportLayer.SIGNAL_TRANSPORTLAYER_SEND_STREAM, sender = TransportLayer.TRANSPORTLAYER_SENDER_NAME)

	def data_available(self):
		return self.stream_in_queue.qsize()

	def pop_input_stream(self):
		return self.stream_in_queue.get()

	@staticmethod
	def print_debug(str):
		if TransportLayer.DEBUG:
			print "TransportLayer (DEBUG): {}".format(str)

	# loose definition of LinkLayer handler, data argument has to be produced by LinkLayer
	def handle_link_layer(self, signal, data):

		if signal == TransportLayer.SIGNAL_LINKLAYER_STREAM_ENQUEUED:
			# enqueue stream data
			#print "TransportLayer: stream from LinkLayer enqueued (Thread: " + current_thread().getName() + ")"
			self.stream_in_queue.put(data)
		elif signal == TransportLayer.SIGNAL_LINKLAYER_CONNECTION_RESET:
			TransportLayer.print_debug("Received connection reset")
		elif signal == TransportLayer.SIGNAL_LINKLAYER_SYNCING:
			print "TransportLayer: Waiting for client connection via HID..."		
		elif signal == TransportLayer.SIGNAL_LINKLAYER_SYNCED:
			print "TransportLayer: Client connected via HID!"		
		else:
			TransportLayer.print_debug("TransportLayer: Unhandled singnal from LinkLayer processed by thread: " + current_thread().getName())
			TransportLayer.print_debug("TransportLayer: signal: " + signal + ", data: " + repr(data[:100]))



#!/usr/bin/python
import Queue
from threading import Condition

class BlockingQueue():
	"""
	A BlockingQueue is a FIFO queue using threading.Contition to receive notifications on queue changes

	Usecase:
	LinkLayer HID communication is somehow asynchronous (although responses SHOULD be in order of
	requests, response delays could be huge). A BlockingQueue is a FIFO
	like solution which accepts data from a thread via put and provides a blocking get
	(blocks in case no data is in queue) for another thread.
	By using a BlockingQueue for a dedicated task, it is possible to sent a request by a HID writer
	thread and wait for the response from another thread (which use put method to propagate data
	into the BlockingQueue). The thread waiting for response could call get, which will block till
	the data is presented by the call to put from the other thread.
	"""

	DEBUG = False

	def __init__(self, name = ""):
		self.name = name
		self.queue = Queue.Queue()
		self.__cond = Condition()

	@staticmethod
	def print_debug(str):
		if BlockingQueue.DEBUG:
			print "BlockingQueue (DEBUG): {}".format(str)

	def put(self, data):
#		BlockingQueue.print_debug("PUT: putting data: {0}".format(repr(data)))
		# aqcuire lock
		BlockingQueue.print_debug("PUT: Acquire lock")
		self.__cond.acquire()
		# enqueue data
		BlockingQueue.print_debug("PUT: enqueue data {0}".format(self.name))
		self.queue.put(data)
		# notify waiters about new data
		BlockingQueue.print_debug("PUT: notify waiters")
		self.__cond.notifyAll()
		# release lock
		BlockingQueue.print_debug("PUT: release lock")
		self.__cond.release()

	def data_available(self):
		return self.queue.qsize()

	def wait_for_data(self):
		"""
		Blocks till data is put to queue
		"""
		self.__cond.acquire()
		self.__cond.wait()
		self.__cond.release()
		
		return


	# blocking get, returns only if data is available
	def get(self):
		"""
		Returns data if available (one stream per call), blocks otherwise
		"""

		# don't block if data is has already arrived
		if self.data_available():
			BlockingQueue.print_debug("GET: {0} ..read is able to deliver data, thus it doesn't block this time".format(self.name))
			return self.queue.get()

		# if we got here, no data was available

		# aqcuire lock
		BlockingQueue.print_debug("GET: acquire lock")
		self.__cond.acquire()
		# wait for notification from put
		BlockingQueue.print_debug("GET: wait for notification")
		self.__cond.wait()
		BlockingQueue.print_debug("GET: continue after notification")
		# dequeue data
		BlockingQueue.print_debug("GET: {0} ..fetch data".format(self.name))
		data = self.queue.get()
		# release lock
		BlockingQueue.print_debug("GET: release lock")
		self.__cond.release()
		
		return data

	# like get but none blocking, returns None if no data available
	def poll(self):
		"""
		Returns data if available, return None otherwise
		"""

		if self.data_available():
			return self.queue.get()
		else:
			return None


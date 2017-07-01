from threading import Event
import struct
from Channel import Channel

class Client(object):
    DEBUG = False

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
        self.__processes = {}
        self.__channels = {}
        self.__channels_in = {}
        self.__channels_out = {}

    def print_state(self):
        print "Client state"
        print "============"
        print "Link:\t{0}".format(self.__hasLink)
        print "Stage2:\t{0}".format(self.__stage2)
        print "PS:\t{0}".format(self.__ps_version)
        print "OS:\n{0}".format(self.__os_info)

    def isConnected(self):
        if self.__hasLink and self.__stage2 == "RUNNING":
            return True
        else:
            return False

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
            if stage2 == "RUNNING":
                self.onConnect()

    def onConnect(self):
        print "\nTarget connected through HID covert channel\n"

    def setOSInfo(self, osinfo):
        self.__os_info = osinfo

    def setPSVersion(self, psver):
        self.__ps_version = psver

    def callMethod(self, name, args, success_handler, error_handler = None, waitForResult = False, deliverResult = False):
        method_id = self.get_next_method_id()
        method = None
        if error_handler:
            method = ClientMethod(method_id, name, args, success_handler, error_handler)
        else:
            method = ClientMethod(method_id, name, args, success_handler, Client.defaultMethodErrorHandler)

        # add method to pending ones
        self.__pending_methods[method_id] = method

        if waitForResult or deliverResult: # deliverResult implies waitResult
            method.waitResult()

        if deliverResult:
            return method.handler_result

    @staticmethod
    def defaultMethodErrorHandler(response):
        print "Error when calling method:\n" + response


    def deliverMethodResponse(self, response):
        '''
        This method takes the payload of a single control message of type
        CTRL_MSG_FROM_CLIENT_RUN_METHOD_RESPONSE and delivers it to the correct method handler (if possible)
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
                method.handler_result = method.error_handler(errmsg)
            else:
                Client.print_debug("Method '{0}' with call ID {1} failed, but no error handler defined. Error Message: {1}".format(method.name, errmsg))
        else:
            # method succeeded
            Client.print_debug("Response for method '{0}' with call ID {1} received. Method succeeded, delivering result to handler: {3}".format(method.name, method.id, success_error, repr(response)))
            # try to fetch error handler
            if method.handler:
                method.handler_result = method.handler(response)
            else:
                Client.print_debug("Method '{0}' with call ID {1} succeeded, but no handler defined. Method result: {1}".format(method.name, response))

        # remove method from pending ones, as the answer was received (caution: has to be checked for thread safety !!!)
        del self.__pending_methods[method_id]
        Client.print_debug("Method '{0}' with call ID {1} removed from pending queue, after receiving and processing result.".format(method.name, method.id, success_error))

        # make method recognize that the result is received (could be placed before if-else-tree above to keep logical order if needed)
        method.result_received = True

    def getPendingMethods(self):
        return self.__pending_methods		

    def getProcess(self, pid):
        if pid in self.__processes:
            return self.__processes[pid]
        else:
            return None			

    def addProc(self, proc):
        self.__processes[proc.id] = proc

    def getProcsWithChannel(self):
        procs=[]
        for proc in self.__processes:
            procs.append(self.__processes[proc])
        return procs

    def addChannel(self, channel):
        self.__channels[channel.id] = channel
        Client.print_debug("Channel with ID {0} added to client".format(channel.id))

        if channel.type != Channel.TYPE_OUT:
            # this is an BIDIRECTIONAL or INPUT channel
            self.__channels_in[channel.id] = channel
            Client.print_debug("Channel with ID {0} added to OUTPUT channels".format(channel.id))

        if channel.type != Channel.TYPE_IN:
            # this is an BIDIRECTIONAL or OUTPUT channel
            self.__channels_out[channel.id] = channel
            Client.print_debug("Channel with ID {0} added to INPUT channels".format(channel.id))

    def sendToInputChannel(self, ch, payload):
        # check if the channel exists in input channels, otherwise we aren't able to write to it
        if ch in self.__channels_in:
            channel = self.__channels_in[ch]
            channel.enqueueInput(payload)
        else:
            Client.print_debug("Channel with ID {0} isn't a known input channel".format(ch))
            Client.print_debug("The following data has been ignored: {0}".format(repr(payload)))

    def getPendingChannelOutput(self):
        outdata = []

        # iterate over output channels
        for ch in self.__channels_out:
            channel = self.__channels_out[ch]
            while channel.hasOutput():
                # retrieve the pending output
                data = channel.dequeueOutput()
                # prepend channel ID
                data = struct.pack("!I", channel.id) + data
                # append to outdata
                outdata.append(data)
                #Client.print_debug("data appended to pending out {0}".format(repr(data)))

        return outdata

class ClientProcess(object):

    def __init__(self, id, ch_stdin, ch_stdout, ch_stderr):
        self.id = id
        self.ch_stdin = ch_stdin
        self.ch_stdout = ch_stdout
        self.ch_stderr = ch_stderr

    def writeStdin(self, data):
        self.ch_stdin.writeOutput(data)

    def setInteract(self, interact):
        self.ch_stdout.setInteract(interact)
        self.ch_stderr.setInteract(interact)

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
        self.__wait_result_event = Event()
        self.__wait_result_event.clear()
        self.handler_result = None

    def createMethodRequest(self):
        # the method request starts with a null terminated method name, the args are appended as char[]
        methodRequest = struct.pack("!I{0}sx{1}s".format(len(self.name), len(self.args)), self.id, self.name, self.args) # method_id (uint32), name (null terminated string), args  

        #print "Method request created: " + repr(methodRequest)
        return methodRequest

    @property
    def run_requested(self):
        #print "Get run_requested for {0} {1}".format(self.name, self.id)
        return self._run_requested

    @run_requested.setter
    def run_requested(self, value):
        #print "Set run_requested for {0} {1} to {2}".format(self.name, self.id, value)
        self._run_requested = value

    @property
    def result_received(self):
        #print "Get result_received for {0} {1}".format(self.name, self.id)
        return self._result_received

    @result_received.setter
    def result_received(self, value):
        #print "Set result_received for {0} {1} to {2}".format(self.name, self.id, value)
        self._result_received = value

        self.__wait_result_event.set()

    def waitResult(self):
        '''
        blocks till result_recieved is set to true
        '''
        # ToDO: implement with conditional (which should get set by setter of "result_received"
        while not self.__wait_result_event.isSet():
            # loop while waiting for the event (interrupt every 100ms to allow interruption of a thread calling this thread)
            self.__wait_result_event.wait(0.1)





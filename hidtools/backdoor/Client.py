
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


from threading import Event
import struct
from Channel import Channel

class Client(object):
    DEBUG = False

    def __init__(self):
        self.__callbacksConnectChange =  []
        self.reset_state()

    @staticmethod
    def print_debug(str):
        if Client.DEBUG:
            print "Client state (DEBUG): {}".format(str)

    def get_next_method_id(self):
        next = self.__next_method_id
        # increase next_method id and cap to 0x7FFFFFFF
        self.__next_method_id = (self.__next_method_id + 1) & 0x7FFFFFFF
        return next

    def reset_state(self):
        self.__hasLink = False
        self.__stage2 = ""
        self.__os_info = ""
        self.__ps_version = ""
        self.__next_method_id = 1
        # abort all pending method with error
        if hasattr(self,  "_Client__pending_methods"):
            for method_id in self.__pending_methods.keys(): # we copy the dictionary keys, as processed methods get removed by another thread while iterating
                errstr =  "Method aborted, because client disconnected"
                err_indicator =  1
                response = struct.pack("!IB{0}sx".format(len(errstr)), method_id, err_indicator, errstr)
                self.deliverMethodResponse(response)
        # close all opened channels
        if hasattr(self,  "_Client__channels"):
            for channel in self.__channels.values():
                channel.onClose() 
        self.__pending_methods = {}
        self.__processes = {}
        self.__channels = {}
        self.__channels_in = {}
        self.__channels_out = {}
        self.__isConnected =  False

    def print_state(self):
        print "Client state"
        print "============"
        print "Link:\t{0}".format(self.__hasLink)
        print "Stage2:\t{0}".format(self.__stage2)
        print "Connected:\t{0}".format(self.__isConnected)
        print "PS:\t{0}".format(self.__ps_version)
        print "OS:\n{0}".format(self.__os_info)

    def setConnected(self, connected):
        if self.__isConnected == connected:
            return
        for callback in self.__callbacksConnectChange:
            callback(connected)
        if connected:
            self.onConnect()
        else:
            self.onDisconnect()
        self.__isConnected = connected
        
    def registerCallbackOnConnectChange(self, callaback):
        self.__callbacksConnectChange.append(callaback)
        
    def unregisterCallbackOnConnectChange(self, callback):
        self.__callbacksConnectChange.remove(callback)
        
    def isConnected(self):
        return self.__isConnected

    def setLink(self, link):
        if not link == self.__hasLink:
            Client.print_debug("Link state changed: {0}".format(link))
            if not link:
                self.setConnected(False)
                self.reset_state() # reset state sets the internal connection state to false, if issued before setConnected(false) there wouldn't be a change in connection state and thus callback aren't issued
                #self.onDisconnect()
        self.__hasLink = link

    def setStage2(self, stage2):
        if not stage2 == self.__stage2:
            Client.print_debug("Stage2 state changed: {0}".format(stage2))
            self.__stage2 = stage2
            
    def onConnect(self):
        pass
        #print "\nTarget connected through HID covert channel\n"
        
    def onDisconnect(self):
        pass
        #print "\nTarget disconnected\n"        

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
                #method.handler_result = method.error_handler(errmsg)
                method.handler_result = (False, method.error_handler(errmsg)) # return a list, boolean indicates error, second entry is result
            else:
                Client.print_debug("Method '{0}' with call ID {1} failed, but no error handler defined. Error Message: {1}".format(method.name, errmsg))
        else:
            # method succeeded
            Client.print_debug("Response for method '{0}' with call ID {1} received. Method succeeded, delivering result to handler: {3}".format(method.name, method.id, success_error, repr(response)))
            # try to fetch error handler
            if method.handler:
                method.handler_result = (True, method.handler(response)) # return a list, boolean indicates success, second entry is result
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
        
    def removeProc(self, proc_id):
        
        #if proc_id in self.__processes:
                #proc =  self.__processes[proc_id]
                #self.removeChannel(proc.ch_stdin.id)
                #self.removeChannel(proc.ch_stderr.id)
                #self.removeChannel(proc.ch_stdout.id)
        
        del self.__processes[proc_id]

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

    def getChannel(self, channel_id):
        if channel_id in self.__channels:
            return self.__channels[channel_id]
        else:
            return None
        
    def removeChannel(self, channel_id):
        ch = self.getChannel(channel_id)
        ch.onClose()
        if ch:
            if channel_id in self.__channels_in:
                del self.__channels_in[channel_id]
            if channel_id in self.__channels_out:
                del self.__channels_out[channel_id]
            del self.__channels[channel_id]

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
        for ch in self.__channels_out.keys():
            try:
                channel = self.__channels_out[ch]
            except KeyError:
                continue
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

    def __init__(self, id, ch_stdin, ch_stdout, ch_stderr,  keepTillInteract = True):
        self.id = id
        self.ch_stdin = ch_stdin
        self.ch_stdout = ch_stdout
        self.ch_stderr = ch_stderr
        self.hasExited = False
        self.keepTillInteract =  keepTillInteract

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





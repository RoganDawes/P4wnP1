
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


import Queue
from FileSystem import FileSystem
import struct
from threading import Event, Condition

class ChannelException(Exception):
    def __init__(self, value):
        self.value = value
        
    def __str__(self):
        return repr(self.value)

class Channel(object):
    TYPE_IN = 1 
    TYPE_OUT = 2
    TYPE_BIDIRECTIONAL = 3

    ENCODING_UTF8 = 1
    ENCODING_BYTEARRAY = 2

    DEBUG = False

    interact = False
    __isClosed = False

    def __init__(self, channel_id, type, encoding):
        self.id = channel_id
        self.encoding = encoding
        self.type = type

        # if INPUT or bidirectional, create INPUT queue
        if self.type == Channel.TYPE_IN or self.type == Channel.TYPE_BIDIRECTIONAL:
            self.__in_queue = Queue.Queue()

        # if OUTPUT or bidirectional, create OUTPUT queue
        if self.type == Channel.TYPE_OUT or self.type == Channel.TYPE_BIDIRECTIONAL:
            self.__out_queue = Queue.Queue()

    def setInteract(self, interact):
        if interact:
            pass
            # if interact got enabled, print out all buffered data and set interact to true afterwards (forces passthru of channel to stdout)
            import sys
            while self.__in_queue.qsize() > 0:
                sys.stdout.write(self.__in_queue.get())
                sys.stdout.flush()
        self.interact = interact

    @staticmethod
    def print_debug(str):
        if Channel.DEBUG:
            print "Channel (DEBUG): {0}".format(str)


    def writeOutput(self, data):
        # enqueue the given output data, if possible
        if self.type == Channel.TYPE_IN:
            Channel.print_debug("Couldn't write output to input channel {0}".format(self.id))
            return

        self.__out_queue.put(data)
        Channel.print_debug("Output written to channel {0}: {1}".format(self.id, repr(data)))


    def readInput(self):
        if self.type == Channel.TYPE_OUT:
            Channel.print_debug("Couldn't read input from output channel {0}".format(self.id))
            return

        result = None
        while not result and not self.__isClosed:
            try:
                result = self.__in_queue.get(block=True, timeout=0.1)
            except Queue.Empty:
                continue
        if not result:
            raise ChannelException("Channel {0} closed, could not read".format(self.id))
        return result

    def enqueueInput(self, data):
        # ToDo: for now we only print out data, the data has to be written to a queue in order to process it later on
        #print "enqueueing for ch {0}: {1}".format(self.id, repr(data))

        #####
        # Debug implementation, printing directly
        ####

        if self.type == Channel.ENCODING_UTF8:
            if self.interact:
                import sys

                sys.stdout.write(data)
                sys.stdout.flush()
            else:
                self.__in_queue.put(data)
        else:
            print "Channel {0} got data written: {1}".format(self.id, repr(data))

    def dequeueOutput(self):
        if self.type == Channel.TYPE_IN:
            Channel.print_debug("Couldn't dequeue output from channel {0}, this is an INPUT channel".format(self.id))
            return False

        return self.__out_queue.get()

    def hasInput(self):
        pass

    def hasOutput(self):
        if self.__isClosed:
            return False
        if self.type == Channel.TYPE_IN:
            Channel.print_debug("Couldn't check channel {0} for pending output, this is an INPUT channel".format(self.id))
            return False

        if self.__out_queue.qsize() > 0:
            return True
        else:
            return False
        
    def onClose(self):
        self.__isClosed = True
        print "ServerChannel: channel ID {0} onClose called".format(self.id)
    

class StreamChannel(Channel):
    '''
    The StreamChannel should provide access methods to remote streams (windows like). Beside pure data transfer (read/write),
    the channel needs to be able to communicate control data to the peer (for example: close, flush etc.). There are multiple options
    to achieve this:
    1) Keep the channel bidirectional and mix pure data with control data, distinguished by some header bytes
        + additional logic is kept in channel
        - complex implemetation (priority of control data over already enqueued channel data has to be assured, channel control
        data has to have priority over other data from different channels), adjustments to multiple communication layers are needed
        anyway
    2) Keep the channels standard functionality (read/write) and use the global control channel to communicate data
        + simpler implementation
        - the channel itself needs access to the Client object, which again is able to send and receive control messages
        - a control message and its remote handler have to be implemented for every possible "channel control communication type"
        + the client is able to create control messages, to push them to the server
    3) The channel could hold a second communictaion queue with outbound control messages, the outer client implementation sends
    these control requests and receives the answers. Instead of using a own CTRL_MSG for every type of possible control communication,
    a single remote method could be used (CTRL_RUN_METHOD). Complexity could be hidden in a "big" remote method with a "big" local
    response handler.
        + remote methods are handled by control messages (RUN_METHOD + RUN_METHOD_RESPONSE) and thus are already given priority
        (at least as long as the other layers are able to assure that global control channel data is priorized)
        + the handler for the "channel_control_method" call (ipmlemented on client level, as all the other handlers), could
        pass in channel control method responses to the correct channel
        - this doesn't allow "push notifications" from the other peer, as remote methodes have to be requested from server
        to client
        
    Test approach is method 1:
    
    '''
    
    BUFFER_SIZE = 3000
    CHANNEL_CONTROL_REQUEST_STATE = 1
    CHANNEL_CONTROL_REQUEST_READ = 2
    CHANNEL_CONTROL_REQUEST_FLUSH = 3
    CHANNEL_CONTROL_REQUEST_CLOSE = 4 # this means to close the stream, not the channel
    CHANNEL_CONTROL_REQUEST_POSITION = 5
    CHANNEL_CONTROL_REQUEST_LENGTH = 6
    CHANNEL_CONTROL_REQUEST_READ_TIMEOUT = 7
    CHANNEL_CONTROL_REQUEST_WRITE_TIMEOUT = 8
    CHANNEL_CONTROL_REQUEST_SEEK = 9
    CHANNEL_CONTROL_REQUEST_WRITE = 10
    
    CHANNEL_CONTROL_INFORM_REMOTEBUFFER_LIMIT = 1001
    CHANNEL_CONTROL_INFORM_REMOTEBUFFER_SIZE = 1002
    CHANNEL_CONTROL_INFORM_WRITE_SUCCEEDED = 1003
    CHANNEL_CONTROL_INFORM_READ_SUCCEEDED = 1004
    CHANNEL_CONTROL_INFORM_WRITE_FAILED = 1005
    CHANNEL_CONTROL_INFORM_READ_FAILED = 1006
    CHANNEL_CONTROL_INFORM_FLUSH_SUCCEEDED = 1007
    CHANNEL_CONTROL_INFORM_FLUSH_FAILED = 1008 

    def __init__(self, channel_id, stream_id, passthrough = True):
        # stream attributes
        self.__can_read = False
        self.__can_seek = False
        self.__can_timeout = False
        self.__can_write = False
        self.__length = 0
        self.__position = 0
        self.__read_timeout = 0
        self.__write_timeout = 0
        self.__passthrough = passthrough
        if not passthrough:
            self.__write_condition = Condition()
            self.__read_condition = Condition()
            self.__flush_condition = Condition()
            self.__write_succeeded = False
            self.__read_succeeded = False
            self.__flush_succeeded = False
            self.__write_size = 0
            self.__read_size = 0
            self.__read_data = ""
        
        # internal attributes
        self.__stream_id = stream_id # id (hasCode) of the stream bound to this channel, if any
        self.__control_in_queue = Queue.Queue()
                
        # we start with a id of '-1' to indicate that the channel isn't bound to a remote stream
        # th channel is bidirectional, to allow control data to be sent (even it is a read only or write only stream)
        # encoding is BYTE (raw)
        super(StreamChannel, self).__init__(channel_id, Channel.TYPE_BIDIRECTIONAL, Channel.ENCODING_BYTEARRAY)

    @property
    def CanRead(self):
        return self.__can_read
    
    @property
    def CanSeek(self):
        return self.__can_seek

    @property
    def CanTimeout(self):
        return self.__can_timeout
    
    @property
    def CanWrite(self):
        return self.__can_write
    
    @property
    def Length(self):
        return self.__length
    
    @property
    def Position(self):
        return self.__position
    
    @Position.setter
    def Position(self, value):
        self.__position = value

    @property
    def ReadTimeout():
        return self.__read_timeout
    
    @ReadTimeout.setter
    def ReadTimeout(self, value):
        self.__read_timeout = value
        
    @property
    def WriteTimeout():
        return self.__write_timeout
    
    @WriteTimeout.setter
    def WriteTimeout(self, value):
        self.__write_timeout = value            

    def Close(self):
        control_msg = struct.pack("!I", StreamChannel.CHANNEL_CONTROL_REQUEST_CLOSE)
        self.__sendControlMessage(control_msg)
    
    def Dispose(self):
        pass
        
    def Flush(self):
        control_msg = struct.pack("!I", StreamChannel.CHANNEL_CONTROL_REQUEST_FLUSH)
        self.__sendControlMessage(control_msg)
        
        if not self.__passthrough:
            self.__flush_condition.acquire()
            self.__flush_condition.wait(timeout=None)
            succeeded =  self.__flush_succeeded
            self.__flush_condition.release()
            
            return succeeded
        
    def Read(self, count, timeout=0):
        # on demand read:
        #control_msg = struct.pack("!Iii", StreamChannel.CHANNEL_CONTROL_REQUEST_READ, count, timeout)
        #self.__sendControlMessage(control_msg)

        if self.__passthrough:
            if not self.hasInput():
                return ""
            return self.readInput()
        else:
             # if passthrough is disable, data is written as control message and an answer is expected
            control_msg = struct.pack("!Iii", StreamChannel.CHANNEL_CONTROL_REQUEST_READ, count,  timeout)
            self.__sendControlMessage(control_msg)
            
            # we wait till an answer is received (based on a condition)
            self.__read_condition.acquire()
            self.__read_condition.wait(timeout=None)
            #check if write succeeded
            succeeded = self.__read_succeeded
            read_size = self.__read_size
            read_data = self.__read_data
            self.__read_condition.release()
            
            if succeeded:
                return read_data
            else:
                raise ChannelException("Error reading from StreamChannel {0}".format(self.id))
                
    
    def ReadByte(self):
        pass
    
    def Seek(self, offset, origin):
        control_msg = struct.pack("!Iii", StreamChannel.CHANNEL_CONTROL_REQUEST_SEEK, offset, origin)
        self.__sendControlMessage(control_msg)
    
    def Write(self, data):
        res = self.__writeData(data)
        if not self.__passthrough:
            return res
    
    def WriteByte(self, byte):
        res = self.__writeData(byte)
        if not self.__passthrough:
            return res
        
    def __writeData(self, data):
        if self.__passthrough:
            # in passthrough mode data is written as dedicated data message
            header = struct.pack("!B", 0)  # header byte 0 indicates that data is written 
            super(StreamChannel, self).writeOutput(header + data)
        else:
            # if passthrough is disable, data is written as control message and an answer is expected
            control_msg = struct.pack("!Ii", StreamChannel.CHANNEL_CONTROL_REQUEST_WRITE, len(data))
            control_msg += data
            self.__sendControlMessage(control_msg)
            
            # we wait till an answer is received (based on a condition)
            self.__write_condition.acquire()
            self.__write_condition.wait(timeout=None)
            #check if write succeeded
            succeeded = self.__write_succeeded
            write_size = self.__write_size
            self.__write_condition.release()
            
            if succeeded:
                return write_size
            else:
                return -1 # indicate write error (alternatively a ChannelException could be raised)
            
            
        
        
    def __sendControlMessage(self, control_data):
        header = struct.pack("!B", 1)  # header byte 1 indicates that control data
        # naive, if the queue is full, that message is pending as it hasn't been priorized
        super(StreamChannel, self).writeOutput(header + control_data)
        
    def writeOutput(self, data):
        res = self.__writeData(data)
        if not self.__passthrough:
            return res
        
    #def readInput(self):
        #print "StreamChannel error: writeOutput shouldn't be called, use Write instead"
        
    def enqueueInput(self, data):
        data_type = struct.unpack("!B", data[0])[0]
        data = data[1:]
        
        if data_type == 0:
            self._Channel__in_queue.put(data) # normal data
        else:
            self.__dispatchControlMessage(data) # control data
        
    def __dispatchControlMessage(self, control_data):
        #print "Channel with id '{0}' received control data: {1}".format(self.id, repr(control_data))
        # grab control_msg id
        control_msg = struct.unpack("!I", control_data[:4])[0]
        data =  control_data[4:]
        if control_msg == self.CHANNEL_CONTROL_INFORM_WRITE_FAILED:
            # set event for write operation response
            self.__write_condition.acquire()
            self.__write_succeeded = False
            self.__write_condition.notifyAll()
            self.__write_condition.release()
        elif control_msg == self.CHANNEL_CONTROL_INFORM_WRITE_SUCCEEDED:
            # read how many bytes have been written
            size_written = struct.unpack("!i", data[:4])[0]
            
            # set event for write operation response
            self.__write_condition.acquire()
            self.__write_size =  size_written
            self.__write_succeeded = True
            self.__write_condition.notifyAll()
            self.__write_condition.release()
        elif control_msg == self.CHANNEL_CONTROL_INFORM_READ_SUCCEEDED:
            # read how many bytes have been read
            size_read = struct.unpack("!i", data[:4])[0]
            data_read = data[4:]
        
            # set event for read operation response
            self.__read_condition.acquire()
            self.__read_size = size_read
            self.__read_data = data_read
            self.__read_succeeded = True
            self.__read_condition.notifyAll()
            self.__read_condition.release()
        elif control_msg == self.CHANNEL_CONTROL_INFORM_READ_FAILED:
            # set event for read operation response
            self.__read_condition.acquire()
            self.__read_succeeded = False
            self.__read_condition.notifyAll()
            self.__read_condition.release()                        
        elif control_msg == self.CHANNEL_CONTROL_INFORM_FLUSH_SUCCEEDED:
            self.__flush_condition.acquire()
            self.__flush_succeeded = True
            self.__flush_condition.notifyAll()
            self.__flush_condition.release()            
        elif control_msg == self.CHANNEL_CONTROL_INFORM_FLUSH_FAILED:
            self.__flush_condition.acquire()
            self.__flush_succeeded = False
            self.__flush_condition.notifyAll()
            self.__flush_condition.release()
            
    
    def onClose(self):
        if not self.__passthrough:
            # set error for pending writes
            self.__write_condition.acquire()
            self.__write_succeeded = False
            self.__write_condition.notifyAll()
            self.__write_condition.release()            
            # set error for pending reads
            self.__read_condition.acquire()
            self.__read_succeeded = False
            self.__read_condition.notifyAll()
            self.__read_condition.release()
        super(StreamChannel, self).onClose()
        

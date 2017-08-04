import Queue
from FileSystem import FileSystem
import struct

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
        if self.type == Channel.TYPE_IN:
            Channel.print_debug("Couldn't check channel {0} for pending output, this is an INPUT channel".format(self.id))
            return False

        if self.__out_queue.qsize() > 0:
            return True
        else:
            return False
        
    def onClose(self):
        self.__isClosed = True
        print "Channel ID {0} onClose called".format(self.id)
    

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
    
    CHANNEL_CONTROL_INFORM_REMOTEBUFFER_LIMIT = 1001
    CHANNEL_CONTROL_INFORM_REMOTEBUFFER_SIZE = 1002    

    def __init__(self, channel_id, stream_id):
        # stream attributes
        self.__can_read = False
        self.__can_seek = False
        self.__can_timeout = False
        self.__can_write = False
        self.__length = 0
        self.__position = 0
        self.__read_timeout = 0
        self.__write_timeout = 0
        
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
        
    def Read(self, count, timeout=0):
        # on demand read:
        #control_msg = struct.pack("!Iii", StreamChannel.CHANNEL_CONTROL_REQUEST_READ, count, timeout)
        #self.__sendControlMessage(control_msg)

        return self.readInput()
    
    def ReadByte(self):
        pass
    
    def Seek(self, offset, origin):
        control_msg = struct.pack("!Iii", StreamChannel.CHANNEL_CONTROL_REQUEST_SEEK, offset, origin)
        self.__sendControlMessage(control_msg)
    
    def Write(self, data):
        self.__writeData(data)
    
    def WriteByte(self, byte):
        self.__writeData(byte)
        
    def __writeData(self, data):
        header = struct.pack("!B", 0)  # header byte 0 indicates that data is written 
        super(StreamChannel, self).writeOutput(header + data)
        
    def __sendControlMessage(self, control_data):
        header = struct.pack("!B", 1)  # header byte 1 indicates that control data
        # naive, if the queue is full, that message is pending as it hasn't been priorized
        super(StreamChannel, self).writeOutput(header + control_data)
        
    def writeOutput(self, data):
        self.__writeData(data)
        
        
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
        print "Channel with id '{0}' received control data: {1}".format(self.id, repr(control_data))
        
    

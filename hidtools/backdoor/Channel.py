import Queue

class Channel(object):
    TYPE_IN = 1 
    TYPE_OUT = 2
    TYPE_BIDIRECTIONAL = 3

    ENCODING_UTF8 = 1
    ENCODING_BYTEARRAY = 2

    DEBUG = False

    interact = False

    def __init__(self, id, type, encoding):
        self.id = id
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
            Channel.print_debug("Couldn't write output to input channel {0}".format(self.id))
            return

        return self.__out_queue.get()
        #pass

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

class FileChannel(Channel):
    '''
    Implementation of a channel dedicated to File Transfer (upload + download)
    '''
    
    READ_CUNK_SIZE = 30000
    FILEMODE_READ = "rb"
    FILEMODE_WRITE = "wb"
    FILEMODE_READWRITE = "r+b"
    FILEMODE_APPEND = "ab"
    
    def __init__(self, id, encoding,  fileName, fileMode):
        _type = Channel.TYPE_BIDIRECTIONAL
        if fileMode == FileChannel.FILEMODE_READ:
            _type = Channel.TYPE_OUT
        elif fileMode == FileChannel.FILEMODE_WRITE or fileMode == FileChannel.FILEMODE_APPEND:
            _type = Channel.TYPE_IN
            
        # before creating the channel, FileAccess is checked and an error thrown if needed
        
            
        Channel.__init__(self, id, _type, encoding)
        self.filename = fileName
        self.filemode = fileMode
        
    
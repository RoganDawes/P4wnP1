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


from pydispatch import dispatcher
from LinkLayer import LinkLayer
from threading import current_thread
import Queue

class TransportLayer():
        """
        Interfaces with LinkLayer via pydispatcher
        """

        DEBUG = False

        
        #SIGNAL_LINKLAYER_STARTED = "LinkLayerStarted"
        #SIGNAL_LINKLAYER_SYNCING = "LinkLayerSyncing"
        #SIGNAL_LINKLAYER_SYNCED = "LinkLayerSynced"
        #SIGNAL_LINKLAYER_CONNECTION_RESET = "LinkLayerConnectionReset"
        #SIGNAL_LINKLAYER_CONNECTION_ESTABLISHED = "LinkLayerConnectionEstablished"
        #SIGNAL_LINKLAYER_CONNECTION_TIMEOUT = "LinkLayerConnectionTimeout"
        #SIGNAL_LINKLAYER_STOPPING = "LinkLayerStopping"
        #SIGNAL_LINKLAYER_STOPPED = "LinkLayerStopped"
        #SIGNAL_LINKLAYER_STREAM_ENQUEUED = "LinkLayerStreamEnqueued"

        TRANSPORTLAYER_SENDER_NAME_DOWN = "TransportLayer"
        TRANSPORTLAYER_SENDER_NAME_UP = "TransportLayerUp"
        SIGNAL_TRANSPORTLAYER_SEND_STREAM = "TransportLayerSendStream"
        SIGNAL_TRANSPORTLAYER_CLIENT_CONNECTED_LINKLAYER = "TransportLayerClientConnectedLinkLayer"
        SIGNAL_TRANSPORTLAYER_WAITING_FOR_CLIENT_LINKLAYER = "TransportLayerWaitingForClient"
        SIGNAL_TRANSPORTLAYER_CONNECTION_RESET_LINKLAYER = "TransportLayerConnectionResetLinkLayer"
        SIGNAL_TRANSPORTLAYER_CONNECTION_TIMEOUT_LINKLAYER = "TransportLayerConnectionTimeoutLinkLayer"

        def __init__(self):
                # create queue for incoming streams to decouple processing from link layer reader thread
                self.stream_in_queue = Queue.Queue()

                # register Listener for LinkLayer signals
                dispatcher.connect(self.handle_link_layer, sender="LinkLayer")

        def write_stream(self, stream):
                self.__write_raw_stream(stream)

        def __write_raw_stream(self, stream):
                # should keep track of LinkLayer's output queue size (needs additional dispatcher messages)
                dispatcher.send(data = stream, signal = TransportLayer.SIGNAL_TRANSPORTLAYER_SEND_STREAM, sender = TransportLayer.TRANSPORTLAYER_SENDER_NAME_DOWN)

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

                if signal == LinkLayer.SIGNAL_LINKLAYER_STREAM_RECEIVED:
                        # enqueue stream data
                        #print "TransportLayer: stream from LinkLayer enqueued (Thread: " + current_thread().getName() + ")"
                        self.stream_in_queue.put(data)
                elif signal == LinkLayer.SIGNAL_LINKLAYER_CONNECTION_RESET:
                        TransportLayer.print_debug("Received connection reset")
                        dispatcher.send(data = "Connection reset from from client received via LinkLayer", signal = TransportLayer.SIGNAL_TRANSPORTLAYER_CONNECTION_RESET_LINKLAYER, sender = TransportLayer.TRANSPORTLAYER_SENDER_NAME_UP)
                elif signal == LinkLayer.SIGNAL_LINKLAYER_SYNCING:
                        #print "TransportLayer: Waiting for client connection via HID..."		
                        dispatcher.send(data = "Waiting for Client conection to LinkLayer via HID", signal = TransportLayer.SIGNAL_TRANSPORTLAYER_WAITING_FOR_CLIENT_LINKLAYER, sender = TransportLayer.TRANSPORTLAYER_SENDER_NAME_UP)
                elif signal == LinkLayer.SIGNAL_LINKLAYER_SYNCED:
                        # fire event		
                        dispatcher.send(data = "Client connected via HID to LinkLayer", signal = TransportLayer.SIGNAL_TRANSPORTLAYER_CLIENT_CONNECTED_LINKLAYER, sender = TransportLayer.TRANSPORTLAYER_SENDER_NAME_UP)
                elif signal == LinkLayer.SIGNAL_LINKLAYER_CONNECTION_TIMEOUT:
                        # no client data received for 100 ms, send connection timeout to upper layer
                        dispatcher.send(data = data, signal = TransportLayer.SIGNAL_TRANSPORTLAYER_CONNECTION_TIMEOUT_LINKLAYER, sender = TransportLayer.TRANSPORTLAYER_SENDER_NAME_UP)
                else:
                        TransportLayer.print_debug("TransportLayer: Unhandled singnal from LinkLayer processed by thread: " + current_thread().getName())
                        TransportLayer.print_debug("TransportLayer: signal: " + signal + ", data: " + repr(data[:100]))



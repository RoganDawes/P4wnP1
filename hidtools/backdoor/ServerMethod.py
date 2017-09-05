
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


from StructHelper import StructHelper
import struct

class ServerMethod:
    def __init__(self, id, name, args):
        self.id = id
        self.name = name
        self.args = args
        self.isStarted = False
        self.hasFinished = False
        self.result = None
        self.hasError = False
        self.errorMessage = ""
        
    @staticmethod
    def createFromRunMethodMessage(message_data):
        # extract method ID
        id = struct.unpack("!I", message_data)
        message_data = message_data[4:]
        
        # extract method name
        name, message_data = StructHelper.extractNullTerminatedString(message_data)
        
        # remaining method data represents the args
        args = message_data
        
        return ServerMethod(id, name, args)
    
    def setError(self, errMsg):
        self.hasError = True
        self.errorMessage = errMsg
        self.hasFinished = True
        
    def setResult(self, result):
        if result == None:
            self.setError("Server method '{0}' has been called, but returned no result", self.name)
            return
        self.result = result
        self.hasFinished = True
        
    def createResponse(self):
        # this should only be called when the server method finished execution (we don't check this condition)
        response = struct.pack("!I", self.id)
        if (self.hasError):
            response += struct.pack("!B{0}sx".format(len(self.errorMessage)), 1, self.errorMessage)
            return response
        
        response += struct.pack("!B{0}", 0)
        response += self.result
        return response
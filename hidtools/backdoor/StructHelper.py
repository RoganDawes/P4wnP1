import struct

class StructHelper:
    @staticmethod
    def extractNullTerminatedString(data):
        parts = data.split('\x00',1)
        if len(parts) == 1:
            return [parts[0],""]
        else:
            return parts
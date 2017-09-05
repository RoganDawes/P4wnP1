
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


import os
import sys

class FileMode:
    CreateNew = 1       # create a new file. If the file already exists, an exception will be thrown
    Create = 2          # Create a new file. If the file already exists, it will be overwritten
    Open = 3            # Open an existing file. If the file doesn't exist, an exception will be thrown
    OpenOrCreate = 4    # Open an existing file. Create it if it doesnt exist.
    Truncate = 5        # unused
    Append = 6          # Opens the file if it exists and seeks to the end of the file, or creates a new file.
    
class FileAccess:
    Read = 1
    Write = 2
    ReadWrite = 3 

class FileSystem:
    def __init__(self):
        pass
    
    @staticmethod
    def open_local_file(filename, fileMode, fileAccess):
        # open the file
       
        # before obening the file, FileAccess is checked and an error thrown if needed
        resfile = None
        exists = FileSystem.fileExists(filename)

        if fileAccess == FileAccess.Read:
    
            if fileMode == FileMode.Append:
                raise Exception("FileMode append choosen for '{0}', but this could only be used in conjuction with 'FileAccess.Write'!".format(filename))
            elif fileMode == FileMode.Create:
                # overwrite if exists
                resfile= open(filename, "wb").truncate(0)
                resfile.close()
                # open for read
                resfile= open(filename, "rb")
            elif fileMode == FileMode.CreateNew:
                if exists:
                    raise Exception("File '{0}' already exists!".format(filename))
                else:
                    resfile= open(filename, "wb")
                    resfile.close()                    
                    resfile= open(filename, "rb")
            elif fileMode == FileMode.Open:
                if exists:
                    resfile= open(filename, "rb")
                else:
                    raise Exception("File '{0}' not found!".format(filename))
            elif fileMode == FileMode.OpenOrCreate:
                if exists:
                    resfile= open(filename, "rb")
                else:                
                    resfile= open(filename, "wb")
                    resfile.close()                    
                    resfile= open(filename, "rb")                
            elif fileMode == FileMode.Truncate:
                resfile= open(filename, "wb")
                resfile.truncate()
                resfile.close()
                resfile= open(filename, "rb")                
            else:
                raise Exception("Unknown FileMode type for '{0}'!".format(filename))
    
        elif fileAccess ==  FileAccess.Write:
    
            if fileMode == FileMode.Append:
                resfile= open(filename, "ab")
            elif fileMode == FileMode.Create:
                resfile= open(filename, "wb")
            elif fileMode == FileMode.CreateNew:
                if exists:
                    raise Exception("File '{0}' already exists!".format(filename))
                else:
                    resfile= open(filename, "wb")
            elif fileMode == FileMode.Open:
                if exists:
                    # not sure.. should this be disallowed or changed to append
                    resfile= open(filename, "wb")
                else:
                    raise Exception("resfile'{0}' not found!".format(filename))
            elif fileMode == FileMode.OpenOrCreate:
                # should maybe disallowed, reflects the behavior of create, but the name doesn't imply that the file gets overwritten
                resfile= open(filename, "wb")
            elif fileMode == FileMode.Truncate:
                resfile= open(filename, "wb")
                resfile.truncate()
            else:
                raise Exception("Unknown FileMode type for '{0}'!".format(filename))            
    
        elif fileAccess ==  FileAccess.ReadWrite:
    
            if fileMode == FileMode.Append:
                raise Exception("FileMode append choosen for '{0}', but this could only be used in conjuction with 'FileAccess.Write'!".format(filename))
            elif fileMode == FileMode.Create:
                resfile= open(filename, "w+b")
            elif fileMode == FileMode.CreateNew:
                if exists:
                    raise Exception("File '{0}' already exists!".format(filename))
                else:
                    resfile= open(filename, "w+b")
            elif fileMode == FileMode.Open:
                if exists:
                    resfile= open(filename, "w+b")
                else:
                    raise Exception("File '{0}' not found!".format(filename))
            elif fileMode == FileMode.OpenOrCreate:
                resfile= open(filename, "w+b")
            elif fileMode == FileMode.Truncate:
                resfile= open(filename, "w+b")
                resfile.truncate()
            else:
                raise Exception("Unknown FileMode type for '{0}'!".format(filename))
        else:
            raise Exception("Unknown FileAccess type for '{0}'!".format(filename))
        
        return resfile
    
    @staticmethod
    def pwd():
        return os.getcwd()
    
    @staticmethod
    def cd(tdir):
        try:
            os.chdir(tdir)
        except OSError:
            ex =  sys.exc_value
            print ex
        return os.getcwd()    

    @staticmethod
    def ls(tdir = "."):
        res =  ""
        try:
            res = os.listdir(tdir)
        except OSError:
            res =  sys.exc_value
        return res
    
    @staticmethod
    def ls_native(tdir = ".",  args = []):
        res =  ""
        import subprocess
        subprocess.call(["ls"]+args)
    
    @staticmethod
    def ls_native2(args = []):
        res =  ""
        from subprocess import PIPE, Popen
        
        pls = Popen(["ls"]+args, stdout=PIPE, 
                   stderr=PIPE, 
                   close_fds=True)
        return [fn.rstrip("\n") for fn in pls.stdout.readlines()] + [fn.rstrip("\n") for fn in pls.stderr.readlines()]
    
    @staticmethod
    def readFile(filename):
        data = ""
        with open(filename, "rb") as f:
            data =  f.read()
        return data
    
    @staticmethod
    def readFileChunks(filename, chunknum, chunksize=10000):
        pos = chunknum * chunksize
        data =  ""
        with open(filename, "rb") as f:
            f.seek(pos)
            data = f.read(chunksize)
        return data
    
    @staticmethod
    def writeFile(filename, data=""):
        with open(filename, "wb") as f:
            f.write(data)
    
    @staticmethod
    def appendFile(filename, data=""):
        with open(filename, "ab") as f:
            f.write(data)
    
    @staticmethod
    def fileExists(filename):
        return os.path.isfile(filename)

    @staticmethod
    def delFile(filename):
        os.remove(filename)
        
    @staticmethod
    def getFileName(path):
        return os.path.basename(path)
    
#fs =  FileSystem()
#fs.writeFile("test", '\x00'*10)
#fs.appendFile("test", '\x01'*10)
#fs.appendFile("test", '\x02'*10)
#fs.appendFile("test", '\x03'*5)
#for i in range(5):
    #print repr(fs.readFileChunks("test", i, 10))

               


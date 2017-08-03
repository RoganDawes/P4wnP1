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

               


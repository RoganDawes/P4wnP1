import os
import sys

class FileSystem:
    def __init__(self):
        pass
    
    def pwd(self):
        return os.getcwd()
    
    def cd(self,  tdir):
        try:
            os.chdir(tdir)
        except OSError:
            ex =  sys.exc_value
            print ex
        return os.getcwd()    

    def ls(self,  tdir = "."):
        res =  ""
        try:
            res = os.listdir(tdir)
        except OSError:
            res =  sys.exc_value
        return res
    
    def ls_native(self,  tdir = ".",  args = []):
        res =  ""
        import subprocess
        subprocess.call(["ls"]+args)
    
    def ls_native2(self, args = []):
        res =  ""
        from subprocess import PIPE, Popen
        
        pls = Popen(["ls"]+args, stdout=PIPE, 
                   stderr=PIPE, 
                   close_fds=True)
        return [fn.rstrip("\n") for fn in pls.stdout.readlines()] + [fn.rstrip("\n") for fn in pls.stderr.readlines()]
    
    def readFile(self, filename):
        data = ""
        with open(filename, "rb") as f:
            data =  f.read()
        return data
    
    def readFileChunks(self, filename, chunknum, chunksize=10000):
        pos = chunknum * chunksize
        data =  ""
        with open(filename, "rb") as f:
            f.seek(pos)
            data = f.read(chunksize)
        return data
    
    def writeFile(self, filename, data=""):
        with open(filename, "wb") as f:
            f.write(data)
    
    def appendFile(self, filename, data=""):
        with open(filename, "ab") as f:
            f.write(data)
    
    def fileExists(self, filename):
        return os.path.isfile(filename)

    def delFile(self, filename):
        os.remove(filename)
    
#fs =  FileSystem()
#fs.writeFile("test", '\x00'*10)
#fs.appendFile("test", '\x01'*10)
#fs.appendFile("test", '\x02'*10)
#fs.appendFile("test", '\x03'*5)
#for i in range(5):
    #print repr(fs.readFileChunks("test", i, 10))

               


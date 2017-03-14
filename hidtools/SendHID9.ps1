# P4wnP1 HID Script
# 1) enumerates HID devices via WMI and finds P4wnP1 (based on VID and PID)
# 2) Creates a devicepath from the PNPDeviceID of the HID device
# 3) Creates a Filestream to the devicepath
# 4) Writes Testdata to the device, respecting the output report descriptor (64 bytes, no report ID)
#
# To acomplish step 3, the CreateFile method from kernel32.dll has to be accessed
# This could for instance be done by a native C# import.
# As P4wnP1 tries to avoid the footprint of compiling C# code (and thus writing temporary data to disc)
# a Reflection approach is used to generate the native method import
# Reference: https://blogs.technet.microsoft.com/heyscriptingguy/2013/06/27/use-powershell-to-interact-with-the-windows-api-part-3/

# Note on data exchange via HID reports
#    Although the report contains an input and output array, filling one of them
#    (either INPUT or OUTPUT) overwrites the whole report.
#    This means if either the HOST or the DEVICE writes data to a report, data
#    written by the other endpoint gets erased if it hasn't been readen already.
#    To cope with that, the following communication scheme will be deployed.
#      - only one Endpoint is allowed to start communication
#      - the Endpoint starting communication will always be the HOST (thus we already
#        knew the target can talk HID)
#      - The USB Device (P4wnP1) starts reading data (read, write, read, write ...)
#      - The USB Host starts writing data (write, read, write, read ...)
#      - both endpoints altenate from reading to writing / writing reading in an endless
#        loop
#      - thus there's permanent communication, !!initiated by the host!!
#      - to achieve bidirectional communication, both side acknowledge how much payload data 
#        has been received (rcv) and sent (snd) in EVERY packet
#      - to be more clear: if an endpoint receives data, it has to answer. If the receiving endpoint
#        doesn't want to send data itself, the snd field of the answer has size 0 (no payload). The rcv
#        field hold the size of the payload received on last read.
#      - read is a blocking call on both side. In every state of comunictaion, one endpoit is in blocking
#        read mode, while waiting for the other endpoint to send. If the endpoint in read mode wants to send 
#        data itself, it has to wait till the other endpoint sends data, to pack its own (ready to send) data 
#        into the answer.
#      - to achieve permanent and instant communication, the endpoint which is in send state ALWAYS sends
#        a packet, no matter if there's data which should get delivered (snd field = 0 if no data).
#      - data which should be delivered has to be buffered in a queue. If there's data in the queue, it will be packed
#        into the payload of the next packet which is going to be sent, until the queue is empty.
#      - both endpoints run an endless loop of sending and receiving. Because the IO operations are slow, there
#        is no need to deploy a sleep in these loops - the respective CPUs have enough idle time.
#        Sending 64 KByte of raw data takes about 20 seconds (while parsing it, printing it out and echo it back
#        on the other endpoint). Thus data transfer rate is about 3,2 KByte/s (synchronous, no further operation on raw data).
#      - The transfer rate isn't high, but should be enoug for text (console data)
# The maximum count of the HID report arrays has to be tested, in order to increase transfer rate.


# packet format
#   0: report id (always 0)
#   1: src   source channel (like source port, but only 0-255)
#   2: dst   destiantion channel (like destination port, but only 0-255)
#   3: snd   length of payload which gets sent in this packet
#   4: rcv   length of payload which has been read in last packet
#   5-64:    payload send

# code for a python echo server:

# !/usr/bin/python
# import sys
#
# with open("/dev/hidg1","r+b") as f:
#         while True:
#                 hidin = f.read(0x40)
#                 print "Input received (" + str(len(hidin)) + " bytes):"
#                 print hidin.encode("hex")
#                 # echo back
#                 f.write(hidin)

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
    #$cr = $devfile.Read($r,0,65)
    # a normal read as used above is a blocking call
    # so we wouldn't be able to send own data, untin the other side sends something
    # this should be avoided by using a heartbeat, to asure permanent packet exchange
    # a heart beat is sent with
    #    src = 0
    #    dst = 0
    #    payload = ""
    $asyncReadResult = $devfile.BeginRead($r, 0, 65, $null, $null)
    while (-not $asyncReadResult.IsCompleted)
    {
        # Sending heartbeat data if needed, heartbeat otherwise
        $heartbeat = New-Object Byte[] (0)
        #send_data $devfile 0 0 $heartbeat 0
    }
    $cr = $devfile.EndRead($asyncReadResult)
    

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

function L4fragment_rcvd($qin, $fragment_assembler, $src, $dst, $data)
{
    # Create ID for fragment (string)
    $stream_id = "$src $dst"
    # if src and dst both 0, ignore (heartbeat)
    if ($src -ne 0 -or $dst -ne 0)
    {
        # this is not a heartbeat (src or dst not 0) so we handle it as stream data
        # check if stream_id is existent
        if ($fragment_assembler.ContainsKey($stream_id))
        {
            # stream already present
            # check if stream closing data packet (payload length = 0)
            if ($data.Length -eq 0)
            {
                # end of this stream
                $stream = $src, $dst, $fragment_assembler[$stream_id][2]
                # add stream to input queue
                $qin.Enqueue($stream)
                # remove stream from fragment_assembler
                $fragment_assembler.Remove($stream_id)
            }
            else
            {
                # new data for existing stream, append
                $old_data = $fragment_assembler[$stream_id][2]
                $new_data = New-Object Byte[] ($data.Length + $old_data.Length)
                # concating static arrays, could be done better
                [System.Buffer]::BlockCopy($old_data, 0, $new_data, 0, $old_data.Length)
                [System.Buffer]::BlockCopy($data, 0, $new_data, $old_data.Length, $data.Length)
                $fragment_assembler[$stream_id][2] = $new_data
                
                # do we have to destroy old arrays ? We hope for the garbage collector to work properbly
            }
        }
        else
        {
            # new stream_id, we have to add a new stream to collect fragments
            $fragment_assembler.Add($stream_id, ($src, $dst, $data))
        }
        
    }
}

function L4send_datastream($qout, $src, $dst, $data)
{
    $chunksize = 60

    for ($offset=0; $offset -lt $data.Length; $offset+=$chunksize)
    {
        $remaining = $data.Length - $offset
        $remaining = [System.Math]::Min($chunksize, $remaining)
        $chunk_data = New-Object Byte[] ($remaining)
        [System.Buffer]::BlockCopy($data, $offset, $chunk_data, 0, $remaining)
        
        $chunk = $src, $dst, $chunk_data
        # add chunk to output queue
        $qout.Enqueue($chunk)
    }
    # add terminating 0 packet
    $chunk_data = New-Object Byte[] (0)
    $chunk = $src, $dst, $chunk_data
    # add chunk to output queue
    $qout.Enqueue($chunk)
}


$script_mainloop = {

    # needs:
    # $devfile
    # $L4qin
    # $L4qout
    # send_data
    # L4fragment_rcvd

    $L4fragment_assembler = @{}
    $last_rcv = 0

    $empty = New-Object Byte[] (0)
    send_data $devfile 0 0 $empty $last_rcv


    while ($devfile.SafeFileHandle -ne $null)
    {
            
        # if output data
        if ($L4qout.Count -gt 0)
        {
            $chunk = $L4qout.Dequeue()
            send_data $devfile $chunk[0] $chunk[1] $chunk[2] $last_rcv
        }
        else
        {
            # send empty packet
            
            send_data $devfile 0 0 $empty $last_rcv
        }

        
        $packet = read_data $devfile
        # set RCV to SND to acknowledge full packet in next send
        $src = $packet[0]
        $dst = $packet[1]
        $snd = $packet[2]
        $rcv = $packet[3]
        $msg = $packet[4]
        
        L4fragment_rcvd $L4qin $L4fragment_assembler $src $dst $msg
        
        $last_rcv = $snd
        
        # convert data payload to ASCII
        #$msg_ascii = [System.Text.Encoding]::ASCII.GetString($msg)
        #"Received packet, SRC: " + $src + " DST: " + $dst + " SND: " + $snd + " RCV: " + $rcv
        #"Payload: $msg_ascii"
        
    
    }
}

$script_hid_in_loop = {
    # handle inpput data
    while ($true)
    {
        # $hostui.WriteLine("loop") # testoutput to check if thread isn't blocked
        if ($L4qin.Count -gt 0)
        {
            $input = $L4qin.Dequeue()
            $src = $input[0]
            $dst = $input[1]
            $stream = $input[2]
            #$hostui.WriteLine("Stream in input queue src $src dst $dst")
            $hostui.WriteLine([System.Text.Encoding]::UTF8.GetString($stream))
        } 
    }
}

#######
# Init RAW HID device
#########

# Use Reflection to create [MaMe82]::CreateFile from kernel32.dll
$MaMe82Class = ReflectCreateFileMethod
# Device Path, could be enumerate via WMI
$USB_VID="1D6B"
$USB_PID="0137"
$path= GetDevicePath $USB_VID $USB_PID
# create FileStream to device
$devfile = CreateFileStreamFromDevicePath $MaMe82Class $path



# Objects used by Layer4 communication (should be added to stage2 script to save space)
$L4qin = New-Object System.Collections.Queue
$L4qout = New-Object System.Collections.Queue



#######
# Prepare Threads
#######

# create session state with needed functions for runspace

#$iss = [initialsessionstate]::Create()
$iss = [InitialSessionState]::CreateDefault()

$def_read_data = Get-Content Function:\read_data -ErrorAction Stop
$ssfe_read_data = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList ‘read_data’, $def_read_data
$iss.Commands.Add($ssfe_read_data)

$def_send_data = Get-Content Function:\send_data -ErrorAction Stop
$ssfe_send_data = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList ‘send_data’, $def_send_data
$iss.Commands.Add($ssfe_send_data)
$def_fragment_rcvd = Get-Content Function:\L4fragment_rcvd -ErrorAction Stop
$ssfe_fragment_rcvd = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList ‘L4fragment_rcvd’, $def_fragment_rcvd
$iss.Commands.Add($ssfe_fragment_rcvd)

# create runspace for main thread
$rs = [runspacefactory]::CreateRunspace($iss)
$rs.Open()
$rs.SessionStateProxy.SetVariable("devfile", $devfile)
$rs.SessionStateProxy.SetVariable("L4qin", $L4qin)
$rs.SessionStateProxy.SetVariable("L4qout", $L4qout)

# create runspace for HID input handling thread
$rs_hid_in = [runspacefactory]::CreateRunspace($iss)
$rs_hid_in.Open()
$rs_hid_in.SessionStateProxy.SetVariable("L4qin", $L4qin)
$rs_hid_in.SessionStateProxy.SetVariable("hostui", $Host.UI)


# create main loop PS thread
$ps_main = [powershell]::Create()
$ps_main.Runspace = $rs
[void]$ps_main.AddScript($script_mainloop)

# create HID input handling loop PS thread
$ps_hid_in = [powershell]::Create()
$ps_hid_in.Runspace = $rs_hid_in
[void]$ps_hid_in.AddScript($script_hid_in_loop)

# start main thread
$handle_main = $ps_main.BeginInvoke()

# start HID input handling thread
$handle_hid_in = $ps_hid_in.BeginInvoke()


# Enque some outbound test data
$msg="Hello to P4wnP1, this message got has been sent through the HID interface!"
$testdata=[system.Text.Encoding]::UTF8.GetBytes($msg)
L4send_datastream $L4qout 3 4 $testdata

# CTRL - c handling (to pipe through HID) see here: http://stackoverflow.com/questions/1710698/gracefully-stopping-in-powershell
# for now we use try / catch / finally
# finally assures the runspaces (threads) are killed 


# HID output loop (console input loop)
try 
{
    # the try block is only needed to run the finally block and destroy threads on unexpected exit (CTRL+C, exit command ...)

    # Sleep to allow HID in thread to print output, before prompt is shown
    Start-Sleep 1

    $host.UI.WriteLine("P4wnP1 HID Shell  by MaMe82")
    $host.UI.WriteLine("===========================")
    $host.UI.WriteLine("")
    $host.UI.WriteLine("Use '!!!' to run powershell commands.")
    $host.UI.WriteLine("Example: !!!Get-Date")
    $host.UI.WriteLine("")

    #Write-Host -NoNewline "P4wnP1 HID Shell >> "
    
    while ($true)
    {
        # !! read-host seems to block the UI and thus the HID_in thread, when i tries to print out data
        # this could be circumvented by checking console input for "keyAvailable"
        # the shortcoming is, that this couldn't be used on ISE
        if ([Console]::KeyAvailable) 
        { 
            $in = read-host  
            # exit loop if input is "exit"
            if ($in -eq "exit") { break }
            if ($in.StartsWith("!!"))
            {
                $pscommand = $in.Split("!!")[2]
                if ($pscommand.Length -gt 0) { iex $pscommand }
            }
            else
            {
                $inbytes =[system.Text.Encoding]::UTF8.GetBytes($in)
                L4send_datastream $L4qout 1 1 $inbytes
            }
            #Write-Host -NoNewline "P4wnP1 HID Shell >> "
        }
    }
}
finally
{
    # end main thread
    $ps_hid_in.Stop()
    $ps_hid_in.Dispose()
    $ps_main.Stop()
    $ps_main.Dispose()
    $devfile.Close()
    $devfile.Dispose()
}
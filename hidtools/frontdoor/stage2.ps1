
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
                $ms = $fragment_assembler[$stream_id][2]
                $ms.Flush()
                
                $whandle = $fragment_assembler[$stream_id][3] # restore IAsyncResult of last write to MemoryStream
                $ms.EndWrite($whandle) # finish pending writes

                $stream = $src, $dst, $ms.ToArray()
                $ms.Close()
                $ms.Dispose()
                # add stream to input queue
                $qin.Enqueue($stream)
                # remove stream from fragment_assembler
                $fragment_assembler.Remove($stream_id)
            }
            else
            {
                # new data for existing stream, append
                $ms = $fragment_assembler[$stream_id][2]
                #$ms.WriteAsync($data, 0, $data.Length) # WriteAsync is a nice idea, but not available on NET 3.5 (PS 2.0)
#[Console]::WriteLine($ms.Position)
                $whandle = $fragment_assembler[$stream_id][3] # restore IAsyncResult of last write to MemoryStream
                $ms.EndWrite($whandle) # finish pending writes
                $whandle = $ms.BeginWrite($data, 0, $data.Length, $null, $null) 
                $fragment_assembler[$stream_id][3] = $whandle # store new whandle
#[Console]::WriteLine($ms.Position)
            }
        }
        else
        {
            # new stream_id, we have to add a new stream to collect fragments
            $ms = New-Object System.IO.MemoryStream
            #$ms.WriteAsync($data, 0, $data.Length) # WriteAsync is a nice idea, but not available on NET 3.5 (PS 2.0)
            $whandle = $ms.BeginWrite($data, 0, $data.Length, $null, $null) # AsyncWrite is a nice idea, but not available on NET 3.5 (PS 2.0)
#[Console]::WriteLine($data.Length)
#[Console]::WriteLine($ms.Position)
            $fragment_assembler.Add($stream_id, ($src, $dst, $ms, $whandle))
        }    
    }
    else
    {
        # heartbeat... do nothing
        #$msg = [System.Text.Encoding]::UTF8.GetString($data)
        #[System.Console]::WriteLine("Heartbeatdata: $msg")
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
    # handle input data
    # dst=1   stdin (not used, we don't allow P4wnP1 server to give input at the moment)
    # dst=2   stdout
    # dst=3   stderr
    # dst=4   getfile
    # dst=?   print unknown stream

    $beginfile=[System.Text.Encoding]::ASCII.GetBytes("BEGINFILE")
    $endfile=[System.Text.Encoding]::ASCII.GetBytes("ENDFILE")
    $filercv_running = $false # this is only true while a file is received on dst=4 (from BEGINFILE till ENDFILE)
    $filercv_name = ""
    $filercv_varname = ""
    $filercv_content = ($null, $null)
    $filercv_sw = New-Object Diagnostics.Stopwatch

    # check if array 1 begins with content of array 2
    # heavy load funtion as string conversion is involved
    function helper_array_begins_with($arr1, $arr2)
    {
        $a=[System.BitConverter]::ToString($arr1)
        $b=[System.BitConverter]::ToString($arr2)
        return $a.Contains($b)    
    }

#    function concat_array($arr1, $arr2)
#    {
#        $res = New-Object Byte[] ($arr1.Length + $arr2.Length)        
#        [System.Buffer]::BlockCopy($arr1, 0, $res, 0, $arr1.Length)
#        [System.Buffer]::BlockCopy($arr2, 0, $res, $arr1.Length, $arr2.Length)
#        return $res
#    }

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
            
            if ($dst -eq 2)
            {
                $hostui.WriteLine([System.Text.Encoding]::UTF8.GetString($stream))
            }
            elseif ($dst -eq 3)
            {
                $hostui.WriteErrorLine([System.Text.Encoding]::UTF8.GetString($stream))
            }
            elseif ($dst -eq 4)
            {
                # incoming file consists of minimum 3 streams
                #   1     - "BEGINFILE filename varname"
                #   n     - file content binary (minimum 1 stream) or ERROR 
                #   n+1   - "ENDFILE filename varname"

                # check if start of file transfer
                if (helper_array_begins_with $stream $beginfile)
                {
                    # convert stream to strings
                    $args = ([System.Text.Encoding]::ASCII.GetString($stream)-replace('\s+',' ')).Split(" ")
                    $filercv_name = $args[1]
                    $filercv_varname = $args[2]
                    $filercv_running = $true
#[Console]::WriteLine("Begin receive")                    
#[Console]::WriteLine($filercv_content[0].Position)                    
                    if ($filercv_content[0] -ne $null)
                    {
                        # aborted filestream pending, clear buffers
                        $filercv_content[0].Close()
                        $filercv_content[0].Dispose()
                        
                        # overwite Asynctask object
                        $filercv_content[1] = $null
                    }
                    $filercv_content[0] = New-Object System.IO.MemoryStream # array containing the MemoryStream and placeholder for AsyncTask handle
                    $filercv_content[1] = $null
                    $hostui.WriteLine("Begin receiving file $filercv_name")
                    #$filercv_sw.Restart() # not on NET 3.5
                    $filercv_sw.Reset()
                    $filercv_sw.Start()
                }
                # check if end of file transfer
                elseif (helper_array_begins_with $stream $endfile) 
                {
                    $filercv_sw.Stop()
                    $timetaken = $filercv_sw.Elapsed.TotalSeconds

                    # finish pending writes
                    $filercv_content[0].Flush()
                    if ($filercv_content[1] -ne $null) { $filercv_content[0].EndWrite($filercv_content[1]) }
                    
                    # save content of file into desired var via hashtable of parent
                    $content = $filercv_content[0].toArray()
                    $size = $content.Length
                    $kBps = $size / $timetaken / 1024
                    $hostui.WriteLine("`nEnd receiving {0} received {1:N0} Byte in {2:N4} seconds ({3:N2} KB/s)" -f ($filercv_name, $size, $timetaken, $kBps))
                    
                    $hashtable.Add($filercv_varname, $content)
                    #New-Variable -Name $filercv_varname -Value $filercv_content -Visibility Public -Scope Script
                            

                    $filercv_running = $false
                    $filercv_name = ""
                    $filercv_varname = ""
                    $filercv_content[0].Close()
                    $filercv_content[0].Dispose()
                    $filercv_content[0] = $null
                    $filercv_content[1] = $null
                }
                elseif ($filercv_running)
                {
                    #$hostui.WriteLine("Receiving chunk for file $filercv_name")
                    $hostui.Write(".")
                    
                    # finish pending writes
                    if ($filercv_content[1] -ne $null) { $filercv_content[0].EndWrite($filercv_content[1]) }
                    
                    
                    # $filercv_content.WriteAsync($stream, 0, $stream.Length) # WriteAsync isn't available on NET 3.5
                    $whandle = $filercv_content[0].BeginWrite($stream, 0, $stream.Length, $null, $null)
                    $filercv_content[1] = $whandle
 #[Console]::WriteLine($filercv_content[0].Position)
                }
                else
                {
                    $msg = [System.Text.Encoding]::UTF8.GetString($stream)
                    $hostui.WriteLine("unknown getfile response: $msg")
                }
            }
            else
            {
                $msg = "Stream received for unhandled dst $dst"
                $hostui.WriteLine($msg)
                $hostui.WriteLine([System.Text.Encoding]::UTF8.GetString($stream))
            }
        }
        else {Start-Sleep -m 50} # delay to safe CPU load if no output in queue
    }
}


# note:
#    dst=1 indicates a bash command for the python server
#    dst=2 indicates a file request (returns file content as base64 string)
$script_hid_out_loop = {
    # the try block is only needed to run the finally block and destroy threads on unexpected exit (CTRL+C, exit command ...)

    # Sleep to allow HID in thread to print output, before prompt is shown
    #Start-Sleep 1
    
    function printhlp()
    {
        $host.UI.WriteLine("P4wnP1 HID Shell  by MaMe82")
        $host.UI.WriteLine("===========================")
        $host.UI.WriteLine("")
        $host.UI.WriteLine("Usage")
        $host.UI.WriteLine("    '!!<command>'        Run local powershell commands.")
        $host.UI.WriteLine("                         Example: !!Get-Date")
        $host.UI.WriteLine("")
        $host.UI.WriteLine("    '!<command>'         Run remote bash commands on P4wnP1.")
        $host.UI.WriteLine("                         Example: !pwd")
        $host.UI.WriteLine("")
        $host.UI.WriteLine("    '!reset_bash'        Restarts the bash on P4wnP1")
        $host.UI.WriteLine("                           This is only needed if the underlying bash doesn't")
        $host.UI.WriteLine("                           respond. This could for example happen if an inter-")
        $host.UI.WriteLine("                           active command like 'base64' is issued")
        $host.UI.WriteLine("                           The new bash process is started with a new and empty")
        $host.UI.WriteLine("                           environment")
        $host.UI.WriteLine("")
        $host.UI.WriteLine("    'getfile file var'  Load a content of a file from P4wnP1 to a local PowerShell variable")
        $host.UI.WriteLine("")
        $host.UI.WriteLine("    'help'              Print this helpscreen")
        $host.UI.WriteLine("")
        $host.UI.WriteLine("    'exit'              Exit the client")
        $host.UI.WriteLine("")
    }
    printhlp

    #Write-Host -NoNewline "P4wnP1 HID Shell >> "
    
    while ($true)
    {
        # !! read-host seems to block the UI and thus the HID_in thread (no write-host in other thread till read-host finished), 
        # when it tries to print out data. This could be circumvented by checking console input for "keyAvailable"
        # the shortcoming is, that this couldn't be used on ISE
        if ([Console]::KeyAvailable) 
        { 
            $in = read-host  
            # exit loop if input is "exit"
            if ($in -eq "exit") { break }
            if ($in -eq "help")
            {
                printhlp
            }
            elseif ($in.StartsWith("getfile"))
            {
                # no argument error handling
                #   arg0 - file to receive
                #   arg1 - name of var to save file to
                $inbytes =[system.Text.Encoding]::UTF8.GetBytes($in)
                L4send_datastream $L4qout 1 4 $inbytes
            }
            elseif ($in.StartsWith("!!"))
            {
                $pscommand = $in.Split("!!")[2]
                if ($pscommand.Length -gt 0) { iex $pscommand }
            }
            elseif ($in.StartsWith("!"))
            {
                $remotecommand = $in.Split("!")[1]
                $inbytes =[system.Text.Encoding]::UTF8.GetBytes($remotecommand)
                L4send_datastream $L4qout 1 1 $inbytes # send to stdin of P4wnP1 background process (bash)
            }
            else
            {
                $host.UI.WriteErrorLine("Unknown P4wnP1 command: $in")
                $host.UI.WriteErrorLine("Enter 'help' for usage")
                #$inbytes =[system.Text.Encoding]::UTF8.GetBytes($in)
                #L4send_datastream $L4qout 1 255 $inbytes
            }
            #Write-Host -NoNewline "P4wnP1 HID Shell >> "
        }
        else 
        {
                       
            # $hashtable keeps track of variables which should be created during runtime
            # so we check if we have to create some
            if ($hashtable.Count -gt 0)
            {
                foreach ($varname in $hashtable.Keys)
                {
                    New-Variable -Name $varname -Value $hashtable[$varname] -Force
                    [Console]::WriteLine("Content of file saved to variable `$$varname")
                }
                $hashtable.Clear()
            }
            else
            {
                Start-Sleep -m 50 # delay to reduce CPU load if no key input
            }
            
        } 
    }
}



# Objects used by Layer4 communication (should be added to stage2 script to save space)
$L4qin = New-Object System.Collections.Queue
$L4qout = New-Object System.Collections.Queue



#######
# Prepare Threads
#######

$hashtable =  [hashtable]::Synchronized(@{}) # hashtable to exchange synchronized data with this thread

# create session state with needed functions for runspace

#$iss = [initialsessionstate]::Create()
$iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

$def_read_data = Get-Content Function:\read_data -ErrorAction Stop
$ssfe_read_data = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList 'read_data', $def_read_data
$iss.Commands.Add($ssfe_read_data)

$def_send_data = Get-Content Function:\send_data -ErrorAction Stop
$ssfe_send_data = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList 'send_data', $def_send_data
$iss.Commands.Add($ssfe_send_data)
$def_fragment_rcvd = Get-Content Function:\L4fragment_rcvd -ErrorAction Stop
$ssfe_fragment_rcvd = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList 'L4fragment_rcvd', $def_fragment_rcvd
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
$rs_hid_in.SessionStateProxy.SetVariable("hashtable", $hashtable)


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
$msg="This text has been sent from PowerShellClient through a HID device and was printed on P4wnP1 with python"
$testdata=[system.Text.Encoding]::UTF8.GetBytes($msg)
L4send_datastream $L4qout 3 2 $testdata

# CTRL - c handling (to pipe through HID) see here: http://stackoverflow.com/questions/1710698/gracefully-stopping-in-powershell
# for now we use try / catch / finally
# finally assures the runspaces (threads) are killed 


# HID output loop (=console input loop)
try 
{
    iex $script_hid_out_loop.toString()
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

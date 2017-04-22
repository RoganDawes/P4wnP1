###################################################
# Create LinkLayer Custom Object (Stage 2 work)
###################################################

$LinkLayerProperties = @{
    globalstate =  [hashtable]::Synchronized(@{}) # Thread global data (synchronized hashtable for state)
    iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault() # initial seesion state for threads (runspaces)


    
    ps_hid_in = [powershell]::Create() # powershell subrocess running HIDin thread
    ps_hid_out = [powershell]::Create() # powershell subrocess running HIDout thread
        
}

$LinkLayer = New-Object PSCustomObject -Property $LinkLayerProperties
# Create construcort / init method
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "Init" -Value {
    param(

        [Parameter(Mandatory=$true, Position=0)]
        [System.IO.FileStream]
        $HIDin,

        [Parameter(Mandatory=$true, Position=1)]
        [System.IO.FileStream]
        $HIDout

    )
    

    # as the mandatory attribute isn't working with Add-Member ScriptMethod, we check manually
    if (!$HIDin -or !$HIDout) { throw [System.ArgumentException]"FileStream for HIDin and HIDout have to be provided as argument (both FileStreams could be the same if access is bot, read and write!"}


    $reportsize = 65
    
    ########################
    # declare script block for HID input thread (reading input reports)
    #########################
    # works with incoming sequence number, as reports could be lost if this host is reading to slow
    # report layout for incoming reports
    #    0: REPORT ID
    #    1: LEN: BIT7 = fin flag, BIT6 = unused, BIT5...BIT0 = Payload Length (Payload length 0 to 62)
    #    2: SEQ: BIT7 = CONNECT BIT, BIT6 = unused, BIT5...BIT0 = SEQ: Sequence number used by the sender (0..31)
    #    3..64: Payload
    $HIDinThread = {
        $hostui.WriteLine("Starting thread to continuously read HID input reports")

        $HIDin = $state.HIDin
    
    
        $inbytes = New-Object Byte[] (65)
        $MAX_SEQ = 32 # how many sequence numbers are used by sender (largest possible SEQ number + 1)
        $hostui.WriteLine("First SEQ received {0}" -f $state.last_valid_seq_received)

        $stream = New-Object Object[] (0)

        while ($true)
        {
            $cr = $HIDin.Read($inbytes,0,65)

#$hostui.WriteLine("Reader: Received $inbytes")     
        
            # extract header data
            ########################
            $LEN = $inbytes[1] -band 63
            $BYTE1_BIT7_FIN = $false # if this bit is set, this means the report is the last one in a fragemented STREAM
            # if this bit isn't set $inbytes[2] contains the SEQ number, 
            # if thi bit is set $inbytes[2] contains the SEQ number of a retransmission - invalidating all reports received after this SEQ number (unused right now)
            $BYTE1_BIT6_UNUSED = $false 
        
            if ($inbytes[1] -band 128) {$BYTE1_BIT7_FIN=$true}
            if ($inbytes[1] -band 64) {$BYTE1_BIT6_UNUSED=$true}
        
            $RECEIVED_SEQ = $inbytes[2] -band 63 # remove flag bits from incoming SEQ number
        
            # calculate next valid SEQ number
            $next_valid_seq = $state.last_valid_seq_received + 1
            if ($next_valid_seq -ge $MAX_SEQ) { $next_valid_seq -= $MAX_SEQ } # clamp next_valid_seq to MAX_SEQ range
        
#$hostui.WriteLine("Reader: Received SEQ: $RECEIVED_SEQ, next valid SEQ: $next_valid_seq")     
        
            # check if received SEQ is valid (in order)
            if ($RECEIVED_SEQ -eq $next_valid_seq)
            {
                # received report has valid SEQ: 
                # - push report to input queue
                # - update last_valid_seq_received
        
                if ($LEN -gt 0) # only handle packets with payload length > 0 (no heartbeat)
                {
                    
                    
                    #keep eye on: http://stackoverflow.com/questions/31620763/no-garbage-collection-while-powershell-pipeline-is-executing

                    # concat stream
                    $stream += $inbytes[3..(2+$LEN)]
                    if ($BYTE1_BIT7_FIN) # FIN bit set ?
                    {
                        # FIN bit is set, enqueue stream and reset
                        $state.report_in_queue.Enqueue($stream) # enqueue stream
                        $stream = New-Object Object[] (0) # create new empty stream
                    }
                    $state.payload_bytes_received += $LEN # sums the payload bytes received, only debug state (bytes mustn't necessarily be enqueued if incomplete stream)
                    $state.payload_bytes_received = $state.payload_bytes_received -band 0x7fffffff # cap to 32 bit int (signed)
#$hostui.WriteLine("Reader: Enqueue report SEQ: $RECEIVED_SEQ length $LEN FIN bit $BYTE1_BIT7_FIN")   
#$hostui.WriteLine("Reader: Bytes {0}" -f $state.payload_bytes_received)   
                }
#                else
#                {
#                    $hostui.WriteLine("Reader: Ignoring report with SEQ $SEQ, as payload is empty")
#                }
            
                $state.last_valid_seq_received = $next_valid_seq
                $state.invalid_seq_received = $false
            }
            else
            {
                # out of order report received
                # - ignore report (don't push report to input queue) 
                # - DON'T update last_valid_seq_received 
                # - inform output thread, that a report with invalid sequence has be received (to trigger a RESEND REQUEST from write thread)
            
#$hostui.WriteLine("Reader: Received invalid (out-of-order) report")
        
                $state.invalid_seq_received = $true
            }
                
            # promote received SEQ number to thread global state
#            $state.last_seq_received = $inbytes[2]

#Start-Sleep -m 200 # try to miss reports

        }
    } # end of HIDin script block




    ########################
    # declare script block for HID outpput thread (writing output reports)
    #########################
    # works with outgoing acknoledge number, as reports could be lost if this host is reading to slow
    # valid (in-order) reports are propagated back to the sender with an acknowledge number (ACK) 
    # Sender has to stop sending after a maximum of 32 reports if the corresponding ACK for the
    # 32th packet isn't received
    # ACKs are accumulating, this means if SEQ 0, 1, 2 are read by the HIDin Thread, without writing an 
    # output report containing the needed ACKs (for example, caused by to much processing overhead in output 
    # loop for example), the next ACK written will be 2 (omitting 0 and 1).
    # To allow the other peer to still detect report loss, without receiving an ack for every single report,
    # a flag is introduced to fire resend request. If this flag is set, this informs the other peer to resend 
    # every report, beginning from the sucessor of the ACK number in the ACK field (this allows to acknowledge additional
    # reports while requesting missed ones).
    
    # report layout for outgoing reports
    #    0: REPORT ID
    #    1: LEN: BIT7 = FIN flag, BIT6 = RESEND REQUEST, BIT5...BIT0 = Payload Length (Payload length 0 to 62)
    #    2: ACK: BIT7 = CONNECT BIT, BIT6 = unused, BIT5...BIT0 = ACK: Acknowledge number holding last valid SEQ number received by reader thread
    #    3..64: Payload
    $HIDoutThread = {
        $MAX_SEQ = 32 # how many sequence numbers are used by sender (largest possible SEQ number + 1)
    
        $hostui.WriteLine("Starting write loop continously sending HID ouput report")

        $HIDout = $state.HIDout

#        $empty = New-Object Byte[] (65)
#        $outbytes = New-Object Byte[] (65)
 
        $PAYLOAD_MAX_SIZE = $state.PAYLOAD_MAX_SIZE
        $PAYLOAD_MAX_INDEX = $PAYLOAD_MAX_SIZE - 1
        $current_stream = New-Object Object[] (0) # holds full outbound stream, which is split up into chunks of PAYLOAD_MAX_SIZE
    
        while ($true)   
        {
#            # dequeue pending output reports, use empty (heartbeat) otherwise
#            if ($state.report_out_queue.Count -gt 0)
#            {
#                $outbytes = $state.report_out_queue.Dequeue()
#            }
#            else
#            {
#                $outbytes = $empty
#            }

            # check if stream with partial send data is pending
            $BYTE1_BIT7_FIN = $true # if this bit is set, this means the report is the last one in a fragemented STREAM
            if ($current_stream.Length -eq 0)
            {
                # no pending data in current stream
                # check if new stream is in out queue
                if ($state.report_out_queue.Count -gt 0)
                {
                    # fetch into current stream
                    $current_stream = $state.report_out_queue.Dequeue()
                }
            }
            if ($current_stream.Length -gt $PAYLOAD_MAX_SIZE)
            {
                $payload = $current_stream[0..$PAYLOAD_MAX_INDEX] # grab next chunk, payload hold array of length 0 if current_stream is empty (fits heartbeat report)
                $current_stream = $current_stream[$PAYLOAD_MAX_SIZE..($current_stream.Length-1)] # remove chunk from pending stream
            }
            else
            {
                $payload = $current_stream
                $current_stream = New-Object Object[] (0)
            }
            if ($current_stream.Length -ne 0)
            {
                # data left in stream, unset FIN bit
                $BYTE1_BIT7_FIN = $false
            }

            # build report
            ################
            $LEN_FIN = $payload.Length
            if ($BYTE1_BIT7_FIN) { $LEN_FIN +=128 } # add FIN bit if set
            
            $outbytes = [Byte[]](0, $LEN_FIN, 0) + $payload + (New-Object Byte[] ($PAYLOAD_MAX_SIZE - $payload.Length)) # construct report (REPORT ID 0, header byte 1, header byte 2, payload, zero padding)

            # if this bit isn't set $inbytes[2] contains the SEQ number, 
            # if thi bit is set $inbytes[2] contains the SEQ number of a retransmission - invalidating all reports received after this SEQ number (unused right now)
            $BYTE2_BIT6_RESEND_REQUEST = $state.invalid_seq_received # set resend bit, if last report read has been invalid (out of order)

#$hostui.WriteLine("Writer: Current stream $current_stream") 
#$hostui.WriteLine("Writer: Payload $payload") 
#$hostui.WriteLine("Writer: Outbytes $outbytes")
         
            if ($BYTE2_BIT6_RESEND_REQUEST)
            { 
                $outbytes[1] = $outbytes[1] -bor 64 # set resend flag if necessary
                $next_needed = $state.last_valid_seq_received + 1 # Request resending, beginning from the successor report of the last in-order-report received
                if ($next_needed -ge $MAX_SEQ) { $next_needed -= $MAX_SEQ }
                $outbytes[2] = $next_needed
            }
            else 
            { 
                $outbytes[1] = $outbytes[1] -band -bnot 64 # unset resend flag if necessary
                $outbytes[2] = $state.last_valid_seq_received # acknowledge last valid SEQ number received
            }

#$hostui.WriteLine("Writer: Outbytes final $outbytes")
        
# slow down loop to mimic overload on output data processing
#Start-Sleep -m 500 # try to write less than read
        
# DEBUG
#$as = $outbytes[2] 
#if ($BYTE2_BIT6_RESEND_REQUEST)
#{ $hostui.WriteLine("Writer: Send resend request beginning from SEQ $as") }
#else
#{ $hostui.WriteLine("Writer: Send report with ACK $as") }
       
            $HIDout.Write($outbytes,0,65)
        }
    }


    
    ##############################
    # init state shared among read and write thread
    ##############################
#    $this.globalstate.last_seq_received = 12 # last seq number read !! has to be exchanged between threads, thus defined in global RunSpace threadsafe hashtable
    $this.globalstate.last_valid_seq_received = 12 # last seq number which has been valid (arrived in sequential order)
    $this.globalstate.invalid_seq_received = $true # last SEQ number received, was invalid if this flag is set, the sender is informed about this with a resend request
    $this.globalstate.report_in_queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    $this.globalstate.report_out_queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    $this.globalstate.payload_bytes_received = 0 # effective payload bytes received
    $this.globalstate.PAYLOAD_MAX_SIZE = 62 # max effective payload size in single report
    $this.globalstate.HIDin = $HIDin
    $this.globalstate.HIDout = $HIDout
    $this.globalstate.connected = $false

    ##
    # Prepare Threads
    ###

    #
    $rs_hid_in = [runspacefactory]::CreateRunspace($this.iss) # RunSpace for HIDin thread (reading HID input reports)
    $rs_hid_out = [runspacefactory]::CreateRunspace($this.iss) # RunSpace for HIDout thread (writing HID output reports)


    # read HID thread
    $rs_hid_in.Open()
    $rs_hid_in.SessionStateProxy.SetVariable("HIDin", $HIDin) # FileStream to HID input report device
    $rs_hid_in.SessionStateProxy.SetVariable("hostui", $Host.UI) # Allow thread accesing stdout of $host
    $rs_hid_in.SessionStateProxy.SetVariable("state", $this.globalstate) # state shared between threads

    
    $this.ps_hid_in.Runspace = $rs_hid_in
    [void] $this.ps_hid_in.AddScript($HIDinThread)

    # write HID thread
    $rs_hid_out.Open()
    $rs_hid_out.SessionStateProxy.SetVariable("HIDout", $HIDout) # FileStream to HID output report device
    $rs_hid_out.SessionStateProxy.SetVariable("hostui", $Host.UI) # Allow thread accesing stdout of $host
    $rs_hid_out.SessionStateProxy.SetVariable("state", $this.globalstate) # state shared between threads

    $this.ps_hid_out.Runspace = $rs_hid_out
    [void] $this.ps_hid_out.AddScript($HIDoutThread)


} # end of init method

$LinkLayer | Add-Member -MemberType ScriptMethod -Name "Start" -Value {
#    param(
#
#        [Parameter(Mandatory=$true, Position=0)]
#        [Byte]
#        $last_SEQ
#    )

#    # as the mandatory attribute isn't working with Add-Member ScriptMethod, we check manually
#    if (!$last_SEQ) { throw [System.ArgumentException]"Last valid SEQ number received has to be provided"}

#    $this.globalstate.last_valid_seq_received = $last_SEQ
    
    if (!$this.globalstate.connected) { throw [System.ArgumentException]"LinkLayer.Connect() has to be called before LinkLayer.Start() to synchronize ACK/SEQ"}

[Console]::WriteLine("Start SEQ {0}" -f $this.globalstate.last_valid_seq_received)

    # start threads
    # start HID input handling thread
    $handle_hid_in = $LinkLayer.ps_hid_in.BeginInvoke()

    # start HID out thread, idle loop till finish    
    $handle_hid_out = $LinkLayer.ps_hid_out.BeginInvoke()
}


$LinkLayer | Add-Member -MemberType ScriptMethod -Name "Stop" -Value {
    # stop threads
    $this.ps_hid_in.Stop() # The ps_hid_in thread blocks stopping, until the internal blocking HIDin.read() call receives data (BeginRead would result in CPU consuming loop)
    $this.ps_hid_in.Dispose()
    $this.ps_hid_out.Stop()
    $this.ps_hid_out.Dispose()
}

# method to get current input report queue size
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "PendingInputStreamCount" -Value {
    $this.globalstate.report_in_queue.Count
}

# method to get current input report queue size
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "GetPayloadBytesReceived" -Value {
    $this.globalstate.payload_bytes_received
}

# method to get current input report queue size
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "ResetPayloadBytesReceived" -Value {
    $this.globalstate.payload_bytes_received = 0
}

# method to get last input report from queue
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "PopPendingInputStream" -Value {
    $this.globalstate.report_in_queue.Dequeue()
}


# method to enqueue output stream
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "PushOutputStream" -Value {
    param(

        [Parameter(Mandatory=$true, Position=0)]
        [Object[]]
        $data
    )

    # as the mandatory attribute isn't working with Add-Member ScriptMethod, we check manually
    if (!$data) { throw [System.ArgumentException]"Data has to be provided as Byte[] or Object[]"}

    
    # slow access (both, state and report_out_queue are synchronized seperately)
    $this.globalstate.report_out_queue.Enqueue($data)
}


# method to synchronize a !NEW! connection
#
#   This method synchronizes LinkLayer connection (reset state of server output queues and sync SEQ to ACK
#   !! The method isn't implemented as MemberFuction of LinkLayer object, as it has to be placed in stage 1
#
#  Return value is the last valid SEQ seen from the other peer, which needs to be handed over to
#  LinkLayer.start($SEQ) in order to continue communication)
#
#  Recalling this method, causes the oher peer to reinit state machine (clear outbound queues)
#  Old reports already in flight are ignored by this method, as they don't have the CONNECT BIT set
#
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "Connect" -Value {

    $connect_req = New-Object Byte[] (65)
    $response = New-Object Byte[] (65)
    $connect_req[2] = $connect_req[2] -bor 128 # set CONNECT BIT

#    $ACK = 0 # ACK number to start with (other peers SEQ should be choosed based on this)
    
    [Console]::WriteLine("Starting connection")
    
    $HIDin = $this.globalstate.HIDin
    $HIDout = $this.globalstate.HIDout

    $connected = $false
    while (-not $connected)
    {
        # send packet with ACK, this should be used by the peer to chooese starting SEQ
        # the CONNECT BIT tells the peer to flush its outbound queue
        # this did ONLY happen, if we receive a report with CONNECT BIT SET (holding the initial sequence number)
        $HIDout.Write($connect_req, 0, 65) # This repoert holds has ACK=0 which should be ignored by the server
        [Console]::WriteLine("Connect request sent")

        $cr = $HIDin.Read($response, 0, 65)
        $SEQ = $response[2] -band 63
        $CONNECT_BIT = $response[2] -band 128
        if ($CONNECT_BIT)
        {
            [Console]::WriteLine("SEQ {0} received on connect" -f $SEQ)
            # this is the initial SEQ number, send corresponding ACK and exit loop
            # this is se last ACK which gets sent with CONNECT BIT set
            # the other peer changes state to FULL duplex communication after receiving this (in
            # sync) ACK without further interaction
            #
            # So to be clear, at the point we receive the first SEQ with CONNECT BIT set from the peer
            # we send the corresponding ACK with connect bit and assume we are in sync (we could be sure
            # that there are no reports with other SEQ numbers in flight, as the peer uses STOP-AND-WAIT
            # till this final ACK is received)
            #
            # To be more clear...we ignore old reports from inbound queue (no CONNECT BIT), which have been
            # in flight before the peer recognized our CONNECT BIT. Thus the first answer with CONNECT BIT from
            # peer contains the first valid SEQ which we now know the valid ACK for.
            # Thus we continue with asynchronous full duplex communication immediately.
            $connect_req[2] = $connect_req[2] -bor $SEQ # set ACK to SEQ and infor sender that we are in sync by sending correct ACK
            $HIDout.Write($connect_req, 0, 65)
    

            # set receiveed SEQ number into global state, before starting thread with $LinkLayer.start()
            $this.globalstate.last_valid_seq_received = $SEQ
            $connected = $true
        }
        else
        {
            [Console]::WriteLine("SEQ {0} received on connect, but no connect response" -f $SEQ)
        }

    }

    # set connected to global state
    $this.globalstate.connected = $connected
    $this.globalstate.invalid_seq_received = $false
   
}



#########################
# test of link layer
#########################

$STREAM_TYPE_ECHO_REQUEST = 2

# Test function to enque output
#  qout:                output queue to use
#  stream_size:         size to use for single stream which gets enqueued
#  max_bytes:           max bytes to enqueue at all
#function TEST_enqueue_ouput($qout, $stream_size, $max_bytes)
function TEST_enqueue_ouput($LinkLayer, $stream_size, $max_bytes)
{
    #[System.Console]::WriteLine("Enqueue $max_bytes Bytes output data split into streams of $stream_size bytes, each...")

    for ($i = 0; $i -lt ($max_bytes/$stream_size); $i++)
    {
        $utf8_msg = "Stream Nr. $i from Powershell, size $stream_size (filled up with As) ..."
        $fill = "A" * ($stream_size - $utf8_msg.Length)
        $utf8_msg += $fill
        # convert to bytes (interpret as UTF8)
        $payload =[system.Text.Encoding]::UTF8.GetBytes($utf8_msg)
        #$qout.Enqueue($payload)
        $stream_type = [BitConverter]::GetBytes([int] $STREAM_TYPE_ECHO_REQUEST)

        $LinkLayer.PushOutputStream($stream_type + $payload)
    }

    #[System.Console]::WriteLine("... done pushing data into output queue")
}



$HIDin = $devfile
$HIDout = $devfile

$LinkLayer.Init($HIDin, $HIDout) # init link layer state

$LinkLayer.Connect() # synchronize connection


try
{
    $LinkLayer.Start() # start link layer threads (HID reader and writer)
    

    ##################
    # Test 2: Go on sending data, measure transfer rate of received data (but throw away received streams) in 1000ms interval
    ##################
    $sw = New-Object System.Diagnostics.Stopwatch

    # keep running
    $BYTES_TO_FETCH = 1000*64
    $sw.Reset()
    $sw.Start()
    while($true)
    {
        $bytes_rcvd = $LinkLayer.GetPayloadBytesReceived()
        if  ($bytes_rcvd -ge $BYTES_TO_FETCH)
        {
            $sw.Stop()
            $ttaken = $sw.Elapsed.TotalSeconds
            $tp = $bytes_rcvd / $ttaken
            $LinkLayer.ResetPayloadBytesReceived()
            $sw.Reset()
            $sw.Start()
            $host.UI.WriteLine("MainThread: {0} payload bytes read in {1} seconds ({2} Bytes/s)." -f ($bytes_rcvd, $ttaken, $tp)) 
        }
        
        Start-Sleep -m 100
        
        # go on processing inbound data
        while ($LinkLayer.PendingInputStreamCount() -gt 0) # print out fully captured streams
        {
            # pop and throw away, we only count received bytes
            $stream = $LinkLayer.PopPendingInputStream()
            $utf8 = ([System.Text.Encoding]::UTF8.GetString($stream))
            $host.UI.WriteLine("{0}" -f $utf8) 
        }

        # enque output
        $stream_size = 10*$LinkLayer.globalstate.PAYLOAD_MAX_SIZE
        #$max_bytes = 62*1024 + $stream_size
        $max_bytes = 6200
        TEST_enqueue_ouput $LinkLayer $stream_size $max_bytes
    }
}
finally
{
    [Console]::WriteLine("Killing remaining threads")
   
    # end threads
    $LinkLayer.Stop() # HIDin thread keeps running, till the blocking read on deivcefile receives a report
    $devfile.Close()
    
    [Console]::WriteLine("Goodbye")
}

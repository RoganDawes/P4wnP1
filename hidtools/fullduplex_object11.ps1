##############################
# Build methods to create filestream to HID device (stage 1 work)
#################################################################

$cs =@"
using System;
using System.Collections.Generic;
using System.Text;
using System.IO;
//using System.ComponentModel;
using System.Runtime.InteropServices;



using Microsoft.Win32.SafeHandles;

//using System.Runtime;


namespace mame
{
    public class HID40
    {
        /* invalid handle value */
        public static IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        // kernel32.dll
        public const uint GENERIC_READ = 0x80000000;
        public const uint GENERIC_WRITE = 0x40000000;
        public const uint FILE_SHARE_WRITE = 0x2;
        public const uint FILE_SHARE_READ = 0x1;
        public const uint FILE_FLAG_OVERLAPPED = 0x40000000;
        public const uint OPEN_EXISTING = 3;
        public const uint OPEN_ALWAYS = 4;
        
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr CreateFile([MarshalAs(UnmanagedType.LPStr)] string strName, uint nAccess, uint nShareMode, IntPtr lpSecurity, uint nCreationFlags, uint nAttributes, IntPtr lpTemplate);
        
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("hid.dll", SetLastError = true)]
        public static extern void HidD_GetHidGuid(out Guid gHid);

        [DllImport("hid.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern Boolean HidD_GetManufacturerString(IntPtr hFile, StringBuilder buffer, Int32 bufferLength);

        [DllImport("hid.dll", CharSet = CharSet.Auto, SetLastError = true)]
        internal static extern bool HidD_GetSerialNumberString(IntPtr hDevice, StringBuilder buffer, Int32 bufferLength);
        
        [DllImport("hid.dll", SetLastError = true)]
        protected static extern bool HidD_GetPreparsedData(IntPtr hFile, out IntPtr lpData);

        [DllImport("hid.dll", SetLastError = true)]
        protected static extern int HidP_GetCaps(IntPtr lpData, out HidCaps oCaps);

        [DllImport("hid.dll", SetLastError = true)]
        protected static extern bool HidD_FreePreparsedData(ref IntPtr pData);

        // setupapi.dll

        public const int DIGCF_PRESENT = 0x02;
        public const int DIGCF_DEVICEINTERFACE = 0x10;

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct DeviceInterfaceData
        {
            public int Size;
            public Guid InterfaceClassGuid;
            public int Flags;
            public IntPtr Reserved;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct DeviceInterfaceDetailData
        {
            public int Size;
            
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 512)]
            public string DevicePath;
        }
        
        //We need to create a _HID_CAPS structure to retrieve HID report information
        //Details: https://msdn.microsoft.com/en-us/library/windows/hardware/ff539697(v=vs.85).aspx
        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        protected struct HidCaps
        {
            public short Usage;
            public short UsagePage;
            public short InputReportByteLength;
            public short OutputReportByteLength;
            public short FeatureReportByteLength;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 0x11)]
            public short[] Reserved;
            public short NumberLinkCollectionNodes;
            public short NumberInputButtonCaps;
            public short NumberInputValueCaps;
            public short NumberInputDataIndices;
            public short NumberOutputButtonCaps;
            public short NumberOutputValueCaps;
            public short NumberOutputDataIndices;
            public short NumberFeatureButtonCaps;
            public short NumberFeatureValueCaps;
            public short NumberFeatureDataIndices;
        }
        

        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern IntPtr SetupDiGetClassDevs(ref Guid gClass, [MarshalAs(UnmanagedType.LPStr)] string strEnumerator, IntPtr hParent, uint nFlags);

        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern bool SetupDiEnumDeviceInterfaces(IntPtr lpDeviceInfoSet, uint nDeviceInfoData, ref Guid gClass, uint nIndex, ref DeviceInterfaceData oInterfaceData);

        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr lpDeviceInfoSet, ref DeviceInterfaceData oInterfaceData, ref DeviceInterfaceDetailData oDetailData, uint nDeviceInterfaceDetailDataSize, ref uint nRequiredSize, IntPtr lpDeviceInfoData);

        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern bool SetupDiDestroyDeviceInfoList(IntPtr lpInfoSet);

        //public static FileStream Open(string tSerial, string tMan)
        public static FileStream Open(string tSerial, string tMan)
        {
            FileStream devFile = null;
            
            Guid gHid;
            HidD_GetHidGuid(out gHid);
            
            // create list of HID devices present right now
            var hInfoSet = SetupDiGetClassDevs(ref gHid, null, IntPtr.Zero, DIGCF_DEVICEINTERFACE | DIGCF_PRESENT);
            
            var iface = new DeviceInterfaceData(); // allocate mem for interface descriptor
            iface.Size = Marshal.SizeOf(iface); // set size field
            uint index = 0; // interface index 

            // Enumerate all interfaces with HID GUID
            while (SetupDiEnumDeviceInterfaces(hInfoSet, 0, ref gHid, index, ref iface)) 
            {
                var detIface = new DeviceInterfaceDetailData(); // detailed interface information
                uint reqSize = (uint)Marshal.SizeOf(detIface); // required size
                detIface.Size = Marshal.SizeOf(typeof(IntPtr)) == 8 ? 8 : 5; // Size depends on arch (32 / 64 bit), distinguish by IntPtr size
                
                // get device path
                SetupDiGetDeviceInterfaceDetail(hInfoSet, ref iface, ref detIface, reqSize, ref reqSize, IntPtr.Zero);
                var path = detIface.DevicePath;
                
                System.Console.WriteLine("Path: {0}", path);
            
                // Open filehandle to device
                
                var handle = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero);
                
                                
                if (handle == INVALID_HANDLE_VALUE) 
                { 
                    System.Console.WriteLine("Invalid handle");
                    index++;
                    continue;
                }
                
                IntPtr lpData;
                if (HidD_GetPreparsedData(handle, out lpData))
                {
                    HidCaps oCaps;
                    HidP_GetCaps(lpData, out oCaps);    // extract the device capabilities from the internal buffer
                    int inp = oCaps.InputReportByteLength;    // get the input...
                    int outp = oCaps.OutputReportByteLength;    // ... and output report length
                    HidD_FreePreparsedData(ref lpData);
                    System.Console.WriteLine("Input: {0}, Output: {1}",inp, outp);
                
                    // we have report length matching our input / output report, so we create a device file in each case
                    if (inp == 65 || outp == 65)
                    {
                        // check if manufacturer and serial string are matching
                    
                        //Manufacturer
                        var s = new StringBuilder(256); // returned string
                        string man = String.Empty; // get string
                        if (HidD_GetManufacturerString(handle, s, s.Capacity)) man = s.ToString();
                
                        //Serial
                        string serial = String.Empty; // get string
                        if (HidD_GetSerialNumberString(handle, s, s.Capacity)) serial = s.ToString();
                                
                        if (tMan.Equals(man, StringComparison.Ordinal) && tSerial.Equals(serial, StringComparison.Ordinal))
                        {
                            //Console.WriteLine("Device found: " + path);
                    
                            var shandle = new SafeFileHandle(handle, false);
                            
                            devFile = new FileStream(shandle, FileAccess.Read | FileAccess.Write, 32, true);
                                                        
                            
                            break;
                        }        
                        
                        
                    }
                
                }
            
                
                               
                

                index++;
            }
            SetupDiDestroyDeviceInfoList(hInfoSet);
            return devFile;
        }
    }
}
"@
Add-Type -TypeDefinition $cs  -Language CsharpVersion3

$devfile = [mame.HID40]::Open("deadbeefdeadbeef", "MaMe82")



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
    
        $inbytes = New-Object Byte[] (65)
        $MAX_SEQ = 32 # how many sequence numbers are used by sender (largest possible SEQ number + 1)
        $hostui.WriteLine("First SEQ received {0}" -f $state.last_valid_seq_received)

        $stream = New-Object Object[] (0)

        while ($true)
        {
            $cr = $HIDin.Read($inbytes,0,65)

        
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
    #    2: SEQ: BIT7 = CONNECT BIT, BIT6 = unused, BIT5...BIT0 = ACK: Acknowledge number holding last valid SEQ number received by reader thread
    #    3..64: Payload
    $HIDoutThread = {
        $MAX_SEQ = 32 # how many sequence numbers are used by sender (largest possible SEQ number + 1)
    
        $hostui.WriteLine("Starting write loop continously sending HID ouput report")

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
    param(

        [Parameter(Mandatory=$true, Position=0)]
        [Byte]
        $last_SEQ
    )

    # as the mandatory attribute isn't working with Add-Member ScriptMethod, we check manually
    if (!$last_SEQ) { throw [System.ArgumentException]"Last valid SEQ number received has to be provided"}

    $this.globalstate.last_valid_seq_received = $last_SEQ
    
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
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "PayloadBytesReceived" -Value {
    $this.globalstate.payload_bytes_received
}

# method to get last input report from queue
$LinkLayer | Add-Member -MemberType ScriptMethod -Name "PopPendingInputStream" -Value {
    $this.globalstate.report_in_queue.Dequeue()
}



######
# Stage1Connect
#   This method synchronizes LinkLayer connection (reset state of server output queues and sync SEQ to ACK
#   !! The method isn't implemented as MemberFuction of LinkLayer object, as it has to be placed in stage 1
#
#  Return value is the last valid SEQ seen from the other peer, which needs to be handed over to
#  LinkLayer.start($SEQ) in order to continue communication)
#
#  Recalling this method, causes the oher peer to reinit state machine (clear outbound queues)
#  Old reports already in flight are ignored by this method, as they don't have the CONNECT BIT set
#
#####
function Stage1Connect($HIDin, $HIDout) {

    $connect_req = New-Object Byte[] (65)
    $response = New-Object Byte[] (65)
    $connect_req[2] = $connect_req[2] -bor 128 # set CONNECT BIT

    $ACK = 0 # ACK number to start with (other peers SEQ should be choosed based on this)
    
    [Console]::WriteLine("Starting connection")
    
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
            $connect_req[2] = $connect_req[2] -bor $SEQ # set ACK to SEQ
            $HIDout.Write($connect_req, 0, 65)
            return $SEQ
        }
        else
        {
            [Console]::WriteLine("SEQ {0} received on connect, but no connect response" -f $SEQ)
        }

    }

}



#########################
# test of link layer
#########################

# Test function to enque output
#  qout:                output queue to use
#  stream_size:         size to use for single stream which gets enqueued
#  max_bytes:           max bytes to enqueue at all
function TEST_enqueue_ouput($qout, $stream_size, $max_bytes)
{
    [System.Console]::WriteLine("Enqueue $max_bytes Bytes output data split into streams of $stream_size bytes, each...")

    for ($i = 0; $i -lt ($max_bytes/$stream_size); $i++)
    {
        $utf8_msg = "Stream Nr. $i from Powershell, size $stream_size (filled up with As) ..."
        $fill = "A" * ($stream_size - $utf8_msg.Length)
        $utf8_msg += $fill
        # convert to bytes (interpret as UTF8)
        $payload =[system.Text.Encoding]::UTF8.GetBytes($utf8_msg)
        $qout.Enqueue($payload)
    }

    [System.Console]::WriteLine("... done pushing data into output queue")
}


$BYTES_TO_FETCH = 1024*1024 # 1MB payload data

$HIDin = $devfile
$HIDout = $devfile

$LinkLayer.Init($HIDin, $HIDout)

# fill out queue with some test data
$qout = $LinkLayer.globalstate.report_out_queue # fetch handle to output queue
$stream_size = 100*$LinkLayer.globalstate.PAYLOAD_MAX_SIZE
$max_bytes = 1024*1024 + $stream_size
TEST_enqueue_ouput $qout $stream_size $max_bytes

try
{
    $Initial_SEQ=Stage1Connect $HIDin $HIDout # This function includes connection syncing, time used isn't taken into account, as this is a one-timer

    $sw = New-Object Diagnostics.Stopwatch
    #$sw.Start()
    $no_data_received=$true
    
    # start link layer threads (with last valid SEQ number received by "connect" function)
    $LinkLayer.Start($Initial_SEQ)
    $bytes_rcvd = 0

    
    # Wait till LinkLayer has receivved at least $BYTES_TO_FETCH bytes of raw paylod data
    # Note: This hasn't to be actual data in input queue
    #       Example: If a 500KByte stream is received followed by a 1 MByte stream and $BYTES_TO_FETCH=1024*1024
    #                $LinkLayer.PayloadBytesReceived() reaches 1 MByte, but the input queue holds only the first
    #                500KByte stream, as the second one isn't fully received ($LinkLayer.PendingInputStreamCount() would be 1)
    while ($true)
    {
        $bytes_rcvd = $LinkLayer.PayloadBytesReceived()

        if ($bytes_rcvd -ge 0 -and $no_data_received)
        {
            # start stopwatch on first received data
            $sw.Start()
            $no_data_received = $false
        }

        if  ($bytes_rcvd -ge $BYTES_TO_FETCH) 
        {
            # abort loop
            break
        }
        

        Start-Sleep -Milliseconds 50 # small sleep to lower CPU load, could change overall time measurement by 50 ms
        [System.Console]::WriteLine("Full streams with payload received {0}. Usable payload bytes received {1}" -f ($LinkLayer.PendingInputStreamCount(), $LinkLayer.PayloadBytesReceived()))
    }

    $sw.Stop() # enough data received, so we stop time and print out full streams

    

    $ttaken = $sw.Elapsed.TotalSeconds
    $throughput_in = $bytes_rcvd / $ttaken # only calculates netto payload data (62 bytes per report, only none-empty reports pushed to input queue) 
    $host.UI.WriteLine("MainThread: {0} payload bytes read in {1} seconds ({2} Bytes/s). Printing out..." -f ($bytes_rcvd, $ttaken, $throughput_in)) # use this to print all reports and check for loss

    # print out payload part of all reports to assure no packet is lost
    while ($LinkLayer.PendingInputStreamCount() -gt 0) # print out fully captured streams
    {
        $stream = $LinkLayer.PopPendingInputStream()
        # $utf8 = ([System.Text.Encoding]::UTF8.GetString($stream))
        $utf8 = ([System.Text.Encoding]::UTF8.GetString($stream[0..99])) # trim received stream to 100 UTF8 chars (uncomment method above to check for stream completeness)
        # $host.UI.WriteLine("MainThread: received report: $utf8") # use this to print all reports and check for loss
        $host.UI.WriteLine("MainThread: received stream of length {0}, printing out first 100 bytes as UTF8:" -f $stream.Length) 
        $host.UI.WriteLine("{0} ...snip..." -f $utf8) 
    }
    
    $host.UI.WriteLine("MainThread: {0} payload bytes read in {1} seconds ({2} Bytes/s)." -f ($bytes_rcvd, $ttaken, $throughput_in)) # use this to print all reports and check for loss
    [Console]::WriteLine("Throughput in {0} bytes/s netto payload data (excluding report loss and resends)" -f $throughput_in)

    # keep running
    $sw.Reset()
    $sw.Start()
    while($true)
    {
        

        $bytes_rcvd = $LinkLayer.PayloadBytesReceived()
        if  ($bytes_rcvd -ge $BYTES_TO_FETCH)
        {
            $sw.Stop()
            $ttaken = $sw.Elapsed.TotalSeconds
            $tp = $bytes_rcvd / $ttaken
            $LinkLayer.globalstate.payload_bytes_received = 0
            $sw.Reset()
            $sw.Start()
            $host.UI.WriteLine("MainThread: {0} payload bytes read in {1} seconds ({2} Bytes/s)." -f ($bytes_rcvd, $ttaken, $tp)) 
        }
        
        Start-Sleep -m 1000
        
        # go on processing inbound data
        while ($LinkLayer.PendingInputStreamCount() -gt 0) # print out fully captured streams
        {
            $stream = $LinkLayer.PopPendingInputStream()
            # $utf8 = ([System.Text.Encoding]::UTF8.GetString($stream))
            $utf8 = ([System.Text.Encoding]::UTF8.GetString($stream[0..99])) # trim received stream to 100 UTF8 chars (uncomment method above to check for stream completeness)
            
            #$host.UI.WriteLine("MainThread: received stream of length {0}, printing out first 100 bytes as UTF8:" -f $stream.Length) 
            #$host.UI.WriteLine("{0} ...snip..." -f $utf8) 
        }

        # enque output
        $stream_size = 100*$LinkLayer.globalstate.PAYLOAD_MAX_SIZE
        #$max_bytes = 62*1024 + $stream_size
        $max_bytes = 9*6200
        TEST_enqueue_ouput $qout $stream_size $max_bytes
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

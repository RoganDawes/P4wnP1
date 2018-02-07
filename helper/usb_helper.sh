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
# inits USB gadget according to config (payload, if not specified in payload according to defaults.conf)

# set variable for USB gadget directory
GADGETS_DIR="mame82gadget"


# ToDo: If USB gadget is reinitialized without Ethernet over USB (RNDIS, CDC ECM or both), the possibly
#	running DHCP client/server isn't killed (handle by usb_ethernet_helper, not usb_helper).
#	This is a minor issue, as these processes are killed with every reconfiguration of Ethernet over
#	USB (command 'init_usb_ethernet')

function init_usb()
{
	### INPUT OTIONS
	
	# USB_VID
	# USB_PID
	# USE_RNDIS
	# USE_ECM
	# USE_HID
	# USE_RAWHID
	# USE_HID_MOUSE
	# USE_UMS
	# UMS_CDROM
	# UMS_FILE_PATH
	# wdir
	
	### OUTPUT OPTIONS
	
	# device_hid_keyboard (optional)
	# device_hid_raw (optional)
	# device_hid_mouse (optional)
	
	# check if there's already a gadget_configuration running
	if is_gadget_running; then
		echo "There's already a gadget configuration ... deinitializing old gadget"
		deinit_usb
	fi
	
	if detect_usb_hostmode; then
		echo "The Pi is running in USB OTG mode, aborting gadget creation ..."
		return 1
	fi
	
	# ====================
	# USB Init
	# ====================

	# configure USB gadget to provide (RNDIS like) ethernet interface
	# see http://isticktoit.net/?p=1383
	# ----------------------------------------------------------------

	echo
	echo "Creating USB composite device..."
	echo "======================================================"

	cd /sys/kernel/config/usb_gadget
	mkdir -p $GADGETS_DIR
	cd $GADGETS_DIR

	# configure gadget details
	# =========================
	# set Vendor ID
	echo $(getoption USB_VID) > idVendor # RNDIS
	
	# set Product ID
	echo $(getoption USB_PID) > idProduct # RNDIS
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
	echo 0x80 > configs/c.1/bmAttributes #  USB_OTG_SRP | USB_OTG_HNP

	local USB_ETHERNET=false

	# create RNDIS function
	# =======================================================
	if $(getoption USE_RNDIS); then
		echo "... adding RNDIS function"
		mkdir -p functions/rndis.usb0
		# set up mac address of remote device
		echo "42:63:65:13:34:56" > functions/rndis.usb0/host_addr
		# set up local mac address
		echo "42:63:65:66:43:21" > functions/rndis.usb0/dev_addr
		
		USB_ETHERNET=true
	fi

	# create CDC ECM function
	# =======================================================
	if $(getoption USE_ECM); then
		echo "... adding CDC ECM function"
		mkdir -p functions/ecm.usb1
		# set up mac address of remote device
		echo "42:63:65:12:34:56" > functions/ecm.usb1/host_addr
		# set up local mac address
		echo "42:63:65:65:43:21" > functions/ecm.usb1/dev_addr
		
		USB_ETHERNET=true
	fi

	# create HID function
	# =======================================================
	if $(getoption USE_HID); then
		echo "... adding HID keyboard function"
		mkdir -p functions/hid.g1
		PATH_HID_KEYBOARD="/sys/kernel/config/usb_gadget/$GADGETS_DIR/functions/hid.g1/dev"
		echo 1 > functions/hid.g1/protocol
		echo 1 > functions/hid.g1/subclass
		echo 8 > functions/hid.g1/report_length
		cat $(getoption wdir)/conf/report_desc > functions/hid.g1/report_desc
	fi

	# create RAW HID function
	# =======================================================
	if $(getoption USE_RAWHID); then
		echo "... adding HID custom device function"
		mkdir -p functions/hid.g2
		PATH_HID_RAW="/sys/kernel/config/usb_gadget/$GADGETS_DIR/functions/hid.g2/dev"
		echo 1 > functions/hid.g2/protocol
		echo 1 > functions/hid.g2/subclass
		echo 64 > functions/hid.g2/report_length
		cat $(getoption wdir)/conf/raw_report_desc > functions/hid.g2/report_desc
	fi

	# create HID mouse function
	# =======================================================
	if $(getoption USE_HID_MOUSE); then
		echo "... adding HID mouse function"
		mkdir -p functions/hid.g3
		PATH_HID_MOUSE="/sys/kernel/config/usb_gadget/$GADGETS_DIR/functions/hid.g3/dev"
		echo 2 > functions/hid.g3/protocol
		echo 1 > functions/hid.g3/subclass
		echo 6 > functions/hid.g3/report_length

		cat $(getoption wdir)/conf/mouse_combined_desc > functions/hid.g3/report_desc
	fi

	# Create USB Mass storage
	# ==============================
	if $(getoption USE_UMS); then
		printf "... adding USB Mass Storage function "
		mkdir -p functions/mass_storage.usb0
		echo 1 > functions/mass_storage.usb0/stall # allow bulk EPs
		if $(getoption UMS_CDROM); then
			echo 1 > functions/mass_storage.usb0/lun.0/cdrom # emulate CD-ROm
			printf "(CDROM)\n"
		else
			printf "(flashdrive)\n"
			echo 0 > functions/mass_storage.usb0/lun.0/cdrom # don't emulate CD-ROm
		fi

		echo 0 > functions/mass_storage.usb0/lun.0/ro # write acces (using ro for CD-Rom resulted in a ro mounted root partition on P4wnP1)

		# enable Force Unit Access (FUA) to make Windows write synchronously
		# this is slow, but unplugging the stick without unmounting works
		echo 0 > functions/mass_storage.usb0/lun.0/nofua
		echo $(getoption wdir)/$(getoption UMS_FILE_PATH) > functions/mass_storage.usb0/lun.0/file
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
	if $(getoption USE_RNDIS); then
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

	if $(getoption USE_RNDIS); then
		ln -s functions/rndis.usb0 configs/c.1/ # RNDIS on config 1 # RNDIS has to be the first interface on Composite device
	fi

	if $(getoption USE_HID); then
		ln -s functions/hid.g1 configs/c.1/ # HID on config 1
	fi

	if $(getoption USE_RAWHID); then
		ln -s functions/hid.g2 configs/c.1/ # HID on config 1
	fi

	if $(getoption USE_HID_MOUSE); then
		ln -s functions/hid.g3 configs/c.1/ # HID mouse on config 1
	fi

	if $(getoption USE_ECM); then
		ln -s functions/ecm.usb1 configs/c.1/ # ECM on config  1
	fi

	if $(getoption USE_UMS); then
		ln -s functions/mass_storage.usb0 configs/c.1/ # USB Mass Storage on config  1
	fi

	#ln -s functions/acm.GS0 configs/c.1/ # USB Mass Storage on config  1

	if $(getoption USE_RNDIS); then
		ln -s configs/c.1/ os_desc # add config 1 to OS descriptors
	fi

	# check for first available UDC driver
	UDC_DRIVER=$(ls /sys/class/udc | cut -f1 | head -n 1)
	# bind USB gadget to this UDC driver
	echo $UDC_DRIVER > UDC

	if [ $? -eq 0 ]; then
		echo "Enabeling USB device succeeded."
	else
		echo "ERROR: Enabeling USB device failed. Too many endpoints used ? Maybe you should disable some functions"
		deinit_usb
		return
	fi

	# time to breath
	sleep 0.2
	
	
	# store device names to file 
	##############################
	if $(getoption USE_HID); then
		udevadm info -rq name  /sys/dev/char/$(cat $PATH_HID_KEYBOARD) > /tmp/device_hid_keyboard
		setoption device_hid_keyboard $(udevadm info -rq name  /sys/dev/char/$(cat $PATH_HID_KEYBOARD))
	else
		deloption device_hid_keyboard
	fi
	
	if $(getoption USE_RAWHID); then
		udevadm info -rq name  /sys/dev/char/$(cat $PATH_HID_RAW) > /tmp/device_hid_raw
		setoption device_hid_raw $(udevadm info -rq name  /sys/dev/char/$(cat $PATH_HID_RAW))
	else
		deloption device_hid_raw
	fi
	
	if $(getoption USE_HID_MOUSE); then
		udevadm info -rq name  /sys/dev/char/$(cat $PATH_HID_MOUSE) > /tmp/device_hid_mouse
		setoption device_hid_mouse $(udevadm info -rq name  /sys/dev/char/$(cat $PATH_HID_MOUSE))
	else
		deloption device_hid_mouse
	fi

	echo "Use USB Ethernet: $USB_ETHERNET"	
	if $USB_ETHERNET; then
		prepare_usb_ethernet
	fi
}

function is_gadget_running()
{
	# check if configfs allows gadget configuration
	if [ ! -d "/sys/kernel/config/usb_gadget" ]; then 
		echo "No gadget configuration support via configfs"
		return 1 # not running
	fi

	for gadget_name in $(ls /sys/kernel/config/usb_gadget); do 
		# if we are here, a subfolder has been found and thus a gadget declared
		return 0
	done
	
	return 1
}

function deinit_usb()
{
	echo
	echo "Deinit USB gadget"
	echo "====================================="

	# check if configfs allows gadget configuration
	if [ ! -d "/sys/kernel/config/usb_gadget" ]; then 
		echo "No gadget configuration support via configfs"
		return
	else
		echo "Gadget configuration via configfs enabled..."
	fi

	# delete the bridge for eth over USB if existing
	deinit_usb_ethernet

	for gadget_name in $(ls /sys/kernel/config/usb_gadget); do 
		echo "Gadget found '$gadget_name' ... deinitializing ..."

		gfldr="/sys/kernel/config/usb_gadget/$gadget_name"


		# unbind from UDC
		echo "Unbind gadget '$gadget_name' from UDC ..."
		echo "" > $gfldr/UDC

		# iterate over configurations
		for config_name in $(ls $gfldr/configs); do 
			echo "Found config '$config_name', deleting ..."
			cfldr="$gfldr/configs/$config_name"

			echo "    Removing functions from configuration '$config_name' ..."

			# find and remove linked functions
			lnfunctions=$(ls -l $cfldr | grep "lrwxrwxrwx" | awk '{print $9}')
			for function_name in $lnfunctions; do
				echo "    Unlinking function '$function_name'"
				rm $cfldr/$function_name
			done

			# remove strings directories from configuration
			for strdir in $(ls $cfldr/strings); do
				echo "    Removing string dir '$strdir' from configuration"
				rmdir $cfldr/strings/$strdir
			done

			# check if there's an os_desc linking the configuration
			if [ -d "$gfldr/os_desc/$config_name" ]; then 
				echo "    Deleting link to '$config_name' from gadgets OS descriptor"
				rm $gfldr/os_desc/$config_name
			fi

			# remove config folder at all
			echo "    Deleting configuration '$config_name'"
			rmdir $cfldr
		done

		# remove functions
		echo "Removing functions from '$gadget_name'"
		rmdir -v $gfldr/functions/*

		# remove strings from gadget
		for strdir in $(ls $gfldr/strings); do
			echo "Removing string dir '$strdir' from '$gadget_name'"
			rmdir $gfldr/strings/$strdir
		done

		# Remove whole gadget
		echo "Removing gadget ..."
		rmdir -v $gfldr

	done
}


# this could be use to re init USB gadget with different settings
function reinit_usb()
{
        # detach USB gadget from UDC driver
        deinit_usb
		sleep 0.2
        # reattach
        init_usb
}


function detect_usb_hostmode()
{
	if grep -q "DCFG=0x00000000" /sys/kernel/debug/20980000.usb/state; then
		echo "USB OTG Mode"
		OTG_MODE=true
		setoption OTG_MODE true
		return 0
	else
		OTG_MODE=false
		setoption OTG_MODE false
		return 1
	fi
}

USB_BRNAME=usbeth
function prepare_usb_ethernet()
{
	printf "... preparing network interface for USB ethernet on $USB_BRNAME"
	active_interface=$USB_BRNAME # backwards compatibility (used in callbacks)
	
	# prepare bridge interface (will include bnep ifaces for connected devices)
	brctl addbr $USB_BRNAME # add bridge interface
	brctl setfd $USB_BRNAME 0 # set forward delay to 0 ms
	brctl stp $USB_BRNAME off # disable spanning tree 
	
	#ifconfig $USB_BRNAME $IF_IP netmask $IF_MASK
	ifconfig $USB_BRNAME up

	for IF in $(ls /sys/class/net | grep usb | grep -v -e "$USB_BRNAME"); do
		brctl addif $USB_BRNAME $IF
		ifconfig $IF up 
	done
	printf  " ... done\n"
}

function deinit_usb_ethernet()
{
	# check if Ethernet over USB bridge exists
	if sudo brctl show | grep -q -e $USB_BRNAME; then 
		echo "Deleting ethernet over USB interface '$USB_BRNAME' ..."
		sudo ifconfig usbeth down
		sudo brctl delbr usbeth
	fi
}

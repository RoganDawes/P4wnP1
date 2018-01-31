#!/bin/bash




wdir=$(cd .. && pwd)
source ../defaults.conf
source ../boot/init_usb.sh

deinit_usb

echo "Reinit USB after RETURN"
read


USB_VID="0x1d6b"        # Vendor ID
USB_PID="0x013A"        # Product ID

USE_ECM=true            # if true CDC ECM will be enabled
USE_RNDIS=false          # if true RNDIS will be enabled
USE_HID=true            # if true HID (keyboard) will be enabled
USE_HID_MOUSE=true            # if true HID mouse will be enabled
USE_RAWHID=false         # if true a raw HID device will be enabled
USE_UMS=true           # if true USB Mass Storage will be enabled
init_usb



echo "Reinit USB after RETURN"
read

deinit_usb

USB_VID="0x1d6b"        # Vendor ID
USB_PID="0x013B"        # Product ID

USE_ECM=true            # if true CDC ECM will be enabled
USE_RNDIS=true          # if true RNDIS will be enabled
USE_HID=false            # if true HID (keyboard) will be enabled
USE_HID_MOUSE=false            # if true HID mouse will be enabled
USE_RAWHID=false         # if true a raw HID device will be enabled
USE_UMS=false           # if true USB Mass Storage will be enabled
init_usb

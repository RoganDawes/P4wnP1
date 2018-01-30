#!/bin/sh


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
# Provides functionality to exchange the WiFi driver + firmware with
# binaries from the Nexmon in order to provide capabilities for
# frame injection and monitor mode (with radiotap header support).
#
# The needed binaries are precompiled and currently only Kernel 4.9.51+ is supported 
#
# Nexmon by [@seemoo-lab](https://github.com/seemoo-lab) (NexMon Team) is licensed under GNU General Public License v3.0. The sources used to compile could be found here:
# https://github.com/seemoo-lab/nexmon/tree/917ee86913ba2826e9525e08929937bf764822b8



nexmondir="$wdir/nexmon"

# check for wifi capability
function check_wifi()
{
	echo "WiFi check init_wifi_nexmon"
	if $wdir/wifi/check_wifi.sh; then WIFI=true; else WIFI=false; fi
}

function validate_nexmon_version()
{
	if [ "$(cat $nexmondir/kernel_release 2>/dev/null)" == "$(uname -r)" ]; then return 0; else return 1; fi
}


function WIFI_activate_nexmon()
{
	if ! validate_nexmon_version; then
		echo "Installed nexmon version doesn't fit kernel release $(uname -r)"
		return 1
	fi

	#backup-firmware (not realy needed as backup firmware is shipped with nexmon additions)
#	if [ ! -f brcmfmac43430-sdio.bin.orig ]; then
#		printf "\033[0;31m  BACKUP\033[0m of brcmfmac43430-sdio.bin written to $(pwd)/brcmfmac43430-sdio.bin.orig\n"
#		sudo cp /lib/firmware/brcm/brcmfmac43430-sdio.bin $nexmondir/brcmfmac43430-sdio.bin.orig
#	fi

	#install-firmware: brcmfmac43430-sdio.bin brcmfmac.ko
	printf "\033[0;31m  COPYING\033[0m brcmfmac43430-sdio.bin => /lib/firmware/brcm/brcmfmac43430-sdio.bin\n"
	sudo cp $nexmondir/brcmfmac43430-sdio.bin /lib/firmware/brcm/brcmfmac43430-sdio.bin

	if [ $(lsmod | grep "^brcmfmac" | wc -l) == "1" ]
	then
		printf "\033[0;31m  UNLOADING\033[0m brcmfmac\n"
	        sudo rmmod brcmfmac
	fi

	sudo modprobe brcmutil
	printf "\033[0;31m  RELOADING\033[0m brcmfmac\n"

	sudo insmod $nexmondir/brcmfmac.ko

	# activate dual interface mode
	sleep 1
#	sudo $nexmondir/nexutil -m7 # The nexmon master has been updated with to support dual interface without -m7

	
	sleep 2
	if $WIFI_NEXMON_BRING_UP_MONITOR_FIRST; then
		# activate the monitor interface, in order to avoid that legacy hostapd uses it (wouldn't work)
		# so this is a dirty hack to let legacy hostapd run on nexmon
		
		sudo $nexmondir/airmon-ng start wlan0
	fi
}

function WIFI_activate_legacy()
{
	if ! validate_nexmon_version; then
		echo "Installed nexmon version doesn't fit kernel release $(uname -r)"
		return 1
	fi

	printf "\033[0;31m  COPYING\033[0m brcmfmac43430-sdio.bin.backup => /lib/firmware/brcm/brcmfmac43430-sdio.bin\n"
	sudo cp $nexmondir/brcmfmac43430-sdio.bin.backup /lib/firmware/brcm/brcmfmac43430-sdio.bin

	if [ $(lsmod | grep "^brcmfmac" | wc -l) == "1" ]
	then
		printf "\033[0;31m  UNLOADING\033[0m brcmfmac\n"
	        sudo rmmod brcmfmac
	fi

	sudo modprobe brcmutil
	printf "\033[0;31m  RELOADING\033[0m brcmfmac\n"

	sudo insmod /lib/modules/$(uname -r)/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko
}


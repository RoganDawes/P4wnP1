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
# provides Bluetooth NAP functionality for Pi Zero W (equipped with BT module)

# This script is ran by a dedicated service, not by the main P4wnP1 boot service
# (because we are depending on d-bus, which is available late at boot).
# Because of this fact the settings of setup.cfg and the current payload have
# to be imported, without executing the payload again.

# source in configurations
############
wdir=$( cd $(dirname $BASH_SOURCE[0]) && cd .. && pwd)
# include setup.cfg (calling source is fine, as no code should be included)
source $wdir/setup.cfg

# include payload (overrides variables set by setup.cfg if needed)
# as the payload could include code (like the hakin9 tutorial), we only
# import bash variables, using a temporary file
cat $wdir/payloads/$PAYLOAD | grep "=" > /tmp/payload_vars
source /tmp/payload_vars
rm /tmp/payload_vars

# ToDo: check for bluetooth capability (Pi Zero hasn't BT)
#       Note: shouldn't be needed, as this file is started by a service
#             which depends on bluetooth.service      

BRNAME=pan0

function generate_dnsmasq_bt_conf()
{
	cat <<- EOF > /tmp/dnsmasq_bt.conf
		bind-interfaces
		port=0
		interface=$BRNAME
		listen-address=$BLUETOOTH_NAP_IP
		dhcp-range=$BLUETOOTH_NAP_DHCP_RANGE,$BLUETOOTH_NAP_NETMASK,5m

		# router
		#dhcp-option=3,$BLUETOOTH_NAP_IP

		# DNS
		#dhcp-option=6,$BLUETOOTH_NAP_IP

		# NETBIOS NS
		#dhcp-option=44,$BLUETOOTH_NAP_IP
		#dhcp-option=45,$BLUETOOTH_NAP_IP

		dhcp-leasefile=/tmp/dnsmasq_bt.leases
		dhcp-authoritative
		log-dhcp
EOF
}

# start BNEP network access point
function start_BLUETOOTH_NAP()
{
	modprobe bnep

	# prepare bridge interface (will include bnep ifaces for connected devices)
	sudo brctl addbr $BRNAME # add bridge interface
	sudo brctl setfd $BRNAME 0 # set forward delay to 0 ms
	sudo brctl stp $BRNAME off # disable spanning tree (this should be the only bridge interface, so no loops)


	# configure interface
	sudo ifconfig $BRNAME $BLUETOOTH_NAP_IP netmask $BLUETOOTH_NAP_NETMASK
	#sudo ifconfig $BRNAME up
	sudo ip link set $BRNAME up

	# start DHCP server (second instance if USB over Etherne is in use)
	generate_dnsmasq_bt_conf
	sudo dnsmasq -C /tmp/dnsmasq_bt.conf

	sudo bt-agent -c NoInputNoOutput& # handle incoming BT requests, no PIN (daemon mode broken according to README)

	sudo bt-adapter -a hci0 --set Discoverable 1 # allow the bluetooth adapter to be discovered (use default adapter)
	sudo bt-adapter -a hci0 --set DiscoverableTimeout 0
	sudo bt-adapter -a hci0 --set Pairable 1
	sudo bt-adapter -a hci0 --set PairableTimeout 0

	#sudo hciconfig hci0 lm master # enable link mode 'master' for bt device # not needed
	
	# Note: if bt-network is used in daemon mode, unregistering the server fails after the process receives SIGTERM
	#       thus we run as background job
	sudo bt-network -a hci0 -s nap pan0 &# register bridge interface via d-bus for server mode "NAP" (use default adapter)
	
	#sudo bt-network -a hci0 -s gn pan0 # register bridge interface via d-bus for server mode "GN" (use default adapter)
	
}

# start BNEP network accessing an existing PAN
# Instead of pairing from P4wnP1 to the device, which provides the NAP, the device
# has to pair to us and we use the provided PAN afterwards (connect to it and receive an
# IP configuration via DHCP). This has two advantages:
#	1) We don't need to interactively handle PASSKEYs or PINs, which would
#	be the case if pairing is initiated from P4wnP1
#	2) We don't need to know or discover the MAC of the remote device, as we simply
#	use the NAP feature of the devices which pairs to us
#
# This is an uncommon approach, as typically the device which provide the NAP
# (bluetooth tethering) receives the pairing request and after successful pairing
# is connected by the remote device (which is P4wnP1 in this case). Anyway, it has 
# been tested with to androids and is working, IF THE FOLLOWING POINTS ARE REGARDED (ANDROID):
#
#	0) Pre Step: If P4wnP1 is already in the list of paired devices of the Android phone, it has to
#	be removed first !!!!
# 	1) Enable bluetooth on Android
#	2) Enable bluetooth tethering on Android to provide an Internet connection
#	3) Instead of waiting for a pairing request, scan for existing bluetooth devices
#	and pair with P4wnP1 when found !!!
#	4) P4wnP1 allows pairing to everyone (no PIN, no Access Key). The Pairing initiated
#	from the android phone is combined with a "connect" from the Adroid phone, this
#	again allows P4wnP1 to connect to the provided Network Access Point, which should
#	be reflected from the phones UI (shortly after pairing succeeds).
#
#	Important: Once P4wnP1 is paired with the phone (and thus known) it isn't possible
#	to connect again (after a disconnect). This is because P4wnP1 provides no bluetooth services
#	which could be connected to when used as PAN user. This essentially means: to reproduce
#	the steps, P4wnP1 has to be removed from the phone's list of paired devices.
#	Pairing again involves the establishment of the needed device connection from the phones
#	end. 
#
#	Additional note: The logic of the NAP code, doesn't account for disconnects at the moment.
#	Thus to reestablih the NAP connection, once lost, P4wnP1 has to be rebooted.

function start_BLUETOOTH_PAN_CLIENT()
{
	# note: commented out all echo's on this function to reduce load on logfiles

	modprobe bnep

	# We don't need a bridge, as we don't receive incoming connections from multiple PANUs
	# when we have successfully connected to a remote PAN, a new interface (bnep0) is spawned

	# Start a pairing agent which accepts every connection !!!INSECURE !!!
	sudo bt-agent -c NoInputNoOutput& # handle incoming BT requests, no PIN (daemon mode broken according to README)

	# Allow P4wnP1 to be discovered and to accept Pairing (forever)
	sudo bt-adapter -a hci0 --set Discoverable 1 # allow the bluetooth adapter to be discovered (use default adapter)
	sudo bt-adapter -a hci0 --set DiscoverableTimeout 0
	sudo bt-adapter -a hci0 --set Pairable 1
	sudo bt-adapter -a hci0 --set PairableTimeout 0

	echo "Starting to search for an available Bluetooth Netwok Access Point (NAP)"

	# run through the list of known devices, till a device is found which is connected
	PAN_UP=false
	while ! $PAN_UP; do
		echo "Inspecting seen BT devices"

		# grab MACs of seen devices
		macs=$(bt-device -l | grep -o -e '..:..:..:..:..:..')


		# for each device, check if it is connected
		for mac in $macs; do 
			echo "... Found bluetooth device $mac ... check if it is connected"
			if (bt-device -i $mac | grep -q -e "Connected: 1"); then 
				echo "... $mac is connected, checking if the device provides NAP"

				if (bt-device -i $mac | grep -q -e "NAP"); then 
					echo "... $mac provides us a NAP, trying to connect to the network" 
					sudo bt-network -a hci0 --connect $mac nap &

					# wait for bnep interface to come up
					BNEP_UP=false
					echo "waiting for bnep0 interface to come up..."
					while ! $BNEP_UP; do
						if (ifconfig | grep -q -e "bnep0"); then
							echo ""
							echo "bnep0 interface up, starting dhcpclient"
							sudo dhclient bnep0
							BNEP_UP=true
						else
							printf "."
						fi
					done

					PAN_UP=true
					echo "ToDo: check for connection success, before break and start DHCP"
					break
				else
					echo "... $mac doesn't provide a NAP (no bluetooth tethering)"
				fi
			else
				echo "... $mac is not connected"
			fi
        done

        # take a 1 second break before evaluating the device list again
        echo "... no device connected, sleeping a while"
        sleep 1
	done



}

function end_BLUETOOTH_NAP()
{
	sudo killall bt-agent
	sudo killall bt-agent # needs two SIGINT (known issue, README)
	sudo killall bt-network
	sudo ifconfig $BRNAME down
	sudo brctl delbr $BRNAME
	sudo kill $(ps -aux | grep 'dnsmasq_bt.conf' | grep -v -e "grep" | awk '{print $2}')
	sudo rm /tmp/dnsmasq_bt.conf
}

function remove_BT_DEVICES()
{
        # remove already discovered bt devices
        macs=$(bt-device -l | grep -o -e '..:..:..:..:..:..')
        for mac in $macs; do 
		echo "... removing device $mac from known ones"
                bt-device -r $mac
        done
}

function discover_BT_DEVICES_till_found()
{
	mac_to_search="$1"
	bt-adapter -a hci0 -d &  # start discovery in background
	while true; do
		# check if mac has been discovered
		printf "."
		if (bt-device -a hci0 -l | grep -q "$mac_to_search"); then
			# we are happy
			echo "... found $mac_to_search"

			# end discovering the hard way
			killall bt-adapter
			break # end while loop
		fi
		sleep 1 # sleep 1 second
	done
}

if $BLUETOOTH_PAN_AUTO; then
	# try to establish a connection to an existing BNEP providing a NAP
	# the NAP providing device has to initiate pairing AND CONNECTION
	(start_BLUETOOTH_PAN_CLIENT > /dev/null) & # supress script output, to avoid log flooding (only needed for debug)
else
	# Bring up an own BNEP NAP and allow everyone to pair
	if $BLUETOOTH_NAP; then
		start_BLUETOOTH_NAP
	fi
fi

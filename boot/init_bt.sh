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

# ToDo: check for bluetooth capability (Pi Zero hasn't BT)

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

function end_BLUETOOTH_NAP()
{
	sudo killall bt-agent
	sudo killall bt-agent # needs to SIGINT (known issue, README)
	sudo killall bt-network
	sudo ifconfig $BRNAME down
	sudo brctl delbr $BRNAME
	sudo kill $(ps -aux | grep 'dnsmasq_bt.conf' | grep -v -e "grep" | awk '{print $2}')
}

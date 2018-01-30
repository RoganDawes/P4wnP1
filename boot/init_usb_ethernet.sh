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
# Functions to init USB ethernet
#	- detect correct interface (ECM / RNDIS) --> exportet to $active_interface
#	- create dnsmasq DHCP configuration for interface



# =================================
# Network init
# =================================

function prepare_usb_ethernet()
{
	USB_BRNAME=usbeth
	active_interface=$USB_BRNAME # backwards compatibility (used in callbacks)
	
	# prepare bridge interface (will include bnep ifaces for connected devices)
	brctl addbr $USB_BRNAME # add bridge interface
	brctl setfd $USB_BRNAME 0 # set forward delay to 0 ms
	brctl stp $USB_BRNAME off # disable spanning tree 
	
	ifconfig $USB_BRNAME $IF_IP netmask $IF_MASK
	
	for IF in $(ls /sys/class/net | grep usb | grep -v -e "$USB_BRNAME"); do
		brctl addif $USB_BRNAME $IF
		ifconfig $IF up 
	done
}

function create_usb_ethernet_DHCP_config()
{
	# create DHCP config file for dnsmasq
	echo "P4wnP1: Creating DHCP configuration for Ethernet over USB..."

		cat <<- EOF > /tmp/dnsmasq_usb_eth.conf
			bind-interfaces
			port=0
			interface=$active_interface
			listen-address=$IF_IP
			dhcp-range=$IF_DHCP_RANGE,$IF_MASK,5m

		EOF

		if $ROUTE_SPOOF; then
			cat <<- EOF >> /tmp/dnsmasq_usb_eth.conf
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
			EOF
		else
			cat <<- EOF >> /tmp/dnsmasq_usb_eth.conf
				# router disable DHCP gateway announcment
				dhcp-option=3

				# disable DNS settings
				dhcp-option=6
			EOF
		fi

		if $WPAD_ENTRY; then
			cat <<- EOF >> /tmp/dnsmasq_usb_eth.conf
				dhcp-option=252,http://$IF_IP/wpad.dat
			EOF
		fi

		cat <<- EOF >> /tmp/dnsmasq_usb_eth.conf
			dhcp-leasefile=/tmp/dnsmasq.leases
			dhcp-authoritative
			log-dhcp
		EOF

}

function start_DHCP_server()
{

	# recreate DHCP config
	if $ROUTE_SPOOF; then
		# DHCP config with static route spoofing
		cat <<- EOF > $wdir/dnsmasq.conf
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

			dhcp-leasefile=/tmp/dnsmasq.leases
			dhcp-authoritative
			log-dhcp
		EOF
	else
		# DHCP config without static route spoofing
		cat <<- EOF > $wdir/dnsmasq.conf
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

			dhcp-leasefile=/tmp/dnsmasq.leases
			dhcp-authoritative
			log-dhcp
		EOF
	fi;


	# start access point if needed
	if $WIFI && $ACCESS_POINT; then
		# start ACCESS POINT
		hostapd $wdir/wifi/hostapd.conf > /dev/null &
		# configure interface
		ifconfig wlan0 172.24.0.1 netmask 255.255.255.252
		# start DHCP server for WLAN interface and RNDIS/CDC ECM
		dnsmasq -C $wdir/dnsmasq.conf -C $wdir/wifi/dnsmasq_wifi.conf
	else

		# start DHCP server (listening on IF_IP)
		dnsmasq -C $wdir/dnsmasq.conf
	fi
}

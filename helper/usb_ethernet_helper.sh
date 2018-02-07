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
#	- create dnsmasq DHCP configuration for interface



# =================================
# Network init
# =================================
function init_usb_ethernet_dhcp()
{
	mode=$(getoption USB_ETHERNET_DHCP_MODE)
	
	# kill DHCP server on usb ethernet interface if runnning (even if still needed, we recreate)
	echo "Killing former DHCP server processes for interface 'usbeth'"
	sudo kill $(cat /tmp/usbeth_dnsmasq.pid 2>/dev/null) 2>/dev/null; sudo rm /tmp/usbeth_dnsmasq.pid 2>/dev/null
	# kill DHCP client on usb ethernet interface if running  (even if still needed, we recreate)
	echo "Killing former DHCP client processes for interface 'usbeth'"
	sudo dhclient -v -r -pf /tmp/usbeth_dhclient.pid usbeth
	
	echo "DHCP mode: $mode"
	if [ $mode == "server" ]; then 
		echo "Starting DHCP server on usb ethernet interface"
		
		
		# (re)create DHCP configuration
		create_usb_ethernet_DHCP_config
		
		# configure interface with correct IP/NETMASK
		sudo ifconfig usbeth $(getoption USB_ETHERNET_IP) netmask $(getoption USB_ETHERNET_NETMASK)
		
		# start DHCP server with respective options
		sudo dnsmasq -C /tmp/usbeth_dnsmasq.conf -x /tmp/usbeth_dnsmasq.pid
		
	else
		if [ $mode == "client" ]; then 
			echo "Starting DHCP client on usb ethernet interface"
			
			# start DHCP client
			sudo dhclient -v -nw -lf /tmp/usbeth_dhclient.leases -pf /tmp/usbeth_dhclient.pid usbeth
		else
			echo "Manual configuration of usb ethernet interface (no DHCP at all)"
			# failover to manual configuration
			
			# configure interface with correct IP/NETMASK
			sudo ifconfig usbeth $(getoption USB_ETHERNET_IP) netmask $(getoption USB_ETHERNET_NETMASK)
		fi;
	fi

	
}

function create_usb_ethernet_DHCP_config()
{
	# create DHCP config file for dnsmasq
	echo "P4wnP1: Creating DHCP server configuration for Ethernet over USB..."

		cat <<- EOF > /tmp/usbeth_dnsmasq.conf
			bind-interfaces
			port=0
			interface=usbeth
			listen-address=$(getoption USB_ETHERNET_IP)
			dhcp-range=$(getoption USB_ETHERNET_DHCP_RANGE),$(getoption USB_ETHERNET_NETMASK),5m

		EOF

		# Gateway options
		if $(getoption USB_ETHERNET_DHCP_OPTION_GW); then
			echo "... propagate as gateway"
			cat <<- EOF >> /tmp/usbeth_dnsmasq.conf
				# router
				dhcp-option=3,$(getoption USB_ETHERNET_IP)
			EOF
			
			# route spoof is only possible if P4wnP1 propagates itself as GW
			if $(getoption USB_ETHERNET_DHCP_OPTION_ROUTESPOOF); then
				echo "... propagate static routes for full public IPv4 address range"
				cat <<- EOF >> /tmp/usbeth_dnsmasq.conf
					# routes static (route 0.0.0.1 to 127.255.255.254 through our device)
					dhcp-option=121,0.0.0.0/1,$(getoption USB_ETHERNET_IP),128.0.0.0/1,$(getoption USB_ETHERNET_IP)
					# routes static (route 128.0.0.1 to 255.255.255.254 through our device)
					dhcp-option=249,0.0.0.0/1,$(getoption USB_ETHERNET_IP),128.0.0.0/1,$(getoption USB_ETHERNET_IP)
				EOF
			fi
		else
			echo "... DON'T propagate as gateway"
			cat <<- EOF >> /tmp/usbeth_dnsmasq.conf
				# router
				dhcp-option=3
			EOF
		fi

		# DNS options
		if $(getoption USB_ETHERNET_DHCP_OPTION_DNS); then
			echo "... propagate as DNS server"
			cat <<- EOF >> /tmp/usbeth_dnsmasq.conf
				# DNS
				dhcp-option=6,$(getoption USB_ETHERNET_IP)
			EOF
		else
			echo "... DON'T propagate as DNS server"
			cat <<- EOF >> /tmp/usbeth_dnsmasq.conf
				# disable DNS settings
				dhcp-option=6
			EOF
		fi
		
		# NETBIOS options
		if $(getoption USB_ETHERNET_DHCP_OPTION_NBS); then
			echo "... propagate as NETBIOS nameserver"
			cat <<- EOF >> /tmp/usbeth_dnsmasq.conf
				# NETBIOS NS
				dhcp-option=44,$(getoption USB_ETHERNET_IP)
				dhcp-option=45,$(getoption USB_ETHERNET_IP)
			EOF
		else
			echo "... DON'T propagate as NETBIOS nameserver"
			cat <<- EOF >> /tmp/usbeth_dnsmasq.conf
				# disable NETBIOS NS
				dhcp-option=44
				dhcp-option=45
			EOF
		fi


		# WPAD options
		if $(getoption USB_ETHERNET_DHCP_OPTION_WPAD); then
			echo "... advertise WPAD delivery on http://$(getoption USB_ETHERNET_IP)/wpad.dat"
			cat <<- EOF >> /tmp/usbeth_dnsmasq.conf
				# WPAD
				dhcp-option=252,http://$(getoption USB_ETHERNET_IP)/wpad.dat
			EOF
		fi

		cat <<- EOF >> /tmp/usbeth_dnsmasq.conf
		
			dhcp-leasefile=/tmp/usbeth_dnsmasq.leases
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

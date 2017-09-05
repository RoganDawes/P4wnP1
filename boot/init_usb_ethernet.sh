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
function detect_active_interface()
{


	# Waiting for one of the interfaces to get a link (either RNDIS or ECM)
	#    loop count is limited by $RETRY_COUNT_LINK_DETECTION, to continue execution if this is used 
	#    as blocking boot script
	#    note: if the loop count is too low, windows may not have enough time to install drivers

	# ToDo: check if operstate could be used for this, without waiting for carrieer
	active_interface="none"

	# if RNDIS and ECM are active check which gets link first
	# Note: Detection for RNDIS (usb0) is done first. In case it is active, link availability
	#	for ECM (usb1) is checked anyway (in case both interfaces got link). This is done
	#	to use ECM as prefered interface on MacOS and Linux if both, RNDIS and ECM, are supported.
	if $USE_RNDIS && $USE_ECM; then
		# bring up both interfaces to check for physical link
		ifconfig usb0 up
		ifconfig usb1 up

		echo "CDC ECM and RNDIS active. Check which interface has to be used via Link detection"
		while [ "$active_interface" == "none" ]; do
		#while [[ $count -lt $RETRY_COUNT_LINK_DETECTION ]]; do
			printf "."

			if [[ $(</sys/class/net/usb0/carrier) == 1 ]]; then
				# special case: macOS/Linux Systems detecting RNDIS should use CDC ECM anyway
				# make sure ECM hasn't come up, too
				sleep 0.5
				if [[ $(</sys/class/net/usb1/carrier) == 1 ]]; then
					echo "Link detected on usb1"; sleep 2
					active_interface="usb1"
					ifconfig usb0 down

					break
				fi

				echo "Link detected on usb0"; sleep 2
				active_interface="usb0"
				ifconfig usb1 down

				break
			fi

			# check ECM for link
			if [[ $(</sys/class/net/usb1/carrier) == 1 ]]; then
				echo "Link detected on usb1"; sleep 2
				active_interface="usb1"
				ifconfig usb0 down

				break
			fi


			sleep 0.5
		done
	fi

	# if eiter one, RNDIS or ECM is active, wait for link on one of them
	if ($USE_RNDIS && ! $USE_ECM) || (! $USE_RNDIS && $USE_ECM); then 
		# bring up interface
		ifconfig usb0 up

		echo "CDC ECM or RNDIS active. Check which interface has to be used via Link detection"
		while [ "$active_interface" == "none" ]; do
			printf "."

			if [[ $(</sys/class/net/usb0/carrier) == 1 ]]; then
				echo "Link detected on usb0"; sleep 2
				active_interface="usb0"
				break
			fi
		done
	fi


	# setup active interface with correct IP
	if [ "$active_interface" != "none" ]; then
		ifconfig $active_interface $IF_IP netmask $IF_MASK
	fi


	# if active_interface not "none" (RNDIS or CDC ECM are running)
#	if [ "$active_interface" != "none" ]; then
#		# setup DHCP server
#		start_DHCP_server
#
#		# call onNetworkUp() from payload
#		declare -f onNetworkUp > /dev/null && onNetworkUp
#
#		# wait for client to receive DHCP lease
#		target_ip=""
#		while [ "$target_ip" == "" ]; do
#			target_ip=$(cat /tmp/dnsmasq.leases | cut -d" " -f3)
#		done
#
#		# call onNetworkUp() from payload
#		declare -f onTargetGotIP > /dev/null && onTargetGotIP
#	fi

}

function create_DHCP_config()
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

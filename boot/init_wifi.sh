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
# provides WiFi functionality for Pi Zero W (equipped with WiFI module)

# check for wifi capability
function check_wifi()
{
	if $wdir/wifi/check_wifi.sh; then WIFI=true; else WIFI=false; fi
}

##########################
# WiFi AP functions
##########################


function generate_dnsmasq_wifi_conf()
{
	if $WIFI_ACCESSPOINT_DNS_FORWARD; then
		DNS_PORT="53"
	else
		DNS_PORT="0"
	fi

	cat <<- EOF > /tmp/dnsmasq_wifi.conf
		bind-interfaces
		port=$DNS_PORT
		interface=wlan0
		listen-address=$WIFI_ACCESSPOINT_IP
		dhcp-range=$WIFI_ACCESSPOINT_DHCP_RANGE,$WIFI_ACCESSPOINT_NETMASK,5m
EOF

	if $WIFI_ACCESSPOINT_DHCP_BE_GATEWAY; then
		cat <<- EOF >> /tmp/dnsmasq_wifi.conf
			# router
			dhcp-option=3,$WIFI_ACCESSPOINT_IP
EOF
	else
		cat <<- EOF >> /tmp/dnsmasq_wifi.conf
			# router
			dhcp-option=3
EOF
	fi

	if $WIFI_ACCESSPOINT_DHCP_BE_DNS; then
		cat <<- EOF >> /tmp/dnsmasq_wifi.conf
			# DNS
			dhcp-option=6,$WIFI_ACCESSPOINT_IP
EOF
	else
		cat <<- EOF >> /tmp/dnsmasq_wifi.conf
			# DNS
			dhcp-option=6
EOF
	fi

		# NETBIOS NS
		#dhcp-option=44,$WIFI_ACCESSPOINT_IP
		#dhcp-option=45,$WIFI_ACCESSPOINT_IP

	cat <<- EOF >> /tmp/dnsmasq_wifi.conf

		dhcp-leasefile=/tmp/dnsmasq_wifi.leases
		dhcp-authoritative
		log-dhcp
EOF
}

function generate_hostapd_conf()
{
	cat <<- EOF > /tmp/hostapd.conf
		# This is the name of the WiFi interface we configured above
		interface=wlan0

		# Use the nl80211 driver with the brcmfmac driver
		driver=nl80211

		# This is the name of the network
		ssid=$WIFI_ACCESSPOINT_NAME

		# Use the 2.4GHz band
		hw_mode=g

		# Use channel 6
		channel=$WIFI_ACCESSPOINT_CHANNEL

		# Enable 802.11n
		ieee80211n=1

		# Enable WMM
		wmm_enabled=1

		# Enable 40MHz channels with 20ns guard interval
		ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]

		# Accept all MAC addresses
		macaddr_acl=0

EOF

	if $WIFI_ACCESSPOINT_HIDE_SSID; then
	cat <<- EOF >> /tmp/hostapd.conf
		# Require clients to know the network name
		ignore_broadcast_ssid=2

EOF
	else
	cat <<- EOF >> /tmp/hostapd.conf
		# Require clients to know the network name
		ignore_broadcast_ssid=0

EOF
	fi

	if $WIFI_ACCESSPOINT_AUTH; then
	cat <<- EOF >> /tmp/hostapd.conf
		# Use WPA authentication
		auth_algs=1

		# Use WPA2
		wpa=2

		# Use a pre-shared key
		wpa_key_mgmt=WPA-PSK

		# The network passphrase
		wpa_passphrase=$WIFI_ACCESSPOINT_PSK

		# Use AES, instead of TKIP
		rsn_pairwise=CCMP
EOF
	else
	cat <<- EOF >> /tmp/hostapd.conf
		# Both open and shared auth
		auth_algs=3
EOF
	fi

#### Note: KARMA attack is done in firmware now, no need to configure it statically, it gets enabled on-demand ###

#	# the following options only apply to hostapd-mana and would fail on legacy hostapd
#	# as hostapd-mana depends on nexmon driver/firmware we check this, too
#	if $WIFI_ACCESSPOINT_MANA && $WIFI_NEXMON; then
#	cat <<- EOF >> /tmp/hostapd.conf
#		enable_mana=1
#		mana_loud=$WIFI_ACCESSPOINT_KARMA_LOUD
#EOF
#	fi
}



function WIFI_enable_KARMA()
{
	$wdir/nexmon/karmatool.py -k 1
}

function WIFI_disable_KARMA()
{
	$wdir/nexmon/karmatool.py -k 0
}

function WIFI_enable_KARMA_LOUD()
{
	$wdir/nexmon/karmatool.py -b 1
}

function WIFI_disable_KARMA_LOUD()
{
	$wdir/nexmon/karmatool.py -b 0
}

function start_wifi_accesspoint()
{
	generate_hostapd_conf

	hostapd -d /tmp/hostapd.conf > /tmp/hostapd.log &

	# configure interface
	ifconfig wlan0 $WIFI_ACCESSPOINT_IP netmask $WIFI_ACCESSPOINT_NETMASK

	# start DHCP server (second instance if USB over Etherne is in use)
	generate_dnsmasq_wifi_conf
	dnsmasq -C /tmp/dnsmasq_wifi.conf
}


##########################
# WiFi client functions
##########################
function generate_wpa_entry()
{

	#wpa_passphrase $1 $2 | grep -v -e "#psk"
	# output result only if valid password was used (8..63 characters)
	res=$(wpa_passphrase "$1" "$2") && echo "$res" | grep -v -e "#psk"
}

function scan_for_essid()
{
	# scan for given ESSID, needs root privs (sudo appended to allow running from user pi if needed)
	scanres=$(sudo iwlist wlan0 scan essid "$1")

	if (echo "$scanres" | grep -q -e "$1\""); then # added '"' to the end to avoid partial match
		#network found

		# check for WPA2
		if (echo "$scanres" | grep -q -e "IE: IEEE 802.11i/WPA2 Version 1"); then
			# check for PSK CCMP
			if (echo "$scanres" | grep -q -e "CCMP" && echo "$scanres" | grep -q -e "PSK"); then
				echo "WPA2_PSK" # confirm WPA2 usage
			else
				echo "WPA2 no CCMP PSK"
			fi
		fi

	else
		echo "Network $1 not found"
	fi
}

function generate_wpa_supplicant_conf()
{
	# generates temporary configuration (sudo prepended to allow running from user pi if needed)
	sudo bash -c "cat /etc/wpa_supplicant/wpa_supplicant.conf > /tmp/wpa_supplicant.conf"

	# ToDo: check if configured WiFi ESSID already exists,
	# if
	#	WIFI_CLIENT_STORE_NETWORK == true
	#	WIFI_CLIENT_OVERWRITE_PSK == true
	# delete the network entry, to overwrite in the next step
	#
	# if
	#	WIFI_CLIENT_STORE_NETWORK == false
	# delete the network entry, to overwrite the old entry in next step (but don't store it later on)

	generate_wpa_entry "$1" "$2" > /tmp/current_wpa.conf
	sudo bash -c 'cat /tmp/current_wpa.conf >> /tmp/wpa_supplicant.conf'

	# ToDo: store the new network back to persistent config
	# if
	#	WIFI_CLIENT_STORE_NETWORK == true
	# cat /tmp/wpa_supplicant.conf > /etc/wpa_supplicant/wpa_supplicant.conf # store config change
}

function start_wpa_supplicant()
{
	# sudo is unneeded, but prepended in case this should be run without root

	# start wpa supplicant as deamon with current config
	sudo wpa_supplicant -B -i wlan0 -c /tmp/wpa_supplicant.conf

	# start DHCP client on WiFi interface (daemon, IPv4 only)
	sudo dhclient -4 -nw -lf /tmp/dhclient.leases wlan0
}

function start_wifi_client()
{

	sudo ifconfig wlan0 up

	if $WIFI_CLIENT; then
		echo "Try to find WiFi $WIFI_CLIENT_SSID"
		res=$(scan_for_essid "$WIFI_CLIENT_SSID")
		if [ "$res" == "WPA2_PSK" ]; then
			echo "Network $WIFI_CLIENT_SSID found"
			echo "... creating config"
			generate_wpa_supplicant_conf "$WIFI_CLIENT_SSID" "$WIFI_CLIENT_PSK"
			echo "... connecting ..."
			start_wpa_supplicant
			return 0
		else
			echo "Network $WIFI_CLIENT_SSID not found"
			return 1 # indicate error
		fi
	else
		return 1 # indicate error
	fi
}

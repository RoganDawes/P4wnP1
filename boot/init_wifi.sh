#!/bin/sh
#
# provides WiFi functionality for Pi Zero W (equipped with WiFI module)

# check for wifi capability
function check_wifi()
{
	if $wdir/wifi/check_wifi.sh; then WIFI=true; else WIFI=false; fi
}

function generate_dnsmasq_wifi_conf()
{
	cat <<- EOF > /tmp/dnsmasq_wifi.conf
		bind-interfaces
		port=0
		interface=wlan0
		listen-address=$WIFI_ACCESSPOINT_IP
		dhcp-range=$WIFI_ACCESSPOINT_DHCP_RANGE,$WIFI_ACCESSPOINT_NETMASK,5m

		# router
		#dhcp-option=3,$WIFI_ACCESSPOINT_IP

		# DNS
		#dhcp-option=6,$WIFI_ACCESSPOINT_IP

		# NETBIOS NS
		#dhcp-option=44,$WIFI_ACCESSPOINT_IP
		#dhcp-option=45,$WIFI_ACCESSPOINT_IP

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
		channel=6

		# Enable 802.11n
		ieee80211n=1

		# Enable WMM
		wmm_enabled=1

		# Enable 40MHz channels with 20ns guard interval
		ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]

		# Accept all MAC addresses
		macaddr_acl=0

		# Use WPA authentication
		auth_algs=1

		# Require clients to know the network name
		ignore_broadcast_ssid=0

		# Use WPA2
		wpa=2

		# Use a pre-shared key
		wpa_key_mgmt=WPA-PSK

		# The network passphrase
		wpa_passphrase=$WIFI_ACCESSPOINT_PSK

		# Use AES, instead of TKIP
		rsn_pairwise=CCMP
EOF
}

function start_wifi_accesspoint()
{
	generate_hostapd_conf

	hostapd /tmp/hostapd.conf > /dev/null &
#	hostapd /tmp/hostapd.conf

	# configure interface
	ifconfig wlan0 $WIFI_ACCESSPOINT_IP netmask $WIFI_ACCESSPOINT_NETMASK

	# start DHCP server (second instance if USB over Etherne is in use)
	generate_dnsmasq_wifi_conf
	dnsmasq -C /tmp/dnsmasq_wifi.conf
}

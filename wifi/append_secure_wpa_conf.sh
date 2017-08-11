#!/bin/sh
#
# basic tool that takes SSID and Passphrase, generates the psk, strips the cleartext password and appends to /etc/wpa_supplicant/wpa_supplicant.conf

conf_dir=/etc/wpa_supplicant/wpa_supplicant.conf

if [ $# -eq 2 ]; then
	echo >> $conf_dir
	wpa_passphrase $1 $2 | sed '/^\s*#/ d' >> $conf_dir
	printf "\nsuccessfully appended to config\n\n"
else
	printf "\nUsage:\n$0 <ssid> <passphrase>\n\n"
fi

#!/bin/sh
#
# P4wnP1 (PiZero IPv4 traffic interceptor and USB hash stealer)
# stetup script
#       Author: Marcus Mengs (MaMe82)
#
# Notes:
#       - setup_p4wnp1.sh should be ran ONCE
#       - work in progress (contains possible errors and typos)
#	- the script needs Internet connection to install the required packages
#	- if /home/pi/.profile is patched correctly, responder output is shown via HDMI while connected to target
#
# ToDo
# - [done] enable autologin
# - [done, not tested] setup correct overlay FS (set "dwoverlay=dwc2" in /boot/config.txt")
# - [done, not tested] add "libcomposite" to /etc/modules
# - [done] create entries in /etc/network/interfaces to exclude RNDIS/ECM from automatic configuration
# - [nothing to do right now] do not: create init.d service to setup USB gadgets on boot, us .profile instead
# - [done, untested] patch /home/pi/.profile to contain "sudo /home/pi/startup_p4wnp1.sh" as the script is meant to be runned
#   in interactive mode. This is needed to be able to abort the "Link detection mode". In order to have
#   the script running at startup autologin has to be enabled for the user pi!
# - [done and needed as nameserver is set to 127.0.0.1 by apt-get] set DNS entry in /etc/resolv.conf in order to connect to Internet via target host if needed 
#	(no description how to setup target here, as too much off topic stuff ... google helps)
# - [done] implement checks to see of all requirements are met (raspbian jessie, auto logon, packages ...)
# - [open] revert changes in case something fails (could be used to uninstall)
# - [done] check if /boot/cmdline.txt has been changed to load USB gadget modules (modules-load=dwc2,g_ether) and undo this additions

# check Internet conectivity against 
echo "Testing Internet connection and name resolution..."
if [ "$(curl -s http://www.msftncsi.com/ncsi.txt)" != "Microsoft NCSI" ]; then 
        echo "...[Error] No Internet connection or name resolution doesn't work! Exiting..."
        exit
fi
echo "...[pass] Internet connection works"

# check for Raspbian Jessie
echo "Testing if the system runs Raspbian Jessie..."
if ! grep -q -E "Raspbian.*jessie" /etc/os-release ; then 
        echo "...[Error] Pi is not running Raspbian Jessie! Exiting ..."
        exit
fi
echo "...[pass] Pi seems to be running Raspbian Jessie"

startdir=$(pwd)

# Check if script is ran from /home/pi, copy over files otherwise
if [ "$(pwd)" != "/home/pi" ]; then 
	echo "Setup isn't running from /home/pi, copying over files..."; 
	cp -R . /home/pi; 
fi

cd /home/pi

# install dhcpd, git, screen, pip
echo "Installing needed packages..."
sudo apt-get install -y dnsmasq git python-pip python-dev screen sqlite3 

# not needed in production setup
#sudo apt-get install -y tshark tcpdump

# at this point the nameserver in /etc/resolv.conf is set to 127.0.0.1, so we replace it with 8.8.8.8
sudo bash -c "echo nameserver 8.8.8.8 > /etc/resolv.conf"

# install pycrypto
echo "Installing needed python additions..."
pip install pycrypto


# clone Responder from git
echo "Installing Responder (patched MaMe82 branch with Internet connection emulation and wpad additions)..."
#git clone https://github.com/spiderlabs/responder
# clone Responder from own repo (at least till patches are merged into master)
git clone -b EMULATE_INTERNET_AND_WPAD_ANYWAY --single-branch https://github.com/mame82/Responder

# disable interfering services
echo "Disabeling unneeded services to shorten boot time ..."
sudo update-rc.d ntp disable
sudo update-rc.d avahi-daemon disable
sudo update-rc.d dhcpcd disable
sudo update-rc.d dnsmasq disable # we start this by hand later on

echo "Enable SSH server..."
sudo update-rc.d ssh enable

echo "Checking network setup.."
# set manual configuration for usb0 (RNDIS) if not already done
if ! grep -q -E '^iface usb0 inet manual$' /etc/network/interfaces; then
	echo "Entry for manual configuration of RNDIS interface not found, adding..."
	sudo /bin/bash -c "printf '\niface usb0 inet manual\n' >> /etc/network/interfaces"
else
	echo "Entry for manual configuration of RNDIS interface found"
fi

# set manual configuration for usb1 (CDC ECM) if not already done
if ! grep -q -E '^iface usb1 inet manual$' /etc/network/interfaces; then
	echo "Entry for manual configuration of CDC ECM interface not found, adding..."
	sudo /bin/bash -c "printf '\niface usb1 inet manual\n' >> /etc/network/interfaces"
else
	echo "Entry for manual configuration of CDC ECM interface found"
fi


# overwrite Responder configuration
echo "Configure Responder..."
cp conf/default_Responder.conf Responder/Responder.conf
cp conf/default_AccessDenied.html Responder/files/AccessDenied.html


# insert startup scrip into /home/pi/.profile if not present
echo "Injecting P4wnP1 startup script..."
if ! grep -q -E '^[[:space:]]+sudo /bin/bash /home/pi/mame82.sh$' /home/pi/.profile; then
	echo "Addin P4wnP1 startup script to /home/pi/.profile..."
cat << EOF >> /home/pi/.profile
# add a control file, to make sure this doesn't re-run after secondary login (ssh)
if [ ! -f /tmp/startup_runned ]; then
	# run P4wnP1 startup script after login
	sudo /bin/bash /home/pi/startup_p4wnp1.sh
	touch /tmp/startup_runned
	echo "Opening responder screen session in 3 seconds. <CTRL> + <A>, <D> to detach!"
	echo "or run 'sudo screen -d -r responder' in ssh console to re-attach to there"
	echo "Don't use <CTRL> + <C> to leave the screen session, this will kill Responder"
	sleep 3
	sudo screen -r responder
fi
echo "Run 'sudo screen -d -r' to attach to running responder session"
echo "Don't use <CTRL> + <C> to leave the screen session, this will kill Responder"
echo "Use <CTRL> + <A>, <D> instead to detach again"
EOF
fi


# enable autologin for user pi (requires RASPBIAN JESSIE LITE, should be checked)
echo "Enable autologin for user pi..."
sudo ln -fs /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty1.service

# setup USB gadget capable overlay FS (needs Pi Zero, but shouldn't be checked - setup must 
# be possible from other Pi to ease up Internet connection)
echo "Enable overlay filesystem for USB gadgedt suport..."
sudo sed -n -i -e '/^dtoverlay=/!p' -e '$adtoverlay=dwc2' /boot/config.txt

# add libcomposite to /etc/modules
echo "Enable kernel module for USB Composite Device emulation..."
if [ ! -f /tmp/modules ]; then sudo touch /etc/modules; fi
sudo sed -n -i -e '/^libcomposite/!p' -e '$alibcomposite' /etc/modules

echo "Removing all former modules enabled in /boot/cmdline.txt..."
sudo sed -i -e 's/modules-load=.*dwc2[',''_'a-zA-Z]*//' /boot/cmdline.txt

echo "If you came till here without errors, you shoud be good to go with your P4wnP1..."
echo "...if not - sorry, you're on your own, as this is work in progress"
echo "Attach P4wnP1 to your target and enjoy output via HDMI"
echo "You should be able to SSH in with pi@172.16.0.1"
echo 
echo "Responder logs are saved to /home/pi/Responder/logs (but are mixed during boots"
echo "due to the missing NTP server, so delete them if you don't need them)"
echo "Interesting stuff like NTLM hashes is dumped into sqlite DB at:"
echo "/home/pi/Responder/Responder.db"
echo

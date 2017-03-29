P4wnP1 Install Guide
==================

Step 1 - Install Raspbian Jessie Lite
-----------------------------------------------

 1. Download the image from [here](https://www.raspberrypi.org/downloads/raspbian/)
 2. Follow the guide [here](https://www.raspberrypi.org/documentation/installation/installing-images/README.md)

Step 2 - Connect the Pi (Zero) to Internet
------------------------------------------------------

Several methods are existing to do this

 - Method 1: Attaching an USB hub along with a Network Interface (NIC) and use it to connect to the Internet
 - Method 2: Put the SD card into another Raspberry Pi with built-in NIC and connect to the Internet (for example a Pi 3)
 - Method 3: This is the preferred one, as no additional hardware should be needed. Configure the Raspberry Pi **Zero** to act as USB Ethernet adapter and connect back to Internet through your host (Internet Connection Sharing on Windows, iptables MASQUERADING rule on Linux). 

A guide on how to do method 3 could be found [here](http://www.circuitbasics.com/raspberry-pi-zero-ethernet-gadget/). Two things should be noted on method 3:

1. Most Raspberry Pi Zero USB gadget configurations interfere with the configuration of P4wnP1 (which for example doesn't use "g_ether"). The setup script of P4wnP1 tries to fix interfering configurations. If you encouter problems, please try another method to connect to Internet and revert the changes done to the bare RASPBIAN JESSIE image.
2. Unlike described in most tutorials (including the linked one), the SSH server on current Raspbian isn't running by default. You have to boot up the Pi into interactive mode and run `sudo update-rc.d ssh enable` (avoid manual changes to `/etc/rc2.d/`, most times this messes things up).

Login to Pi Zero
---------------------
Now you should be ready to login to the Internet connected **Raspberry Pi Zero** either directly or via SSH. Only the Pi Zero supports USB device emulation at time of this writing, so it doesn't make any sence to try this with another model.
P4wnP1 setup is meant to be run by the user `pi` so use this user, the default password is `raspberry` which of course could be changed.

Install P4wnP1
--------------------
Enter the following commands to install P4wnP1:

    sudo apt-get -y install git
    cd /home/pi
    git clone --recursive https://github.com/mame82/P4wnP1
    cd P4wnP1
    ./setup_p4wnp1.sh

The setup process will take some time (installing packages, compiling pycrypto), so go and have a coffee.
If something goes wrong you should receive some error message.

Run P4wnP1
----------------
If nothing went wrong you could shutdown the Pi and reconnect it to a Windows Box.
To see the output, you could either connect a HDMI device or login via SSH (use PuTTY on Windows) with `pi@172.16.0.1`.

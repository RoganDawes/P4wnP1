# P4wnP1 Install Guide

## Step 1 - Install Raspbian Lite
 1.  Download: 
 [Jessie Lite image](http://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2017-07-05/) 
 or
 [Stretch Lite image](https://www.raspberrypi.org/downloads/raspbian/) (recomended)
 2. Follow the guide [here](https://www.raspberrypi.org/documentation/installation/installing-images/README.md)

## Step 2 - Connect the Pi (Zero) to Internet

Several methods are existing to do this

 - Method 1: Attaching an USB hub along with a Network Interface (NIC) and use it to connect to the Internet
 - Method 2: Put the SD card into another Raspberry Pi with built-in NIC and connect to the Internet (for example a Pi 3)
 - Method 3: This is the preferred one, as no additional hardware should be needed. Configure the Raspberry Pi **Zero** to act as USB Ethernet adapter and connect back to Internet through your host (Internet Connection Sharing on Windows, iptables MASQUERADING rule on Linux).
 - Method 4: How I do it currently (see `"Getting headless Pi Zero online"`)

A guide on how to do method 3 could be found [here](http://www.circuitbasics.com/raspberry-pi-zero-ethernet-gadget/). Two things should be noted on method 3:

1. Most Raspberry Pi Zero USB gadget configurations interfere with the configuration of P4wnP1 (which for example doesn't use "g_ether"). The setup script of P4wnP1 tries to fix interfering configurations. If you encouter problems, please try another method to connect to Internet and revert the changes done to the bare RASPBIAN JESSIE/STRETCH image.
2. Unlike described in most tutorials (including the linked one), the SSH server on current Raspbian isn't running by default. You have to boot up the Pi into interactive mode and run `sudo update-rc.d ssh enable` (avoid manual changes to `/etc/rc2.d/`, most times this messes things up).
 
## Getting headless Pi Zero Online (my way, needs a micro USB cable + SD card reader + KALI Linux)

I'm doing this on Kali Linux, most other distros should be fine, too (I'm working as root user on Kali, so depending on the distribution you need to add `sudo` or change too root, in order to run privileged commands). I don't use Windows 10 anymore, because the default USB over Ethernet driver gets detected as "USB Serial device", which is hard to overcome.
1. Prepare a fresh Raspbian Lite SD card
2. Mount the SD card to your KALI box **before** booting the Pi to first time.
3. On the boot partition edit the file `config.txt` and append the line `dtoverlay=dwc2` to enable USB gadget overlay.
4. On boot partition change insert `modules-load=dwc2,g_ether` into `cmdline.txt` between "rootwait" and "quiet". This enables the Ethernet USB gadget kernel module on boot.
5. Create an empty file called `ssh` in the same folder where `cmdline.txt` and `config.txt` reside, in order to enable SSH on boot.
6. The SD card is prepared. Install it in your Pi and connect a micro USB capable to the inner USB port of the Pi (the one marked with "USB" not with "PWR in".
7. Connect the Pi to your Kali Box and wait till it finished booting.

So this should bring up a new network interface on your box, which in my case is called `usb0` and has to be enabled with `ifconfig usb0 up`. The problem is, that the Pi runs a DHCP client on títs internal interface, waiting to receive a DHCP lease with an IP to use. As this lease will never be sent (as long as you haven't configured a DHCP server on usb0). We don't know the IP of the Pi. You could attach an HDMI monitor and the Pi will print out the IP used. But as promised, we do it in my way and that is headless.
Now that the Pi isn't able too receive a DHCP lease, it chooses its own IP with a process called APIPA. I don't want to explain everything here, but one part of APIPA is important: Before the Pi chooses its IP, it has to check if any other host is using it already. This is done via ARP request. So if we sniff on our `usb0` interface, shortly after bringing it up, we should see an ARP request. To fecth this request, I personally use tshark, but every other sniffer should be fine, as long as you bring it up fast enough. So instead of running only `ifconfig usb0 up` we do the following.
`ifconfig usb0 up && thshark -i usb0`

8. Watch the tshark output, till you see an ARP request with an IP (who has 169.254.241.194 in my case)
9. Stop tshark with `CTRL + C` and grab a copy of the IP.
10. Configure your `usb0` interface to reside in the same subnet, I choose `169.254.241.1` and thus run the following command:
`ifconfig usb0 169.254.241.1`.

Important: If the interface `usb0` isn't configured to manual setup, it is likely that a DHCP client is running. Trying to retreive a DHCP lease would wipe the IP configuration done in step 10 (ending up with Internet connection loss at some later point). The quick and dirty way to circumvent this on Kali, is to stop the network manager service with `service network-manager stop`

11. test if you could reach out to the Pi with `ping 169.254.241.194`
12. If everything goes fine, you should now be able to login with `ssh pi@169.254.241.194`

Two more things left. You have to configure your Kali box to allow outbound masquerading on your internet interface (eth0 in my case), like this:

13. `iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE` to enable masquerading (don't forget to replace eth0 with your internet interface)
14. `echo 1 > /proc/sys/net/ipv4/ip_forward` to enable kernel based routing on the Kali machine

Now KALI should be ready to root out traffic on its internet interface, but the Pi doesn't need to know who is the rooter, so we tell him. From the SSH session on the Pi run:

15. `route add -net default gw 169.254.241.1` (here the address you configured on your usb interface is needed
16. At this point raspbian should be able to reach the internet, test this with something like `ping 8.8.8.8`

The last thing to do is to tell the Pi, how to resolve DNS names, with:

17. `echo nameserver 8.8.8.8 > /etc/resolv.conf` where 8.8.8.8 is a google DNS which you could change according to your needs
18. The Pi should be online and able to resolve DNS names, test with `ping www.google.de`

If you made it till here, your're ready to go on with P4wnP1 installation.

## Login to Pi Zero online

Now you should be ready to login to the Internet connected **Raspberry Pi Zero** either directly or via SSH. Only the Pi Zero supports USB device emulation at time of this writing, so it doesn't make any sence to try this with another model.
P4wnP1 setup is meant to be run by the user `pi` so use this user, the default password is `raspberry` which of course could be changed.

## Install P4wnP1

Enter the following commands to install P4wnP1:

    sudo apt-get -y install git
    cd /home/pi
    git clone --recursive https://github.com/mame82/P4wnP1
    cd P4wnP1
    ./install.sh

The setup process will take some time (installing packages, compiling pycrypto), so go and have a coffee.
If something goes wrong you should receive some error message.

## Run P4wnP1

If nothing went wrong you could shutdown the Pi and reconnect it to a Windows Box.
To see the output, you could either connect a HDMI device or login via SSH (use PuTTY on Windows) with `pi@172.16.0.1`.

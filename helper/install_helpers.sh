#!/bin/bash


sudo cp createiso.sh /usr/bin/createiso
sudo cp parsevar.py /usr/bin/setoptionsfile
sudo cp readvar.sh /usr/bin/getoption
sudo cp delvar.sh /usr/bin/deloption
sudo cp storevar.sh /usr/bin/setoption
sudo cp clearvars.sh /usr/bin/clearoptions
sudo cp led_blink.sh /usr/bin/led_blink
sudo cp init_usb.sh /usr/bin/init_usb
sudo cp init_usb_ethernet.sh /usr/bin/init_usb_ethernet

sudo chmod a+x /usr/bin/createiso
sudo chmod a+x /usr/bin/setoptionsfile
sudo chmod a+x /usr/bin/getoption
sudo chmod a+x /usr/bin/deloption
sudo chmod a+x /usr/bin/setoption
sudo chmod a+x /usr/bin/clearoptions
sudo chmod a+x /usr/bin/led_blink
sudo chmod a+x /usr/bin/init_usb
sudo chmod a+x /usr/bin/init_usb_ethernet

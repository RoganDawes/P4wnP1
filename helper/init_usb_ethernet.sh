#!/bin/bash
sudo /bin/bash -c "source $(getoption wdir)/helper/usb_ethernet_helper.sh; init_usb_ethernet_dhcp >> /tmp/init_usb_ethernet_dhcp.log"



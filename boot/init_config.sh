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


# load global configuration variables

# include startup config
source $wdir/defaults.conf
source $wdir/startup_payload.conf

# include payload (overrides variables set by defaults.conf if needed)
# PAYLOAD itself is defined in startup_payload.conf
source $wdir/payloads/$PAYLOAD

# check for wifi capability
echo "WiFi check init_config"
if $wdir/wifi/check_wifi.sh; then WIFI=true; else WIFI=false; fi

# set variable for USB gadget directory
GADGETS_DIR="mame82gadget"


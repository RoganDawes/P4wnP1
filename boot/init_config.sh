#!/bin/sh
#
# load global configuration variables


# find working dir of script
#wdir=$( cd $(dirname $BASH_SOURCE[0]) && pwd)


# include setup.cfg
source $wdir/setup.cfg

# include payload (overrides variables set by setup.cfg if needed)
# PAYLOAD itself is define in setup.cfg
source $wdir/payloads/$PAYLOAD

# check for wifi capability
if $wdir/wifi/check_wifi.sh; then WIFI=true; else WIFI=false; fi

# set variable for USB gadget directory
GADGETS_DIR="mame82gadget"


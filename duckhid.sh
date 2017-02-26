#!/bin/bash
wdir=$( cd $(dirname $BASH_SOURCE[0]) && pwd)
source $wdir/setup.cfg
#cat | python duckencoder/duckencoder.py -l $lang -r | python transhid.py > /dev/hidg0
cat | python duckencoder/duckencoder.py -l $lang -p | python transhid.py 

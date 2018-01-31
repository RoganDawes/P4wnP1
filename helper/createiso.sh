#!/bin/bash


wdir=$( cd $(dirname $BASH_SOURCE[0]) && cd .. && pwd)

ISO_FOLDER="/tmp/iso"
VOL_ID="Test_CD"

rm -R $ISO_FOLDER # in case it exists
mkdir $ISO_FOLDER
printf "Hello World\r\nTestfile" > $ISO_FOLDER/hello.txt

# generate iso
genisoimage -udf -joliet-long -V $VOL_ID -o $wdir/USB_STORAGE/cdrom.iso $ISO_FOLDER

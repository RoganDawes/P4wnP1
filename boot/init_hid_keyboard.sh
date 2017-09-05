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

#
# Declares function used in conjunction with HID keyboard

# output raw ASCII to HID keyboard
function outhid()
{
#	cat | python $wdir/duckencoder/duckencoder.py -l $lang -r | python $wdir/transhid.py > /dev/hidg0
	cat | python $wdir/duckencoder/duckencoder.py -l $lang -r | python $wdir/hidtools/transhid.py 
}

# output DUCKY SCRIPT to HID keyboard
function duckhid()
{
#	cat | python $wdir/duckencoder/duckencoder.py -l $lang -p | python $wdir/transhid.py > /dev/hidg0
	cat | python $wdir/duckencoder/duckencoder.py -l $lang -p | python $wdir/hidtools/transhid.py 
}

# Blocks till NUMLOCK, CAPSLOCK or SCROLLLOCK has been hit 5 time on targets keyboard
# return value define which key was hit
function key_trigger()
{
	sudo python $wdir/hidtools/watchhidled.py trigger
	return $?
}

# reads LEDs from keyboard device till something is sent
# as this is done on driver init, we use it as trigger for HID keyboard beeing ready

#function detect_HID_keyboard()
#{
#	echo "Waiting for HID keyboard to be usable..."
#
#	# blocking read of LED status
#	python -c "with open('/dev/hidg0','rb') as f:  print ord(f.read(1))"
#	# fire 'onKeyboardUp' after read has succeeded
#	declare -f onKeyboardUp > /dev/null && onKeyboardUp
#
#}

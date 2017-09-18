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
# Declares function used in conjunction with HID mouse

# output mouse commands from MouseScript (see $wdir/MouseScripts/test.mouse for example Script)
function outmouse()
{
#	cat | python $wdir/duckencoder/duckencoder.py -l $lang -r | python $wdir/transhid.py > /dev/hidg0
	cat | python $wdir/hidtools/mouse/MouseScriptParser.py 
}


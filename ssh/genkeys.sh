#!/bin/bash

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


wdir=$( cd $(dirname $BASH_SOURCE[0]) && cd .. && pwd)
source $wdir/setup.cfg

DEFAULT_COMMENT="AutoSSH reachback"

read -p "Enter target filename for keypair ($AUTOSSH_PRIVATE_KEY): " PRIVATE_KEY
PRIVATE_KEY=${PRIVATE_KEY:-"$AUTOSSH_PRIVATE_KEY"}

read -p "Enter comment for public key ($DEFAULT_COMMENT): " COMMENT
COMMENT=${COMMENT:-"$DEFAULT_COMMENT"}

echo "Generating keys at $AUTOSSH_PRIVATE_KEY ..."
ssh-keygen -q -N "" -C "$COMMENT" -f $AUTOSSH_PRIVATE_KEY && SUCCESS=true
echo "... done"
ls -la $AUTOSSH_PRIVATE_KEY*

if $SUCCESS; then
	echo
	echo
	echo "Use \"$wdir/ssh/pushkey.sh\""
	echo "in order to promote the public key to a remote SSH server"
fi

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

read -p "Enter remote SSH host to push the key on ($AUTOSSH_REMOTE_HOST): " REMOTE_HOST
REMOTE_HOST=${REMOTE_HOST:-"$AUTOSSH_REMOTE_HOST"}
#echo $REMOTE_HOST

read -p "Enter remote SSH user to use ($AUTOSSH_REMOTE_USER): " REMOTE_USER
REMOTE_USER=${REMOTE_USER:-"$AUTOSSH_REMOTE_USER"}
#echo $REMOTE_USER

read -p "Enter path to public key ID file ($AUTOSSH_PUBLIC_KEY): " PUBLIC_KEY
PUBLIC_KEY=${PUBLIC_KEY:-"$AUTOSSH_PUBLIC_KEY"}
#echo $PUBLIC_KEY

read -p "Enter path to private key ID file ($AUTOSSH_PRIVATE_KEY): " PRIVATE_KEY
PRIVATE_KEY=${PRIVATE_KEY:-"$AUTOSSH_PRIVATE_KEY"}
#echo $PRIVATE_KEY

echo
echo "Trying to add P4wnP1 public key for $REMOTE_USER@$REMOTE_HOST..."
echo
echo "  The SSH server's password is needed to publish the key, but if"
echo "  nothing wents wrong this is the last time it is needed."
echo
res=$(ssh $REMOTE_USER@$REMOTE_HOST "echo \"$(cat $PUBLIC_KEY)\" >> ~/.ssh/authorized_keys;cat ~/.ssh/authorized_keys")
if echo "$res" | grep -q -e "$(cat $PUBLIC_KEY)"; then
	echo "... SUCCESS !"
	echo
	echo "Run the following command to test password-less access"
	echo "(if you're prompted for a password, something went wrong):"
	echo "----------------------------------------------------------"
	echo
	echo "ssh -i $PRIVATE_KEY $REMOTE_USER@$REMOTE_HOST"
else
	echo "... failed"
fi

echo
echo
echo "You could repeat key publishing at any time (P4wnP1 has to be able to reach the"
echo "target SSH server, e.g. Internet access). Use the following command:"
echo "-------------------------------------------------------------------------------"
echo
echo "$wdir/ssh/pushkey.sh"

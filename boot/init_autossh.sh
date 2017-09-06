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


# Enable AutoSSH reachback connection according to the settings of setup.cfg or current payload

function start_autossh()
{
	if $AUTOSSH_ENABLED; then
		echo "Forwarding P4wnP1 SSH server to \"$AUTOSSH_REMOTE_HOST\" ..."
		echo "    P4wnP1 SSH will be reachable on localhost:$AUTOSSH_REMOTE_PORT on this server"
		cp $AUTOSSH_PRIVATE_KEY /tmp/ssh_id

		sudo autossh -M 0 -f -T -N  -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i /tmp/ssh_id -R localhost:$AUTOSSH_REMOTE_PORT:localhost:22 $AUTOSSH_REMOTE_USER@$AUTOSSH_REMOTE_HOST
	fi
}

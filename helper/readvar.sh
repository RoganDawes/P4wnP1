
#!/bin/bash
if [ $# -lt 1 ]; then
	>&2 echo "Too few args"
	exit
fi
name=$1
if [ ! -f /dev/shm/$name ]; then
	>&2 echo "Unknown variable '$name'"
	exit
fi
cat /dev/shm/$name

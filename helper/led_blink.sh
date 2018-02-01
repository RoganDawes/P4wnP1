#!/bin/bash

# led blink function
if [ "$1" ]; then
	setoption blink_count $1
fi


#!/bin/bash
kdev=$(getoption device_hid_keyboard)
python -c "with open('$kdev','rb') as f:  print ord(f.read(1))"

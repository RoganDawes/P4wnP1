
#!/bin/bash

# Blocks till NUMLOCK, CAPSLOCK or SCROLLLOCK has been hit 5 time on targets keyboard
# exit code determines which key was been pressed

sudo python $(getoption wdir)/hidtools/watchhidled.py trigger
exit $?

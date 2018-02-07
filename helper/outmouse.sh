
#!/bin/bash

wdir=$(getoption wdir)
cat | python $wdir/hidtools/mouse/MouseScriptParser.py

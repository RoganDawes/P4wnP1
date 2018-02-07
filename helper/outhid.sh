
#!/bin/bash

wdir=$(getoption wdir)
cat | python $wdir/duckencoder/duckencoder.py -l $(getoption lang) -r | python $wdir/hidtools/transhid.py 
#cat | python $wdir/duckencoder/duckencoder.py -l $lang -p | python $wdir/hidtools/transhid.py 

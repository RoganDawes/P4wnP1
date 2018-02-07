
#!/bin/bash
wdir=$(getoption wdir)
cat | python $wdir/duckencoder/duckencoder.py -l $(getoption lang) -p | python $wdir/hidtools/transhid.py 

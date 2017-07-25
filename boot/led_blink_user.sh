ledtrigger="/tmp/blink_count"
# led blink function
function led_blink()
{
	if [ "$1" ] 
	then
		echo "$1" > $ledtrigger
	fi
}

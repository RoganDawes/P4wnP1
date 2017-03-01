import time

def send_key(key,mod,file):
	time.sleep(0.01)
	# press key and modifier

	str = chr(mod) + '\x00' + chr(key) + '\x00\x00\x00\x00\x00' + '\x00\x00\x00\x00\x00\x00\x00\x00'
	file.write(str)
	file.flush()

def send_raw(data,fd):
	for i in range(0, len(data), 2):
		key = data[i]
		mod = data[i+1]
		send_key(key,mod,fd)

def send_duck_payload(payloadfilename,fd):
	with open(payloadfilename, "rb") as f:
		payload = bytearray(f.read())
	send_raw(payload,fd)


device_filename="/dev/hidg0"
payload_filename="hid.raw"

fd = open(device_filename,'wb')

# content from hid.raw (generated with duckencoder)
send_duck_payload("hid.raw",fd)

fd.close()

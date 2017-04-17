P4wnP1 by MaMe82 (devel branch)
================

P4wnP1 is a highly customizable USB attack platform, based on a low cost Raspberry Pi Zero or Raspberry Pi Zero W.

The branch is dedicated to HID covert channel feature development

Hint
----
If you want to try devel branch, be sure to setup payload language of HID payloads to your needs (wrong keyboard language renders most payloads useless).
Features which aren't already merged into receive no support (please don't open issues).

Video demo of first HID payload (comments in subtitles)
-------------------------------------------------------

[![P4wnP1 HID demo youtube](https://img.youtube.com/vi/MI8DFlKLHBk/0.jpg)](https://www.youtube.com/watch?v=MI8DFlKLHBk&yt:cc=on)

Progress (things already done)
------------------------------

- Plug and Play install of HID device on Windows Windows 7 and Windows 10
- Covert channel based on raw HID
- synchronous data transfer with 3,2KBytes/s over HID (already working, fast enough for shells or low traffic TCP applications)
- Rework of raw channel to achieve higher transfer rates **current tests as 56000 Byte per second FULLDUPLEX**
- HID report loss handling for full duplex transfer (done on LinkLayer implementation, not integrated into payload)
- fasten up fragmentation / defragmentation of HID reports from/to byte streams (done on LinkLayer implementation, not integrated into payload)
- in memory PowerShell Payload - nothing is written to disk (done for demo payload, has to be reworked for LinkLayer implementation)
- Payload to talk from the host to a bash shell on P4wnP1 via pure HID (implemented in demo payload ``hid_backdoor.txt``)
- HID based file transfer from and to P4wnP1 (implemented in demo payload ``hid_backdoor.txt``, will be reworked for current link layer implementation)
- PowerShell on-demand in-memory file injection (file is saved into local powershell variable as Byte[], demoed in ``hid_backdoor.txt``, see video for reference)


Other features currently not available in master
--------------------------------------
- finished **payload trigger via target's keyboard** CAPSLOCK / NUMLOCK / SCROLLLOCK (could be used to fire insider attacks on demand or for payload branching), see payload: ``hid_keyboard2.txt``
- payload **callback when target installed keyboard driver** (no more delays to fire keyboard attacks), see payloads: ``hid_keyboard.txt`` and ``hid_keyboard2.txt``


ToDo before merging into master:
-------------------------------
1. Finish LinkLayer (split into stages, reimplement stage 1 keyboard typeout)
2. Reimplement HID backdoor demo payload (use new LinkLayer which doubles data throughput)
3. Implement Payload to bridge an Airgap target: by relaying a invisible PowerShell session through raw HID to P4wnP1 and binding it to a socket reachable via WiFi or Bluetooth (Pi Zero W only)
4. Implement command to use LED as indicator (low priority)
5. integrate ratepatch into installer (20 GBit/s RNDIS, 4 GBit/s CDC ECM ... low priority, as patches are public)

Considered to be implemented
-----------------------------
- Binding HID channel to a TCP socket, on both, target and P4wnP1 to use TCP based tools (metasploit, nmap etc.)
- Socks5 proxy, relaying TCP connections to target via covert HID channel to expose internal network services
- HID mouse support (no meaningful use case which is worth the effort)
- USB serial support (not needed at the moment)


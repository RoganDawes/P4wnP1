P4wnP1 by MaMe82
================

P4wnP1 is a highly customizable USB attack platform, based on a low cost Raspberry Pi Zero or Raspberry Pi Zero W.

Suprise suprise - 20 GBit network
-------------------
While working on the covert HID channel (see Feature announcment), there are no frequent commits to the RePo, so I thought I should provide a little suprise from current development. [Here's the kernel module patch](https://github.com/mame82/ratepatch) which magically changes P4wnP1 into a **20 GBit per second** RNDIS device. How to use it, what is the benefit anw what are possible issues: [See here](https://github.com/mame82/ratepatch/blob/master/README.md)

The patch will be integrated into P4wnP1 on the next major release.

P4wnP1 Features
---------------

-   Support for **HID Keyboard**
-   Support for **USB Mass storage** (currently only in demo setup with 128 Megabyte Drive)
-   Support for **Windows Networking via RNDIS**
-   Support for **MacOS / Linux Networking via CDC ECM**
-   All the Features mentioned work with **Windows Class Drivers (Plug and Play)**
-   **All USB features work in parallel if needed (Composite Device RNDIS, USB Mass Storage, HID)**
-   **Customizable simple payload scripts** (see payloads/payload1.txt for an example)
-   includes **Responder** and a precompiled **John the Ripper Jumbo** Version
-   Supports **DuckyScript** (see payload1.txt for example)
-   Supports **raw ASCII Output via HID Keyboard** (see payload1.txt for an example printing out a logfile via Keyboard on target)
-   **Multi Keyboard language layout support** via Setup.cfg (no need to worry about target language when using HID commands)
-   Automatic Link detection if both (RNDIS and ECM) network interfaces are enabled
-   Payload callbacks when target activates network, when target receives DHCP lease, when device is booted
-   If an USB OTG adapter is connected, P4wnP1 boots into interactive mode without running the payload, which allows easy configuration
-   SSH server is running by default, so P4wnP1 could be connected on 172.16.0.1 (as long as the payload enables RNDIS, CDC ECM or both)

Feature announcement
--------------------

Something nifty is coming! Currently I'm working on a **covert channel** to communicate from P4wnP1 to target host and back, **based on pure HID**. This means there's no need for RNDIS, ECM or other non stealthy device modes to get a shell on the target.
But code has to be executed on the target, to handle the non standard communication channel. To run the code I'm focused on the major platform (Windows) and I'm using PowerShell on target (packed since Windows 7). 

As this is going to be a major P4wnP1 feature, I'm not working on anything else at the moment - so please excuse if commits are less frequently, right now. The focus of this attack vector isn't drive-by, but gaining persistent backdoor access. 
This should be done with a low detection profile (no serial, no Ethernet over USB, no USB Mass Storage)

What will be implemented:

- Plug and Play install of HID device on Windows (already working on Windows 7 and Windows 10)
- Covert channel based on raw HID (already working)
- synchronous data transfer with 3,2KBytes/s oer HID (already working, fast enough for shells or low traffic TCP applications)
- Stack to handle HID communication and deal with HID data fragmentation (partially implemented)
- in memory PowerShell Payload - nothing is written to disk (already working, needs to be minified)
- Payload to talk from the host to a shell on P4wnP1 from PowerShell on pure HID (needs to be implemented)
- Payload to bridge an Airgap target, by relaying a shell over raw HID and provide it from P4wnP1 via WiFi or Bluetooth (not implemented, needs Pi Zero W)


What would be possible, but won't be implemented at the moment:

- Modular, RAT like payload enhancement (integration of PowerSploit etc.) for airgapped targets
- Binding HID channel to a TCP socket, on both, target and P4wnP1 to use TCP based tools (metasploit, nmap etc.)
- HID based file transfer from and to P4wnP1

Feature Comparison with BashBunny
---------------------------------

Some days after initial P4wnP1 commit, Hak5's BashBunny was announced (and ordered by myself). Here's a little feature comparison:

| Feature                                                                         	| BashBunny                                                                                             	| P4wnP1                                                                                                                                 	|
|---------------------------------------------------------------------------------	|-------------------------------------------------------------------------------------------------------	|----------------------------------------------------------------------------------------------------------------------------------------	|
| RNDIS, CDC ECM, HID , serial and Mass storage support                           	| supported, usable in several combinations, Windows Class driver support (Plug and Play) in most modes 	| supported, usable in most combinations, Windows Class driver support (Plug and Play) in all modes as composite device                  	|
| USB configuration changable during runtime                                      	| supported                                                                                             	| will maybe be implemented                                                                                                              	|
| Support for RubberDucky payloads                                                	| supported                                                                                             	| supported                                                                                                                              	|
| Support for piping command output to HID keyboard out                           	| no                                                                                                    	| supported                                                                                                                              	|
| Switchable payloads                                                             	| Hardware switch                                                                                       	| manually in interactive mode (Hardware switch could be soldered, script support is a low priority ToDo)                                	|
| Interactive Login with display out                                              	| SSH / serial                                                                                          	| SSH / serial / stand-alone (USB OTG + HDMI)                                                                                            	|
| Performance                                                                     	| High performance ARM quad core CPU, SSD Flash                                                         	| Low performance single core ARM CPU, SDCARD                                                                                            	|
| Network interface bitrate                                                       	| Windows RNDIS: **2 GBit/s**</br>Linux/MacOS ECM: **100 MBit/s**</br>Real bitrate 450 MBit max (USB 2.0)     	| Windows RNDIS: **20 GBit/s**</br>Linux/MacOS ECM: **4 GBit/s** (detected as 1 GBit/s interface on MacOS)</br>Real bitrate 450 MBit max (USB 2.0)</br>[Here's the needed P4wnP1 patch](https://github.com/mame82/ratepatch)	|
| LED indicator                                                                   	| RGB Led, driven by single payload command                                                             	| mono color LED, payload command under development (low priority)                                                                       	|
| Customization                                                                   	| Debian based OS with package manager                                                                  	| Debian based OS with package manager                                                                                                   	|
| External network access via WLAN (relay attacks, MitM attacks, airgap bridging) 	| Not possible, no external interface                                                                   	| supported with Pi Zero W (payloads under development)                                                                                  	|
| Ease of use                                                                     	| Easy, change payloads based on USB drive, simple bash based scripting language                        	| Medium, bash based event driven payloads, inline commands for HID (DuckyScript and ASCII pipe)                                         	|
| Available payloads                                                              	| Fast growing github repo (big community)                                                              	| Slowly growing github repo (spare time one man show ;-))                                                                               	|
| Costs                                                                           	| about 99 USD                                                                                          	| about 5 USD (11 USD fow WLAN capability with Pi Zero W)                                                                                	|

SumUp: BashBunny is directed to easy usage, but costs 20 times as much as the basic P4wnP1 hardware. P4wnP1 is directed to a more advanced user, but allows outbound communication on a separate network interface (routing and MitM traffic to upstream internet, hardware backdoor etc.)


Credits to
----------

Samy Kamkar: [PoisonTap]

Rob ‘MUBIX’ Fuller: [“Snagging creds from locked machines”] and MUBIX at [github]

Laurent Gaffie (lgandx): [Responder]

Darren Kitchen (hak5darren): [DuckEncoder]

Getting started
---------------

The Default payload (payloads/payload1.txt) implements NTLM hash capturing from locked Windows boxes with Responder. The payload is well commented and should be a starting point for customization. The payload includes various HID Keyboard outputs, to show the possibilities. The attack itself shouldn’t be working since patch MS16-112, but some third party software helps to still carry it out (see section ‘Snagging creds from locked machines after MS16-112’)

Setup Instructions
------------------

Refer to [INSTALL.md] (including usage example)

Requirements
------------

-   Raspberry Pi Zero / Pi Zero W (other Pis don’t support USB gadget because they’re equipped with a Hub, so don’t ask)
-   Raspbian Jessie Lite pre installed
-   Internet connection to run the setup
-   the project is still work in progress, so features and new payloads are added in frequently (make sure to have an updated copy of P4

  [PoisonTap]: https://github.com/samyk/poisontap
  [“Snagging creds from locked machines”]: https://room362.com/post/2016/snagging-creds-from-locked-machines/
  [github]: https://github.com/mubix
  [Responder]: https://github.com/lgandx/Responder
  [DuckEncoder]: https://github.com/hak5darren/USB-Rubber-Ducky/
  [INSTALL.md]: https://github.com/mame82/P4wnP1/blob/master/INSTALL.md

Snagging creds from locked machines after MS16-112
--------------------------------------------------

During tests of P4wnP1 a product has been found to answer NTLM authentication requests on wpad.dat on a locked and fully patched Windows 10 machine (including patch for MS16-112). The NTLM hash of the logged in user is sent by a third party software, even if the machine isn’t domain joined. The flaw has been reported to the respective vendor. Details will be added to the readme as soon as a patch is available. For now I’ll recently update the disclosure timeline here.

Disclosure Timeline discovered NTLM hash leak:

| Date        	| Action                                       	|
|-------------	|----------------------------------------------	|
| Feb-23-2017 	| Initial report submitted to vendor (Email)   	|
| Feb-23-2017 	| Vendor reports back, investigating the issue 	|
| Mar-01-2017 	| Vendor confirmed issue, working on fix       	|
| Mar-23-2017 	| Vendor: monthly status Update "Being fixed in main codeline"      	|

Of course you’re free to try this on your own. Hint: The product doesn’t fire requests to wpad.dat immediately, it could take several minutes.

ToDo / Work In Progress
-----------------------

-   Payload: HID-only based “Airgap bridge” for Pi Zero W (under development)
-   Payload: Empty template (done)
-   Boot: Fasten up boot (change startup script to init service)
-   Payload: Android PIN bruteforce
-   Payload: Advanced NTLM capture (hand over hashes to JtR and unlock machines with weak creds immediately)
-   Usability: Additional payload callback function “onHIDKeyboardUp”
-   Payload: OS fingerprinting
-   Usability: payload command to drive RPi builtin LED
-   Usability: payload switching via GPIO pins (conneting a hardware switch)


P4wnP1 by MaMe82
================

P4wnP1 is a highly customizable USB attack platform, based on a low cost Raspberry Pi Zero or Raspberry Pi Zero W.

P4wnP1 Features
---------------
- Support for **HID Keyboard**
- Support for **USB Mass storage** (currently only in demo setup with 128 Megabyte Drive)
- Support for **Windows Networking via RNDIS**
- Support for **MacOS / Linux Networking via CDC ECM**
- All the Features mentioned work with **Windows Class Drivers (Plug and Play)**
- **All USB features work in parallel if needed (Composite Device RNDIS, USB Mass Storage, HID)**
- **Customizable simple payload scripts** (see payloads/payload1.txt for an example)
- includes **Responder** and a precompiled **John the Ripper Jumbo** Version
- Supports **DuckyScript** (see payload1.txt for example)
- Supports **raw ASCII Output via HID Keyboard** (see payload1.txt for an example printing out a logfile via Keyboard on target)
- **Multi Keyboard language layout support** via Setup.cfg (no need to worry about target language when using HID commands)
- Automatic Link detection if both (RNDIS and ECM) network interfaces are enabled
- Payload callbacks when target activates network, when target receives DHCP lease, when device is booted
- If an USB OTG adapter is connected, P4wnP1 boots into interactive mode without running the payload, which allows easy configuration
- SSH server is running by default, so P4wnP1 could be connected on 172.16.0.1 (as long as the payload enables RNDIS, CDC ECM or both)

Credits to
----------
Samy Kamkar:                   `PoisonTap <https://github.com/samyk/poisontap>`_ 

Rob 'MUBIX' Fuller:            `"Snagging creds from locked machines" <https://room362.com/post/2016/snagging-creds-from-locked-machines/>`_ and MUBIX at `github <https://github.com/mubix>`_

Laurent Gaffie (lgandx):           `Responder <https://github.com/lgandx/Responder>`_

Darren Kitchen (hak5darren):           `DuckEncoder <https://github.com/hak5darren/USB-Rubber-Ducky/>`_

Getting started
---------------
The Default payload (payloads/payload1.txt) implements NTLM hash capturing from locked Windows boxes with Responder. The payload is well commented and should be a starting point for customization. The payload includes various HID Keyboard outputs, to show the possibilities. The attack itself shouldn't be working since patch MS16-112, but some third party software helps to still carry it out (see section 'Snagging creds from locked machines after MS16-112')

Setup Instructions
------------------
Refer to `INSTALL.md <https://github.com/mame82/P4wnP1/blob/master/INSTALL.md>`_ (including usage example)

Requirements
------------
- Raspberry Pi Zero / Pi Zero W (other Pis don't support USB gadget because they're equipped with a Hub, so don't ask)
- Raspbian Jessie Lite pre installed
- Internet connection to run the setup
- the project is still work in progress, so features and new payloads are added in frequently (make sure to have an updated copy of P4wnP1)

Snagging creds from locked machines after MS16-112
--------------------------------------------------
During tests of P4wnP1 a product has been found to answer NTLM authentication requests on wpad.dat on a locked and fully patched Windows 10 machine (including patch for MS16-112).
The NTLM hash of the logged in user is sent by a third party software, even if the machine isn't domain joined. The flaw has been reported to the respective vendor. Details will be added to the readme as soon as a patch is available. For now I'll recently update the disclosure timeline here.

Disclosure Timeline discovered NTLM hash leak:

:Feb-23-2017: Initial report submitted to vendor (Email)
:Feb-23-2017: Vendor reports back, investigating the issue
:Mar-01-2017: Vendor confirmed issue, working on fix

Of course you're free to try this on your own. Hint: The product doesn't fire requests to wpad.dat immediately, it could take several minutes.

ToDo / Work In Progress
-----------------------

- Payload: HID-only based "Airgap bridge" for Pi Zero W
- Payload: Empty template
- Boot: Fasten up boot (change startup script to init service)
- Payload: Android PIN bruteforce
- Payload: Advanced NTLM capture (hand over hashes to JtR and unlock machines with weak creds immediately)
- Usability: Additional payload callback function "onHIDKeyboardUp"
- Payload: OS fingerprinting
- Usability: payload command to drive RPi builtin LED
- Usability: payload switching via GPIO pins (conneting a hardware switch)

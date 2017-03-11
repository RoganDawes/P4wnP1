P4wnP1 by MaMe82
================

P4wnP1 is a highly customizable USB attack platform, based on a low cost Raspberry Pi Zero or Raspberry Pi Zero W.

P4wnP1 Features
---------------
- Support for **HID Keyboard**
- Support for **USB Mass storage** (currently only in demo setup with 1 Megabyte Drive)
- Support for **Windows Networking via RNDIS**
- Support for **MacOS / Linux Networking via CDC ECM**
- All the Features mentioned work with **Windows Class Drivers (Plug and Play)**
- **All USB features work in parallel if needed (Composite Device RNDIS, USB Mass Storage, HID)**
- **Customizable simple payload scripts** (see payloads/payload1.txt for an example)
- includes **Responder** and a precompiled **John the Ripper Jumbo** Version
- Supports **DuckyScript** (could be included in payload script)
- Supports **raw ASCII Output via HID Keyboard** (see tutorial1 for an example printing out a logfile via Keyboard on target)
- **Multi Keyboard language layout support** via Setup.cfg (no Need to worry about target language when using HID commands)
- Automatic Link detection if both (RNDIS and ECM) Network Interfaces are enabled
- Payload callbacks when target activates network, when target receives DHCP lease, when device is booted
- If an USB OTG adapter is connected, P4wnP1 boots into interactive mode without running the payload, which allows easy configuration
- SSH server is running by default

Credits to
----------
Samy Kamkar:                   `PoisonTap <https://github.com/samyk/poisontap>`_ 

Rob 'MUBIX' Fuller:            `"Snagging creds from locked machines" <https://room362.com/post/2016/snagging-creds-from-locked-machines/>`_ and MUBIX at `github <https://github.com/mubix>`_

Laurent Gaffie (lgandx):           `Responder <https://github.com/lgandx/Responder>`_

Getting started
---------------
The Default payload (payloads/payload1.txt) implements NTLM hash capturing from locked Windows boxes with Responder. The payload is well commented and should be a starting point for customization. The payload includes various HID Keyboard outputs, to show the possibilities.

Setup Instructions
------------------
Refer to `INSTALL.md <https://github.com/mame82/P4wnP1/blob/master/INSTALL.md>`_ (including usage example)

Requirements
------------
- Raspberry Pi Zero (other Pis don't support USB gadget because they're equipped with a Hub, so don't ask)
- Raspbian Jessie Lite pre installed
- Internet connection to run setup
- As this project is "considered work in progress" not all setup steps are covered programatically by setup.sh at the moment (see comments "ToDo", for example autologin has to be enabled manually)

Snagging creds from locked machines after MS16-112
==================================================
During tests of P4wnP1 a product has been found to answer NTLM authentication requests on wpad.dat on a locked and fully patched Windows 10 machine.
The NTLM hash of the logged in user is sent, even if the machine isn't domain joined. The flaw has been reported to the respective vendor. Details will be added to the readme as soon as a patch is available. For now I'll recently update the disclosure timeline here.

Disclosure Timeline discovered NTLM hash leak:

:Feb-23-2017: Initial report submitted to vendor (Email)
:Feb-23-2017: Vendor reports back, investigating the issue
:Mar-01-2017: Vendor confirmed issue, working on fix

Of course you're free to try this on your own. Hint: The product doesn't fire requests to wpad.dat immediately, it could take several minutes.

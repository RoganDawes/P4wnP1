P4wnP1 (PiZero IPv4 traffic interceptor and USB hash stealer) by MaMe82
=======================================================================
This script emulates an **Ethernet over USB** device on a Raspberry Pi Zero in order to **intercept packets for every single IPv4 address and every hostname the target host connects to**. In the current example it is used to steal NTLM hashes from Windows boxes (in some cases even locked ones). The work is influenced by the projects mentioned below.

This project is considered work in progress. Not all setup steps are automated, neither are typos removed from the comments - but there are many comments (in fact more than code). So if you're interested, feel free to reuse anything you want. Please don't open issues because something doesn't work, while the project isn't in final state.

Creds to
--------
:Samy Kamkar:                   PoisonTap
:Rob 'MUBIX' Fuller:            "Snagging creds from locked machines"
:Laurent Gaffie (lgandx):       Responder

Requirements
------------
- Raspberry Pi Zero (other Pis don't support USB gadget because they're equipped with a Hub, so don't ask)
- Raspbian Jessie Lite pre installed
- Internet connection to run setup.sh 
- As this project is "considered work in progress" not all setup steps are covered programatically by setup.sh at the moment (see comments "ToDo", for example autologin has to be enabled manually)

Notes/Features
--------------
- The Pi acts as **Ethernet over USB Composite Device**. The target hosts is provided with RNDIS for Windows and CDC ECM for Linux/Unix like machines.
- The RNDIS setup should support **automatic PnP driver installation on Windows** (Microsoft OS Descriptors added to the USB descriptor and tested on Windows 7 and Windows 10).
- The Setup works well on USB 2.0 Ports (only in some cases on USB3.0)
- The script **detects if RNDIS or CDC ECM** is used, by polling the link state of both internal interfaces. If RNDIS (usb0) is detected to be active CDC ECM gets disabled (usb1). If CDC ECM (usb1) gets link, RNDIS (usb0) will be disabled. If neither one gets link both are disabled after RETRY_COUNT_LINK_DETECTION attempts.
- Because only one adapter is used after link detection, the **DHCP setup doesn't differ between Windows and Linux**. This comes in handy if this should be used to trigger reverse connections, as the IP of the Raspberry is always known.
- The initial idea was to **steal NTLM hashes from locked machines**, as shown by MUBIX. The underlying issue seems to be addressed by Microsoft with MS16-112. Unfortunately this vector is still alive, see "Snagging creds from locked machines after MS16-112" for details.
- To allow raise the chance of NTLM hash capturing on boxes with MS16-112 patch, the setup of P4wnP1 intercepts communication to every public IPv4 address (see section on "PoisonTap approach" for details). Additionally, names resolved via DNS, LLMNR and NBT-NS always end up on P4wnP1's IP as long as the device is connected.
- **All outgoing HTTP requests are intercepted** and answered with custom HTML content. The HTML page holds a payload which **forces the client to initiate an authenticated SMB request**. This again **allows capturing NTLM hashes** of the target host in many cases. A modified version of Responder.py is used to achieve this.
- As Responder has capabilities to handle other protocols, the following traffic is **intercepted in addition: SQL, Kerberos, FTP, POP3, SMTP, IMAP, LDAP, HTTPS**
- To make P4wnPi behave naturally, **Responder.py has been patched with the following additional functionality**:
    1. If "Serve-Html" is set to on, responder delivers the same custom Page, no matter what URL is requested. This behavior has been changed, to let Responder **deliver the custom WPAD script** if the requested URL contains "/wpad.dat" or "/\*.pac", anyway.
    2. As Responder runs without upstream (not forwarding to Internet) in this setup, Windows hosts detect that the new network has no Internet access because the connectivity tests fail. An option to correctly reply to connection tests in order to **mimic an available Internet connection for Windows** has been added to Responder (at time of writing for Windows 7 and Windows 10 IPv4 tests). As Windows now believes Internet access is granted, the P4wnP1 network stays enabled and more requests could be intercepted.

Modification to PoisonTap approach of fetching traffic to the whole IPv4 address range
---------------------------------------------------------------------------------------
PoisonTap uses the following setup:

:IP: 1.0.0.1
:Netmask: 0.0.0.0

This means the subnet PoisonTap is using covers the whole IPv4 range. The target host receives the following setup via DHCP:

:IP: somewhere between 1.0.0.1-50
:Netmask: 128.0.0.0 !!
:Gateway: 1.0.0.1
:DNS: 1.0.0.1
:static routes:
     0.0.0.0/1 via 1.0.0.1 !!

     128.0.0.0/1 via 1.0.0.1 !!

The crucial DHCP parts are marked with '!!' and should be discussed here:

* A Netmask of 128.0.0.0 is chosen. The route to this net receives a higher priority (lower metric) than the targets default gateway, as the Netmask is more specific.
* Every IP from 1.0.0.1 up to 126.255.255.254 is considered to belong to the PoisonTap subnet by the target.
* Every IP from 128.0.0.1 up to 255.255.255.254 is considered to not belong to this subnet.
* Every IP from 127.0.0.0/24 is considered to be a localhost entry.

This involves a **problem: For all IPs from 1.0.0.1 up to 126.255.255.254** the target would try to send an ARP request, as they are considered to be reachable directly via PoisonTap's subnet. This ARP request wouldn't be answered (as long as no ARP spoofing is involved on PoisonTap) and thus **the target will never initiate follow up communication on application layer to these IPs**. 

The upper IP **range from 128.0.0.1 up to 255.255.255.254** would be considered to not to belong to PoisonTap subnet and (under normal circumstances) be routed via targets DEFAULT gateway.
At exactly this point the static routes which have been set via DHCP come into play. As the routing entry 128.0.0.0/1 has a higher priority than 0.0.0.0/0 (default gateway), all traffic directed to the range from 128.0.0.1 up to 255.255.255.254 **gets routed through the PoisonTap** now. As already described, this unfortunately isn't true for the lower half of the IPv4 address space - as these IPs are considered to belong to PoisonTap's subnet and are reachable directly if present (unanswered ARP request to these IPs).

So the whole idea could be brought down to setup more specific routes for all IPv4 addresses than the default routes used by th target in order to force it to use the R4wnP1 as router.
At this point it should be clear, that **the P4wnP1 subnet should be chosen as tight as possible in order to force the target client into routing instead of ARP'ing.**

P4wnP1 setup to intercept whole IPv4 range
------------------------------------------
P4wnP1 uses the following setup:

:IP: 172.16.0.1
:Netmask: 255.255.255.252

Target setup via DHCP:

:IP: 172.16.0.2-172.16.0.2 (only one possible target IP)
:Netmask: 255.255.255.252 (tightest Netmask possible) !!
:Gateway: 172.16.0.1
:DNS: 172.16.0.1
:static routes:
     0.0.0.0/1 via 172.16.0.1 (route lower IPv4 half through P4wnP1) !!

     128.0.0.0/1 via 172.16.0.1 (route upper IPv4 half through Raspberry) !!

Now all traffic to IPs for which there isn't a more specific route defined on the target (this should match every public IPv4 address on standard clients) are routed through the P4wnP1. In order to intercept this traffic, all packets meant to be routed are redirected to 127.0.0.1 (localhost) on P4wnP1. The only thing left is to run the proper servers on P4wnP1. The example setup uses Responder to provide a listener for the most common services (HTTP, HTTPS, POP3, IMAP, SMTP, DNS, NETBIOS, LDAP, Kerberos, SQL). This behavior could be changed easily in order to customize P4wnP1 for other tasks.

It should be noted, that LLMNR, Netbios and DNS requests are answered by Responder with the IP address of P4wnP1. Under normal circumstances this isn't needed, as every IPv4 address is rooted to P4wnP1 anyway, but there are some special uses cases:

- DNS requests for IPv6 hosts resolve to the IPv4 address of P4wnP1 now
- Formerly unknown hosts get mapped to P4wnP1's IP, too (LLMNR)
- Even non existing hosts get mapped to P4wnP1. 
  This could be tested by running `ping notexistinghostname` from a windows target and P4wnP1 should reply from 172.16.0.1
- The forced SMB request, triggered from the delivered HTML page uses the latter. The request targets a SMB share on a host named `spoofsmb`. Although this host never existed, it is resolved to P4wnP1's IP and thus requests to it could easily be identified in log files, based on the targeted hostname `spoofsmb`

Snagging creds from locked machines after MS16-112
==================================================
During tests of P4wnP1 a product has been found to answer NTLM authentication requests on wpad.dat on a locked and fully patched Windows 10 machine.
The NTLM hash of the logged in user is sent, even if the machine isn't domain joined. The flaw will be reported to the respective vendor and added to the README after a patch is in delivery.
Of course you're free to try this on your own. Hint: The product doesn't fire requests to wpad.dat immediately, it could take several minutes.

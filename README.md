# blsh

blsh is a mostly bash script that queries blackslists through the dnsbl mechanism to find out if a given IP or domain is listed. As depending on the number of queries can be considerate, there is a reporting mechanism that may output the resulting summary to telegram (feature added for my own convenience).
Query data is stored with sqlite so that you can analyze behaviors related to the listings.

DNSBL is often used by mail servers to decide whether to accept, reject or mark incoming messages as spam in "real time". Sometimes your IP or domain may be listed on them which will give you trouble to deliver your mail on the internet, so checking them proactively looks like good practice, hence this script was born.

Some lists are not blacklists at all and may provide different services. Often DNSBL is also used to flag incoming connections as malicious on security systems.

DNSBL follows an RFC, which you should consult for more information.

## requirements

`sqlite3, curl` and `dig`. There's no package right now, so you should install these yourself on your distribution. If you're trying this on Windows, I think you shouldn't, but please let me know about it =)

## instructions

There is still no installation package for this, so just place `blsh` on `/usr/local/bin` and setup your data folder. You can edit the (default) paths inside the script and via arguments, but it is assumed the following:

```
Base path: ~/.local/blsh
Database: ~/.local/blsh/blsh.sqlite
Blacklists list: ~/.local/blsh/lists/bl
Hosts list: ~/.local/blsh/lists/host
Telegram creds (optional): ~/.local/blsh/lists/telegram
DNS list: ~/.local/blsh/lists/dns
Unsent reports: ~/.local/blsh/unsentreports
```

Blacklists and hosts can be of 3 types: ipv4, ipv6 and domain.
The the bl and host files should follow the `type,entry` format, one per line. In case of doubt check the list examples.
The telegram creds should follow the `bot-token,channel` format. If you don't know what this means, please check how to create a bot on Telegram. This way you can notify multiple channels, each with a different bot if required.

Example lists can be found under `lists` in this repository.

## notes

I **very strongly** suggest that you set up your own recursive DNS server to make the queries instead of some public infrastructure. Blacklists often employ query limits for IPs for various reasons, or may not answer at all without some kind of subscription. When such a limit is reached (which is pretty common with public DNS servers, but may also happen if your checks are too frequent even with a dedicated DNS) the blacklist will most likely report ANY query as a positive listing. Due to this behaviour I have implemented a "double check" that will try a different DNS server when a positive is found. To use this feature just add more DNS servers to the configuration.

If you happen to find out that my example list contains a blacklist that shouldn't be here, let me know the reason and I'll remove it ASAP.

## credits

The displaytime function, that "converts" a number of seconds to something more readable, was obtained from http://www.infotinks.com/bash-convert-seconds-to-human-readable/. Thanks! Saved me a good time =D

## licence

Copyright (C) 2021 Renato Rodrigues Zippert

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

You can contact the author by email at automail_blsh 'AT' zppr.tk.

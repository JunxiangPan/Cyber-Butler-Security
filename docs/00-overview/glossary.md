# Glossary

| Term | Meaning |
|---|---|
| CBS | Cyber-Butler Security, the control plane in this repository |
| SCM | Windows Service Control Manager; hosts `CyberButlerAstrBot` |
| S4U | Service-for-User Task Scheduler logon; retired for AstrBot on this host |
| WFP | Windows Filtering Platform; current guard writes audit status, not a native filter |
| Broker | Local TOTP/approval HTTP service on 18090 |
| OneBot adapter | AstrBot platform adapter; it dynamically opens 6199 |
| Job Object | Windows kernel object used to kill the whole child tree |

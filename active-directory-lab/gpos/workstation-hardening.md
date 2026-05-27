# GPO: Workstation Security Hardening

**Linked to:** `OU=Workstations,OU=Computers,OU=Contoso,DC=contoso,DC=local`  
**Linked to:** `OU=Laptops,OU=Computers,OU=Contoso,DC=contoso,DC=local`  
**Scope:** All end-user workstations and laptops  
**Author:** Nikhil Mahtani  

---

## Overview

This GPO enforces a security baseline on all managed workstations. Settings are applied silently at machine startup and user logon. Users cannot override them.

The policy aligns with the CIS Microsoft Windows 10 Benchmark (Level 1) and is reviewed quarterly.

---

## Computer Configuration Settings

### Windows Firewall

`Computer Configuration → Windows Settings → Security Settings → Windows Defender Firewall`

| Setting | Value |
|---|---|
| Firewall state (Domain profile) | On |
| Firewall state (Private profile) | On |
| Firewall state (Public profile) | On |
| Inbound connections (Public) | Block all |
| Outbound connections | Allow |
| Log dropped packets | Yes |

---

### User Rights Assignment

`Computer Configuration → Windows Settings → Security Settings → Local Policies → User Rights Assignment`

| Setting | Value | Reason |
|---|---|---|
| Allow log on locally | Domain Users, Administrators | Restricts interactive logon |
| Deny log on through Remote Desktop | Guests | No guest RDP |
| Shut down the system | Administrators, Domain Users | Users can shut down their own machine |
| Take ownership of files | Administrators only | Prevents unauthorized file access |

---

### Security Options

`Computer Configuration → Windows Settings → Security Settings → Local Policies → Security Options`

| Setting | Value |
|---|---|
| Interactive logon: Machine inactivity limit | 300 seconds (5 min) |
| Interactive logon: Do not require CTRL+ALT+DEL | Disabled (require it) |
| Interactive logon: Display user information when session is locked | Do not display user name |
| Interactive logon: Number of previous logons to cache | 2 |
| Network access: Do not allow anonymous enumeration of SAM accounts | Enabled |
| Network security: LAN Manager authentication level | Send NTLMv2 response only, refuse LM and NTLM |
| Network security: Minimum session security for NTLM SSP | Require NTLMv2 and 128-bit encryption |
| Accounts: Rename administrator account | Enabled (rename to non-default name) |
| Accounts: Guest account status | Disabled |
| Devices: Prevent users from installing printer drivers | Enabled |

---

### Windows Update

`Computer Configuration → Administrative Templates → Windows Components → Windows Update`

| Setting | Value |
|---|---|
| Configure Automatic Updates | Enabled — Auto download and schedule install |
| Scheduled install day | Every day |
| Scheduled install time | 03:00 |
| No auto-restart with logged on users | Enabled |
| Delay restart for scheduled installations | 5 minutes |

---

### Windows Defender

`Computer Configuration → Administrative Templates → Windows Components → Microsoft Defender Antivirus`

| Setting | Value |
|---|---|
| Turn off Microsoft Defender Antivirus | Disabled (keep Defender on) |
| Turn on real-time protection | Enabled |
| Turn on behavior monitoring | Enabled |
| Scan removable drives | Enabled |
| Check for new signatures before scheduled scan | Enabled |

---

### Remote Desktop

`Computer Configuration → Administrative Templates → Windows Components → Remote Desktop Services`

| Setting | Value |
|---|---|
| Allow users to connect remotely using RDS | Enabled (IT support use only) |
| Require NLA for remote connections | Enabled |
| Set time limit for disconnected sessions | 1 hour |
| Set time limit for idle sessions | 30 minutes |

---

## User Configuration Settings

### Control Panel and Settings Access

`User Configuration → Administrative Templates → Control Panel`

| Setting | Value |
|---|---|
| Prohibit access to Control Panel and PC Settings | Disabled (allow access) |
| Hide specified Control Panel items | Network and Sharing Center (users cannot change network settings) |

---

### Removable Storage

`User Configuration → Administrative Templates → System → Removable Storage Access`

| Setting | Value | Reason |
|---|---|---|
| All Removable Storage classes: Deny all access | Enabled | DLP — USB storage blocked for all users |

> **Exception:** IT staff in `grp-it-staff` are excluded from this policy via Security Filtering on the GPO.

---

### Browser (Microsoft Edge)

`User Configuration → Administrative Templates → Microsoft Edge`

| Setting | Value |
|---|---|
| Configure SmartScreen | Enabled |
| Prevent bypassing SmartScreen prompts for sites | Enabled |
| Prevent bypassing SmartScreen prompts for downloads | Enabled |
| Block access to a list of URLs | Configured per org policy |
| Configure Tracking Prevention | Enabled — Balanced |

---

## GPO Security Filtering

| Applied to | Excluded from |
|---|---|
| `Domain Computers` security group | `grp-it-staff` (USB exception), `Domain Controllers` |

Security filtering is preferred over WMI filters for performance reasons.

---

## GPO Precedence

This GPO has a higher precedence than the Default Domain Policy and lower precedence than any emergency-response GPO linked at the same OU level.

| Order | GPO | Notes |
|---|---|---|
| 1 (highest) | Emergency-Lockdown | Manual — linked only when needed |
| 2 | Workstation Hardening | This GPO |
| 3 | Software Restriction | AppLocker rules |
| 4 (lowest) | Default Domain Policy | |

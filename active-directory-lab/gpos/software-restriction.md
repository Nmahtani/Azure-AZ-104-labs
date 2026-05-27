# GPO: Software Restriction Policy (AppLocker)

**Linked to:** `OU=Workstations,OU=Computers,OU=Contoso,DC=contoso,DC=local`  
**Scope:** Standard users on all managed workstations  
**Author:** Nikhil Mahtani  

---

## Overview

AppLocker is used to control which applications users can run on managed workstations. The policy uses a whitelist (allow-list) approach — only approved software is permitted. Everything not explicitly allowed is blocked.

AppLocker requires Windows 10/11 Enterprise or Education. For Pro editions, Software Restriction Policies (SRP) are used as a fallback.

---

## AppLocker Rule Collections

### Executable Rules (.exe, .com)

| Rule | Type | Path / Publisher | Applied to |
|---|---|---|---|
| Allow Windows system files | Publisher | `O=MICROSOFT CORPORATION` | Everyone |
| Allow Program Files | Path | `%PROGRAMFILES%\*` | Everyone |
| Allow Program Files (x86) | Path | `%PROGRAMFILES(X86)%\*` | Everyone |
| Allow IT admin tools | Publisher | `O=MICROSOFT CORPORATION` | `grp-it-staff` only |
| Block unsigned executables from user profile | Path | `%USERPROFILE%\*` | Everyone |
| Block Downloads folder execution | Path | `%USERPROFILE%\Downloads\*` | Everyone |
| Block temp folder execution | Path | `%TEMP%\*` | Everyone |

---

### Windows Installer Rules (.msi, .msp, .mst)

| Rule | Type | Value |
|---|---|---|
| Allow signed installers from Microsoft | Publisher | `O=MICROSOFT CORPORATION` |
| Allow IT-deployed packages | Path | `\\fileserver\Software\*` |
| Block all other MSI | Default | Deny |

> Standard users cannot install software. All deployments go through the IT software repository or Intune.

---

### Script Rules (.ps1, .bat, .cmd, .vbs, .js)

| Rule | Type | Value |
|---|---|---|
| Allow IT scripts from network share | Path | `\\fileserver\Scripts\*` |
| Allow signed PowerShell scripts | Publisher | `O=MICROSOFT CORPORATION` |
| Block scripts in user profile | Path | `%USERPROFILE%\*` |
| Block scripts in Downloads | Path | `%USERPROFILE%\Downloads\*` |

---

### Packaged App Rules (MSIX / AppX)

| Rule | Type | Value |
|---|---|---|
| Allow all Microsoft Store apps | Publisher | `O=CN=MICROSOFT CORPORATION` |
| Block sideloaded packages | Default | Deny |

---

## Enforcement Mode

| Collection | Mode |
|---|---|
| Executable Rules | Enforce |
| Windows Installer Rules | Enforce |
| Script Rules | Enforce |
| Packaged App Rules | Audit only (monitor before enforcing) |

Audit mode logs blocked events to `Event Log → Applications and Services → Microsoft → Windows → AppLocker` without blocking execution. Use audit mode on new collections for at least 2 weeks before switching to Enforce.

---

## Exceptions — IT Staff

Members of `grp-it-staff` are excluded from AppLocker script rules via a separate GPO (`GPO-IT-Staff-Override`) linked at the same OU with higher precedence. This allows IT admins to run PowerShell and other tools needed for management.

---

## Blocked Software Examples

The following categories are blocked by the default-deny rules:

- Unsigned executables run from `%TEMP%`, `%APPDATA%`, or `Downloads`
- Portable applications (no installer, run directly from .exe)
- Shadow IT tools (Dropbox personal, unauthorized VPN clients)
- Script-based malware dropped to user profile directories

---

## Event Log Monitoring

AppLocker events to monitor:

| Event ID | Description |
|---|---|
| 8003 | Executable was allowed to run |
| 8004 | Executable was blocked |
| 8007 | Script was blocked |
| 8022 | Packaged app was audited (not blocked) |

Forward these events to your SIEM or Microsoft Sentinel workspace for alerting on repeated block events, which may indicate malware execution attempts.

---

## PowerShell: Export Current AppLocker Policy

```powershell
# Export current effective AppLocker policy to XML
Get-AppLockerPolicy -Effective -Xml | Out-File ".\AppLockerPolicy-$(Get-Date -Format 'yyyy-MM-dd').xml"

# Test a specific file against the policy
Test-AppLockerPolicy -Path "C:\Users\john.doe\Downloads\tool.exe" -User "contoso\john.doe"
```

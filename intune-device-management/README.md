# intune-device-management

> **Author:** Nikhil Mahtani · IT Systems Administrator  
> **Stack:** Microsoft Intune · Entra ID · PowerShell · Microsoft Graph API  
> **Scope:** End-to-end MDM deployment — Windows 10/11 and macOS, from zero to compliant

---

## Overview

This project covers a full Microsoft Intune MDM implementation for a mixed Windows and macOS environment. It includes compliance policies, security configuration profiles, and a PowerShell script to generate device compliance audit reports via the Microsoft Graph API.

The target outcome is zero-touch enrollment: a device powers on, the user signs in with corporate credentials, and Intune automatically enrolls it, enforces security baselines, and blocks access to Microsoft 365 if requirements are not met.

---

## Repository Structure

```
intune-device-management/
├── README.md
├── compliance-policies/
│   ├── windows-compliance.json          # Compliance rules for Windows 10/11
│   └── macos-compliance.json            # Compliance rules for macOS
├── config-profiles/
│   ├── windows-security-baseline.json   # Security hardening profile for Windows
│   └── macos-security-baseline.json     # Security hardening profile for macOS
├── scripts/
│   └── Get-DeviceComplianceReport.ps1   # Graph API compliance report exporter
└── reports/
    └── (generated CSV reports land here — excluded from version control)
```

---

## Architecture

```
Entra ID (Identity Provider)
        │
        ▼
Microsoft Intune (MDM Authority)
        │
        ├── Enrollment
        │     ├── Windows  →  Autopilot (User-Driven, AAD Join)
        │     └── macOS    →  ADE via Apple Business Manager
        │
        ├── Dynamic Device Groups
        │     ├── grp-intune-windows   rule: device.deviceOSType -eq "Windows"
        │     └── grp-intune-macos     rule: device.deviceOSType -eq "MacMDM"
        │
        ├── Compliance Policies (assigned to groups above)
        │     ├── windows-compliance.json
        │     └── macos-compliance.json
        │
        ├── Configuration Profiles (assigned to groups above)
        │     ├── windows-security-baseline.json
        │     └── macos-security-baseline.json
        │
        └── Conditional Access
              └── Block M365 access if ComplianceState ≠ Compliant
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Microsoft Intune license | M365 Business Premium, EMS E3/E5, or Intune standalone |
| Entra ID | At least one verified custom domain |
| Apple Business Manager | Required for macOS ADE enrollment only |
| Windows Autopilot | Hardware hash must be registered before device ships |
| PowerShell 7+ | For the compliance report script |
| Microsoft.Graph module | `Install-Module Microsoft.Graph -Scope CurrentUser` |

---

## Compliance Policies

Compliance policies define the minimum security requirements a device must meet. Devices that fail are marked **Non-Compliant** and blocked from Microsoft 365 resources via Conditional Access after a 72-hour grace period.

### Windows — `compliance-policies/windows-compliance.json`

| Setting | Required Value | Reason |
|---|---|---|
| BitLocker | Enabled | Disk encryption at rest |
| Secure Boot | Enabled | Boot integrity verification |
| TPM | Required | Hardware-backed key storage |
| Microsoft Defender | Enabled | Endpoint protection |
| Real-time protection | Enabled | Active threat detection |
| Firewall | Enabled | Network perimeter control |
| Minimum OS version | 10.0.19041 (20H1) | Security patch baseline |
| Threat protection level | Medium | Microsoft Defender for Endpoint |
| Action on noncompliance | Block after 72h | Enforced via Conditional Access |

### macOS — `compliance-policies/macos-compliance.json`

| Setting | Required Value | Reason |
|---|---|---|
| FileVault | Enabled | Disk encryption at rest |
| Gatekeeper | App Store + Identified Developers | Prevents unsigned app execution |
| Firewall | Enabled | Network perimeter control |
| Firewall stealth mode | Enabled | No response to probe requests |
| System Integrity Protection | Enabled | Protects core OS files |
| Minimum OS version | 13.0 (Ventura) | Security patch baseline |
| Threat protection level | Medium | Microsoft Defender for Endpoint |

---

## Configuration Profiles

Configuration profiles push settings silently to enrolled devices. Users cannot override them. They are assigned to the dynamic device groups and applied automatically on enrollment.

### Windows — `config-profiles/windows-security-baseline.json`

Applied via MDM CSP (Configuration Service Provider).

| Category | Setting |
|---|---|
| Password | Min 12 chars, alphanumeric, 90-day expiry, 5 previous blocked |
| Screen lock | 5 minutes idle |
| Storage | Removable storage blocked (DLP) |
| Defender | Real-time monitoring, behaviour monitoring, cloud protection High |
| Defender signatures | Update every 4 hours |
| SmartScreen | Enabled, block file override |
| Telemetry | Security level (minimum collection) |
| Assignment | grp-intune-windows |

### macOS — `config-profiles/macos-security-baseline.json`

Applied via Apple MDM payload.

| Category | Setting |
|---|---|
| Password | Min 12 chars, alphanumeric, 90-day expiry, 5 previous blocked |
| Screen lock | 5 minutes idle |
| Firewall | Enabled with stealth mode |
| Microsoft Defender | Full disk access granted via privacy controls (MDM-managed) |
| Software updates | Automatic |
| Assignment | grp-intune-macos |

---

## Compliance Report Script

`scripts/Get-DeviceComplianceReport.ps1` connects to Microsoft Graph and exports a full device inventory with compliance status to CSV.

### Install dependency

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

### Usage

```powershell
# Full report — all devices
.\scripts\Get-DeviceComplianceReport.ps1 -ExportCsv

# Filter by OS
.\scripts\Get-DeviceComplianceReport.ps1 -OS Windows -ExportCsv
.\scripts\Get-DeviceComplianceReport.ps1 -OS macOS -ExportCsv

# Non-compliant devices only
.\scripts\Get-DeviceComplianceReport.ps1 -NonCompliantOnly -ExportCsv

# Combined filter
.\scripts\Get-DeviceComplianceReport.ps1 -OS Windows -NonCompliantOnly -ExportCsv
```

Output saved to `reports/compliance-report-<timestamp>.csv`.

### Required Graph permission

`DeviceManagementManagedDevices.Read.All` — read-only, no write access.

### Report columns

`DeviceName` · `UserPrincipalName` · `OS` · `OSVersion` · `ComplianceState` · `LastSyncDateTime` · `SyncAgeHours` · `EnrolledDate` · `Manufacturer` · `Model` · `SerialNumber` · `OwnerType` · `EnrollmentType` · `AzureADDeviceId` · `IntuneDeviceId`

---

## Enrollment Overview

### Windows — Autopilot (User-Driven, AAD Join)

1. IT registers hardware hash in Autopilot via MEM portal or CSV
2. Autopilot profile assigned (skip EULA, skip privacy, force AAD join)
3. Device ships to user — user powers on, connects to internet
4. OOBE detects Autopilot profile, prompts for corporate sign-in
5. User authenticates with Entra ID credentials + MFA
6. Device joins Entra ID, Intune enrolls automatically
7. Dynamic group rule matches → device assigned to `grp-intune-windows`
8. Compliance policy and configuration profile applied
9. Device compliant → Conditional Access grants M365 access

**Estimated time:** ~55 minutes, zero IT presence required on-site.

### macOS — ADE via Apple Business Manager

1. IT connects Apple Business Manager to Intune via MDM server token
2. ADE enrollment profile created in MEM and assigned
3. Mac purchased via authorized reseller linked to ABM — assigned to MDM server
4. User powers on, macOS Setup Assistant detects ADE profile
5. User authenticates with Entra ID credentials + MFA
6. MDM payload installed, device assigned to `grp-intune-macos`
7. Compliance policy and configuration profile applied
8. Device compliant → Conditional Access grants M365 access

**Key difference from Windows:** macOS ADE requires an Apple Business Manager account and an MDM server token that must be renewed annually. The Mac must be purchased through an authorized reseller linked to ABM.

---

## Skills Demonstrated

- Microsoft Intune MDM deployment for Windows and macOS
- Entra ID dynamic device group membership rules
- Compliance policy design with Conditional Access enforcement
- Configuration profile deployment via MDM CSP and Apple MDM payload
- Microsoft Graph API querying via PowerShell (`Microsoft.Graph` module)
- Zero-touch enrollment: Windows Autopilot and macOS ADE
- Principle of least privilege (read-only Graph permission scoping)

---

## Related Projects

- [az104-rbac-governance](../az104-rbac-governance) — Azure RBAC and custom role automation
- [m365-admin-scripts](../m365-admin-scripts) — Microsoft 365 tenant administration
- [active-directory-lab](../active-directory-lab) — On-premises AD and Entra ID hybrid

---

*Nikhil Mahtani · IT Systems Administrator · Las Palmas de Gran Canaria, Spain*  
*Microsoft 365 · Intune · Entra ID · Azure · AWS Cloud Practitioner*

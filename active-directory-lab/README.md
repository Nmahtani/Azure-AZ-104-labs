# active-directory-lab

> **Author:** Nikhil Mahtani · IT Systems Administrator  
> **Stack:** Active Directory DS · Entra ID · Entra Connect · PowerShell · Group Policy  
> **Scope:** Hybrid identity environment — on-premises AD with Entra ID synchronization, user lifecycle automation, OU structure, and GPO hardening

---

## Overview

This project covers the design and automation of a hybrid Active Directory environment. It combines on-premises AD DS with Entra ID (Azure Active Directory) via Entra Connect, giving users a single identity that works both on-prem and in the cloud.

The repository includes PowerShell scripts for user onboarding and offboarding, group and OU management, Entra Connect health checks, and Group Policy Object definitions for security hardening — all reflecting real-world sysadmin workflows.

---

## Repository Structure

```
active-directory-lab/
├── README.md
├── scripts/
│   ├── onboarding/
│   │   ├── New-ADUser-Onboard.ps1         # Create AD user + assign groups + trigger sync
│   │   └── New-BulkUsers.ps1              # Bulk user creation from CSV
│   ├── groups-ous/
│   │   ├── New-OUStructure.ps1            # Build full OU hierarchy from scratch
│   │   └── Manage-ADGroups.ps1            # Create groups, add/remove members, audit
│   └── hybrid/
│       ├── Invoke-EntraSync.ps1           # Trigger delta/full Entra Connect sync
│       └── Get-HybridUserReport.ps1       # Compare on-prem AD vs Entra ID user state
├── gpos/
│   ├── password-policy.md                 # Domain password policy definition
│   ├── workstation-hardening.md           # Workstation security GPO settings
│   └── software-restriction.md           # AppLocker / software restriction policy
├── docs/
│   └── hybrid-architecture.md            # Hybrid identity design decisions
└── .gitignore
```

---

## Environment Design

### Domain

```
Forest root:    contoso.local  (on-premises)
UPN suffix:     contoso.com    (synced to Entra ID)
Entra tenant:   contoso.onmicrosoft.com
```

### OU Structure

```
contoso.local
└── Contoso
    ├── Users
    │   ├── Employees
    │   ├── ServiceAccounts
    │   └── Disabled
    ├── Computers
    │   ├── Workstations
    │   └── Servers
    ├── Groups
    │   ├── Security
    │   └── Distribution
    └── Admin
```

### Entra Connect Sync Scope

Only OUs under `Contoso\Users\Employees` and `Contoso\Groups\Security` are synced to Entra ID. Service accounts and disabled users are intentionally excluded from cloud sync.

---

## Scripts

### Onboarding

#### `New-ADUser-Onboard.ps1`

Creates a new AD user with all required attributes, adds them to the correct security groups based on department, and triggers a delta sync to Entra ID.

```powershell
.\scripts\onboarding\New-ADUser-Onboard.ps1 `
    -FirstName "John" `
    -LastName "Doe" `
    -Department "Finance" `
    -JobTitle "Financial Analyst" `
    -Manager "jane.smith"
```

What it does:
- Generates UPN as `firstname.lastname@contoso.com`
- Creates user in the correct department OU
- Sets all required AD attributes (department, title, manager, phone)
- Assigns base security groups + department-specific groups
- Forces password change on first login
- Triggers Entra Connect delta sync
- Outputs a summary with the new user's details

#### `New-BulkUsers.ps1`

Creates multiple users from a CSV file. Useful for migrations or large onboarding batches.

```powershell
.\scripts\onboarding\New-BulkUsers.ps1 -CsvPath ".\users.csv"
```

CSV format:
```
FirstName,LastName,Department,JobTitle,Manager
John,Doe,Finance,Analyst,jane.smith
Jane,Smith,IT,SysAdmin,nikhil.mahtani
```

---

### Groups and OUs

#### `New-OUStructure.ps1`

Builds the full OU hierarchy from scratch. Safe to run on a new domain — checks for existing OUs before creating.

```powershell
.\scripts\groups-ous\New-OUStructure.ps1 -DomainDN "DC=contoso,DC=local"
```

#### `Manage-ADGroups.ps1`

Creates groups, adds or removes members, and exports a group membership audit report.

```powershell
# Create a new security group
.\scripts\groups-ous\Manage-ADGroups.ps1 -Action Create -GroupName "grp-finance-users" -OU "Groups\Security"

# Add members
.\scripts\groups-ous\Manage-ADGroups.ps1 -Action AddMember -GroupName "grp-finance-users" -Members "john.doe","jane.smith"

# Export membership audit
.\scripts\groups-ous\Manage-ADGroups.ps1 -Action Audit -ExportCsv
```

---

### Hybrid (Entra Connect)

#### `Invoke-EntraSync.ps1`

Triggers a delta or full synchronization cycle on the Entra Connect server.

```powershell
# Delta sync (recommended for routine use)
.\scripts\hybrid\Invoke-EntraSync.ps1 -SyncType Delta

# Full sync (use after major OU or attribute changes)
.\scripts\hybrid\Invoke-EntraSync.ps1 -SyncType Full
```

#### `Get-HybridUserReport.ps1`

Compares user state between on-premises AD and Entra ID. Identifies users that exist on-prem but are not synced, or have attribute mismatches.

```powershell
.\scripts\hybrid\Get-HybridUserReport.ps1 -ExportCsv
```

Output columns: `SamAccountName` · `UPN` · `ADEnabled` · `EntraIDExists` · `EntraIDEnabled` · `LastSync` · `SyncStatus`

---

## Group Policy Objects

See the `gpos/` folder for full definitions of each policy. All GPOs follow the principle of least privilege and are linked at the appropriate OU level — not domain-wide — to minimize blast radius.

| GPO | Linked To | Purpose |
|---|---|---|
| [Password Policy](gpos/password-policy.md) | Domain root | Enforce password complexity and history |
| [Workstation Hardening](gpos/workstation-hardening.md) | Computers\Workstations | Security baseline for all workstations |
| [Software Restriction](gpos/software-restriction.md) | Computers\Workstations | Block unauthorized software execution |

---

## Hybrid Identity Design

See [`docs/hybrid-architecture.md`](docs/hybrid-architecture.md) for full design decisions including sync scope, UPN suffix strategy, password hash sync vs pass-through authentication, and Conditional Access integration.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Windows Server 2019/2022 | Domain controller with AD DS role |
| PowerShell 5.1+ | RSAT AD module: `Install-WindowsFeature RSAT-AD-PowerShell` |
| Entra Connect | Installed on a dedicated member server, not the DC |
| Microsoft.Graph module | For hybrid report: `Install-Module Microsoft.Graph` |
| Entra ID P1 license | Required for Conditional Access integration |

---

## Skills Demonstrated

- Active Directory DS design and deployment (OUs, users, groups)
- PowerShell automation with the ActiveDirectory module
- Hybrid identity with Entra Connect (delta and full sync)
- Group Policy design and OU-scoped linking
- User lifecycle management — onboarding, offboarding, bulk operations
- Cross-environment user state auditing (on-prem vs cloud)
- Security hardening via GPO

---

## Related Projects

- [intune-device-management](../intune-device-management) — Intune MDM for Windows and macOS
- [az104-rbac-governance](../az104-rbac-governance) — Azure RBAC and custom role automation
- [m365-admin-scripts](../m365-admin-scripts) — Microsoft 365 tenant administration

---

*Nikhil Mahtani · IT Systems Administrator · Las Palmas de Gran Canaria, Spain*  
*Active Directory · Entra ID · Microsoft 365 · Intune · Azure · AWS Cloud Practitioner*

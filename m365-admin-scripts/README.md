# m365-admin-scripts

> **Author:** Nikhil Mahtani · IT Systems Administrator  
> **Stack:** Microsoft 365 · Exchange Online · Teams · SharePoint · PowerShell · Microsoft Graph API  
> **Scope:** Day-to-day M365 tenant administration — automation scripts and audit reports covering Exchange Online, Teams, SharePoint, and license management

---

## Overview

This repository contains PowerShell scripts for administering a Microsoft 365 tenant. It covers the four main pillars of M365 administration: Exchange Online mailbox and distribution group management, Teams and SharePoint provisioning, license assignment and optimization, and cross-service audit reporting.

All scripts use the modern PowerShell modules (`ExchangeOnlineManagement`, `MicrosoftTeams`, `PnP.PowerShell`, `Microsoft.Graph`) and follow least-privilege principles — each script requests only the permissions it needs.

---

## Repository Structure

```
m365-admin-scripts/
├── README.md
├── scripts/
│   ├── exchange/
│   │   ├── Manage-Mailboxes.ps1           # Create, convert, and audit mailboxes
│   │   └── Manage-DistributionGroups.ps1  # Create DLs, manage membership, audit
│   ├── teams-sharepoint/
│   │   ├── New-TeamProvisioning.ps1       # Provision a new Team with standard structure
│   │   └── Get-TeamsUsageReport.ps1       # Teams activity and guest access audit
│   ├── licensing/
│   │   ├── Set-UserLicense.ps1            # Assign or remove M365 licenses
│   │   └── Get-LicenseReport.ps1          # Full license inventory and cost report
│   └── reporting/
│       └── Get-M365AuditReport.ps1        # Cross-service security and access audit
└── docs/
    └── module-setup.md                    # Required modules and connection guide
```

---

## Prerequisites

| Module | Install Command | Used For |
|---|---|---|
| ExchangeOnlineManagement | `Install-Module ExchangeOnlineManagement` | Exchange Online |
| MicrosoftTeams | `Install-Module MicrosoftTeams` | Teams |
| PnP.PowerShell | `Install-Module PnP.PowerShell` | SharePoint Online |
| Microsoft.Graph | `Install-Module Microsoft.Graph` | Licensing, reporting |

See [`docs/module-setup.md`](docs/module-setup.md) for full connection instructions and required permissions per script.

---

## Scripts

### Exchange Online

#### `Manage-Mailboxes.ps1`

Creates user mailboxes, converts them to shared mailboxes, sets forwarding, manages permissions, and exports a mailbox inventory.

```powershell
# Create a shared mailbox
.\scripts\exchange\Manage-Mailboxes.ps1 -Action CreateShared -DisplayName "Finance Team" -Alias "finance"

# Grant full access to a shared mailbox
.\scripts\exchange\Manage-Mailboxes.ps1 -Action GrantAccess -Mailbox "finance@contoso.com" -User "john.doe@contoso.com"

# Export full mailbox inventory
.\scripts\exchange\Manage-Mailboxes.ps1 -Action Audit -ExportCsv
```

#### `Manage-DistributionGroups.ps1`

Creates distribution lists and Microsoft 365 groups, manages membership, and audits group membership across the tenant.

```powershell
# Create a distribution list
.\scripts\exchange\Manage-DistributionGroups.ps1 -Action Create -Name "Finance DL" -Alias "finance-dl" -Type Distribution

# Add members
.\scripts\exchange\Manage-DistributionGroups.ps1 -Action AddMember -GroupAlias "finance-dl" -Members "john.doe@contoso.com","jane.smith@contoso.com"

# Audit all groups
.\scripts\exchange\Manage-DistributionGroups.ps1 -Action Audit -ExportCsv
```

---

### Teams and SharePoint

#### `New-TeamProvisioning.ps1`

Provisions a new Microsoft Team with a standard channel structure, sets membership and guest access policies, and creates the associated SharePoint site with correct permissions.

```powershell
.\scripts\teams-sharepoint\New-TeamProvisioning.ps1 `
    -TeamName "Finance Team" `
    -Description "Finance department collaboration space" `
    -Owner "jane.smith@contoso.com" `
    -Members "john.doe@contoso.com","sara.garcia@contoso.com" `
    -AllowGuests $false
```

#### `Get-TeamsUsageReport.ps1`

Audits Teams activity across the tenant — inactive teams, guest members, external sharing, and channel usage.

```powershell
# Full Teams audit
.\scripts\teams-sharepoint\Get-TeamsUsageReport.ps1 -ExportCsv

# Show only teams with guest members
.\scripts\teams-sharepoint\Get-TeamsUsageReport.ps1 -GuestsOnly -ExportCsv

# Show inactive teams (no activity in 90 days)
.\scripts\teams-sharepoint\Get-TeamsUsageReport.ps1 -InactiveDays 90 -ExportCsv
```

---

### Licensing

#### `Set-UserLicense.ps1`

Assigns or removes Microsoft 365 licenses for individual users or groups. Supports license plan selection and service plan toggling.

```powershell
# Assign Business Premium license
.\scripts\licensing\Set-UserLicense.ps1 -UserPrincipalName "john.doe@contoso.com" -Action Assign -LicenseSku "SPB"

# Remove license
.\scripts\licensing\Set-UserLicense.ps1 -UserPrincipalName "john.doe@contoso.com" -Action Remove -LicenseSku "SPB"

# Bulk assign from CSV
.\scripts\licensing\Set-UserLicense.ps1 -CsvPath ".\users.csv" -Action Assign -LicenseSku "SPB"
```

#### `Get-LicenseReport.ps1`

Exports a full license inventory showing assigned licenses per user, available license pools, and unlicensed users.

```powershell
# Full license report
.\scripts\licensing\Get-LicenseReport.ps1 -ExportCsv

# Show unlicensed users only
.\scripts\licensing\Get-LicenseReport.ps1 -UnlicensedOnly

# Show license pool summary (how many available vs assigned)
.\scripts\licensing\Get-LicenseReport.ps1 -PoolSummary
```

---

### Reporting

#### `Get-M365AuditReport.ps1`

Cross-service security and access audit. Pulls data from Exchange, Teams, SharePoint, and Entra ID to produce a unified report covering MFA status, mailbox access, guest accounts, and inactive users.

```powershell
# Full audit — all services
.\scripts\reporting\Get-M365AuditReport.ps1 -ExportCsv

# MFA status only
.\scripts\reporting\Get-M365AuditReport.ps1 -Section MFA -ExportCsv

# Guest accounts audit
.\scripts\reporting\Get-M365AuditReport.ps1 -Section Guests -ExportCsv
```

---

## Permissions Reference

| Script | Required Permission / Role |
|---|---|
| Manage-Mailboxes.ps1 | Exchange Admin or Recipient Management role |
| Manage-DistributionGroups.ps1 | Exchange Admin or Recipient Management role |
| New-TeamProvisioning.ps1 | Teams Admin + SharePoint Admin |
| Get-TeamsUsageReport.ps1 | Teams Admin (read-only) |
| Set-UserLicense.ps1 | License Admin or User Admin |
| Get-LicenseReport.ps1 | `Organization.Read.All` (Graph) |
| Get-M365AuditReport.ps1 | `AuditLog.Read.All`, `User.Read.All`, `Reports.Read.All` |

---

## Skills Demonstrated

- Exchange Online mailbox and distribution group management
- Microsoft Teams provisioning and governance
- SharePoint Online site permissions via PnP.PowerShell
- Microsoft 365 license management via Microsoft Graph
- Cross-service audit reporting
- PowerShell automation with modern M365 modules
- Least-privilege permission design per script

---

## Related Projects

- [active-directory-lab](../active-directory-lab) — On-premises AD and Entra ID hybrid identity
- [intune-device-management](../intune-device-management) — Intune MDM for Windows and macOS
- [az104-rbac-governance](../az104-rbac-governance) — Azure RBAC and custom role automation

---

*Nikhil Mahtani · IT Systems Administrator · Las Palmas de Gran Canaria, Spain*  
*Microsoft 365 · Exchange Online · Teams · Intune · Entra ID · Azure · AWS Cloud Practitioner*

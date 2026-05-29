# Module Setup and Connection Guide

**Author:** Nikhil Mahtani · IT Systems Administrator  
**Project:** m365-admin-scripts

---

## Required Modules

Install all modules once on the admin machine:

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
Install-Module MicrosoftTeams           -Scope CurrentUser
Install-Module PnP.PowerShell          -Scope CurrentUser
Install-Module Microsoft.Graph         -Scope CurrentUser
```

Update to latest versions:

```powershell
Update-Module ExchangeOnlineManagement
Update-Module MicrosoftTeams
Update-Module PnP.PowerShell
Update-Module Microsoft.Graph
```

---

## Connecting to Each Service

### Exchange Online

```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com
```

Required role: **Exchange Administrator** or **Recipient Management**

Disconnect when done:
```powershell
Disconnect-ExchangeOnline -Confirm:$false
```

---

### Microsoft Teams

```powershell
Connect-MicrosoftTeams
```

Required role: **Teams Administrator**

Disconnect:
```powershell
Disconnect-MicrosoftTeams
```

---

### Microsoft Graph

Each script specifies its own scopes. The connection prompt will ask for consent on first run.

```powershell
# Example — licensing scripts
Connect-MgGraph -Scopes "User.ReadWrite.All", "Organization.Read.All"

# Example — audit report
Connect-MgGraph -Scopes "AuditLog.Read.All", "User.Read.All", "Reports.Read.All", "UserAuthenticationMethod.Read.All"
```

Required roles: **Global Reader** (for read-only scripts) or **License Administrator** / **User Administrator** (for write operations)

Disconnect:
```powershell
Disconnect-MgGraph
```

---

## Permissions per Script

| Script | Module | Minimum Role |
|---|---|---|
| Manage-Mailboxes.ps1 | ExchangeOnlineManagement | Recipient Management |
| Manage-DistributionGroups.ps1 | ExchangeOnlineManagement | Recipient Management |
| New-TeamProvisioning.ps1 | MicrosoftTeams | Teams Administrator |
| Get-TeamsUsageReport.ps1 | MicrosoftTeams | Teams Administrator (read) |
| Set-UserLicense.ps1 | Microsoft.Graph | License Administrator |
| Get-LicenseReport.ps1 | Microsoft.Graph | Global Reader |
| Get-M365AuditReport.ps1 | Microsoft.Graph + Exchange + Teams | Global Reader + Exchange Admin |

---

## Running Scripts Without Interactive Login (Automation)

For scheduled or unattended runs, use a service principal with certificate authentication:

```powershell
# Exchange Online — certificate-based
Connect-ExchangeOnline `
    -CertificateThumbprint "THUMBPRINT" `
    -AppId "APP_ID" `
    -Organization "contoso.onmicrosoft.com"

# Microsoft Graph — service principal
Connect-MgGraph `
    -ClientId "APP_ID" `
    -TenantId "TENANT_ID" `
    -CertificateThumbprint "THUMBPRINT"
```

The app registration requires the following API permissions (application, not delegated):
- `Mail.Read` — mailbox audit
- `User.Read.All` — user and license reports
- `Reports.Read.All` — usage reports
- `AuditLog.Read.All` — sign-in and audit logs

Certificate-based auth is preferred over client secrets for production automation.

# az104-rbac-governance

> AZ-104 Lab 02 — Subscriptions & RBAC  
> Automating role-based access control governance in Azure using PowerShell.

---

## Overview

This project automates Azure RBAC management across a subscription:

- Create **custom roles** scoped to specific resource groups
- **Assign built-in and custom roles** to users, groups, or service principals
- Generate a **full access report** (who has access to what) for audits
- **Remove role assignments** cleanly during offboarding

Built with PowerShell + Az module. No Azure portal clicks required.

---

## Project Structure

```
az104-rbac-governance/
├── scripts/
│   ├── New-CustomRole.ps1            # Create a custom RBAC role from JSON definition
│   ├── Set-RoleAssignment.ps1        # Assign a role to a user/group/SP
│   ├── Remove-RoleAssignment.ps1     # Remove a role assignment (offboarding)
│   └── Get-AccessReport.ps1          # Generate full subscription access report
├── roles/
│   └── custom-role-vm-operator.json  # Example custom role definition
├── reports/
│   └── (generated .csv reports land here)
├── docs/
│   └── rbac-design.md                # Design decisions and role matrix
└── README.md
```

---

## Prerequisites

```powershell
# Install the Az PowerShell module
Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force

# Authenticate
Connect-AzAccount

# Set your target subscription
Set-AzContext -SubscriptionId "<your-subscription-id>"
```

---

## Usage

### 1. Create a Custom Role

```powershell
.\scripts\New-CustomRole.ps1 -RoleDefinitionPath ".\roles\custom-role-vm-operator.json"
```

### 2. Assign a Role

```powershell
# Assign built-in Reader role to a user on a specific Resource Group
.\scripts\Set-RoleAssignment.ps1 `
    -UserPrincipalName "john.doe@contoso.com" `
    -RoleName "Reader" `
    -ResourceGroupName "rg-production"

# Assign custom role
.\scripts\Set-RoleAssignment.ps1 `
    -UserPrincipalName "jane.smith@contoso.com" `
    -RoleName "VM Operator (Custom)" `
    -ResourceGroupName "rg-compute"
```

### 3. Generate Access Report

```powershell
# Full subscription report — exports to ./reports/
.\scripts\Get-AccessReport.ps1 -ExportCsv

# Filter by resource group
.\scripts\Get-AccessReport.ps1 -ResourceGroupName "rg-production" -ExportCsv
```

Sample output (`reports/access-report-2024-01-15.csv`):

| DisplayName   | SignInName               | RoleDefinitionName   | Scope                         | PrincipalType |
|---------------|--------------------------|----------------------|-------------------------------|---------------|
| John Doe      | john.doe@contoso.com     | Reader               | /subscriptions/.../rg-prod    | User          |
| Jane Smith    | jane.smith@contoso.com   | VM Operator (Custom) | /subscriptions/.../rg-compute | User          |
| DevOps Team   | —                        | Contributor          | /subscriptions/.../rg-staging | Group         |

### 4. Remove a Role Assignment (Offboarding)

```powershell
.\scripts\Remove-RoleAssignment.ps1 `
    -UserPrincipalName "john.doe@contoso.com" `
    -RoleName "Reader" `
    -ResourceGroupName "rg-production"
```

---

## Custom Role: VM Operator

The included `custom-role-vm-operator.json` follows the **principle of least privilege** — the user can start/stop/restart VMs and read diagnostics, but cannot create, delete, or modify VM configurations.

| Allowed                          | Not Allowed                        |
|----------------------------------|------------------------------------|
| Start / Stop / Restart VMs       | Create or delete VMs               |
| Read VM status & diagnostics     | Modify VM size or disks            |
| View resource group contents     | Manage networking or storage       |

---

## RBAC Design Decisions

See [`docs/rbac-design.md`](docs/rbac-design.md) for the full role matrix and justification for each assignment.

---

## AZ-104 Exam Relevance

This project covers the **Manage Identities and Governance** domain (~20–25% of the exam):

- `Microsoft.Authorization/roleDefinitions` — custom role creation
- `Microsoft.Authorization/roleAssignments` — role assignment at RG and subscription scope
- Difference between **Owner**, **Contributor**, **Reader**, and custom roles
- Understanding **inherited vs direct** role assignments
- Principle of **least privilege** in practice

---

## Skills Demonstrated

- PowerShell scripting with the `Az` module
- Azure RBAC at subscription and resource group scope
- Custom role definition in JSON
- Access auditing and CSV reporting
- Offboarding automation

---

*Part of the az104-labs-portfolio — AZ-104 exam preparation projects.*

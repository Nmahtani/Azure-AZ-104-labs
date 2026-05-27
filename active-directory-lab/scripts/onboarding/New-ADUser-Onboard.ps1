<#
.SYNOPSIS
    Creates a new Active Directory user, assigns groups, and triggers Entra Connect sync.

.DESCRIPTION
    Full onboarding automation for a new employee:
    - Generates UPN and SamAccountName from first/last name
    - Creates user in the correct department OU
    - Sets all required AD attributes
    - Assigns base security groups and department-specific groups
    - Forces password change on first login
    - Triggers Entra Connect delta sync
    - Outputs a summary of the created account

.PARAMETER FirstName
    User's first name.

.PARAMETER LastName
    User's last name.

.PARAMETER Department
    Department name. Determines OU placement and group assignment.
    Accepted: IT, Finance, HR, Operations, Marketing, Sales

.PARAMETER JobTitle
    User's job title (stored in AD Title attribute).

.PARAMETER Manager
    SamAccountName of the user's manager.

.PARAMETER PhoneNumber
    Office phone number (optional).

.PARAMETER DomainDN
    Distinguished name of the domain root. Defaults to contoso.local.

.PARAMETER EntraConnectServer
    Hostname of the Entra Connect server. Defaults to ENTRACONNECT01.

.EXAMPLE
    .\New-ADUser-Onboard.ps1 -FirstName "John" -LastName "Doe" -Department "Finance" -JobTitle "Financial Analyst" -Manager "jane.smith"

.NOTES
    Requires: ActiveDirectory PowerShell module (RSAT)
    Author:   Nikhil Mahtani · IT Systems Administrator
    Project:  active-directory-lab
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]  [string]$FirstName,
    [Parameter(Mandatory = $true)]  [string]$LastName,
    [Parameter(Mandatory = $true)]
    [ValidateSet("IT", "Finance", "HR", "Operations", "Marketing", "Sales")]
    [string]$Department,
    [Parameter(Mandatory = $true)]  [string]$JobTitle,
    [Parameter(Mandatory = $true)]  [string]$Manager,
    [Parameter(Mandatory = $false)] [string]$PhoneNumber,
    [Parameter(Mandatory = $false)] [string]$DomainDN = "DC=contoso,DC=local",
    [Parameter(Mandatory = $false)] [string]$EntraConnectServer = "ENTRACONNECT01"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory

# ─────────────────────────────────────────────
# 1. BUILD USER ATTRIBUTES
# ─────────────────────────────────────────────

$firstName    = (Get-Culture).TextInfo.ToTitleCase($FirstName.ToLower())
$lastName     = (Get-Culture).TextInfo.ToTitleCase($LastName.ToLower())
$samAccount   = "$($firstName.ToLower()).$($lastName.ToLower())"
$upn          = "$samAccount@contoso.com"
$displayName  = "$firstName $lastName"

# Target OU based on department
$targetOU = "OU=$Department,OU=Employees,OU=Users,OU=Contoso,$DomainDN"

Write-Host "`n[INFO] Creating user account..." -ForegroundColor Cyan
Write-Host "  Display Name : $displayName"
Write-Host "  UPN          : $upn"
Write-Host "  SamAccount   : $samAccount"
Write-Host "  Department   : $Department"
Write-Host "  Target OU    : $targetOU"

# ─────────────────────────────────────────────
# 2. CHECK FOR DUPLICATE
# ─────────────────────────────────────────────

$existing = Get-ADUser -Filter { SamAccountName -eq $samAccount } -ErrorAction SilentlyContinue
if ($existing) {
    Write-Error "User '$samAccount' already exists in AD. Aborting."
    exit 1
}

# ─────────────────────────────────────────────
# 3. RESOLVE MANAGER
# ─────────────────────────────────────────────

$managerDN = $null
try {
    $managerObj = Get-ADUser -Identity $Manager -Properties DistinguishedName
    $managerDN  = $managerObj.DistinguishedName
    Write-Host "  Manager      : $($managerObj.Name) ($Manager)"
}
catch {
    Write-Warning "Manager '$Manager' not found in AD. Account will be created without manager attribute."
}

# ─────────────────────────────────────────────
# 4. GENERATE INITIAL PASSWORD
# ─────────────────────────────────────────────
# Temporary password: Welcome + current year + ! — user must change on first login.

$tempPassword = ConvertTo-SecureString "Welcome$(Get-Date -Format 'yyyy')!" -AsPlainText -Force

# ─────────────────────────────────────────────
# 5. CREATE USER
# ─────────────────────────────────────────────

$newUserParams = @{
    SamAccountName        = $samAccount
    UserPrincipalName     = $upn
    Name                  = $displayName
    GivenName             = $firstName
    Surname               = $lastName
    DisplayName           = $displayName
    Department            = $Department
    Title                 = $JobTitle
    AccountPassword       = $tempPassword
    Enabled               = $true
    ChangePasswordAtLogon = $true
    Path                  = $targetOU
    EmailAddress          = $upn
}

if ($managerDN)   { $newUserParams["Manager"]     = $managerDN }
if ($PhoneNumber) { $newUserParams["OfficePhone"]  = $PhoneNumber }

New-ADUser @newUserParams
Write-Host "`n[SUCCESS] AD user created: $samAccount" -ForegroundColor Green

# ─────────────────────────────────────────────
# 6. ASSIGN SECURITY GROUPS
# ─────────────────────────────────────────────

# Base groups applied to all employees
$baseGroups = @(
    "grp-all-employees",
    "grp-m365-licensed",
    "grp-vpn-users"
)

# Department-specific groups
$deptGroups = @{
    "IT"         = @("grp-it-staff", "grp-helpdesk", "grp-intune-admins")
    "Finance"    = @("grp-finance-users", "grp-sharepoint-finance")
    "HR"         = @("grp-hr-users", "grp-sharepoint-hr")
    "Operations" = @("grp-ops-users", "grp-sharepoint-ops")
    "Marketing"  = @("grp-marketing-users", "grp-sharepoint-marketing")
    "Sales"      = @("grp-sales-users", "grp-sharepoint-sales", "grp-crm-access")
}

$allGroups = $baseGroups + $deptGroups[$Department]

Write-Host "`n[INFO] Assigning groups..." -ForegroundColor Cyan
foreach ($group in $allGroups) {
    try {
        Add-ADGroupMember -Identity $group -Members $samAccount
        Write-Host "  + $group" -ForegroundColor Green
    }
    catch {
        Write-Warning "  Could not add to '$group': $_"
    }
}

# ─────────────────────────────────────────────
# 7. TRIGGER ENTRA CONNECT DELTA SYNC
# ─────────────────────────────────────────────

Write-Host "`n[INFO] Triggering Entra Connect delta sync on $EntraConnectServer..." -ForegroundColor Cyan

try {
    Invoke-Command -ComputerName $EntraConnectServer -ScriptBlock {
        Import-Module ADSync
        Start-ADSyncSyncCycle -PolicyType Delta
    }
    Write-Host "[INFO] Delta sync triggered. User will appear in Entra ID within ~2 minutes." -ForegroundColor Green
}
catch {
    Write-Warning "Could not trigger sync on $EntraConnectServer. Run manually: Start-ADSyncSyncCycle -PolicyType Delta"
}

# ─────────────────────────────────────────────
# 8. OUTPUT SUMMARY
# ─────────────────────────────────────────────

Write-Host "`n─── New User Summary ─────────────────────────────" -ForegroundColor Cyan
Write-Host "  Display Name   : $displayName"
Write-Host "  UPN            : $upn"
Write-Host "  SamAccountName : $samAccount"
Write-Host "  Department     : $Department"
Write-Host "  Job Title      : $JobTitle"
Write-Host "  Temp Password  : Welcome$(Get-Date -Format 'yyyy')!  (must change on first login)"
Write-Host "  Groups         : $($allGroups -join ', ')"
Write-Host "  Entra Sync     : Delta sync triggered"
Write-Host "──────────────────────────────────────────────────`n" -ForegroundColor Cyan

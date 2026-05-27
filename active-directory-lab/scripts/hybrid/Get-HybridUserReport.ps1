<#
.SYNOPSIS
    Compares user state between on-premises Active Directory and Entra ID.

.DESCRIPTION
    Queries both AD and Entra ID and produces a side-by-side comparison of each
    user's state. Identifies sync issues: users that exist on-prem but not in
    Entra ID, disabled on-prem but still active in the cloud, or attribute mismatches.

    Useful for monthly identity audits and troubleshooting sync problems.

.PARAMETER DomainDN
    Search base for on-prem AD users. Defaults to Employees OU.

.PARAMETER ExportCsv
    Exports results to ./reports/hybrid-user-report-<timestamp>.csv

.PARAMETER ShowMismatchOnly
    If specified, only shows users with sync issues or mismatches.

.EXAMPLE
    .\Get-HybridUserReport.ps1 -ExportCsv

.EXAMPLE
    .\Get-HybridUserReport.ps1 -ShowMismatchOnly

.NOTES
    Requires: ActiveDirectory module + Microsoft.Graph module
    Graph permission: User.Read.All (read-only)
    Author:   Nikhil Mahtani · IT Systems Administrator
    Project:  active-directory-lab
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$DomainDN = "DC=contoso,DC=local",

    [Parameter(Mandatory = $false)]
    [switch]$ExportCsv,

    [Parameter(Mandatory = $false)]
    [switch]$ShowMismatchOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory

# ─────────────────────────────────────────────
# 1. CONNECT TO MICROSOFT GRAPH
# ─────────────────────────────────────────────

Write-Host "`n[INFO] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.Read.All"
Write-Host "[INFO] Connected.`n" -ForegroundColor Green

# ─────────────────────────────────────────────
# 2. GET ON-PREM AD USERS (Employees OU only)
# ─────────────────────────────────────────────

$searchBase = "OU=Employees,OU=Users,OU=Contoso,$DomainDN"
Write-Host "[INFO] Querying AD users from: $searchBase" -ForegroundColor Cyan

$adUsers = Get-ADUser -Filter * -SearchBase $searchBase -Properties `
    "UserPrincipalName", "Enabled", "Department", "Title",
    "LastLogonDate", "PasswordLastSet", "DistinguishedName"

Write-Host "[INFO] Found $($adUsers.Count) AD users.`n" -ForegroundColor Cyan

# ─────────────────────────────────────────────
# 3. GET ENTRA ID USERS
# ─────────────────────────────────────────────

Write-Host "[INFO] Querying Entra ID users..." -ForegroundColor Cyan

$entraUsers = Get-MgUser -All -Property `
    "UserPrincipalName", "AccountEnabled", "OnPremisesSyncEnabled",
    "OnPremisesLastSyncDateTime", "DisplayName", "Department"

# Build a hashtable for fast lookup by UPN
$entraIndex = @{}
foreach ($u in $entraUsers) {
    $entraIndex[$u.UserPrincipalName.ToLower()] = $u
}

Write-Host "[INFO] Found $($entraUsers.Count) Entra ID users.`n" -ForegroundColor Cyan

# ─────────────────────────────────────────────
# 4. COMPARE AND BUILD REPORT
# ─────────────────────────────────────────────

$report = foreach ($adUser in $adUsers) {
    $upn         = $adUser.UserPrincipalName.ToLower()
    $entraUser   = $entraIndex[$upn]
    $entraExists = $null -ne $entraUser

    $syncStatus = if (-not $entraExists) {
        "NOT_IN_ENTRA"
    } elseif ($adUser.Enabled -and -not $entraUser.AccountEnabled) {
        "ENABLED_MISMATCH"
    } elseif (-not $adUser.Enabled -and $entraUser.AccountEnabled) {
        "DISABLED_ON_PREM_ACTIVE_CLOUD"
    } elseif ($entraUser.OnPremisesSyncEnabled -eq $false) {
        "CLOUD_ONLY_NO_SYNC"
    } else {
        "OK"
    }

    [PSCustomObject]@{
        SamAccountName      = $adUser.SamAccountName
        UPN                 = $adUser.UserPrincipalName
        ADEnabled           = $adUser.Enabled
        ADDepartment        = $adUser.Department
        ADLastLogon         = if ($adUser.LastLogonDate) { $adUser.LastLogonDate.ToString("yyyy-MM-dd") } else { "Never" }
        EntraIDExists       = $entraExists
        EntraIDEnabled      = if ($entraExists) { $entraUser.AccountEnabled } else { "N/A" }
        EntraOnPremSync     = if ($entraExists) { $entraUser.OnPremisesSyncEnabled } else { "N/A" }
        LastSyncDateTime    = if ($entraExists -and $entraUser.OnPremisesLastSyncDateTime) {
                                $entraUser.OnPremisesLastSyncDateTime.ToString("yyyy-MM-dd HH:mm")
                              } else { "N/A" }
        SyncStatus          = $syncStatus
    }
}

# ─────────────────────────────────────────────
# 5. DISPLAY RESULTS
# ─────────────────────────────────────────────

$displayReport = if ($ShowMismatchOnly) {
    $report | Where-Object { $_.SyncStatus -ne "OK" }
} else { $report }

$displayReport | Format-Table -AutoSize

$okCount       = ($report | Where-Object { $_.SyncStatus -eq "OK" }).Count
$issueCount    = ($report | Where-Object { $_.SyncStatus -ne "OK" }).Count

Write-Host "─── Hybrid Identity Summary ──────────────────────" -ForegroundColor Cyan
Write-Host "  Total AD users    : $($report.Count)"
Write-Host "  In sync (OK)      : $okCount"      -ForegroundColor Green
Write-Host "  Issues found      : $issueCount"   -ForegroundColor $(if ($issueCount -gt 0) { "Red" } else { "Green" })

$report | Where-Object { $_.SyncStatus -ne "OK" } | ForEach-Object {
    Write-Host "  [$($_.SyncStatus)] $($_.UPN)" -ForegroundColor Yellow
}
Write-Host "──────────────────────────────────────────────────`n" -ForegroundColor Cyan

# ─────────────────────────────────────────────
# 6. EXPORT
# ─────────────────────────────────────────────

if ($ExportCsv) {
    $reportsDir = Join-Path $PSScriptRoot "..\..\reports"
    if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
    $outputPath = Join-Path $reportsDir "hybrid-user-report-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
    $report | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
    Write-Host "[SUCCESS] Report exported to: $outputPath" -ForegroundColor Green
}

Disconnect-MgGraph | Out-Null

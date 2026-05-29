<#
.SYNOPSIS
    Exports a full Microsoft 365 license inventory and cost report.

.DESCRIPTION
    Connects to Microsoft Graph and produces three views:
    - Per-user license assignments
    - License pool summary (total, assigned, available)
    - Unlicensed users (have an account but no M365 license)

.PARAMETER ExportCsv
    Exports results to ./reports/license-report-<timestamp>.csv

.PARAMETER UnlicensedOnly
    Returns only users with no assigned license.

.PARAMETER PoolSummary
    Shows license pool summary only (SKUs, total seats, consumed, available).

.EXAMPLE
    .\Get-LicenseReport.ps1 -ExportCsv

.EXAMPLE
    .\Get-LicenseReport.ps1 -UnlicensedOnly

.EXAMPLE
    .\Get-LicenseReport.ps1 -PoolSummary

.NOTES
    Requires: Microsoft.Graph module
    Permission: Organization.Read.All, User.Read.All
    Author: Nikhil Mahtani · IT Systems Administrator
    Project: m365-admin-scripts
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)] [switch]$ExportCsv,
    [Parameter(Mandatory = $false)] [switch]$UnlicensedOnly,
    [Parameter(Mandatory = $false)] [switch]$PoolSummary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Connect-MgGraph -Scopes "User.Read.All", "Organization.Read.All"

# ─────────────────────────────────────────────
# POOL SUMMARY MODE
# ─────────────────────────────────────────────

if ($PoolSummary) {
    Write-Host "`n[INFO] Retrieving license pool summary..." -ForegroundColor Cyan

    $skus = Get-MgSubscribedSku

    $summary = foreach ($sku in $skus) {
        [PSCustomObject]@{
            SkuPartNumber = $sku.SkuPartNumber
            TotalSeats    = $sku.PrepaidUnits.Enabled
            Assigned      = $sku.ConsumedUnits
            Available     = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits
            Suspended     = $sku.PrepaidUnits.Suspended
        }
    }

    $summary | Sort-Object Available | Format-Table -AutoSize

    if ($ExportCsv) {
        $reportsDir = Join-Path $PSScriptRoot "..\..\reports"
        if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
        $outputPath = Join-Path $reportsDir "license-pool-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
        $summary | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "[SUCCESS] Pool summary exported to: $outputPath" -ForegroundColor Green
    }

    Disconnect-MgGraph | Out-Null
    return
}

# ─────────────────────────────────────────────
# PER-USER REPORT
# ─────────────────────────────────────────────

Write-Host "`n[INFO] Retrieving user license assignments..." -ForegroundColor Cyan

$allUsers = Get-MgUser -All -Property `
    "UserPrincipalName", "DisplayName", "AccountEnabled",
    "AssignedLicenses", "UsageLocation", "Department",
    "CreatedDateTime", "SignInActivity"

$allSkus = Get-MgSubscribedSku

# Build SKU ID → name lookup
$skuLookup = @{}
foreach ($sku in $allSkus) { $skuLookup[$sku.SkuId] = $sku.SkuPartNumber }

$report = foreach ($user in $allUsers) {
    $licenseNames = if ($user.AssignedLicenses.Count -gt 0) {
        ($user.AssignedLicenses | ForEach-Object {
            $skuLookup[$_.SkuId] ?? $_.SkuId
        }) -join "; "
    } else { "None" }

    $lastSignIn = $user.SignInActivity.LastSignInDateTime

    [PSCustomObject]@{
        DisplayName       = $user.DisplayName
        UserPrincipalName = $user.UserPrincipalName
        AccountEnabled    = $user.AccountEnabled
        Department        = $user.Department
        UsageLocation     = $user.UsageLocation
        LicenseCount      = $user.AssignedLicenses.Count
        Licenses          = $licenseNames
        LastSignIn        = if ($lastSignIn) { $lastSignIn.ToString("yyyy-MM-dd") } else { "Never" }
        CreatedDate       = if ($user.CreatedDateTime) { $user.CreatedDateTime.ToString("yyyy-MM-dd") } else { "N/A" }
    }
}

$filtered = if ($UnlicensedOnly) {
    $report | Where-Object { $_.LicenseCount -eq 0 -and $_.AccountEnabled }
} else { $report }

$filtered | Format-Table -AutoSize -Property DisplayName, UserPrincipalName, AccountEnabled, Department, LicenseCount, Licenses, LastSignIn

Write-Host "─── License Summary ──────────────────────────────" -ForegroundColor Cyan
Write-Host "  Total users       : $($report.Count)"
Write-Host "  Licensed          : $(($report | Where-Object { $_.LicenseCount -gt 0 }).Count)"     -ForegroundColor Green
Write-Host "  Unlicensed active : $(($report | Where-Object { $_.LicenseCount -eq 0 -and $_.AccountEnabled }).Count)" -ForegroundColor Yellow
Write-Host "  Disabled accounts : $(($report | Where-Object { -not $_.AccountEnabled }).Count)"
Write-Host "──────────────────────────────────────────────────`n" -ForegroundColor Cyan

if ($ExportCsv) {
    $reportsDir = Join-Path $PSScriptRoot "..\..\reports"
    if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
    $outputPath = Join-Path $reportsDir "license-report-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
    $filtered | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
    Write-Host "[SUCCESS] Report exported to: $outputPath" -ForegroundColor Green
}

Disconnect-MgGraph | Out-Null

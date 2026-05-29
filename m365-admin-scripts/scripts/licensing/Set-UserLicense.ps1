<#
.SYNOPSIS
    Assigns or removes Microsoft 365 licenses for one user or a bulk CSV list.

.DESCRIPTION
    Uses Microsoft Graph to assign or remove licenses by SKU name.
    Supports single user or bulk CSV mode.
    Common SKU aliases: SPB (Business Premium), SPE_E3 (E3), SPE_E5 (E5),
    EXCHANGESTANDARD (Exchange Online Plan 1), TEAMS_FREE (Teams Free)

.PARAMETER UserPrincipalName
    UPN of a single user. Use this OR -CsvPath.

.PARAMETER CsvPath
    Path to CSV with column: UserPrincipalName. Use this OR -UserPrincipalName.

.PARAMETER Action
    Action to perform: Assign | Remove

.PARAMETER LicenseSku
    License SKU part number (e.g. SPB, SPE_E3). Run Get-MgSubscribedSku to list available SKUs.

.PARAMETER UsageLocation
    Two-letter country code required for license assignment (e.g. ES, GB, US).
    Defaults to ES (Spain).

.EXAMPLE
    .\Set-UserLicense.ps1 -UserPrincipalName "john.doe@contoso.com" -Action Assign -LicenseSku "SPB"

.EXAMPLE
    .\Set-UserLicense.ps1 -UserPrincipalName "john.doe@contoso.com" -Action Remove -LicenseSku "SPB"

.EXAMPLE
    .\Set-UserLicense.ps1 -CsvPath ".\users.csv" -Action Assign -LicenseSku "SPB"

.NOTES
    Requires: Microsoft.Graph module
    Permission: Organization.Read.All, User.ReadWrite.All
    Author: Nikhil Mahtani · IT Systems Administrator
    Project: m365-admin-scripts
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)] [string]$UserPrincipalName,
    [Parameter(Mandatory = $false)] [string]$CsvPath,
    [Parameter(Mandatory = $true)]
    [ValidateSet("Assign", "Remove")]
    [string]$Action,
    [Parameter(Mandatory = $true)]  [string]$LicenseSku,
    [Parameter(Mandatory = $false)] [string]$UsageLocation = "ES"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $UserPrincipalName -and -not $CsvPath) {
    Write-Error "Provide either -UserPrincipalName or -CsvPath."
    exit 1
}

# ─────────────────────────────────────────────
# 1. CONNECT AND RESOLVE SKU
# ─────────────────────────────────────────────

Connect-MgGraph -Scopes "User.ReadWrite.All", "Organization.Read.All"

$allSkus = Get-MgSubscribedSku
$targetSku = $allSkus | Where-Object { $_.SkuPartNumber -eq $LicenseSku }

if (-not $targetSku) {
    Write-Error "SKU '$LicenseSku' not found in tenant. Available SKUs:"
    $allSkus | Select-Object SkuPartNumber, SkuId, ConsumedUnits | Format-Table
    exit 1
}

Write-Host "`n[INFO] SKU: $($targetSku.SkuPartNumber) | Available: $($targetSku.PrepaidUnits.Enabled - $targetSku.ConsumedUnits)" -ForegroundColor Cyan

# ─────────────────────────────────────────────
# 2. BUILD USER LIST
# ─────────────────────────────────────────────

$upnList = if ($UserPrincipalName) {
    @($UserPrincipalName)
} else {
    (Import-Csv $CsvPath).UserPrincipalName
}

$results = @()

foreach ($upn in $upnList) {
    try {
        $user = Get-MgUser -UserId $upn -Property Id, UserPrincipalName, AssignedLicenses, UsageLocation

        if ($Action -eq "Assign") {
            # Set usage location if not already set
            if (-not $user.UsageLocation) {
                Update-MgUser -UserId $user.Id -UsageLocation $UsageLocation
                Write-Host "  [INFO] Set UsageLocation = $UsageLocation for $upn"
            }

            # Check if already licensed
            $alreadyLicensed = $user.AssignedLicenses | Where-Object { $_.SkuId -eq $targetSku.SkuId }
            if ($alreadyLicensed) {
                Write-Host "  [SKIP] $upn already has $LicenseSku" -ForegroundColor Yellow
                $results += [PSCustomObject]@{ UPN = $upn; Action = "Skipped"; Reason = "Already licensed" }
                continue
            }

            Set-MgUserLicense -UserId $user.Id `
                -AddLicenses @{ SkuId = $targetSku.SkuId } `
                -RemoveLicenses @()

            Write-Host "  [+] Assigned $LicenseSku to $upn" -ForegroundColor Green
            $results += [PSCustomObject]@{ UPN = $upn; Action = "Assigned"; Reason = "" }
        }
        elseif ($Action -eq "Remove") {
            Set-MgUserLicense -UserId $user.Id `
                -AddLicenses @() `
                -RemoveLicenses @($targetSku.SkuId)

            Write-Host "  [-] Removed $LicenseSku from $upn" -ForegroundColor Yellow
            $results += [PSCustomObject]@{ UPN = $upn; Action = "Removed"; Reason = "" }
        }
    }
    catch {
        Write-Warning "  [FAIL] $upn : $_"
        $results += [PSCustomObject]@{ UPN = $upn; Action = "Failed"; Reason = $_.ToString() }
    }
}

Write-Host "`n─── License Operation Summary ────────────────────" -ForegroundColor Cyan
Write-Host "  Action    : $Action $LicenseSku"
Write-Host "  Processed : $($results.Count)"
Write-Host "  Success   : $(($results | Where-Object { $_.Action -in @('Assigned','Removed') }).Count)" -ForegroundColor Green
Write-Host "  Skipped   : $(($results | Where-Object { $_.Action -eq 'Skipped' }).Count)"              -ForegroundColor Yellow
Write-Host "  Failed    : $(($results | Where-Object { $_.Action -eq 'Failed' }).Count)"               -ForegroundColor Red
Write-Host "──────────────────────────────────────────────────`n" -ForegroundColor Cyan

Disconnect-MgGraph | Out-Null

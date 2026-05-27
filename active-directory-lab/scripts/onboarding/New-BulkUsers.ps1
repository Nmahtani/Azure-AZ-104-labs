<#
.SYNOPSIS
    Creates multiple Active Directory users from a CSV file.

.DESCRIPTION
    Reads a CSV of new employees and creates each user in AD with correct
    OU placement, group assignments, and Entra Connect sync trigger.
    Designed for large onboarding batches or domain migrations.

    CSV required columns: FirstName, LastName, Department, JobTitle, Manager
    CSV optional columns: PhoneNumber

.PARAMETER CsvPath
    Path to the CSV file containing new user data.

.PARAMETER DomainDN
    Distinguished name of the domain root. Defaults to contoso.local.

.PARAMETER EntraConnectServer
    Hostname of the Entra Connect server. Defaults to ENTRACONNECT01.

.PARAMETER ExportReport
    If specified, exports a creation report to ./reports/bulk-onboard-<timestamp>.csv

.EXAMPLE
    .\New-BulkUsers.ps1 -CsvPath ".\users.csv"

.EXAMPLE
    .\New-BulkUsers.ps1 -CsvPath ".\users.csv" -ExportReport

.NOTES
    Requires: ActiveDirectory PowerShell module (RSAT)
    Author:   Nikhil Mahtani · IT Systems Administrator
    Project:  active-directory-lab
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)] [string]$DomainDN = "DC=contoso,DC=local",
    [Parameter(Mandatory = $false)] [string]$EntraConnectServer = "ENTRACONNECT01",
    [Parameter(Mandatory = $false)] [switch]$ExportReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory

$users    = Import-Csv -Path $CsvPath
$results  = @()
$created  = 0
$skipped  = 0
$failed   = 0

Write-Host "`n[INFO] Loaded $($users.Count) users from CSV: $CsvPath" -ForegroundColor Cyan

$deptGroups = @{
    "IT"         = @("grp-all-employees", "grp-m365-licensed", "grp-it-staff", "grp-helpdesk")
    "Finance"    = @("grp-all-employees", "grp-m365-licensed", "grp-finance-users")
    "HR"         = @("grp-all-employees", "grp-m365-licensed", "grp-hr-users")
    "Operations" = @("grp-all-employees", "grp-m365-licensed", "grp-ops-users")
    "Marketing"  = @("grp-all-employees", "grp-m365-licensed", "grp-marketing-users")
    "Sales"      = @("grp-all-employees", "grp-m365-licensed", "grp-sales-users", "grp-crm-access")
}

foreach ($user in $users) {
    $firstName  = (Get-Culture).TextInfo.ToTitleCase($user.FirstName.ToLower())
    $lastName   = (Get-Culture).TextInfo.ToTitleCase($user.LastName.ToLower())
    $samAccount = "$($firstName.ToLower()).$($lastName.ToLower())"
    $upn        = "$samAccount@contoso.com"
    $targetOU   = "OU=$($user.Department),OU=Employees,OU=Users,OU=Contoso,$DomainDN"
    $status     = ""

    # Skip if already exists
    $existing = Get-ADUser -Filter { SamAccountName -eq $samAccount } -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warning "  [SKIP] $samAccount already exists."
        $status = "Skipped - already exists"
        $skipped++
    }
    else {
        try {
            $tempPassword = ConvertTo-SecureString "Welcome$(Get-Date -Format 'yyyy')!" -AsPlainText -Force

            $newUserParams = @{
                SamAccountName        = $samAccount
                UserPrincipalName     = $upn
                Name                  = "$firstName $lastName"
                GivenName             = $firstName
                Surname               = $lastName
                DisplayName           = "$firstName $lastName"
                Department            = $user.Department
                Title                 = $user.JobTitle
                AccountPassword       = $tempPassword
                Enabled               = $true
                ChangePasswordAtLogon = $true
                Path                  = $targetOU
                EmailAddress          = $upn
            }

            if ($user.PhoneNumber) { $newUserParams["OfficePhone"] = $user.PhoneNumber }

            try {
                $mgr = Get-ADUser -Identity $user.Manager -ErrorAction SilentlyContinue
                if ($mgr) { $newUserParams["Manager"] = $mgr.DistinguishedName }
            } catch {}

            New-ADUser @newUserParams

            # Assign groups
            $groups = $deptGroups[$user.Department]
            foreach ($group in $groups) {
                try { Add-ADGroupMember -Identity $group -Members $samAccount } catch {}
            }

            Write-Host "  [OK] Created: $samAccount ($($user.Department))" -ForegroundColor Green
            $status = "Created"
            $created++
        }
        catch {
            Write-Warning "  [FAIL] $samAccount : $_"
            $status = "Failed: $_"
            $failed++
        }
    }

    $results += [PSCustomObject]@{
        SamAccountName = $samAccount
        UPN            = $upn
        Department     = $user.Department
        JobTitle       = $user.JobTitle
        Status         = $status
    }
}

# Trigger single sync after all users are created
Write-Host "`n[INFO] Triggering Entra Connect delta sync..." -ForegroundColor Cyan
try {
    Invoke-Command -ComputerName $EntraConnectServer -ScriptBlock {
        Import-Module ADSync
        Start-ADSyncSyncCycle -PolicyType Delta
    }
    Write-Host "[INFO] Delta sync triggered." -ForegroundColor Green
}
catch {
    Write-Warning "Could not trigger sync. Run manually: Start-ADSyncSyncCycle -PolicyType Delta"
}

Write-Host "`n─── Bulk Onboarding Summary ──────────────────────" -ForegroundColor Cyan
Write-Host "  Total in CSV : $($users.Count)"
Write-Host "  Created      : $created" -ForegroundColor Green
Write-Host "  Skipped      : $skipped" -ForegroundColor Yellow
Write-Host "  Failed       : $failed"  -ForegroundColor Red
Write-Host "──────────────────────────────────────────────────`n" -ForegroundColor Cyan

if ($ExportReport) {
    $reportsDir = Join-Path $PSScriptRoot "..\..\reports"
    if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
    $outputPath = Join-Path $reportsDir "bulk-onboard-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
    $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
    Write-Host "[SUCCESS] Report exported to: $outputPath" -ForegroundColor Green
}

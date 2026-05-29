<#
.SYNOPSIS
    Creates and manages Exchange Online distribution lists and Microsoft 365 groups.

.DESCRIPTION
    Covers four actions:
    - Create: creates a distribution list or M365 group
    - AddMember / RemoveMember: manages group membership
    - Audit: exports all groups with member counts and settings

.PARAMETER Action
    Action to perform: Create | AddMember | RemoveMember | Audit

.PARAMETER Name
    Display name of the group (for Create).

.PARAMETER Alias
    Email alias (for Create). Full address: alias@contoso.com.

.PARAMETER Type
    Group type: Distribution | M365Group. Defaults to Distribution.

.PARAMETER GroupAlias
    Alias of the target group for membership actions.

.PARAMETER Members
    Array of UPNs to add or remove.

.PARAMETER ExportCsv
    Exports audit to ./reports/groups-audit-<timestamp>.csv

.EXAMPLE
    .\Manage-DistributionGroups.ps1 -Action Create -Name "Finance DL" -Alias "finance-dl"

.EXAMPLE
    .\Manage-DistributionGroups.ps1 -Action AddMember -GroupAlias "finance-dl" -Members "john.doe@contoso.com"

.EXAMPLE
    .\Manage-DistributionGroups.ps1 -Action Audit -ExportCsv

.NOTES
    Requires: ExchangeOnlineManagement module
    Author: Nikhil Mahtani · IT Systems Administrator
    Project: m365-admin-scripts
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Create", "AddMember", "RemoveMember", "Audit")]
    [string]$Action,

    [Parameter(Mandatory = $false)] [string]$Name,
    [Parameter(Mandatory = $false)] [string]$Alias,
    [Parameter(Mandatory = $false)]
    [ValidateSet("Distribution", "M365Group")]
    [string]$Type = "Distribution",
    [Parameter(Mandatory = $false)] [string]$GroupAlias,
    [Parameter(Mandatory = $false)] [string[]]$Members,
    [Parameter(Mandatory = $false)] [switch]$ExportCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

switch ($Action) {

    "Create" {
        if (-not $Name -or -not $Alias) {
            Write-Error "-Name and -Alias are required for Create."
            exit 1
        }

        $primarySmtp = "$Alias@contoso.com"
        Write-Host "`n[INFO] Creating $Type group: $primarySmtp" -ForegroundColor Cyan

        if ($Type -eq "Distribution") {
            New-DistributionGroup `
                -Name $Name `
                -DisplayName $Name `
                -Alias $Alias `
                -PrimarySmtpAddress $primarySmtp `
                -MemberJoinRestriction Closed `
                -MemberDepartRestriction Closed
        }
        elseif ($Type -eq "M365Group") {
            New-UnifiedGroup `
                -DisplayName $Name `
                -Alias $Alias `
                -PrimarySmtpAddress $primarySmtp `
                -AccessType Private
        }

        Write-Host "[SUCCESS] Group created: $primarySmtp" -ForegroundColor Green
    }

    "AddMember" {
        if (-not $GroupAlias -or -not $Members) {
            Write-Error "-GroupAlias and -Members are required for AddMember."
            exit 1
        }

        Write-Host "`n[INFO] Adding members to '$GroupAlias'..." -ForegroundColor Cyan
        foreach ($member in $Members) {
            try {
                Add-DistributionGroupMember -Identity $GroupAlias -Member $member -ErrorAction Stop
                Write-Host "  [+] Added: $member" -ForegroundColor Green
            }
            catch {
                # Try as M365 group if DL fails
                try {
                    Add-UnifiedGroupLinks -Identity $GroupAlias -LinkType Members -Links $member
                    Write-Host "  [+] Added to M365 Group: $member" -ForegroundColor Green
                }
                catch {
                    Write-Warning "  Could not add '$member': $_"
                }
            }
        }
    }

    "RemoveMember" {
        if (-not $GroupAlias -or -not $Members) {
            Write-Error "-GroupAlias and -Members are required for RemoveMember."
            exit 1
        }

        Write-Host "`n[INFO] Removing members from '$GroupAlias'..." -ForegroundColor Cyan
        foreach ($member in $Members) {
            try {
                Remove-DistributionGroupMember -Identity $GroupAlias -Member $member -Confirm:$false
                Write-Host "  [-] Removed: $member" -ForegroundColor Yellow
            }
            catch {
                try {
                    Remove-UnifiedGroupLinks -Identity $GroupAlias -LinkType Members -Links $member -Confirm:$false
                    Write-Host "  [-] Removed from M365 Group: $member" -ForegroundColor Yellow
                }
                catch {
                    Write-Warning "  Could not remove '$member': $_"
                }
            }
        }
    }

    "Audit" {
        Write-Host "`n[INFO] Auditing all distribution groups and M365 groups..." -ForegroundColor Cyan

        $dlGroups = Get-DistributionGroup -ResultSize Unlimited
        $m365Groups = Get-UnifiedGroup -ResultSize Unlimited

        $report = @()

        foreach ($group in $dlGroups) {
            $members = Get-DistributionGroupMember -Identity $group.Alias -ResultSize Unlimited
            $report += [PSCustomObject]@{
                DisplayName     = $group.DisplayName
                PrimarySmtp     = $group.PrimarySmtpAddress
                GroupType       = "DistributionList"
                MemberCount     = $members.Count
                HiddenFromGAL   = $group.HiddenFromAddressListsEnabled
                ManagedBy       = ($group.ManagedBy -join "; ")
            }
        }

        foreach ($group in $m365Groups) {
            $members = Get-UnifiedGroupLinks -Identity $group.Alias -LinkType Members -ResultSize Unlimited
            $report += [PSCustomObject]@{
                DisplayName     = $group.DisplayName
                PrimarySmtp     = $group.PrimarySmtpAddress
                GroupType       = "M365Group"
                MemberCount     = $members.Count
                HiddenFromGAL   = $group.HiddenFromAddressListsEnabled
                ManagedBy       = ($group.ManagedBy -join "; ")
            }
        }

        $report | Format-Table -AutoSize

        Write-Host "─── Group Summary ────────────────────────────────" -ForegroundColor Cyan
        Write-Host "  Distribution Lists : $(($report | Where-Object { $_.GroupType -eq 'DistributionList' }).Count)"
        Write-Host "  M365 Groups        : $(($report | Where-Object { $_.GroupType -eq 'M365Group' }).Count)"
        Write-Host "  Total              : $($report.Count)"
        Write-Host "──────────────────────────────────────────────────`n" -ForegroundColor Cyan

        if ($ExportCsv) {
            $reportsDir = Join-Path $PSScriptRoot "..\..\reports"
            if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
            $outputPath = Join-Path $reportsDir "groups-audit-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
            $report | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
            Write-Host "[SUCCESS] Report exported to: $outputPath" -ForegroundColor Green
        }
    }
}

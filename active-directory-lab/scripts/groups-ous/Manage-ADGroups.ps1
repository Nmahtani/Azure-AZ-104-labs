<#
.SYNOPSIS
    Creates AD security groups, manages membership, and exports audit reports.

.DESCRIPTION
    Covers three actions:
    - Create: creates a new security group in the specified OU
    - AddMember / RemoveMember: adds or removes users from a group
    - Audit: exports all group memberships to a CSV for access reviews

.PARAMETER Action
    Action to perform: Create | AddMember | RemoveMember | Audit

.PARAMETER GroupName
    Name of the target group.

.PARAMETER OU
    Relative OU path for group creation (e.g. "Groups\Security").

.PARAMETER Members
    Array of SamAccountNames to add or remove.

.PARAMETER DomainDN
    Domain root DN. Defaults to DC=contoso,DC=local.

.PARAMETER ExportCsv
    Exports audit report to ./reports/group-audit-<timestamp>.csv

.EXAMPLE
    .\Manage-ADGroups.ps1 -Action Create -GroupName "grp-finance-users" -OU "Groups\Security"

.EXAMPLE
    .\Manage-ADGroups.ps1 -Action AddMember -GroupName "grp-finance-users" -Members "john.doe","jane.smith"

.EXAMPLE
    .\Manage-ADGroups.ps1 -Action Audit -ExportCsv

.NOTES
    Requires: ActiveDirectory PowerShell module (RSAT)
    Author:   Nikhil Mahtani · IT Systems Administrator
    Project:  active-directory-lab
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Create", "AddMember", "RemoveMember", "Audit")]
    [string]$Action,

    [Parameter(Mandatory = $false)] [string]$GroupName,
    [Parameter(Mandatory = $false)] [string]$OU,
    [Parameter(Mandatory = $false)] [string[]]$Members,
    [Parameter(Mandatory = $false)] [string]$DomainDN = "DC=contoso,DC=local",
    [Parameter(Mandatory = $false)] [switch]$ExportCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory

switch ($Action) {

    "Create" {
        if (-not $GroupName -or -not $OU) {
            Write-Error "-GroupName and -OU are required for Create action."
            exit 1
        }

        # Convert OU path to DN (e.g. "Groups\Security" → "OU=Security,OU=Groups,OU=Contoso,DC=...")
        $ouParts  = $OU -split "\\" | ForEach-Object { "OU=$_" }
        [array]::Reverse($ouParts)
        $ouDN     = ($ouParts -join ",") + ",OU=Contoso,$DomainDN"

        $existing = Get-ADGroup -Filter { Name -eq $GroupName } -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Warning "Group '$GroupName' already exists. No changes made."
            exit 0
        }

        New-ADGroup `
            -Name            $GroupName `
            -SamAccountName  $GroupName `
            -GroupCategory   Security `
            -GroupScope      Global `
            -Path            $ouDN `
            -Description     "Security group managed by active-directory-lab"

        Write-Host "[SUCCESS] Group '$GroupName' created in $ouDN" -ForegroundColor Green
    }

    "AddMember" {
        if (-not $GroupName -or -not $Members) {
            Write-Error "-GroupName and -Members are required for AddMember action."
            exit 1
        }

        Write-Host "`n[INFO] Adding members to '$GroupName'..." -ForegroundColor Cyan
        foreach ($member in $Members) {
            try {
                Add-ADGroupMember -Identity $GroupName -Members $member
                Write-Host "  [+] Added: $member" -ForegroundColor Green
            }
            catch {
                Write-Warning "  Could not add '$member': $_"
            }
        }
    }

    "RemoveMember" {
        if (-not $GroupName -or -not $Members) {
            Write-Error "-GroupName and -Members are required for RemoveMember action."
            exit 1
        }

        Write-Host "`n[INFO] Removing members from '$GroupName'..." -ForegroundColor Cyan
        foreach ($member in $Members) {
            try {
                Remove-ADGroupMember -Identity $GroupName -Members $member -Confirm:$false
                Write-Host "  [-] Removed: $member" -ForegroundColor Yellow
            }
            catch {
                Write-Warning "  Could not remove '$member': $_"
            }
        }
    }

    "Audit" {
        Write-Host "`n[INFO] Generating group membership audit..." -ForegroundColor Cyan

        $allGroups = Get-ADGroup -Filter * -SearchBase "OU=Groups,OU=Contoso,$DomainDN" -Properties Members

        $report = foreach ($group in $allGroups) {
            $members = Get-ADGroupMember -Identity $group -Recursive -ErrorAction SilentlyContinue
            if ($members) {
                foreach ($member in $members) {
                    [PSCustomObject]@{
                        GroupName      = $group.Name
                        GroupScope     = $group.GroupScope
                        MemberName     = $member.Name
                        MemberSAM      = $member.SamAccountName
                        MemberType     = $member.objectClass
                    }
                }
            } else {
                [PSCustomObject]@{
                    GroupName  = $group.Name
                    GroupScope = $group.GroupScope
                    MemberName = "(empty)"
                    MemberSAM  = ""
                    MemberType = ""
                }
            }
        }

        $report | Format-Table -AutoSize
        Write-Host "[INFO] Total groups audited: $($allGroups.Count)" -ForegroundColor Cyan

        if ($ExportCsv) {
            $reportsDir = Join-Path $PSScriptRoot "..\..\reports"
            if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
            $outputPath = Join-Path $reportsDir "group-audit-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
            $report | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
            Write-Host "[SUCCESS] Audit exported to: $outputPath" -ForegroundColor Green
        }
    }
}

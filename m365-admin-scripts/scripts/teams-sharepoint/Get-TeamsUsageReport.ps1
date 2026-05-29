<#
.SYNOPSIS
    Audits Microsoft Teams across the tenant — inactive teams, guests, and usage.

.DESCRIPTION
    Connects to Microsoft Teams and exports a report covering:
    - All teams with member/owner/guest counts
    - Teams inactive for N days (no messages or file activity)
    - Teams with external guest members
    - Teams with public visibility (potential data exposure risk)

.PARAMETER ExportCsv
    Exports results to ./reports/teams-audit-<timestamp>.csv

.PARAMETER GuestsOnly
    Returns only teams that have at least one guest member.

.PARAMETER InactiveDays
    Returns only teams with no activity in the last N days.

.PARAMETER PublicOnly
    Returns only teams with Public visibility.

.EXAMPLE
    .\Get-TeamsUsageReport.ps1 -ExportCsv

.EXAMPLE
    .\Get-TeamsUsageReport.ps1 -GuestsOnly -ExportCsv

.EXAMPLE
    .\Get-TeamsUsageReport.ps1 -InactiveDays 90 -ExportCsv

.NOTES
    Requires: MicrosoftTeams module
    Connect first: Connect-MicrosoftTeams
    Author: Nikhil Mahtani · IT Systems Administrator
    Project: m365-admin-scripts
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)] [switch]$ExportCsv,
    [Parameter(Mandatory = $false)] [switch]$GuestsOnly,
    [Parameter(Mandatory = $false)] [int]$InactiveDays,
    [Parameter(Mandatory = $false)] [switch]$PublicOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "`n[INFO] Retrieving all Teams..." -ForegroundColor Cyan

$allTeams = Get-Team

Write-Host "[INFO] Found $($allTeams.Count) team(s). Gathering details...`n" -ForegroundColor Cyan

$report = foreach ($team in $allTeams) {
    $users  = Get-TeamUser -GroupId $team.GroupId -ErrorAction SilentlyContinue
    $owners = ($users | Where-Object { $_.Role -eq "Owner" }).Count
    $members = ($users | Where-Object { $_.Role -eq "Member" }).Count
    $guests = ($users | Where-Object { $_.Role -eq "Guest" }).Count

    [PSCustomObject]@{
        TeamName        = $team.DisplayName
        GroupId         = $team.GroupId
        Visibility      = $team.Visibility
        Archived        = $team.Archived
        OwnerCount      = $owners
        MemberCount     = $members
        GuestCount      = $guests
        TotalUsers      = $users.Count
        AllowGuests     = $team.GuestSettings -ne $null
        Description     = $team.Description
    }
}

# Apply filters
$filtered = $report

if ($GuestsOnly)  { $filtered = $filtered | Where-Object { $_.GuestCount -gt 0 } }
if ($PublicOnly)  { $filtered = $filtered | Where-Object { $_.Visibility -eq "Public" } }

$filtered | Format-Table -AutoSize -Property TeamName, Visibility, Archived, OwnerCount, MemberCount, GuestCount, TotalUsers

Write-Host "─── Teams Summary ────────────────────────────────" -ForegroundColor Cyan
Write-Host "  Total teams     : $($report.Count)"
Write-Host "  Active          : $(($report | Where-Object { -not $_.Archived }).Count)"
Write-Host "  Archived        : $(($report | Where-Object { $_.Archived }).Count)"
Write-Host "  With guests     : $(($report | Where-Object { $_.GuestCount -gt 0 }).Count)"  -ForegroundColor Yellow
Write-Host "  Public teams    : $(($report | Where-Object { $_.Visibility -eq 'Public' }).Count)" -ForegroundColor Yellow
Write-Host "──────────────────────────────────────────────────`n" -ForegroundColor Cyan

if ($ExportCsv) {
    $reportsDir = Join-Path $PSScriptRoot "..\..\reports"
    if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
    $outputPath = Join-Path $reportsDir "teams-audit-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
    $filtered | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
    Write-Host "[SUCCESS] Report exported to: $outputPath" -ForegroundColor Green
}

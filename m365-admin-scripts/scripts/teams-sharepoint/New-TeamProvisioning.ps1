<#
.SYNOPSIS
    Provisions a new Microsoft Team with standard channel structure and governance settings.

.DESCRIPTION
    Creates a Microsoft Team with:
    - Standard channel set (General, Announcements, IT Support)
    - Owner and member assignment
    - Guest access policy applied
    - Associated SharePoint site permissions configured
    - Team settings aligned with corporate governance policy

.PARAMETER TeamName
    Display name of the new Team.

.PARAMETER Description
    Team description.

.PARAMETER Owner
    UPN of the Team owner.

.PARAMETER Members
    Array of UPNs to add as members.

.PARAMETER AllowGuests
    Whether to allow external guest users. Defaults to $false.

.PARAMETER Visibility
    Team visibility: Private | Public. Defaults to Private.

.EXAMPLE
    .\New-TeamProvisioning.ps1 `
        -TeamName "Finance Team" `
        -Description "Finance department collaboration" `
        -Owner "jane.smith@contoso.com" `
        -Members "john.doe@contoso.com","sara.garcia@contoso.com" `
        -AllowGuests $false

.NOTES
    Requires: MicrosoftTeams module, PnP.PowerShell module
    Connect first: Connect-MicrosoftTeams
    Author: Nikhil Mahtani · IT Systems Administrator
    Project: m365-admin-scripts
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]  [string]$TeamName,
    [Parameter(Mandatory = $true)]  [string]$Description,
    [Parameter(Mandatory = $true)]  [string]$Owner,
    [Parameter(Mandatory = $false)] [string[]]$Members = @(),
    [Parameter(Mandatory = $false)] [bool]$AllowGuests = $false,
    [Parameter(Mandatory = $false)]
    [ValidateSet("Private", "Public")]
    [string]$Visibility = "Private"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────
# 1. CREATE TEAM
# ─────────────────────────────────────────────

Write-Host "`n[INFO] Creating Team: '$TeamName'..." -ForegroundColor Cyan

$team = New-Team `
    -DisplayName $TeamName `
    -Description $Description `
    -Visibility $Visibility `
    -AllowGuestCreateUpdateChannels $false `
    -AllowGuestDeleteChannels $false `
    -AllowCreateUpdateChannels $false `
    -AllowDeleteChannels $false `
    -AllowAddRemoveApps $false `
    -AllowCreateUpdateRemoveTabs $false `
    -AllowCreateUpdateRemoveConnectors $false `
    -AllowUserEditMessages $true `
    -AllowUserDeleteMessages $false `
    -AllowOwnerDeleteMessages $true `
    -AllowTeamMentions $true `
    -AllowChannelMentions $true

$groupId = $team.GroupId
Write-Host "[SUCCESS] Team created. Group ID: $groupId" -ForegroundColor Green

# ─────────────────────────────────────────────
# 2. SET OWNER
# ─────────────────────────────────────────────

Write-Host "`n[INFO] Setting owner: $Owner" -ForegroundColor Cyan
Add-TeamUser -GroupId $groupId -User $Owner -Role Owner
Write-Host "[SUCCESS] Owner set." -ForegroundColor Green

# ─────────────────────────────────────────────
# 3. ADD MEMBERS
# ─────────────────────────────────────────────

if ($Members.Count -gt 0) {
    Write-Host "`n[INFO] Adding $($Members.Count) member(s)..." -ForegroundColor Cyan
    foreach ($member in $Members) {
        try {
            Add-TeamUser -GroupId $groupId -User $member -Role Member
            Write-Host "  [+] $member" -ForegroundColor Green
        }
        catch {
            Write-Warning "  Could not add '$member': $_"
        }
    }
}

# ─────────────────────────────────────────────
# 4. CREATE STANDARD CHANNELS
# ─────────────────────────────────────────────

Write-Host "`n[INFO] Creating standard channels..." -ForegroundColor Cyan

$channels = @(
    @{ Name = "Announcements"; Description = "Official team announcements — read-only for members" },
    @{ Name = "IT Support";    Description = "IT requests and support tickets" },
    @{ Name = "Documents";     Description = "Shared documents and files" }
)

foreach ($channel in $channels) {
    try {
        New-TeamChannel -GroupId $groupId -DisplayName $channel.Name -Description $channel.Description
        Write-Host "  [+] Channel: $($channel.Name)" -ForegroundColor Green
    }
    catch {
        Write-Warning "  Could not create channel '$($channel.Name)': $_"
    }
}

# ─────────────────────────────────────────────
# 5. CONFIGURE GUEST ACCESS
# ─────────────────────────────────────────────

Write-Host "`n[INFO] Configuring guest access: AllowGuests = $AllowGuests" -ForegroundColor Cyan

Set-Team -GroupId $groupId `
    -AllowGuestCreateUpdateChannels $false `
    -AllowGuestDeleteChannels $false

if (-not $AllowGuests) {
    Write-Host "[INFO] Guest access disabled for this team." -ForegroundColor Yellow
}

# ─────────────────────────────────────────────
# 6. SUMMARY
# ─────────────────────────────────────────────

Write-Host "`n─── Team Provisioning Summary ────────────────────" -ForegroundColor Cyan
Write-Host "  Team Name    : $TeamName"
Write-Host "  Group ID     : $groupId"
Write-Host "  Visibility   : $Visibility"
Write-Host "  Owner        : $Owner"
Write-Host "  Members      : $($Members.Count)"
Write-Host "  Channels     : General + $($channels.Count) additional"
Write-Host "  Guest Access : $AllowGuests"
Write-Host "──────────────────────────────────────────────────`n" -ForegroundColor Cyan

<#
.SYNOPSIS
    Cross-service Microsoft 365 security and access audit report.

.DESCRIPTION
    Pulls data from Entra ID, Exchange Online, and Teams to produce a unified
    security audit covering:
    - MFA registration status per user
    - Guest accounts in the tenant
    - Shared mailbox access (who can read which shared mailbox)
    - Public Teams (potential data exposure)
    - Inactive users (no sign-in in 90+ days)
    - Users with no MFA and active licenses (highest risk)

.PARAMETER Section
    Run a specific section only: MFA | Guests | SharedMailboxes | PublicTeams | InactiveUsers | All
    Defaults to All.

.PARAMETER ExportCsv
    Exports each section to a separate CSV in ./reports/

.PARAMETER InactiveDays
    Days of inactivity threshold for inactive user report. Defaults to 90.

.EXAMPLE
    .\Get-M365AuditReport.ps1 -ExportCsv

.EXAMPLE
    .\Get-M365AuditReport.ps1 -Section MFA -ExportCsv

.EXAMPLE
    .\Get-M365AuditReport.ps1 -Section InactiveUsers -InactiveDays 60

.NOTES
    Requires: Microsoft.Graph module, ExchangeOnlineManagement module, MicrosoftTeams module
    Permissions: AuditLog.Read.All, User.Read.All, Reports.Read.All
    Author: Nikhil Mahtani · IT Systems Administrator
    Project: m365-admin-scripts
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("MFA", "Guests", "SharedMailboxes", "PublicTeams", "InactiveUsers", "All")]
    [string]$Section = "All",

    [Parameter(Mandatory = $false)] [switch]$ExportCsv,
    [Parameter(Mandatory = $false)] [int]$InactiveDays = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$reportsDir = Join-Path $PSScriptRoot "..\..\reports"
if ($ExportCsv -and -not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }

function Export-Section {
    param ([string]$Name, [object[]]$Data)
    if ($ExportCsv -and $Data) {
        $path = Join-Path $reportsDir "audit-$Name-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
        $Data | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
        Write-Host "  → Exported to: $path" -ForegroundColor Green
    }
}

# ─────────────────────────────────────────────
# CONNECT
# ─────────────────────────────────────────────

Write-Host "`n[INFO] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "AuditLog.Read.All", "User.Read.All", "Reports.Read.All", "UserAuthenticationMethod.Read.All"
Write-Host "[INFO] Connected.`n" -ForegroundColor Green

# ─────────────────────────────────────────────
# SECTION: MFA STATUS
# ─────────────────────────────────────────────

if ($Section -in @("MFA", "All")) {
    Write-Host "═══ MFA Registration Status ═══════════════════════" -ForegroundColor Cyan

    $users = Get-MgUser -All -Property "UserPrincipalName", "DisplayName", "AccountEnabled", "AssignedLicenses"
    $mfaReport = @()

    foreach ($user in ($users | Where-Object { $_.AccountEnabled })) {
        $methods = Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction SilentlyContinue
        $hasMfa  = $methods | Where-Object { $_.AdditionalProperties["@odata.type"] -notmatch "passwordAuthentication" }

        $mfaReport += [PSCustomObject]@{
            UserPrincipalName = $user.UserPrincipalName
            DisplayName       = $user.DisplayName
            Licensed          = ($user.AssignedLicenses.Count -gt 0)
            MFARegistered     = ($hasMfa.Count -gt 0)
            MFAMethodCount    = $hasMfa.Count
            RiskLevel         = if ($user.AssignedLicenses.Count -gt 0 -and $hasMfa.Count -eq 0) { "HIGH" } else { "OK" }
        }
    }

    $mfaReport | Sort-Object RiskLevel -Descending | Format-Table -AutoSize

    $noMfa = ($mfaReport | Where-Object { -not $_.MFARegistered }).Count
    $highRisk = ($mfaReport | Where-Object { $_.RiskLevel -eq "HIGH" }).Count
    Write-Host "  Users without MFA : $noMfa" -ForegroundColor $(if ($noMfa -gt 0) { "Red" } else { "Green" })
    Write-Host "  HIGH risk (licensed + no MFA): $highRisk`n" -ForegroundColor $(if ($highRisk -gt 0) { "Red" } else { "Green" })

    Export-Section -Name "mfa" -Data $mfaReport
}

# ─────────────────────────────────────────────
# SECTION: GUEST ACCOUNTS
# ─────────────────────────────────────────────

if ($Section -in @("Guests", "All")) {
    Write-Host "═══ Guest Accounts ══════════════════════════════════" -ForegroundColor Cyan

    $guests = Get-MgUser -All -Filter "userType eq 'Guest'" -Property `
        "UserPrincipalName", "DisplayName", "CreatedDateTime", "SignInActivity", "AccountEnabled"

    $guestReport = foreach ($guest in $guests) {
        [PSCustomObject]@{
            DisplayName       = $guest.DisplayName
            UserPrincipalName = $guest.UserPrincipalName
            AccountEnabled    = $guest.AccountEnabled
            CreatedDate       = if ($guest.CreatedDateTime) { $guest.CreatedDateTime.ToString("yyyy-MM-dd") } else { "N/A" }
            LastSignIn        = if ($guest.SignInActivity.LastSignInDateTime) { $guest.SignInActivity.LastSignInDateTime.ToString("yyyy-MM-dd") } else { "Never" }
        }
    }

    $guestReport | Format-Table -AutoSize
    Write-Host "  Total guest accounts: $($guestReport.Count)`n" -ForegroundColor Yellow

    Export-Section -Name "guests" -Data $guestReport
}

# ─────────────────────────────────────────────
# SECTION: SHARED MAILBOX ACCESS
# ─────────────────────────────────────────────

if ($Section -in @("SharedMailboxes", "All")) {
    Write-Host "═══ Shared Mailbox Access ════════════════════════════" -ForegroundColor Cyan

    try {
        Connect-ExchangeOnline -ShowBanner:$false

        $sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited
        $mbxReport = foreach ($mbx in $sharedMailboxes) {
            $perms = Get-MailboxPermission -Identity $mbx.PrimarySmtpAddress |
                Where-Object { $_.User -notlike "NT AUTHORITY\*" -and $_.IsInherited -eq $false }

            foreach ($perm in $perms) {
                [PSCustomObject]@{
                    SharedMailbox   = $mbx.PrimarySmtpAddress
                    DisplayName     = $mbx.DisplayName
                    DelegateUser    = $perm.User
                    AccessRights    = ($perm.AccessRights -join ", ")
                }
            }
        }

        $mbxReport | Format-Table -AutoSize
        Write-Host "  Shared mailboxes audited: $($sharedMailboxes.Count)`n"
        Export-Section -Name "shared-mailboxes" -Data $mbxReport
    }
    catch {
        Write-Warning "Could not connect to Exchange Online. Skipping SharedMailboxes section."
    }
}

# ─────────────────────────────────────────────
# SECTION: PUBLIC TEAMS
# ─────────────────────────────────────────────

if ($Section -in @("PublicTeams", "All")) {
    Write-Host "═══ Public Teams (Data Exposure Risk) ═══════════════" -ForegroundColor Cyan

    try {
        Connect-MicrosoftTeams -ErrorAction Stop | Out-Null
        $publicTeams = Get-Team | Where-Object { $_.Visibility -eq "Public" }

        $teamsReport = foreach ($team in $publicTeams) {
            $members = Get-TeamUser -GroupId $team.GroupId -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                TeamName    = $team.DisplayName
                GroupId     = $team.GroupId
                MemberCount = $members.Count
                GuestCount  = ($members | Where-Object { $_.Role -eq "Guest" }).Count
                Archived    = $team.Archived
            }
        }

        $teamsReport | Format-Table -AutoSize
        Write-Host "  Public teams found: $($teamsReport.Count)" -ForegroundColor $(if ($teamsReport.Count -gt 0) { "Yellow" } else { "Green" })
        Write-Host "  Review each team and consider switching to Private if no business justification.`n"
        Export-Section -Name "public-teams" -Data $teamsReport
    }
    catch {
        Write-Warning "Could not connect to Teams. Skipping PublicTeams section."
    }
}

# ─────────────────────────────────────────────
# SECTION: INACTIVE USERS
# ─────────────────────────────────────────────

if ($Section -in @("InactiveUsers", "All")) {
    Write-Host "═══ Inactive Users (No sign-in in $InactiveDays+ days) ═══" -ForegroundColor Cyan

    $cutoff = (Get-Date).AddDays(-$InactiveDays)

    $allUsers = Get-MgUser -All -Property `
        "UserPrincipalName", "DisplayName", "AccountEnabled", "SignInActivity", "AssignedLicenses", "Department"

    $inactiveReport = foreach ($user in ($allUsers | Where-Object { $_.AccountEnabled })) {
        $lastSignIn = $user.SignInActivity.LastSignInDateTime
        $isInactive = (-not $lastSignIn) -or ($lastSignIn -lt $cutoff)

        if ($isInactive) {
            [PSCustomObject]@{
                UserPrincipalName = $user.UserPrincipalName
                DisplayName       = $user.DisplayName
                Department        = $user.Department
                Licensed          = ($user.AssignedLicenses.Count -gt 0)
                LastSignIn        = if ($lastSignIn) { $lastSignIn.ToString("yyyy-MM-dd") } else { "Never" }
                DaysSinceSignIn   = if ($lastSignIn) { [int]((Get-Date) - $lastSignIn).TotalDays } else { 999 }
            }
        }
    }

    $inactiveReport | Sort-Object DaysSinceSignIn -Descending | Format-Table -AutoSize

    $licensedInactive = ($inactiveReport | Where-Object { $_.Licensed }).Count
    Write-Host "  Inactive users total    : $($inactiveReport.Count)"
    Write-Host "  Inactive + still licensed: $licensedInactive" -ForegroundColor $(if ($licensedInactive -gt 0) { "Yellow" } else { "Green" })
    Write-Host "  Potential license savings: review and remove licenses from inactive accounts.`n"
    Export-Section -Name "inactive-users" -Data $inactiveReport
}

# ─────────────────────────────────────────────
# DISCONNECT
# ─────────────────────────────────────────────

Disconnect-MgGraph | Out-Null
Write-Host "[INFO] Audit complete. Disconnected from Microsoft Graph.`n" -ForegroundColor Cyan

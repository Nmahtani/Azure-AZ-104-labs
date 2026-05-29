<#
.SYNOPSIS
    Creates, converts, and audits Exchange Online mailboxes.

.DESCRIPTION
    Covers four actions:
    - CreateShared: creates a shared mailbox and grants access to specified users
    - GrantAccess: adds Full Access or Send As permissions to an existing mailbox
    - RevokeAccess: removes mailbox permissions (offboarding use case)
    - Audit: exports a full mailbox inventory with size, type, and permissions

.PARAMETER Action
    Action to perform: CreateShared | GrantAccess | RevokeAccess | Audit

.PARAMETER DisplayName
    Display name of the mailbox (for CreateShared).

.PARAMETER Alias
    Email alias (for CreateShared). Full address will be alias@contoso.com.

.PARAMETER Mailbox
    Primary SMTP address of the target mailbox.

.PARAMETER User
    UPN of the user to grant or revoke access.

.PARAMETER AccessRight
    Permission type: FullAccess | SendAs. Defaults to FullAccess.

.PARAMETER ExportCsv
    Exports audit results to ./reports/mailbox-audit-<timestamp>.csv

.EXAMPLE
    .\Manage-Mailboxes.ps1 -Action CreateShared -DisplayName "Finance Team" -Alias "finance"

.EXAMPLE
    .\Manage-Mailboxes.ps1 -Action GrantAccess -Mailbox "finance@contoso.com" -User "john.doe@contoso.com"

.EXAMPLE
    .\Manage-Mailboxes.ps1 -Action Audit -ExportCsv

.NOTES
    Requires: ExchangeOnlineManagement module
    Connect first: Connect-ExchangeOnline -UserPrincipalName admin@contoso.com
    Author: Nikhil Mahtani · IT Systems Administrator
    Project: m365-admin-scripts
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("CreateShared", "GrantAccess", "RevokeAccess", "Audit")]
    [string]$Action,

    [Parameter(Mandatory = $false)] [string]$DisplayName,
    [Parameter(Mandatory = $false)] [string]$Alias,
    [Parameter(Mandatory = $false)] [string]$Mailbox,
    [Parameter(Mandatory = $false)] [string]$User,
    [Parameter(Mandatory = $false)]
    [ValidateSet("FullAccess", "SendAs")]
    [string]$AccessRight = "FullAccess",
    [Parameter(Mandatory = $false)] [switch]$ExportCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

switch ($Action) {

    "CreateShared" {
        if (-not $DisplayName -or -not $Alias) {
            Write-Error "-DisplayName and -Alias are required for CreateShared."
            exit 1
        }

        $primarySmtp = "$Alias@contoso.com"

        Write-Host "`n[INFO] Creating shared mailbox: $primarySmtp" -ForegroundColor Cyan

        New-Mailbox `
            -Shared `
            -Name $DisplayName `
            -DisplayName $DisplayName `
            -Alias $Alias `
            -PrimarySmtpAddress $primarySmtp

        Write-Host "[SUCCESS] Shared mailbox created: $primarySmtp" -ForegroundColor Green
        Write-Host "[INFO] Use -Action GrantAccess to add users to this mailbox.`n"
    }

    "GrantAccess" {
        if (-not $Mailbox -or -not $User) {
            Write-Error "-Mailbox and -User are required for GrantAccess."
            exit 1
        }

        Write-Host "`n[INFO] Granting $AccessRight on '$Mailbox' to '$User'..." -ForegroundColor Cyan

        if ($AccessRight -eq "FullAccess") {
            Add-MailboxPermission `
                -Identity $Mailbox `
                -User $User `
                -AccessRights FullAccess `
                -InheritanceType All `
                -AutoMapping $true

            Write-Host "[SUCCESS] Full Access granted. Mailbox will auto-map in Outlook." -ForegroundColor Green
        }
        elseif ($AccessRight -eq "SendAs") {
            Add-RecipientPermission `
                -Identity $Mailbox `
                -Trustee $User `
                -AccessRights SendAs `
                -Confirm:$false

            Write-Host "[SUCCESS] Send As permission granted." -ForegroundColor Green
        }
    }

    "RevokeAccess" {
        if (-not $Mailbox -or -not $User) {
            Write-Error "-Mailbox and -User are required for RevokeAccess."
            exit 1
        }

        Write-Host "`n[INFO] Revoking $AccessRight on '$Mailbox' from '$User'..." -ForegroundColor Cyan

        if ($AccessRight -eq "FullAccess") {
            Remove-MailboxPermission `
                -Identity $Mailbox `
                -User $User `
                -AccessRights FullAccess `
                -Confirm:$false
        }
        elseif ($AccessRight -eq "SendAs") {
            Remove-RecipientPermission `
                -Identity $Mailbox `
                -Trustee $User `
                -AccessRights SendAs `
                -Confirm:$false
        }

        Write-Host "[SUCCESS] $AccessRight permission removed from '$User' on '$Mailbox'." -ForegroundColor Green
    }

    "Audit" {
        Write-Host "`n[INFO] Generating mailbox audit..." -ForegroundColor Cyan

        $mailboxes = Get-Mailbox -ResultSize Unlimited -Properties DisplayName, RecipientTypeDetails, PrimarySmtpAddress

        $report = foreach ($mbx in $mailboxes) {
            # Get mailbox statistics (size, item count)
            $stats = Get-MailboxStatistics -Identity $mbx.PrimarySmtpAddress -ErrorAction SilentlyContinue

            # Get Full Access delegates
            $delegates = Get-MailboxPermission -Identity $mbx.PrimarySmtpAddress |
                Where-Object { $_.User -notlike "NT AUTHORITY\*" -and $_.IsInherited -eq $false } |
                Select-Object -ExpandProperty User

            [PSCustomObject]@{
                DisplayName      = $mbx.DisplayName
                PrimarySmtp      = $mbx.PrimarySmtpAddress
                MailboxType      = $mbx.RecipientTypeDetails
                TotalSizeMB      = if ($stats) { [math]::Round($stats.TotalItemSize.Value.ToMB(), 1) } else { 0 }
                ItemCount        = if ($stats) { $stats.ItemCount } else { 0 }
                LastLogon        = if ($stats) { $stats.LastLogonTime } else { "Never" }
                FullAccessUsers  = if ($delegates) { $delegates -join "; " } else { "None" }
            }
        }

        $report | Format-Table -AutoSize

        Write-Host "─── Mailbox Summary ──────────────────────────────" -ForegroundColor Cyan
        Write-Host "  Total mailboxes  : $($report.Count)"
        Write-Host "  User mailboxes   : $(($report | Where-Object { $_.MailboxType -eq 'UserMailbox' }).Count)"
        Write-Host "  Shared mailboxes : $(($report | Where-Object { $_.MailboxType -eq 'SharedMailbox' }).Count)"
        Write-Host "  Room/Equipment   : $(($report | Where-Object { $_.MailboxType -match 'Room|Equipment' }).Count)"
        Write-Host "──────────────────────────────────────────────────`n" -ForegroundColor Cyan

        if ($ExportCsv) {
            $reportsDir = Join-Path $PSScriptRoot "..\..\reports"
            if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
            $outputPath = Join-Path $reportsDir "mailbox-audit-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
            $report | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
            Write-Host "[SUCCESS] Report exported to: $outputPath" -ForegroundColor Green
        }
    }
}

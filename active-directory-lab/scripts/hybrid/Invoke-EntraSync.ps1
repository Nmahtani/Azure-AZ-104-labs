<#
.SYNOPSIS
    Triggers a delta or full Entra Connect synchronization cycle.

.DESCRIPTION
    Remotely invokes an ADSync cycle on the Entra Connect server.
    Delta sync is recommended for routine use after adding or modifying users.
    Full sync should be used after major structural changes (new OUs, sync scope changes).

.PARAMETER SyncType
    Type of sync to trigger. Accepted values: Delta, Full. Defaults to Delta.

.PARAMETER EntraConnectServer
    Hostname of the Entra Connect server. Defaults to ENTRACONNECT01.

.PARAMETER WaitForCompletion
    If specified, polls the sync status until the cycle completes.

.EXAMPLE
    .\Invoke-EntraSync.ps1 -SyncType Delta

.EXAMPLE
    .\Invoke-EntraSync.ps1 -SyncType Full -WaitForCompletion

.NOTES
    Requires: ADSync module on the Entra Connect server
    Run from: Domain controller or member server with remote access to Entra Connect host
    Author:   Nikhil Mahtani · IT Systems Administrator
    Project:  active-directory-lab
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Delta", "Full")]
    [string]$SyncType = "Delta",

    [Parameter(Mandatory = $false)]
    [string]$EntraConnectServer = "ENTRACONNECT01",

    [Parameter(Mandatory = $false)]
    [switch]$WaitForCompletion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "`n[INFO] Triggering $SyncType sync on $EntraConnectServer..." -ForegroundColor Cyan

try {
    Invoke-Command -ComputerName $EntraConnectServer -ScriptBlock {
        param ($type)
        Import-Module ADSync

        # Check if a sync is already running
        $scheduler = Get-ADSyncScheduler
        if ($scheduler.SyncCycleInProgress) {
            Write-Warning "A sync cycle is already in progress. Skipping."
            return
        }

        Start-ADSyncSyncCycle -PolicyType $type
        Write-Host "[$env:COMPUTERNAME] $type sync cycle started."
    } -ArgumentList $SyncType

    Write-Host "[SUCCESS] $SyncType sync triggered successfully." -ForegroundColor Green
}
catch {
    Write-Error "Failed to trigger sync on $EntraConnectServer`: $_"
    exit 1
}

# ── Optional: wait for completion ──
if ($WaitForCompletion) {
    Write-Host "`n[INFO] Waiting for sync cycle to complete..." -ForegroundColor Cyan
    $timeout  = 300  # 5 minutes max
    $interval = 10
    $elapsed  = 0

    do {
        Start-Sleep -Seconds $interval
        $elapsed += $interval

        $inProgress = Invoke-Command -ComputerName $EntraConnectServer -ScriptBlock {
            Import-Module ADSync
            (Get-ADSyncScheduler).SyncCycleInProgress
        }

        Write-Host "  Elapsed: ${elapsed}s — Sync in progress: $inProgress"
    } while ($inProgress -and $elapsed -lt $timeout)

    if ($elapsed -ge $timeout) {
        Write-Warning "Timed out after ${timeout}s. Sync may still be running."
    } else {
        Write-Host "[SUCCESS] Sync cycle completed in ${elapsed}s." -ForegroundColor Green
    }
}

Write-Host "`n[INFO] Changes will appear in Entra ID within 2–5 minutes after sync completes.`n" -ForegroundColor Cyan

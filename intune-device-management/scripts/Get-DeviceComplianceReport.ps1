<#
.SYNOPSIS
    Generates a device compliance report for all Intune-managed devices.

.DESCRIPTION
    Connects to Microsoft Graph API and retrieves all managed devices with their
    compliance status, OS version, last sync time, and assigned user.
    Supports filtering by OS and compliance state. Exports to CSV for audits.

.PARAMETER OS
    Filter by operating system. Accepted values: Windows, macOS.

.PARAMETER NonCompliantOnly
    Returns only devices with ComplianceState = NonCompliant.

.PARAMETER ExportCsv
    Exports results to ./reports/compliance-report-<timestamp>.csv

.PARAMETER TenantId
    Entra ID Tenant ID. Defaults to current Graph context.

.EXAMPLE
    .\Get-DeviceComplianceReport.ps1 -ExportCsv

.EXAMPLE
    .\Get-DeviceComplianceReport.ps1 -OS Windows -NonCompliantOnly -ExportCsv

.NOTES
    Requires: PowerShell 7+, Microsoft.Graph module
    Permission: DeviceManagementManagedDevices.Read.All (read-only)

    Author:  Nikhil Mahtani · IT Systems Administrator
    Project: intune-device-management
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Windows", "macOS")]
    [string]$OS,

    [Parameter(Mandatory = $false)]
    [switch]$NonCompliantOnly,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCsv,

    [Parameter(Mandatory = $false)]
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────
# 1. CONNECT TO MICROSOFT GRAPH
# ─────────────────────────────────────────────

Write-Host "`n[INFO] Connecting to Microsoft Graph..." -ForegroundColor Cyan

$graphParams = @{ Scopes = "DeviceManagementManagedDevices.Read.All" }
if ($TenantId) { $graphParams["TenantId"] = $TenantId }

try {
    Connect-MgGraph @graphParams
    Write-Host "[INFO] Connected.`n" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit 1
}

# ─────────────────────────────────────────────
# 2. RETRIEVE ALL MANAGED DEVICES
# ─────────────────────────────────────────────
# -All automatically pages through results for tenants with 1000+ devices.

Write-Host "[INFO] Retrieving managed devices..." -ForegroundColor Cyan

$allDevices = Get-MgDeviceManagementManagedDevice -All -Property `
    "deviceName", "userPrincipalName", "operatingSystem", "osVersion",
    "complianceState", "lastSyncDateTime", "enrolledDateTime",
    "manufacturer", "model", "serialNumber",
    "managedDeviceOwnerType", "deviceEnrollmentType",
    "azureADDeviceId", "id"

Write-Host "[INFO] Total devices retrieved: $($allDevices.Count)`n" -ForegroundColor Cyan

# ─────────────────────────────────────────────
# 3. APPLY FILTERS
# ─────────────────────────────────────────────

$filtered = $allDevices

if ($OS) {
    $filtered = $filtered | Where-Object { $_.OperatingSystem -eq $OS }
    Write-Host "[FILTER] OS = $OS → $($filtered.Count) device(s)" -ForegroundColor Yellow
}

if ($NonCompliantOnly) {
    $filtered = $filtered | Where-Object { $_.ComplianceState -eq "noncompliant" }
    Write-Host "[FILTER] NonCompliant only → $($filtered.Count) device(s)" -ForegroundColor Yellow
}

if ($filtered.Count -eq 0) {
    Write-Host "`n[RESULT] No devices match the specified filters." -ForegroundColor Yellow
    Disconnect-MgGraph | Out-Null
    exit 0
}

# ─────────────────────────────────────────────
# 4. BUILD REPORT OBJECT
# ─────────────────────────────────────────────

$report = foreach ($device in $filtered) {
    $lastSync     = $device.LastSyncDateTime
    $syncAgeHours = if ($lastSync) {
        [math]::Round(((Get-Date) - $lastSync).TotalHours, 1)
    } else { "N/A" }

    [PSCustomObject]@{
        DeviceName        = $device.DeviceName
        UserPrincipalName = $device.UserPrincipalName
        OS                = $device.OperatingSystem
        OSVersion         = $device.OsVersion
        ComplianceState   = $device.ComplianceState
        LastSyncDateTime  = if ($lastSync) { $lastSync.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
        SyncAgeHours      = $syncAgeHours
        EnrolledDate      = if ($device.EnrolledDateTime) { $device.EnrolledDateTime.ToString("yyyy-MM-dd") } else { "N/A" }
        Manufacturer      = $device.Manufacturer
        Model             = $device.Model
        SerialNumber      = $device.SerialNumber
        OwnerType         = $device.ManagedDeviceOwnerType
        EnrollmentType    = $device.DeviceEnrollmentType
        AzureADDeviceId   = $device.AzureADDeviceId
        IntuneDeviceId    = $device.Id
    }
}

# ─────────────────────────────────────────────
# 5. DISPLAY SUMMARY IN CONSOLE
# ─────────────────────────────────────────────

$report | Format-Table -AutoSize -Property `
    DeviceName, UserPrincipalName, OS, OSVersion, ComplianceState, LastSyncDateTime, SyncAgeHours

$compliantCount    = ($report | Where-Object { $_.ComplianceState -eq "compliant" }).Count
$nonCompliantCount = ($report | Where-Object { $_.ComplianceState -eq "noncompliant" }).Count
$unknownCount      = ($report | Where-Object { $_.ComplianceState -notin @("compliant", "noncompliant") }).Count
$staleCount        = ($report | Where-Object { $_.SyncAgeHours -ne "N/A" -and $_.SyncAgeHours -gt 72 }).Count

Write-Host "─── Summary ──────────────────────────────────────" -ForegroundColor Cyan
Write-Host "  Total devices  : $($report.Count)"
Write-Host "  Compliant      : $compliantCount"    -ForegroundColor Green
Write-Host "  Non-Compliant  : $nonCompliantCount" -ForegroundColor Red
Write-Host "  Unknown/Other  : $unknownCount"      -ForegroundColor Yellow
if ($staleCount -gt 0) {
    Write-Host "  Stale (>72h)   : $staleCount  ← check enrollment/connectivity" -ForegroundColor Yellow
}
Write-Host "──────────────────────────────────────────────────`n" -ForegroundColor Cyan

# ─────────────────────────────────────────────
# 6. EXPORT TO CSV
# ─────────────────────────────────────────────

if ($ExportCsv) {
    $reportsDir = Join-Path $PSScriptRoot "..\reports"
    if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }

    $timestamp  = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $osLabel    = if ($OS) { "-$OS" } else { "" }
    $ncLabel    = if ($NonCompliantOnly) { "-NonCompliant" } else { "" }
    $outputPath = Join-Path $reportsDir "compliance-report${osLabel}${ncLabel}-${timestamp}.csv"

    $report | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
    Write-Host "[SUCCESS] Report exported to: $outputPath" -ForegroundColor Green
}

# ─────────────────────────────────────────────
# 7. DISCONNECT
# ─────────────────────────────────────────────

Disconnect-MgGraph | Out-Null
Write-Host "[INFO] Disconnected from Microsoft Graph." -ForegroundColor Cyan

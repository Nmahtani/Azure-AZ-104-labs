<#
.SYNOPSIS
    Generates a full RBAC access report for an Azure subscription or resource group.

.DESCRIPTION
    Queries all role assignments at the specified scope and produces a structured
    report showing who has access to what. Output can be displayed in the console
    as a formatted table or exported to a timestamped CSV file for audits.

    Includes:
    - Display name, sign-in name, and principal type (User/Group/ServicePrincipal)
    - Role definition name and whether it is built-in or custom
    - Full scope of the assignment
    - Whether the assignment is directly applied or inherited

.PARAMETER ResourceGroupName
    (Optional) Filter report to a specific resource group.
    If omitted, reports on the full subscription.

.PARAMETER SubscriptionId
    (Optional) Target subscription. Defaults to current Az context.

.PARAMETER ExportCsv
    If specified, exports results to ./reports/access-report-<timestamp>.csv

.PARAMETER ShowInherited
    If specified, includes assignments inherited from parent scopes.
    Omitted by default to reduce noise.

.EXAMPLE
    .\Get-AccessReport.ps1

.EXAMPLE
    .\Get-AccessReport.ps1 -ResourceGroupName "rg-production" -ExportCsv

.EXAMPLE
    .\Get-AccessReport.ps1 -ExportCsv -ShowInherited

.NOTES
    Requires: Az.Resources module
    Author:   az104-rbac-governance project
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCsv,

    [Parameter(Mandatory = $false)]
    [switch]$ShowInherited
)

#region --- Setup ---
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $SubscriptionId) {
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "No active Az context. Run Connect-AzAccount first."
        exit 1
    }
    $SubscriptionId = $context.Subscription.Id
}

$subscriptionScope = "/subscriptions/$SubscriptionId"

Write-Host "`n[INFO] Generating RBAC access report..." -ForegroundColor Cyan
Write-Host "[INFO] Subscription: $SubscriptionId"
#endregion

#region --- Get role assignments ---
$params = @{}

if ($ResourceGroupName) {
    $params["ResourceGroupName"] = $ResourceGroupName
    Write-Host "[INFO] Scope: Resource Group '$ResourceGroupName'"
} else {
    $params["Scope"] = $subscriptionScope
    Write-Host "[INFO] Scope: Full subscription"
}

$assignments = Get-AzRoleAssignment @params

# Optionally filter out inherited assignments
if (-not $ShowInherited -and $ResourceGroupName) {
    $rgScope = "$subscriptionScope/resourceGroups/$ResourceGroupName"
    $assignments = $assignments | Where-Object { $_.Scope -eq $rgScope }
    Write-Host "[INFO] Showing direct assignments only (use -ShowInherited to include inherited)"
}

Write-Host "[INFO] Found $($assignments.Count) assignment(s)`n" -ForegroundColor Cyan
#endregion

#region --- Enrich data ---
# Load all custom role definitions once for efficient lookup
$customRoles = Get-AzRoleDefinition -Custom | Select-Object -ExpandProperty Name

$report = foreach ($a in $assignments) {
    $isCustom = if ($customRoles -contains $a.RoleDefinitionName) { "Custom" } else { "BuiltIn" }

    [PSCustomObject]@{
        DisplayName        = $a.DisplayName
        SignInName         = if ($a.SignInName) { $a.SignInName } else { "N/A (Group or SP)" }
        PrincipalType      = $a.ObjectType
        RoleDefinitionName = $a.RoleDefinitionName
        RoleType           = $isCustom
        Scope              = $a.Scope
        AssignmentId       = $a.RoleAssignmentId
    }
}
#endregion

#region --- Display report ---
$report | Format-Table -AutoSize -Property DisplayName, SignInName, PrincipalType, RoleDefinitionName, RoleType, Scope

# Summary
$userCount    = ($report | Where-Object { $_.PrincipalType -eq "User" }).Count
$groupCount   = ($report | Where-Object { $_.PrincipalType -eq "Group" }).Count
$spCount      = ($report | Where-Object { $_.PrincipalType -eq "ServicePrincipal" }).Count
$customCount  = ($report | Where-Object { $_.RoleType -eq "Custom" }).Count

Write-Host "--- Summary ---" -ForegroundColor Cyan
Write-Host "  Total assignments : $($report.Count)"
Write-Host "  Users             : $userCount"
Write-Host "  Groups            : $groupCount"
Write-Host "  Service Principals: $spCount"
Write-Host "  Custom roles used : $customCount"
#endregion

#region --- Export to CSV ---
if ($ExportCsv) {
    $reportsDir = Join-Path $PSScriptRoot "..\reports"
    if (-not (Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir | Out-Null
    }

    $timestamp  = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $outputPath = Join-Path $reportsDir "access-report-$timestamp.csv"

    $report | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

    Write-Host "`n[SUCCESS] Report exported to: $outputPath" -ForegroundColor Green
}
#endregion

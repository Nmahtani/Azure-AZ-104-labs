<#
.SYNOPSIS
    Removes an Azure RBAC role assignment from a user, group, or service principal.

.DESCRIPTION
    Removes a role assignment at resource group or subscription scope.
    Intended for offboarding or access cleanup. Validates the assignment
    exists before attempting removal and confirms before proceeding.

.PARAMETER UserPrincipalName
    UPN of the user (e.g. john.doe@contoso.com). Use this OR ObjectId.

.PARAMETER ObjectId
    Object ID of a user, group, or service principal. Use this OR UserPrincipalName.

.PARAMETER RoleName
    Display name of the role to remove (e.g. "Reader").

.PARAMETER ResourceGroupName
    (Optional) Scope of the assignment to remove. If omitted, targets subscription scope.

.PARAMETER SubscriptionId
    (Optional) Target subscription. Defaults to current Az context.

.PARAMETER Force
    Skip confirmation prompt.

.EXAMPLE
    .\Remove-RoleAssignment.ps1 -UserPrincipalName "john.doe@contoso.com" -RoleName "Reader" -ResourceGroupName "rg-production"

.EXAMPLE
    .\Remove-RoleAssignment.ps1 -UserPrincipalName "john.doe@contoso.com" -RoleName "Reader" -ResourceGroupName "rg-production" -Force

.NOTES
    Requires: Az.Resources module
    Author:   az104-rbac-governance project
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $false)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $false)]
    [string]$ObjectId,

    [Parameter(Mandatory = $true)]
    [string]$RoleName,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

#region --- Setup ---
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $UserPrincipalName -and -not $ObjectId) {
    Write-Error "Provide either -UserPrincipalName or -ObjectId."
    exit 1
}

if (-not $SubscriptionId) {
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "No active Az context. Run Connect-AzAccount first."
        exit 1
    }
    $SubscriptionId = $context.Subscription.Id
}

Write-Host "`n[INFO] Target subscription: $SubscriptionId" -ForegroundColor Cyan
#endregion

#region --- Resolve principal ---
if ($UserPrincipalName) {
    Write-Host "[INFO] Resolving principal: $UserPrincipalName" -ForegroundColor Cyan
    $principal = Get-AzADUser -UserPrincipalName $UserPrincipalName -ErrorAction SilentlyContinue
    if (-not $principal) {
        Write-Error "User '$UserPrincipalName' not found in Entra ID."
        exit 1
    }
    $ObjectId = $principal.Id
}
#endregion

#region --- Build scope ---
if ($ResourceGroupName) {
    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
} else {
    $scope = "/subscriptions/$SubscriptionId"
}
#endregion

#region --- Find assignment ---
Write-Host "[INFO] Looking for assignment..." -ForegroundColor Cyan
$assignment = Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $scope -ErrorAction SilentlyContinue

if (-not $assignment) {
    Write-Host "`n[SKIP] No matching assignment found. Nothing to remove." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n[FOUND] Assignment to remove:" -ForegroundColor Yellow
Write-Host "  Principal : $($assignment.DisplayName) ($($assignment.SignInName))"
Write-Host "  Role      : $($assignment.RoleDefinitionName)"
Write-Host "  Scope     : $($assignment.Scope)"
#endregion

#region --- Confirm and remove ---
if (-not $Force) {
    $confirm = Read-Host "`nProceed with removal? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "[CANCELLED] No changes made." -ForegroundColor Yellow
        exit 0
    }
}

Remove-AzRoleAssignment `
    -ObjectId $ObjectId `
    -RoleDefinitionName $RoleName `
    -Scope $scope

Write-Host "`n[SUCCESS] Role assignment removed." -ForegroundColor Green
Write-Host "  $($assignment.DisplayName) no longer has '$RoleName' on scope: $scope"
#endregion

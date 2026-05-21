<#
.SYNOPSIS
    Assigns an Azure RBAC role to a user, group, or service principal.

.DESCRIPTION
    Assigns a built-in or custom role at resource group or subscription scope.
    Validates that the principal and role exist before attempting assignment.
    Skips silently if the assignment already exists (idempotent).

.PARAMETER UserPrincipalName
    UPN of the user (e.g. john.doe@contoso.com). Use this OR ObjectId.

.PARAMETER ObjectId
    Object ID of a user, group, or service principal. Use this OR UserPrincipalName.

.PARAMETER RoleName
    Display name of the role (e.g. "Reader", "Contributor", "VM Operator (Custom)").

.PARAMETER ResourceGroupName
    (Optional) Scope the assignment to a specific resource group.
    If omitted, assignment is at subscription scope.

.PARAMETER SubscriptionId
    (Optional) Target subscription. Defaults to current Az context.

.EXAMPLE
    .\Set-RoleAssignment.ps1 -UserPrincipalName "john.doe@contoso.com" -RoleName "Reader" -ResourceGroupName "rg-production"

.EXAMPLE
    .\Set-RoleAssignment.ps1 -ObjectId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -RoleName "VM Operator (Custom)" -ResourceGroupName "rg-compute"

.NOTES
    Requires: Az.Resources module
    Author:   az104-rbac-governance project
#>

[CmdletBinding()]
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
    [string]$SubscriptionId
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
    Write-Host "[INFO] Resolved Object ID: $ObjectId"
}
#endregion

#region --- Validate role ---
Write-Host "[INFO] Validating role: '$RoleName'" -ForegroundColor Cyan
$role = Get-AzRoleDefinition -Name $RoleName -ErrorAction SilentlyContinue
if (-not $role) {
    Write-Error "Role '$RoleName' not found. Check the name and try again."
    exit 1
}
Write-Host "[INFO] Role found: $($role.Name) (ID: $($role.Id))"
#endregion

#region --- Build scope ---
if ($ResourceGroupName) {
    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
    Write-Host "[INFO] Scope: Resource Group '$ResourceGroupName'"
} else {
    $scope = "/subscriptions/$SubscriptionId"
    Write-Host "[INFO] Scope: Subscription (root)"
}
#endregion

#region --- Check existing assignment ---
$existing = Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $scope -ErrorAction SilentlyContinue

if ($existing) {
    Write-Host "`n[SKIP] Assignment already exists — no changes made." -ForegroundColor Yellow
    Write-Host "  Principal : $($existing.DisplayName)"
    Write-Host "  Role      : $($existing.RoleDefinitionName)"
    Write-Host "  Scope     : $($existing.Scope)"
    exit 0
}
#endregion

#region --- Assign role ---
Write-Host "`n[INFO] Assigning role..." -ForegroundColor Cyan

$assignment = New-AzRoleAssignment `
    -ObjectId $ObjectId `
    -RoleDefinitionName $RoleName `
    -Scope $scope

Write-Host "`n[SUCCESS] Role assigned." -ForegroundColor Green
Write-Host "  Principal      : $($assignment.DisplayName)"
Write-Host "  Role           : $($assignment.RoleDefinitionName)"
Write-Host "  Scope          : $($assignment.Scope)"
Write-Host "  Assignment ID  : $($assignment.RoleAssignmentId)"
#endregion

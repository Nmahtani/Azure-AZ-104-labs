<#
.SYNOPSIS
    Creates a custom Azure RBAC role from a JSON definition file.

.DESCRIPTION
    Reads a role definition JSON file and creates the custom role in Azure.
    Checks for an existing role with the same name to avoid duplicates.
    Replaces the AssignableScopes placeholder with the current subscription ID
    if not already set.

.PARAMETER RoleDefinitionPath
    Path to the JSON file containing the role definition.

.PARAMETER SubscriptionId
    (Optional) Target subscription ID. Defaults to the current Az context.

.EXAMPLE
    .\New-CustomRole.ps1 -RoleDefinitionPath ".\roles\custom-role-vm-operator.json"

.EXAMPLE
    .\New-CustomRole.ps1 -RoleDefinitionPath ".\roles\custom-role-vm-operator.json" -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.NOTES
    Requires: Az.Resources module
    Author:   az104-rbac-governance project
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$RoleDefinitionPath,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
)

#region --- Setup ---
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve subscription
if (-not $SubscriptionId) {
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "No active Az context found. Run Connect-AzAccount first."
        exit 1
    }
    $SubscriptionId = $context.Subscription.Id
}

Write-Host "`n[INFO] Target subscription: $SubscriptionId" -ForegroundColor Cyan
#endregion

#region --- Load and validate JSON ---
Write-Host "[INFO] Loading role definition from: $RoleDefinitionPath" -ForegroundColor Cyan

$roleJson = Get-Content -Path $RoleDefinitionPath -Raw

# Replace placeholder subscription ID if present
if ($roleJson -match "<your-subscription-id>") {
    Write-Host "[INFO] Replacing subscription placeholder in JSON..." -ForegroundColor Yellow
    $roleJson = $roleJson -replace "<your-subscription-id>", $SubscriptionId
}

$roleDef = $roleJson | ConvertFrom-Json
$roleName = $roleDef.Name

Write-Host "[INFO] Role name: $roleName"
#endregion

#region --- Check for existing role ---
$existingRole = Get-AzRoleDefinition -Name $roleName -ErrorAction SilentlyContinue

if ($existingRole) {
    Write-Warning "A custom role named '$roleName' already exists."
    Write-Host "  Role ID : $($existingRole.Id)"
    Write-Host "  To update it, delete first with: Remove-AzRoleDefinition -Id '$($existingRole.Id)'"
    exit 0
}
#endregion

#region --- Create the role ---
Write-Host "`n[INFO] Creating custom role '$roleName'..." -ForegroundColor Cyan

# Save the resolved JSON to a temp file (New-AzRoleDefinition requires a file path)
$tempFile = [System.IO.Path]::GetTempFileName() + ".json"
$roleJson | Out-File -FilePath $tempFile -Encoding UTF8

try {
    $newRole = New-AzRoleDefinition -InputFile $tempFile

    Write-Host "`n[SUCCESS] Custom role created." -ForegroundColor Green
    Write-Host "  Name        : $($newRole.Name)"
    Write-Host "  Role ID     : $($newRole.Id)"
    Write-Host "  Description : $($newRole.Description)"
    Write-Host "  Actions     : $($newRole.Actions.Count) allowed actions"
    Write-Host "  NotActions  : $($newRole.NotActions.Count) denied actions"
    Write-Host "  Scopes      : $($newRole.AssignableScopes -join ', ')"
}
finally {
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
}
#endregion

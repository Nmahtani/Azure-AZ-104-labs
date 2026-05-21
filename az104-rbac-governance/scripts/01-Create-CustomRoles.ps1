<#
.SYNOPSIS
    Creates custom RBAC roles in Azure from JSON definition files.

.DESCRIPTION
    Reads role definition JSON files from the /roles directory and deploys them
    to the specified Azure subscription. Checks for existing roles before creating
    to avoid duplicates. Updates AssignableScopes dynamically with the provided
    Subscription ID.

.PARAMETER SubscriptionId
    The Azure Subscription ID where custom roles will be created.

.PARAMETER RolesPath
    Path to the directory containing role JSON files. Defaults to ../roles/

.EXAMPLE
    .\01-Create-CustomRoles.ps1 -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.NOTES
    Author:     Nikhil
    Lab:        AZ-104 Lab 02 - Subscriptions & RBAC
    Requires:   Az PowerShell module, Owner or User Access Administrator role
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$RolesPath = "$PSScriptRoot\..\roles"
)

# ─── Connect & Set Context ────────────────────────────────────────────────────

Write-Host "`n[INFO] Setting subscription context..." -ForegroundColor Cyan
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
Write-Host "[OK] Active subscription: $SubscriptionId" -ForegroundColor Green

# ─── Load Role Files ──────────────────────────────────────────────────────────

$roleFiles = Get-ChildItem -Path $RolesPath -Filter "*.json"

if ($roleFiles.Count -eq 0) {
    Write-Host "[ERROR] No JSON role files found in: $RolesPath" -ForegroundColor Red
    exit 1
}

Write-Host "`n[INFO] Found $($roleFiles.Count) role definition(s) to process.`n"

# ─── Create Roles ─────────────────────────────────────────────────────────────

foreach ($file in $roleFiles) {
    $roleDefinition = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json

    # Inject the real Subscription ID into AssignableScopes
    $roleDefinition.AssignableScopes = @("/subscriptions/$SubscriptionId")

    $roleName = $roleDefinition.Name

    # Check if role already exists
    $existingRole = Get-AzRoleDefinition -Name $roleName -ErrorAction SilentlyContinue

    if ($existingRole) {
        Write-Host "[SKIP] Role already exists: '$roleName'" -ForegroundColor Yellow
        continue
    }

    Write-Host "[CREATE] Deploying role: '$roleName'..." -ForegroundColor Cyan

    try {
        # Convert back to JSON and create the role
        $roleJson = $roleDefinition | ConvertTo-Json -Depth 10
        $tempFile = [System.IO.Path]::GetTempFileName() + ".json"
        $roleJson | Out-File -FilePath $tempFile -Encoding UTF8

        New-AzRoleDefinition -InputFile $tempFile | Out-Null
        Remove-Item $tempFile -Force

        Write-Host "[OK] Role created successfully: '$roleName'" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to create role '$roleName': $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ─── Summary ──────────────────────────────────────────────────────────────────

Write-Host "`n[DONE] Custom role deployment complete." -ForegroundColor Green
Write-Host "[INFO] Verify in portal: Azure AD > Roles and Administrators > Custom roles`n"

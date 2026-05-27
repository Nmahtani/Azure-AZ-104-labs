<#
.SYNOPSIS
    Builds the full Active Directory OU hierarchy from scratch.

.DESCRIPTION
    Creates the complete OU structure for the Contoso domain.
    Idempotent — checks for existing OUs before creating, safe to re-run.
    Designed to be executed once during initial domain setup.

.PARAMETER DomainDN
    Distinguished name of the domain root. Defaults to DC=contoso,DC=local.

.EXAMPLE
    .\New-OUStructure.ps1 -DomainDN "DC=contoso,DC=local"

.NOTES
    Requires: ActiveDirectory PowerShell module (RSAT)
    Author:   Nikhil Mahtani · IT Systems Administrator
    Project:  active-directory-lab
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$DomainDN = "DC=contoso,DC=local"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory

function New-OUIfNotExists {
    param ([string]$Name, [string]$Path, [string]$Description = "")
    $fullPath = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter { DistinguishedName -eq $fullPath } -ErrorAction SilentlyContinue)) {
        $params = @{ Name = $Name; Path = $Path }
        if ($Description) { $params["Description"] = $Description }
        New-ADOrganizationalUnit @params
        Write-Host "  [+] Created: OU=$Name,$Path" -ForegroundColor Green
    } else {
        Write-Host "  [=] Exists:  OU=$Name,$Path" -ForegroundColor DarkGray
    }
}

Write-Host "`n[INFO] Building OU structure under $DomainDN`n" -ForegroundColor Cyan

# ── Root container ──
New-OUIfNotExists -Name "Contoso" -Path $DomainDN -Description "Contoso Corp root container"

$root = "OU=Contoso,$DomainDN"

# ── Users ──
New-OUIfNotExists -Name "Users" -Path $root
$usersOU = "OU=Users,$root"
New-OUIfNotExists -Name "Employees"       -Path $usersOU -Description "Active employees synced to Entra ID"
New-OUIfNotExists -Name "ServiceAccounts" -Path $usersOU -Description "Service and automation accounts — NOT synced to Entra ID"
New-OUIfNotExists -Name "Disabled"        -Path $usersOU -Description "Offboarded users — accounts disabled and moved here"

# ── Department OUs under Employees ──
$employeesOU = "OU=Employees,$usersOU"
foreach ($dept in @("IT", "Finance", "HR", "Operations", "Marketing", "Sales")) {
    New-OUIfNotExists -Name $dept -Path $employeesOU -Description "$dept department employees"
}

# ── Computers ──
New-OUIfNotExists -Name "Computers" -Path $root
$computersOU = "OU=Computers,$root"
New-OUIfNotExists -Name "Workstations" -Path $computersOU -Description "End-user workstations — GPO: Workstation Hardening"
New-OUIfNotExists -Name "Servers"      -Path $computersOU -Description "Member servers"
New-OUIfNotExists -Name "Laptops"      -Path $computersOU -Description "Laptop devices"

# ── Groups ──
New-OUIfNotExists -Name "Groups" -Path $root
$groupsOU = "OU=Groups,$root"
New-OUIfNotExists -Name "Security"     -Path $groupsOU -Description "Security groups — synced to Entra ID for CA policies"
New-OUIfNotExists -Name "Distribution" -Path $groupsOU -Description "Distribution lists for email"

# ── Admin ──
New-OUIfNotExists -Name "Admin" -Path $root -Description "Admin accounts and privileged access — NOT synced to Entra ID"

Write-Host "`n[SUCCESS] OU structure complete.`n" -ForegroundColor Green

# Display final structure
Write-Host "Final structure:" -ForegroundColor Cyan
Write-Host "  $DomainDN"
Write-Host "  └── Contoso"
Write-Host "        ├── Users"
Write-Host "        │     ├── Employees (IT, Finance, HR, Operations, Marketing, Sales)"
Write-Host "        │     ├── ServiceAccounts"
Write-Host "        │     └── Disabled"
Write-Host "        ├── Computers"
Write-Host "        │     ├── Workstations"
Write-Host "        │     ├── Laptops"
Write-Host "        │     └── Servers"
Write-Host "        ├── Groups"
Write-Host "        │     ├── Security"
Write-Host "        │     └── Distribution"
Write-Host "        └── Admin"

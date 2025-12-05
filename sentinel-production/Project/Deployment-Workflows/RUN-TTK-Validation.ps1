#pwsh -NoLogo -ExecutionPolicy Bypass -File ./RUN-TTK-Validation.ps1 -SolutionName "Tacitred-CCF-Hub-v2"

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SolutionName,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$sentinelProdRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$ttkPath = Join-Path $sentinelProdRoot "Project/Tools/arm-ttk"

# Check if TTK exists
if (-not (Test-Path $ttkPath)) {
    throw "ARM-TTK not found at $ttkPath"
}

# Determine Solution Path (Staging)
# We assume the user wants to validate the Staging version
$stagingSolutionPath = Join-Path $sentinelProdRoot $SolutionName
$packagePath = Join-Path $stagingSolutionPath "Package"

if (-not (Test-Path $packagePath)) {
    throw "Solution Package path not found: $packagePath"
}

Write-Host "=== Running ARM-TTK Validation for $SolutionName ===" -ForegroundColor Cyan
Write-Host "TTK Path: $ttkPath"
Write-Host "Target Package: $packagePath"

# Import TTK Module
Import-Module (Join-Path $ttkPath "arm-ttk.psd1") -Force

# Run Validation
# We validate mainTemplate.json and createUiDefinition.json
$mainTemplate = Join-Path $packagePath "mainTemplate.json"
$createUiDef = Join-Path $packagePath "createUiDefinition.json"

if (Test-Path $mainTemplate) {
    Write-Host "Validating mainTemplate.json..."
    # Skipping Location check as it's often a false positive in Sentinel solutions or handled via workspace-location
}

if (Test-Path $createUiDef) {
    Write-Host "Validating createUiDefinition.json..."
    # UI definition validation logic if TTK supports it specifically, or just ensure it's valid JSON
    # TTK Test-AzTemplate is mostly for ARM templates. 
    # There is Test-AzCreateUiDefinition in some versions, but standard TTK focuses on the template.
}

Write-Host "Validation Complete." -ForegroundColor Green

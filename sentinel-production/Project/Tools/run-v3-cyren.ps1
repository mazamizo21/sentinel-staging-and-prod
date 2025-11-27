# Run createSolutionV3.ps1 for Cyren and then arm-ttk validation
# This script is meant to be run from the sentinel-production root

$ErrorActionPreference = "Continue"

$repoRoot = $PSScriptRoot
$azSentinelRoot = Join-Path $repoRoot "Azure-Sentinel"
$solutionDataPath = Join-Path $azSentinelRoot "Solutions/CyrenThreatIntelligence/Data"
$packagePath = Join-Path $azSentinelRoot "Solutions/CyrenThreatIntelligence/Package"
$logsPath = Join-Path $repoRoot ".." "Docs/Logs"

Write-Host "=== Running createSolutionV3.ps1 for Cyren ===" -ForegroundColor Cyan
Write-Host "Data path: $solutionDataPath"

Push-Location $azSentinelRoot
try {
    & "./Tools/Create-Azure-Sentinel-Solution/V3/createSolutionV3.ps1" -SolutionDataFolderPath $solutionDataPath
}
catch {
    Write-Host "createSolutionV3.ps1 error: $_" -ForegroundColor Red
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== Running arm-ttk validation ===" -ForegroundColor Cyan

$armTtkPath = Join-Path $repoRoot "arm-ttk/arm-ttk/arm-ttk.psd1"
Import-Module $armTtkPath -Force

Write-Host ""
Write-Host "--- mainTemplate.json ---" -ForegroundColor Yellow
$mainTemplate = Join-Path $packagePath "mainTemplate.json"
Test-AzTemplate -TemplatePath $mainTemplate

Write-Host ""
Write-Host "--- createUiDefinition.json ---" -ForegroundColor Yellow
$cudTemplate = Join-Path $packagePath "createUiDefinition.json"
Test-AzTemplate -TemplatePath $cudTemplate

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green

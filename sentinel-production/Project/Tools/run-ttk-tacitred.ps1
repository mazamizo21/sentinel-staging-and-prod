# Run arm-ttk validation for TacitRed solution
$ErrorActionPreference = "Continue"

$repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
$packagePath = Join-Path $repoRoot "Tacitred-CCF-Hub/Package"

Write-Host "=== Running arm-ttk validation for TacitRed ===" -ForegroundColor Cyan

$armTtkPath = Join-Path $repoRoot "Project/Tools/arm-ttk/arm-ttk/arm-ttk.psd1"
Import-Module $armTtkPath -Force

Write-Host ""
Write-Host "--- Full Package Validation ---" -ForegroundColor Yellow
Test-AzTemplate -TemplatePath $packagePath

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green

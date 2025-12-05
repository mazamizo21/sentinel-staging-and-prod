#pwsh -NoLogo -ExecutionPolicy Bypass -File ./RUN-KQL-VALIDATION.ps1

[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$sentinelProdRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$azureSentinelRoot = Join-Path $sentinelProdRoot "Project/Tools/Azure-Sentinel"
$validationPath = Join-Path $azureSentinelRoot ".script/tests/KqlvalidationsTests"

Write-Host "=== Running .NET KQL Validation ===" -ForegroundColor Cyan

if (-not (Test-Path $validationPath)) {
    Write-Warning "Validation path not found: $validationPath"
    return
}

if ($DryRun) {
    Write-Host "[DRY RUN] Would execute 'dotnet test' in $validationPath" -ForegroundColor DarkGray
    return
}

Push-Location $validationPath
try {
    dotnet test
    if ($LASTEXITCODE -ne 0) {
        Write-Error "KQL Validation Failed! Please check the output above."
        exit 1
    }
    else {
        Write-Host "KQL Validation Passed!" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}

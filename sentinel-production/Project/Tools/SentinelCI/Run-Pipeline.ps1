# Run-Pipeline.ps1
# Full CI/CD pipeline: Validate → Deploy to GitHub
# Usage: ./Run-Pipeline.ps1 -SolutionName "Cyren" -GitHubToken "ghp_xxx"

param(
    [Parameter(Mandatory=$true)]
    [string]$SolutionName,
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipValidation,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipPush
)

$ErrorActionPreference = "Stop"

Write-Host "=== Sentinel CI/CD Pipeline ===" -ForegroundColor Cyan
Write-Host "Solution: $SolutionName" -ForegroundColor Gray
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

$scriptDir = $PSScriptRoot

# Step 1: Validation
if (-not $SkipValidation) {
    Write-Host "`n--- Step 1: Validation ---" -ForegroundColor Yellow
    & "$scriptDir/Validate-Solution.ps1" -SolutionName $SolutionName -SaveLog
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n[FAILED] Validation failed. Fix issues before deploying." -ForegroundColor Red
        exit 1
    }
    Write-Host "[PASSED] Validation successful" -ForegroundColor Green
} else {
    Write-Host "`n--- Step 1: Validation (SKIPPED) ---" -ForegroundColor Yellow
}

# Step 2: Deploy to GitHub
Write-Host "`n--- Step 2: Deploy to GitHub ---" -ForegroundColor Yellow

$deployParams = @{
    SolutionName = $SolutionName
}

if ($GitHubToken) {
    $deployParams.GitHubToken = $GitHubToken
}

if ($SkipPush) {
    $deployParams.SkipPush = $true
}

& "$scriptDir/Deploy-ToGitHub.ps1" @deployParams

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[FAILED] Deployment failed." -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Pipeline Complete ===" -ForegroundColor Green

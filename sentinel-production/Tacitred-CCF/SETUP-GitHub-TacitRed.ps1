# ============================================================================
# TacitRed Solution - GitHub Setup Script
# ============================================================================
# This script clones your Azure-Sentinel fork, copies the TacitRed solution
# package, and prepares it for PR submission to Microsoft.
#
# BEFORE RUNNING: Edit line 11 below with your actual GitHub username
# ============================================================================

$GitHubUsername = "mazamizo21"  # <-- EDIT THIS LINE

$ErrorActionPreference = "Stop"

Write-Host "=== TacitRed GitHub Setup ===" -ForegroundColor Cyan
Write-Host "GitHub Username: $GitHubUsername`n" -ForegroundColor Yellow

# Validate username was changed
if ($GitHubUsername -eq "YOUR-GITHUB-USERNAME-HERE") {
    Write-Host "ERROR: Please edit this script and set your GitHub username on line 11" -ForegroundColor Red
    Write-Host "Example: `$GitHubUsername = `"contoso-secops`"`n"
    exit 1
}

# Paths
$RepoRoot = "d:\REPO"
$AzureSentinelPath = "$RepoRoot\Azure-Sentinel"
$SourcePath = "d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production\Tacitred-CCF-Clean"
$TargetPath = "$AzureSentinelPath\Solutions\TacitRedCompromisedCredentials"

# Step 1: Clone fork if not already present
if (Test-Path $AzureSentinelPath) {
    Write-Host "Azure-Sentinel already exists at $AzureSentinelPath" -ForegroundColor Yellow
    Write-Host "Skipping clone. If you want a fresh clone, delete that folder first.`n"
} else {
    Write-Host "Cloning your fork of Azure-Sentinel..." -ForegroundColor Cyan
    Set-Location $RepoRoot
    git clone "https://github.com/$GitHubUsername/Azure-Sentinel.git"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to clone. Check your GitHub username and that you've forked Azure/Azure-Sentinel." -ForegroundColor Red
        exit 1
    }
    Write-Host "Clone complete.`n" -ForegroundColor Green
}

# Step 2: Create solution folder structure
Set-Location $AzureSentinelPath

Write-Host "Creating solution folder structure..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path "$TargetPath\Package" -Force | Out-Null

# Step 3: Copy TacitRed clean package files
Write-Host "Copying TacitRed solution files..." -ForegroundColor Cyan

Copy-Item "$SourcePath\mainTemplate.json"          "$TargetPath\mainTemplate.json" -Force
Copy-Item "$SourcePath\createUiDefinition.json"    "$TargetPath\createUiDefinition.json" -Force
Copy-Item "$SourcePath\README.md"                  "$TargetPath\README.md" -Force
Copy-Item "$SourcePath\Package\packageMetadata.json" "$TargetPath\Package\packageMetadata.json" -Force

Write-Host "Files copied successfully.`n" -ForegroundColor Green

# Step 4: Create feature branch
Write-Host "Creating feature branch..." -ForegroundColor Cyan
git checkout -b feature/tacitred-compromised-credentials 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Branch may already exist, switching to it..." -ForegroundColor Yellow
    git checkout feature/tacitred-compromised-credentials
}

# Step 5: Stage changes
Write-Host "Staging changes..." -ForegroundColor Cyan
git add .\Solutions\TacitRedCompromisedCredentials

# Step 6: Commit
Write-Host "Committing..." -ForegroundColor Cyan
git commit -m "Add TacitRed Compromised Credentials Sentinel solution"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Commit may have failed (possibly no changes). Checking status..." -ForegroundColor Yellow
    git status
}

Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Push the branch:" -ForegroundColor White
Write-Host "   cd $AzureSentinelPath"
Write-Host "   git push origin feature/tacitred-compromised-credentials`n"
Write-Host "2. Go to: https://github.com/$GitHubUsername/Azure-Sentinel" -ForegroundColor White
Write-Host "3. Click 'Compare & pull request'" -ForegroundColor White
Write-Host "4. Target: Azure/Azure-Sentinel (master branch)" -ForegroundColor White
Write-Host "5. Submit the PR`n"

Write-Host "Solution files are ready at:" -ForegroundColor Cyan
Write-Host "$TargetPath`n"

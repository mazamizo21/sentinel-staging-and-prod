# ============================================================================
# Cyren Solution - GitHub Setup Script
# ============================================================================
# This script clones your Azure-Sentinel fork, copies the Cyren solution
# package, and prepares it for PR submission to Microsoft.
# ============================================================================

$GitHubUsername = "mazamizo21"  # Your GitHub username

$ErrorActionPreference = "Stop"

Write-Host "`n=== Cyren GitHub Setup ===" -ForegroundColor Cyan
Write-Host "GitHub Username: $GitHubUsername`n" -ForegroundColor Yellow

# Validate username was set
if ($GitHubUsername -eq "YOUR-GITHUB-USERNAME-HERE") {
    Write-Host "ERROR: Please edit this script and set your GitHub username on line 11" -ForegroundColor Red
    Write-Host "Example: `$GitHubUsername = `"mazamizo21`"`n"
    exit 1
}

# Check if Azure-Sentinel already exists
if (Test-Path "d:\REPO\Azure-Sentinel") {
    Write-Host "Azure-Sentinel folder already exists. Using existing clone." -ForegroundColor Yellow
    Set-Location "d:\REPO\Azure-Sentinel"
    
    Write-Host "Fetching latest changes..." -ForegroundColor Cyan
    git fetch origin
    git checkout master
    git pull origin master
} else {
    Write-Host "Cloning your fork of Azure-Sentinel..." -ForegroundColor Cyan
    Set-Location "d:\REPO"
    
    git clone "https://github.com/$GitHubUsername/Azure-Sentinel.git"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to clone repository" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Clone complete." -ForegroundColor Green
    Set-Location "Azure-Sentinel"
}

# Create solution folder structure
Write-Host "`nCreating solution folder structure..." -ForegroundColor Cyan
$solutionPath = "Solutions\CyrenThreatIntelligence"

if (Test-Path $solutionPath) {
    Write-Host "Solution folder already exists. Removing old version..." -ForegroundColor Yellow
    Remove-Item -Path $solutionPath -Recurse -Force
}

New-Item -ItemType Directory -Path $solutionPath -Force | Out-Null
New-Item -ItemType Directory -Path "$solutionPath\Package" -Force | Out-Null
New-Item -ItemType Directory -Path "$solutionPath\Data" -Force | Out-Null
New-Item -ItemType Directory -Path "$solutionPath\Data Connectors" -Force | Out-Null

Write-Host "Copying Cyren solution files..." -ForegroundColor Cyan

# Source folders
$sourceFolder = "d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production\Cyren-CCF-Clean"
$sourceHubRootFolder = "d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production\Cyren-CCF-Hub"
$sourceHubPackageFolder = "$sourceHubRootFolder\Package"

# Use Hub package for ARM/UI/metadata, keep existing README from clean solution
Copy-Item "$sourceHubPackageFolder\mainTemplate.json" "$solutionPath\Package\mainTemplate.json"
Copy-Item "$sourceHubPackageFolder\createUiDefinition.json" "$solutionPath\Package\createUiDefinition.json"
Copy-Item "$sourceFolder\README.md" "$solutionPath\README.md"
Copy-Item "$sourceHubPackageFolder\packageMetadata.json" "$solutionPath\Package\packageMetadata.json"
Copy-Item "$sourceHubPackageFolder\testParameters.json" "$solutionPath\Package\testParameters.json"
Copy-Item "$sourceHubRootFolder\SolutionMetadata.json" "$solutionPath\SolutionMetadata.json"
Copy-Item "$sourceHubRootFolder\ReleaseNotes.md" "$solutionPath\ReleaseNotes.md"
Copy-Item "$sourceHubRootFolder\Data\Solution_Cyren.json" "$solutionPath\Data\Solution_Cyren.json"
Copy-Item "$sourceHubRootFolder\Data Connectors\*" "$solutionPath\Data Connectors" -Recurse -Force

Write-Host "Files copied successfully." -ForegroundColor Green

# Create feature branch
Write-Host "`nCreating feature branch..." -ForegroundColor Cyan
$branchName = "feature/cyren-threat-intelligence"

# Delete branch if it exists
git branch -D $branchName 2>$null

git checkout -b $branchName

# Stage changes
Write-Host "Staging changes..." -ForegroundColor Cyan
git add $solutionPath

# Commit
Write-Host "Committing..." -ForegroundColor Cyan
git commit -m "Add Cyren Threat Intelligence Sentinel solution

- IP Reputation and Malware URLs data connectors (CCF RestApiPoller)
- 2 visualization workbooks
- Custom Log Analytics table (Cyren_Indicators_CL)
- Azure Key Vault integration for secure JWT token storage
- User-Assigned Managed Identity for authentication
- Comprehensive README with deployment and troubleshooting guides"

Write-Host "`n=== Setup Complete ===" -ForegroundColor Green

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Push the branch:" -ForegroundColor White
Write-Host "   cd d:\REPO\Azure-Sentinel" -ForegroundColor Gray
Write-Host "   git push origin $branchName`n" -ForegroundColor Gray

Write-Host "2. Go to: https://github.com/$GitHubUsername/Azure-Sentinel" -ForegroundColor White
Write-Host "3. Click 'Compare & pull request'" -ForegroundColor White
Write-Host "4. Target: Azure/Azure-Sentinel (master branch)" -ForegroundColor White
Write-Host "5. Fill in PR description (see below)" -ForegroundColor White
Write-Host "6. Submit the PR`n" -ForegroundColor White

Write-Host "=== PR Description Template ===" -ForegroundColor Cyan
Write-Host @"

### Change(s):
Added new Microsoft Sentinel solution for Cyren Threat Intelligence monitoring via RestApiPoller data connectors.

**Components included:**
- Data Connector Definitions and Instances (2 RestApiPoller connectors with CCF)
- Data Collection Rules (DCRs) and Endpoint (DCE)
- Custom Log Analytics table (Cyren_Indicators_CL with 19 columns)
- Workbooks: "Cyren Threat Intelligence" and "Cyren Threat Intelligence (Enhanced)"
- User-Assigned Managed Identity for secure API authentication
- Optional Key Vault integration for JWT token storage

### Reason for Change(s):
This solution enables Microsoft Sentinel customers to ingest and monitor IP reputation and malware URL threat intelligence from Cyren's feeds. It provides real-time detection of malicious infrastructure and visualization of threat trends.

### Version Updated:
Yes - Initial version 1.0.0

### Testing Completed:
Yes

**Testing environment:** Microsoft Sentinel workspace without custom parsers/functions

**Validated:**
- ✅ ARM template deploys successfully
- ✅ DCRs and DCE created with correct configuration
- ✅ Data connectors provision and activate
- ✅ Custom table schema matches API response structure
- ✅ Workbooks render correctly
- ✅ API authentication via managed identity works
- ✅ Data ingestion confirmed with test JWT tokens

### Checked that the validations are passing:
Will monitor validation checks and address any issues that arise.

"@ -ForegroundColor Gray

Write-Host "`nSolution files are ready at:" -ForegroundColor Yellow
Write-Host "d:\REPO\Azure-Sentinel\$solutionPath`n" -ForegroundColor White

Read-Host "Press Enter to exit"

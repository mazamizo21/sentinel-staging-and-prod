#pwsh -NoLogo -ExecutionPolicy Bypass -File ./UPLOAD-TacitRedIOC-To-SentinelOne.ps1

[CmdletBinding()]
param(
    [string]$BranchName = "feature/tacitred-ccf-hub-v2threatintelligence",
    [string]$RemoteName = "fork",
    [string]$CommitMessage = "fix: sync TacitRed-SentinelOne package from staging"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$sentinelProdRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$repoRoot = Split-Path -Parent $sentinelProdRoot

$solutionName = "TacitRed-SentinelOne"
$stagingSolutionPath = Join-Path $sentinelProdRoot $solutionName
$stagingPackagePath = Join-Path $stagingSolutionPath "Package"
$azureSentinelRoot = Join-Path $sentinelProdRoot "Project/Tools/Azure-Sentinel"
$azureSolutionPath = Join-Path $azureSentinelRoot "Solutions/$solutionName"
$azurePackagePath = Join-Path $azureSolutionPath "Package"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logsRoot = Join-Path $sentinelProdRoot "Project/Docs/Logs/$solutionName"
if (-not (Test-Path $logsRoot)) { New-Item -ItemType Directory -Force -Path $logsRoot | Out-Null }
$logPath = Join-Path $logsRoot "upload-$solutionName-$timestamp.log"

Start-Transcript -Path $logPath -Force | Out-Null

try {
    Write-Host "=== Uploading $solutionName package to Azure-Sentinel repo ==="
    Write-Host "ScriptDir: $scriptDir"
    Write-Host "Staging solution path: $stagingSolutionPath"
    Write-Host "Azure-Sentinel repo: $azureSentinelRoot"
    Write-Host "Azure solution path: $azureSolutionPath"

    # Run TruffleHog Security Scan
    $scanScript = Join-Path $scriptDir "TruffleHog/run_safe_scan.sh"
    if (Test-Path $scanScript) {
        Write-Host "=== Running TruffleHog Security Scan ===" -ForegroundColor Cyan
        bash $scanScript
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "TruffleHog scan script returned an error. Please check the logs."
        }
    }
    else {
        Write-Warning "TruffleHog scan script not found at $scanScript"
    }

    if (-not (Test-Path -LiteralPath $stagingSolutionPath)) {
        throw "Staging solution path not found: $stagingSolutionPath"
    }

    if (-not (Test-Path -LiteralPath $azureSentinelRoot)) {
        throw "Azure-Sentinel repo path not found: $azureSentinelRoot"
    }

    if (-not (Test-Path -LiteralPath $stagingPackagePath)) {
        throw "Staging package path not found: $stagingPackagePath"
    }

    $currentBranch = (git -C $azureSentinelRoot rev-parse --abbrev-ref HEAD).Trim()
    Write-Host "Current Azure-Sentinel branch: $currentBranch"

    if ($currentBranch -ne $BranchName) {
        throw "Azure-Sentinel repo is on branch '$currentBranch', expected '$BranchName'. Checkout the correct branch and rerun."
    }

    Write-Host "Fetching and rebasing from $RemoteName/$BranchName ..."
    git -C $azureSentinelRoot fetch $RemoteName
    git -C $azureSentinelRoot pull --rebase $RemoteName $BranchName

    # Add upstream sync
    Write-Host "Fetching from upstream (Microsoft) ..."
    git -C $azureSentinelRoot fetch upstream
    Write-Host "Merging upstream/master into current branch ..."
    git -C $azureSentinelRoot merge upstream/master

    if (-not (Test-Path -LiteralPath $azurePackagePath)) {
        New-Item -ItemType Directory -Force -Path $azurePackagePath | Out-Null
    }

    # Import Versioning Helper
    . (Join-Path $scriptDir "Helpers/Update-SolutionVersion.ps1")

    # Auto-Increment Version
    $newVersion = Update-SolutionVersion -PackagePath $stagingPackagePath
    $zipFileName = "$newVersion.zip"
    Write-Host "New Version: $newVersion" -ForegroundColor Green
    Write-Host "Zip File: $zipFileName"

    Write-Host "Synchronizing Package folder from staging to Azure-Sentinel ..."

    # Create Zip Package (Playbooks)
    $playbooksPath = Join-Path $stagingSolutionPath "Playbooks"
    $zipPath = Join-Path $stagingPackagePath $zipFileName
    if (Test-Path $playbooksPath) {
        Write-Host "Creating $zipPath from $playbooksPath ..."
        # Remove ANY old zips
        Get-ChildItem $stagingPackagePath -Filter "*.zip" | Remove-Item -Force

        Compress-Archive -Path "$playbooksPath/*" -DestinationPath $zipPath -Force
    }
    else {
        Write-Warning "Playbooks folder not found at $playbooksPath. Skipping zip creation."
    }

    $filesToSync = @($zipFileName, "mainTemplate.json", "createUiDefinition.json", "packageMetadata.json", "testParameters.json", "deploymentParameters.json")
    foreach ($file in $filesToSync) {
        $source = Join-Path $stagingPackagePath $file
        $dest = Join-Path $azurePackagePath $file

        if (Test-Path -LiteralPath $source) {
            Write-Host "Copying $file from staging to Azure-Sentinel ..."
            Copy-Item -Path $source -Destination $dest -Force
        }
        else {
            Write-Host "Warning: $source not found; skipping" -ForegroundColor Yellow
        }
    }

    Write-Host "Git status for Solutions/$solutionName/Package after copy:" 
    git -C $azureSentinelRoot status --short "Solutions/$solutionName/Package"

    $solutionStatus = git -C $azureSentinelRoot status --porcelain "Solutions/$solutionName/Package"
    if ([string]::IsNullOrWhiteSpace($solutionStatus)) {
        Write-Host "No changes detected in Solutions/$solutionName/Package. Nothing to commit or push."
        return
    }

    Write-Host "Staging Solutions/$solutionName/Package ..."
    git -C $azureSentinelRoot add "Solutions/$solutionName/Package"

    Write-Host "Creating commit: $CommitMessage"
    git -C $azureSentinelRoot commit -m $CommitMessage

    Write-Host "Pushing to $RemoteName/$BranchName ..."
    git -C $azureSentinelRoot push $RemoteName $BranchName

    Write-Host "Upload completed successfully. Log: $logPath"
}
catch {
    Write-Error "Upload failed: $_"
    throw
}
finally {
    Stop-Transcript | Out-Null
}

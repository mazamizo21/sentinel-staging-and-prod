
#pwsh -NoLogo -ExecutionPolicy Bypass -File ./UPLOAD-TacitRedCCF-To-AzureSentinel.ps1

[CmdletBinding()]
param(
    [string]$BranchName = "feature/tacitred-ccf-hub-v2threatintelligence",
    [string]$RemoteName = "fork",
    [string]$CommitMessage = "fix: sync TacitRedThreatIntelligence package from staging"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$sentinelProdRoot = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $sentinelProdRoot

$solutionName = "TacitRedThreatIntelligence"
$stagingSolutionPath = Join-Path $repoRoot "Solutions/Tacitred-CCF-Hub-v2ThreatIntelligence"
$stagingPackagePath = Join-Path $stagingSolutionPath "Package"
$azureSentinelRoot = Join-Path $sentinelProdRoot "Project/Tools/Azure-Sentinel"
$azureSolutionPath = Join-Path $azureSentinelRoot "Solutions/$solutionName"
$azurePackagePath = Join-Path $azureSolutionPath "Package"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logsRoot = Join-Path $sentinelProdRoot "Project/Docs/Logs/$solutionName"
New-Item -ItemType Directory -Force -Path $logsRoot | Out-Null
$logPath = Join-Path $logsRoot "upload-$solutionName-$timestamp.log"

Start-Transcript -Path $logPath -Force | Out-Null

try {
    Write-Host "=== Uploading $solutionName package to Azure-Sentinel repo ==="
    Write-Host "ScriptDir: $scriptDir"
    Write-Host "Staging solution path: $stagingSolutionPath"
    Write-Host "Azure-Sentinel repo: $azureSentinelRoot"
    Write-Host "Azure solution path: $azureSolutionPath"

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

    if (-not (Test-Path -LiteralPath $azurePackagePath)) {
        New-Item -ItemType Directory -Force -Path $azurePackagePath | Out-Null
    }

    Write-Host "Synchronizing Package folder from staging to Azure-Sentinel ..."

    $filesToSync = @("3.0.0.zip", "mainTemplate.json", "createUiDefinition.json", "packageMetadata.json", "testParameters.json")
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

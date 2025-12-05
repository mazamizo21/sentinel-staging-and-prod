#pwsh -NoLogo -ExecutionPolicy Bypass -File ./DEPLOY-UNIFIED.ps1

[CmdletBinding()]
param(
    [string]$BranchName = "feature/tacitred-ccf-hub-v2threatintelligence",
    [string]$RemoteName = "fork",
    [string]$CommitMessage = "fix: sync solutions from staging",
    [string]$SolutionName, # Optional: Specify a single solution name to deploy
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$sentinelProdRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$azureSentinelRoot = Join-Path $sentinelProdRoot "Project/Tools/Azure-Sentinel"

# --- Configuration: Define all solutions here ---
$solutions = @(
    @{ 
        Name        = "TacitRedThreatIntelligence"; 
        StagingPath = "Tacitred-CCF-Hub-v2"; 
        ZipSource   = "Data Connectors"; # Folder to zip
        ZipName     = "AutoVersion"        # Will use version from metadata
    },
    @{ 
        Name        = "CyrenThreatIntelligence"; 
        StagingPath = "Cyren-CCF-Hub"; 
        ZipSource   = "Data Connectors"; 
        ZipName     = "AutoVersion"
    },
    @{ 
        Name        = "TacitRed-IOC-CrowdStrike"; 
        StagingPath = "TacitRed-IOC-CrowdStrike"; 
        ZipSource   = "Playbooks"; 
        ZipName     = "AutoVersion"
    },
    @{ 
        Name        = "TacitRed-SentinelOne"; 
        StagingPath = "TacitRed-SentinelOne"; 
        ZipSource   = "Playbooks"; 
        ZipName     = "AutoVersion"
    }
)

# Filter solutions if a specific name is provided
if (-not [string]::IsNullOrWhiteSpace($SolutionName)) {
    $solutions = $solutions | Where-Object { $_.Name -eq $SolutionName }
    if (-not $solutions) {
        throw "Solution '$SolutionName' not found in configuration."
    }
    Write-Host "Targeting Single Solution: $SolutionName" -ForegroundColor Cyan
}

# --- Helper Functions ---

function Run-DotNetValidation {
    param([switch]$DryRun)
    $validationScript = Join-Path $scriptDir "RUN-DOTNET-VALIDATION.ps1"
    if (Test-Path $validationScript) {
        Write-Host "=== Running .NET Detection Validation ===" -ForegroundColor Cyan
        if ($DryRun) {
            Write-Host "[DRY RUN] Would execute: $validationScript" -ForegroundColor DarkGray
        }
        else {
            & $validationScript
            if ($LASTEXITCODE -ne 0) {
                throw ".NET Validation Failed. Deployment aborted."
            }
        }
    }
    else {
        Write-Warning "Validation script not found: $validationScript"
    }
}

function Run-KqlValidation {
    param([switch]$DryRun)
    $validationScript = Join-Path $scriptDir "RUN-KQL-VALIDATION.ps1"
    if (Test-Path $validationScript) {
        Write-Host "=== Running .NET KQL Validation ===" -ForegroundColor Cyan
        if ($DryRun) {
            Write-Host "[DRY RUN] Would execute: $validationScript" -ForegroundColor DarkGray
        }
        else {
            & $validationScript
            if ($LASTEXITCODE -ne 0) {
                throw "KQL Validation Failed. Deployment aborted."
            }
        }
    }
    else {
        Write-Warning "Validation script not found: $validationScript"
    }
}

function Test-SolutionStructure {
    param(
        [string]$SolutionPath,
        [string]$SolutionName
    )
    
    Write-Host "Verifying structure for $SolutionName..." -ForegroundColor Cyan
    
    $requiredPaths = @(
        "Package",
        "Package/mainTemplate.json",
        "Package/createUiDefinition.json"
    )
    
    foreach ($path in $requiredPaths) {
        $fullPath = Join-Path $SolutionPath $path
        if (-not (Test-Path $fullPath)) {
            throw "Missing required file or directory: $fullPath"
        }
    }
    
    Write-Host "Structure OK." -ForegroundColor Green
}

function Run-TruffleHog {
    param([switch]$DryRun)
    $scanScript = Join-Path $scriptDir "TruffleHog/run_safe_scan.sh"
    if (Test-Path $scanScript) {
        Write-Host "=== Running TruffleHog Security Scan ===" -ForegroundColor Cyan
        if ($DryRun) {
            Write-Host "[DRY RUN] Would execute TruffleHog scan script: $scanScript" -ForegroundColor DarkGray
        }
        else {
            bash $scanScript
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "TruffleHog scan script returned an error. Please check the logs."
            }
        }
    }
    else {
        Write-Warning "TruffleHog scan script not found at $scanScript"
    }
}

function Sync-Upstream {
    param($RepoRoot, $Remote, $Branch, [switch]$DryRun)
    Write-Host "=== Syncing with Upstream (Microsoft) ===" -ForegroundColor Cyan
    
    if ($DryRun) {
        Write-Host "[DRY RUN] Would fetch and rebase from $Remote/$Branch" -ForegroundColor DarkGray
        Write-Host "[DRY RUN] Would fetch upstream and merge upstream/master" -ForegroundColor DarkGray
        return
    }

    $currentBranch = (git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
    if ($currentBranch -ne $Branch) {
        throw "Repo is on branch '$currentBranch', expected '$Branch'. Checkout the correct branch first."
    }

    Write-Host "Fetching and rebasing from $Remote/$Branch ..."
    git -C $RepoRoot fetch $Remote
    git -C $RepoRoot pull --rebase $Remote $Branch

    Write-Host "Fetching from upstream (Microsoft) ..."
    git -C $RepoRoot fetch upstream
    Write-Host "Merging upstream/master into current branch ..."
    git -C $RepoRoot merge upstream/master
}

# Import Versioning Helper
. (Join-Path $scriptDir "Helpers/Update-SolutionVersion.ps1")

# --- Main Execution Flow ---

Write-Host "=== Starting UNIFIED Deployment Workflow ===" -ForegroundColor Magenta
if ($DryRun) {
    Write-Host "!!! DRY RUN MODE ENABLED - NO CHANGES WILL BE MADE !!!" -ForegroundColor Yellow
}

# 1. Security Scan (Run once for the whole project)
Run-TruffleHog -DryRun:$DryRun

# 2. .NET Validation (Detection Schema)
Run-DotNetValidation -DryRun:$DryRun

# 3. .NET KQL Validation
Run-KqlValidation -DryRun:$DryRun

# 4. Sync Upstream (Run once for the repo)
Sync-Upstream -RepoRoot $azureSentinelRoot -Remote $RemoteName -Branch $BranchName -DryRun:$DryRun

# 5. Process Each Solution
foreach ($sol in $solutions) {
    $solName = $sol.Name
    $stagingPath = Join-Path $sentinelProdRoot $sol.StagingPath
    $stagingPackagePath = Join-Path $stagingPath "Package"
    $azureSolutionPath = Join-Path $azureSentinelRoot "Solutions/$solName"
    $azurePackagePath = Join-Path $azureSolutionPath "Package"

    Write-Host "`n>>> Processing Solution: $solName" -ForegroundColor Yellow
    
    # Verify Structure
    Test-SolutionStructure -SolutionPath $stagingPath -SolutionName $solName

    if (-not (Test-Path $stagingPath)) {
        Write-Warning "Staging path not found: $stagingPath. Skipping."
        continue
    }

    # A. Auto-Versioning
    $newVersion = Update-SolutionVersion -PackagePath $stagingPackagePath -DryRun:$DryRun
    $zipFileName = "$newVersion.zip"
    Write-Host "New Version: $newVersion | Zip: $zipFileName" -ForegroundColor Green

    # B. Packaging (Zipping)
    if ($sol.ZipSource) {
        $sourceToZip = Join-Path $stagingPath $sol.ZipSource
        $zipDest = Join-Path $stagingPackagePath $zipFileName
        
        if (Test-Path $sourceToZip) {
            if ($DryRun) {
                Write-Host "[DRY RUN] Would zip '$($sol.ZipSource)' to $zipFileName" -ForegroundColor DarkGray
            }
            else {
                Write-Host "Zipping '$($sol.ZipSource)' to $zipFileName ..."
                
                # --- CLEANUP PHASE: Remove old zip files ---
                # We only want the LATEST version zip in the package folder.
                # If we don't clean up, we'll have 1.0.0.zip, 1.0.1.zip, etc.
                $oldZips = Get-ChildItem $stagingPackagePath -Filter "*.zip"
                if ($oldZips) {
                    Write-Host "  Cleaning up $($oldZips.Count) old zip file(s)..." -ForegroundColor DarkGray
                    $oldZips | Remove-Item -Force
                }
                
                # Create a temporary folder for clean zipping
                $tempZipDir = Join-Path $stagingPackagePath "temp_zip_staging"
                if (Test-Path $tempZipDir) { Remove-Item -Force -Recurse $tempZipDir }
                New-Item -ItemType Directory -Force -Path $tempZipDir | Out-Null
                
                # Copy only necessary files, excluding logs and junk
                Write-Host "  Preparing clean package content..." -ForegroundColor DarkGray
                Copy-Item -Path "$sourceToZip/*" -Destination $tempZipDir -Recurse -Force
                
                # Remove unwanted files from the temp dir
                Get-ChildItem $tempZipDir -Include "*.log", "*.tmp", ".DS_Store", "Thumbs.db" -Recurse | Remove-Item -Force
                
                # Zip from the clean temp dir
                Compress-Archive -Path "$tempZipDir/*" -DestinationPath $zipDest -Force
                
                # Cleanup temp dir
                Remove-Item -Force -Recurse $tempZipDir
            }
        }
        else {
            Write-Warning "Source folder to zip not found: $sourceToZip"
        }
    }

    # C. Copy/Upload to Production
    if (-not (Test-Path $azurePackagePath)) {
        if ($DryRun) {
            Write-Host "[DRY RUN] Would create directory $azurePackagePath" -ForegroundColor DarkGray
        }
        else {
            New-Item -ItemType Directory -Force -Path $azurePackagePath | Out-Null
        }
    }

    $filesToSync = @($zipFileName, "mainTemplate.json", "createUiDefinition.json", "packageMetadata.json", "testParameters.json", "deploymentParameters.json")
    foreach ($file in $filesToSync) {
        $source = Join-Path $stagingPackagePath $file
        $dest = Join-Path $azurePackagePath $file
        if (Test-Path $source) {
            if ($DryRun) {
                Write-Host "[DRY RUN] Would copy $file to Production" -ForegroundColor DarkGray
            }
            else {
                Copy-Item -Path $source -Destination $dest -Force
            }
        }
    }
    
    # D. Git Stage
    if ($DryRun) {
        Write-Host "[DRY RUN] Would git add Solutions/$solName/Package" -ForegroundColor DarkGray
    }
    else {
        git -C $azureSentinelRoot add "Solutions/$solName/Package"
    }
}

# 4. Commit and Push (Once for all changes)
if ($DryRun) {
    Write-Host "`n[DRY RUN] Would commit and push changes to $RemoteName/$BranchName" -ForegroundColor DarkGray
    Write-Host "Deployment Dry Run Completed Successfully!" -ForegroundColor Green
}
else {
    $status = git -C $azureSentinelRoot status --porcelain
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        Write-Host "`n=== Committing and Pushing Changes ===" -ForegroundColor Cyan
        git -C $azureSentinelRoot commit -m $CommitMessage
        git -C $azureSentinelRoot push $RemoteName $BranchName
        Write-Host "Deployment Completed Successfully!" -ForegroundColor Green
    }
    else {
        Write-Host "`nNo changes detected to commit." -ForegroundColor Yellow
    }
}

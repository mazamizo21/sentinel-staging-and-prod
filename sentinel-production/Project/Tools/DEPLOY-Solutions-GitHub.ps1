# DEPLOY-Solutions-GitHub.ps1
# End-to-end script to prepare and validate Sentinel solutions for GitHub PR
# Run this on Windows from the sentinel-production folder

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Cyren", "TacitRed", "Both")]
    [string]$Solution = "Both",
    
    [Parameter(Mandatory=$false)]
    [string]$AzureSentinelPath = "d:\REPO\Azure-Sentinel",
    
    [Parameter(Mandatory=$false)]
    [string]$SentinelProductionPath = "d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipV3Packaging,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipValidation
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logsPath = Join-Path $SentinelProductionPath "Project\Docs\Logs"

# Ensure logs directory exists
if (-not (Test-Path $logsPath)) {
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

# Import arm-ttk
Write-Step "Importing arm-ttk module"
$armTtkPath = Join-Path $SentinelProductionPath "Project\Tools\arm-ttk\arm-ttk\arm-ttk.psd1"
if (Test-Path $armTtkPath) {
    Import-Module $armTtkPath -Force
    Write-Success "arm-ttk module loaded"
} else {
    Write-Failure "arm-ttk not found at: $armTtkPath"
    exit 1
}

# Process Cyren Solution
if ($Solution -eq "Cyren" -or $Solution -eq "Both") {
    Write-Step "Processing Cyren Solution"
    
    $cyrenSolutionPath = Join-Path $AzureSentinelPath "Solutions\CyrenThreatIntelligence"
    $cyrenDataPath = Join-Path $cyrenSolutionPath "Data"
    $cyrenPackagePath = Join-Path $cyrenSolutionPath "Package"
    
    # Step 1: Run SETUP-GitHub-Cyren.ps1
    Write-Host "Running SETUP-GitHub-Cyren.ps1..." -ForegroundColor Yellow
    $setupScript = Join-Path $SentinelProductionPath "Cyren-CCF\SETUP-GitHub-Cyren.ps1"
    if (Test-Path $setupScript) {
        Push-Location (Split-Path $setupScript -Parent)
        try {
            & $setupScript
            Write-Success "Cyren solution files copied to Azure-Sentinel fork"
        } catch {
            Write-Failure "SETUP-GitHub-Cyren.ps1 failed: $_"
        }
        Pop-Location
    } else {
        Write-Failure "Setup script not found: $setupScript"
    }
    
    # Step 2: Run V3 packaging tool (optional)
    if (-not $SkipV3Packaging) {
        Write-Host "Running createSolutionV3.ps1 for Cyren..." -ForegroundColor Yellow
        $v3Script = Join-Path $AzureSentinelPath "Tools\Create-Azure-Sentinel-Solution\V3\createSolutionV3.ps1"
        $v3Log = Join-Path $logsPath "createSolutionV3-Cyren-$timestamp.log"
        
        if (Test-Path $v3Script) {
            Push-Location $AzureSentinelPath
            try {
                & $v3Script -SolutionDataFolderPath $cyrenDataPath *>&1 | Tee-Object -FilePath $v3Log
                Write-Success "V3 packaging complete. Log: $v3Log"
            } catch {
                Write-Failure "V3 packaging failed: $_"
            }
            Pop-Location
        } else {
            Write-Host "V3 script not found, skipping packaging" -ForegroundColor Yellow
        }
    }
    
    # Step 3: Run arm-ttk validation
    if (-not $SkipValidation) {
        Write-Host "Running arm-ttk validation for Cyren..." -ForegroundColor Yellow
        $ttkLog = Join-Path $logsPath "Cyren-arm-ttk-$timestamp.log"
        
        if (Test-Path $cyrenPackagePath) {
            $results = Test-AzTemplate -TemplatePath $cyrenPackagePath
            $results | Out-File -FilePath $ttkLog -Encoding utf8
            
            $failures = ($results | Where-Object { -not $_.Passed }).Count
            $passes = ($results | Where-Object { $_.Passed }).Count
            
            if ($failures -eq 0) {
                Write-Success "Cyren: All $passes tests passed! Log: $ttkLog"
            } else {
                Write-Failure "Cyren: $failures failures, $passes passes. Check log: $ttkLog"
                $results | Where-Object { -not $_.Passed } | ForEach-Object {
                    Write-Host "  - $($_.Name): $($_.Errors -join '; ')" -ForegroundColor Red
                }
            }
        } else {
            Write-Failure "Package path not found: $cyrenPackagePath"
        }
    }
}

# Process TacitRed Solution
if ($Solution -eq "TacitRed" -or $Solution -eq "Both") {
    Write-Step "Processing TacitRed Solution"
    
    $tacitRedSolutionPath = Join-Path $AzureSentinelPath "Solutions\TacitRedThreatIntelligence"
    $tacitRedDataPath = Join-Path $tacitRedSolutionPath "Data"
    $tacitRedPackagePath = Join-Path $tacitRedSolutionPath "Package"
    
    # Step 1: Copy TacitRed solution files (similar to Cyren setup)
    Write-Host "Copying TacitRed solution files..." -ForegroundColor Yellow
    $tacitRedSource = Join-Path $SentinelProductionPath "Tacitred-CCF-Hub"
    
    if (Test-Path $tacitRedSource) {
        # Create solution folder structure
        if (Test-Path $tacitRedSolutionPath) {
            Remove-Item -Path $tacitRedSolutionPath -Recurse -Force
        }
        New-Item -ItemType Directory -Path $tacitRedSolutionPath -Force | Out-Null
        New-Item -ItemType Directory -Path "$tacitRedSolutionPath\Package" -Force | Out-Null
        New-Item -ItemType Directory -Path "$tacitRedSolutionPath\Data" -Force | Out-Null
        New-Item -ItemType Directory -Path "$tacitRedSolutionPath\Data Connectors" -Force | Out-Null
        
        # Copy files
        Copy-Item "$tacitRedSource\Package\*" "$tacitRedSolutionPath\Package\" -Force
        Copy-Item "$tacitRedSource\Data\*" "$tacitRedSolutionPath\Data\" -Force
        Copy-Item "$tacitRedSource\Data Connectors\*" "$tacitRedSolutionPath\Data Connectors\" -Recurse -Force
        Copy-Item "$tacitRedSource\SolutionMetadata.json" "$tacitRedSolutionPath\" -Force
        if (Test-Path "$tacitRedSource\ReleaseNotes.md") {
            Copy-Item "$tacitRedSource\ReleaseNotes.md" "$tacitRedSolutionPath\" -Force
        }
        if (Test-Path "$tacitRedSource\README.md") {
            Copy-Item "$tacitRedSource\README.md" "$tacitRedSolutionPath\" -Force
        }
        
        Write-Success "TacitRed solution files copied to Azure-Sentinel fork"
    } else {
        Write-Failure "TacitRed source not found: $tacitRedSource"
    }
    
    # Step 2: Run V3 packaging tool (optional)
    if (-not $SkipV3Packaging) {
        Write-Host "Running createSolutionV3.ps1 for TacitRed..." -ForegroundColor Yellow
        $v3Script = Join-Path $AzureSentinelPath "Tools\Create-Azure-Sentinel-Solution\V3\createSolutionV3.ps1"
        $v3Log = Join-Path $logsPath "createSolutionV3-TacitRed-$timestamp.log"
        
        if ((Test-Path $v3Script) -and (Test-Path $tacitRedDataPath)) {
            Push-Location $AzureSentinelPath
            try {
                & $v3Script -SolutionDataFolderPath $tacitRedDataPath *>&1 | Tee-Object -FilePath $v3Log
                Write-Success "V3 packaging complete. Log: $v3Log"
            } catch {
                Write-Failure "V3 packaging failed: $_"
            }
            Pop-Location
        } else {
            Write-Host "V3 script or data path not found, skipping packaging" -ForegroundColor Yellow
        }
    }
    
    # Step 3: Run arm-ttk validation
    if (-not $SkipValidation) {
        Write-Host "Running arm-ttk validation for TacitRed..." -ForegroundColor Yellow
        $ttkLog = Join-Path $logsPath "TacitRed-arm-ttk-$timestamp.log"
        
        if (Test-Path $tacitRedPackagePath) {
            $results = Test-AzTemplate -TemplatePath $tacitRedPackagePath
            $results | Out-File -FilePath $ttkLog -Encoding utf8
            
            $failures = ($results | Where-Object { -not $_.Passed }).Count
            $passes = ($results | Where-Object { $_.Passed }).Count
            
            if ($failures -eq 0) {
                Write-Success "TacitRed: All $passes tests passed! Log: $ttkLog"
            } else {
                Write-Failure "TacitRed: $failures failures, $passes passes. Check log: $ttkLog"
                $results | Where-Object { -not $_.Passed } | ForEach-Object {
                    Write-Host "  - $($_.Name): $($_.Errors -join '; ')" -ForegroundColor Red
                }
            }
        } else {
            Write-Failure "Package path not found: $tacitRedPackagePath"
        }
    }
}

Write-Step "Summary"
Write-Host @"

Next Steps:
1. Review the logs in: $logsPath
2. If all validations passed, push to GitHub:
   cd $AzureSentinelPath
   git add Solutions/CyrenThreatIntelligence Solutions/TacitRedThreatIntelligence
   git commit -m "Add Cyren and TacitRed Sentinel solutions"
   git push origin feature/threat-intelligence-solutions

3. Create PR at: https://github.com/YOUR_USERNAME/Azure-Sentinel
   Target: Azure/Azure-Sentinel (master branch)

"@ -ForegroundColor Yellow

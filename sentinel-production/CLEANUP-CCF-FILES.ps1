<#
.SYNOPSIS
Cleanup all CCF-related files by renaming them to .outofscope

.DESCRIPTION
This script finds all files related to TacitRed, Cyren, and CCF connectors
and renames them with .outofscope extension to mark them as no longer needed.
#>

$ErrorActionPreference = 'Continue'

Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  CCF FILES CLEANUP - RENAME TO .outofscope                    ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$rootPath = "d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production"

# Patterns to search for
$patterns = @(
    "*tacitred*",
    "*cyren*",
    "*ccf*",
    "*ThreatIntel*Feeds*",
    "*Compromised*Credentials*"
)

# Directories to exclude
$excludeDirs = @(
    "Project\Docs\ccf-deletion-*",
    ".git"
)

$renamedFiles = @()
$skippedFiles = @()

foreach ($pattern in $patterns) {
    Write-Host "Searching for: $pattern" -ForegroundColor Yellow
    
    $files = Get-ChildItem -Path $rootPath -Recurse -Filter $pattern -File -ErrorAction SilentlyContinue | 
        Where-Object { 
            $exclude = $false
            foreach ($dir in $excludeDirs) {
                if ($_.FullName -like "*$dir*") {
                    $exclude = $true
                    break
                }
            }
            -not $exclude -and $_.Extension -ne ".outofscope"
        }
    
    foreach ($file in $files) {
        try {
            # Skip if already has .outofscope extension
            if ($file.Name -like "*.outofscope*") {
                continue
            }
            
            # Skip the cleanup scripts themselves
            if ($file.Name -like "*CLEANUP*" -or $file.Name -like "*DELETE-CCF*" -or $file.Name -like "*VERIFY-CCF*") {
                Write-Host "  ⊘ Skipping cleanup script: $($file.Name)" -ForegroundColor Gray
                $skippedFiles += $file.FullName
                continue
            }
            
            # Skip deletion log directories
            if ($file.DirectoryName -like "*ccf-deletion-*") {
                continue
            }
            
            $newName = "$($file.FullName).outofscope"
            
            # Check if target already exists
            if (Test-Path $newName) {
                Write-Host "  ⚠ Already exists: $($file.Name).outofscope" -ForegroundColor Yellow
                continue
            }
            
            Rename-Item -Path $file.FullName -NewName $newName -Force
            Write-Host "  ✓ Renamed: $($file.Name)" -ForegroundColor Green
            $renamedFiles += $file.FullName
            
        } catch {
            Write-Host "  ✗ Failed to rename: $($file.Name) - $_" -ForegroundColor Red
        }
    }
}

# Also rename Data-Connectors directory
$dataConnectorsDir = Join-Path $rootPath "sentinel-production\Data-Connectors"
if (Test-Path $dataConnectorsDir) {
    try {
        $newName = "$dataConnectorsDir.outofscope"
        if (-not (Test-Path $newName)) {
            Rename-Item -Path $dataConnectorsDir -NewName $newName -Force
            Write-Host "`n✓ Renamed directory: Data-Connectors" -ForegroundColor Green
        }
    } catch {
        Write-Host "`n✗ Failed to rename Data-Connectors directory: $_" -ForegroundColor Red
    }
}

Write-Host "`n═══ CLEANUP SUMMARY ═══" -ForegroundColor Cyan
Write-Host "`nTotal files renamed: $($renamedFiles.Count)" -ForegroundColor Green
Write-Host "Total files skipped: $($skippedFiles.Count)" -ForegroundColor Yellow

if ($renamedFiles.Count -gt 0) {
    Write-Host "`nRenamed files:" -ForegroundColor Yellow
    $renamedFiles | ForEach-Object {
        $relativePath = $_.Replace($rootPath, "").TrimStart("\")
        Write-Host "  - $relativePath" -ForegroundColor Gray
    }
}

Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✓ CCF FILES CLEANUP COMPLETE                                 ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

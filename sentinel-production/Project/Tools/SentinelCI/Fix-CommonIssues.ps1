# Fix-CommonIssues.ps1
# Auto-fix common arm-ttk failures in Sentinel solution files
# Usage: ./Fix-CommonIssues.ps1 -SolutionName "Cyren"

param(
    [Parameter(Mandatory=$true)]
    [string]$SolutionName,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

# Load config
. "$PSScriptRoot/Config.ps1"
$config = Get-SentinelConfig
$repoRoot = Get-RepoRoot

Write-Host "=== Fix Common arm-ttk Issues ===" -ForegroundColor Cyan
Write-Host "Solution: $SolutionName" -ForegroundColor Gray
if ($DryRun) {
    Write-Host "Mode: DRY RUN (no changes will be made)" -ForegroundColor Yellow
}

# Find solution folder
$solutionPatterns = @(
    "$SolutionName$($config.SolutionSuffix)",
    "$SolutionName-CCF-Hub",
    "$SolutionName-Hub",
    $SolutionName
)

$solutionPath = $null
foreach ($pattern in $solutionPatterns) {
    $testPath = Join-Path $repoRoot $pattern
    if (Test-Path $testPath) {
        $solutionPath = $testPath
        break
    }
}

if (-not $solutionPath) {
    Write-Host "[ERROR] Solution folder not found" -ForegroundColor Red
    exit 1
}

Write-Host "Path: $solutionPath" -ForegroundColor Gray

$fixCount = 0

# Fix 1: Connector Definition - id → connectorId
Write-Host "`n--- Fix 1: Rename 'id' to 'connectorId' in connector definitions ---" -ForegroundColor Yellow
$connectorDefs = Get-ChildItem -Path $solutionPath -Recurse -Filter "*ConnectorDefinition*.json"

foreach ($file in $connectorDefs) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match '"id"\s*:\s*"[^"]+"\s*,') {
        Write-Host "  [FIX] $($file.Name)" -ForegroundColor Green
        if (-not $DryRun) {
            $newContent = $content -replace '"id"\s*:\s*"([^"]+)"\s*,', '"connectorId": "$1",'
            Set-Content -Path $file.FullName -Value $newContent -NoNewline
        }
        $fixCount++
    }
}

# Fix 2: Remove empty value arrays from connectivityCriteria
Write-Host "`n--- Fix 2: Remove empty 'value: []' from connectivityCriteria ---" -ForegroundColor Yellow
$jsonFiles = Get-ChildItem -Path $solutionPath -Recurse -Filter "*.json"

foreach ($file in $jsonFiles) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match '"value"\s*:\s*\[\s*\]') {
        Write-Host "  [FIX] $($file.Name)" -ForegroundColor Green
        if (-not $DryRun) {
            # Remove the value: [] line
            $newContent = $content -replace ',?\s*"value"\s*:\s*\[\s*\]', ''
            Set-Content -Path $file.FullName -Value $newContent -NoNewline
        }
        $fixCount++
    }
}

# Fix 3: Rename feedId to feed in poller configs
Write-Host "`n--- Fix 3: Rename 'feedId' to 'feed' in poller configs ---" -ForegroundColor Yellow
$pollerConfigs = Get-ChildItem -Path $solutionPath -Recurse -Filter "*PollerConfig*.json"

foreach ($file in $pollerConfigs) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match '"feedId"\s*:') {
        Write-Host "  [FIX] $($file.Name)" -ForegroundColor Green
        if (-not $DryRun) {
            $newContent = $content -replace '"feedId"\s*:', '"feed":'
            Set-Content -Path $file.FullName -Value $newContent -NoNewline
        }
        $fixCount++
    }
}

# Fix 4: Fix empty ApiKeyIdentifier
Write-Host "`n--- Fix 4: Fix empty 'ApiKeyIdentifier' ---" -ForegroundColor Yellow

foreach ($file in $pollerConfigs) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match '"ApiKeyIdentifier"\s*:\s*""') {
        Write-Host "  [FIX] $($file.Name)" -ForegroundColor Green
        if (-not $DryRun) {
            $newContent = $content -replace '"ApiKeyIdentifier"\s*:\s*""', '"ApiKeyIdentifier": "Bearer"'
            Set-Content -Path $file.FullName -Value $newContent -NoNewline
        }
        $fixCount++
    }
}

# Fix 5: mainTemplate.json fixes
Write-Host "`n--- Fix 5: mainTemplate.json fixes ---" -ForegroundColor Yellow
$mainTemplate = Join-Path $solutionPath "Package/mainTemplate.json"

if (Test-Path $mainTemplate) {
    $content = Get-Content $mainTemplate -Raw
    $modified = $false
    
    # Add location parameter if missing
    if ($content -notmatch '"location"\s*:\s*\{[^}]*"type"\s*:\s*"string"') {
        Write-Host "  [INFO] Consider adding 'location' parameter manually" -ForegroundColor Yellow
    }
    
    # Remove empty groupByAlertDetails and groupByCustomDetails
    if ($content -match '"groupByAlertDetails"\s*:\s*\[\s*\]') {
        Write-Host "  [FIX] Removing empty groupByAlertDetails" -ForegroundColor Green
        if (-not $DryRun) {
            $content = $content -replace ',?\s*"groupByAlertDetails"\s*:\s*\[\s*\]', ''
            $modified = $true
        }
        $fixCount++
    }
    
    if ($content -match '"groupByCustomDetails"\s*:\s*\[\s*\]') {
        Write-Host "  [FIX] Removing empty groupByCustomDetails" -ForegroundColor Green
        if (-not $DryRun) {
            $content = $content -replace ',?\s*"groupByCustomDetails"\s*:\s*\[\s*\]', ''
            $modified = $true
        }
        $fixCount++
    }
    
    if ($modified -and -not $DryRun) {
        Set-Content -Path $mainTemplate -Value $content -NoNewline
    }
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($fixCount -eq 0) {
    Write-Host "No issues found to fix." -ForegroundColor Green
} else {
    if ($DryRun) {
        Write-Host "$fixCount issues would be fixed. Run without -DryRun to apply." -ForegroundColor Yellow
    } else {
        Write-Host "$fixCount issues fixed." -ForegroundColor Green
        Write-Host "Run validation to verify: ./Validate-Solution.ps1 -SolutionName $SolutionName" -ForegroundColor Gray
    }
}

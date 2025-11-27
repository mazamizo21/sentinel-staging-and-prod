# Validate-Solution.ps1
# Run arm-ttk validation on a Sentinel solution
# Usage: ./Validate-Solution.ps1 -SolutionName "Cyren" [-Detailed]

param(
    [Parameter(Mandatory=$true)]
    [string]$SolutionName,
    
    [Parameter(Mandatory=$false)]
    [switch]$Detailed,
    
    [Parameter(Mandatory=$false)]
    [switch]$SaveLog
)

$ErrorActionPreference = "Continue"

# Load config
. "$PSScriptRoot/Config.ps1"
$config = Get-SentinelConfig
$repoRoot = Get-RepoRoot

Write-Host "=== Sentinel Solution Validation ===" -ForegroundColor Cyan
Write-Host "Solution: $SolutionName" -ForegroundColor Gray
Write-Host "Repo Root: $repoRoot" -ForegroundColor Gray

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
    Write-Host "[ERROR] Solution folder not found. Tried:" -ForegroundColor Red
    $solutionPatterns | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

$packagePath = Join-Path $solutionPath "Package"
if (-not (Test-Path $packagePath)) {
    Write-Host "[ERROR] Package folder not found: $packagePath" -ForegroundColor Red
    exit 1
}

Write-Host "Package Path: $packagePath" -ForegroundColor Gray

# Import arm-ttk
$armTtkPath = Get-FullPath $config.ArmTtkPath
if (-not (Test-Path $armTtkPath)) {
    Write-Host "[ERROR] arm-ttk not found: $armTtkPath" -ForegroundColor Red
    exit 1
}

Import-Module $armTtkPath -Force
Write-Host "[OK] arm-ttk loaded" -ForegroundColor Green

# Run validation
Write-Host "`nRunning arm-ttk validation..." -ForegroundColor Yellow
$results = Test-AzTemplate -TemplatePath $packagePath

# Count results
$passed = ($results | Where-Object { $_.Passed -eq $true }).Count
$failed = ($results | Where-Object { $_.Passed -eq $false }).Count
$skipped = ($results | Where-Object { $_.Passed -eq $null }).Count

# Display results
Write-Host "`n=== Results ===" -ForegroundColor Cyan

if ($failed -eq 0) {
    Write-Host "[PASS] All $passed tests passed!" -ForegroundColor Green
} else {
    Write-Host "[FAIL] $failed failures, $passed passed" -ForegroundColor Red
    
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $results | Where-Object { $_.Passed -eq $false } | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor Red
        if ($Detailed -and $_.Errors) {
            $_.Errors | ForEach-Object {
                Write-Host "      $_" -ForegroundColor DarkRed
            }
        }
    }
}

if ($Detailed) {
    Write-Host "`nAll Tests:" -ForegroundColor Gray
    $results | ForEach-Object {
        $status = if ($_.Passed -eq $true) { "[+]" } elseif ($_.Passed -eq $false) { "[-]" } else { "[?]" }
        $color = if ($_.Passed -eq $true) { "Green" } elseif ($_.Passed -eq $false) { "Red" } else { "Yellow" }
        Write-Host "  $status $($_.Name)" -ForegroundColor $color
    }
}

# Save log if requested
if ($SaveLog) {
    $logsPath = Get-FullPath $config.LogsPath
    if (-not (Test-Path $logsPath)) {
        New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logFile = Join-Path $logsPath "$SolutionName-validation-$timestamp.log"
    $results | Out-File -FilePath $logFile -Encoding utf8
    Write-Host "`nLog saved: $logFile" -ForegroundColor Gray
}

# Return exit code
if ($failed -gt 0) {
    exit 1
} else {
    exit 0
}

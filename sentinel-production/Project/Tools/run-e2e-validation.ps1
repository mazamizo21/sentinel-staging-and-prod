# run-e2e-validation.ps1
# End-to-end arm-ttk validation for both Cyren and TacitRed solutions
# Works on macOS and Windows

$ErrorActionPreference = "Continue"

# Detect paths based on script location
$scriptDir = $PSScriptRoot
$repoRoot = Split-Path (Split-Path $scriptDir -Parent) -Parent
$logsPath = Join-Path $repoRoot "Project/Docs/Logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "=== End-to-End Solution Validation ===" -ForegroundColor Cyan
Write-Host "Repository root: $repoRoot" -ForegroundColor Gray

# Ensure logs directory exists
if (-not (Test-Path $logsPath)) {
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
}

# Import arm-ttk
$armTtkPath = Join-Path $repoRoot "Project/Tools/arm-ttk/arm-ttk/arm-ttk.psd1"
if (Test-Path $armTtkPath) {
    Import-Module $armTtkPath -Force
    Write-Host "[OK] arm-ttk module loaded" -ForegroundColor Green
} else {
    Write-Host "[FAIL] arm-ttk not found at: $armTtkPath" -ForegroundColor Red
    exit 1
}

# === CYREN ===
Write-Host "`n=== Cyren Solution ===" -ForegroundColor Cyan
$cyrenPackage = Join-Path $repoRoot "Cyren-CCF-Hub/Package"
$cyrenLog = Join-Path $logsPath "Cyren-e2e-$timestamp.log"

if (Test-Path $cyrenPackage) {
    Write-Host "Validating: $cyrenPackage" -ForegroundColor Gray
    $cyrenResults = Test-AzTemplate -TemplatePath $cyrenPackage
    $cyrenResults | Out-File -FilePath $cyrenLog -Encoding utf8
    
    $cyrenFail = ($cyrenResults | Where-Object { $_.Passed -eq $false }).Count
    $cyrenPass = ($cyrenResults | Where-Object { $_.Passed -eq $true }).Count
    
    if ($cyrenFail -eq 0) {
        Write-Host "[PASS] Cyren: $cyrenPass tests passed, 0 failures" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Cyren: $cyrenPass passed, $cyrenFail failures" -ForegroundColor Red
        $cyrenResults | Where-Object { $_.Passed -eq $false } | ForEach-Object {
            Write-Host "  - $($_.Name)" -ForegroundColor Red
        }
    }
    Write-Host "Log: $cyrenLog" -ForegroundColor Gray
} else {
    Write-Host "[SKIP] Cyren package not found: $cyrenPackage" -ForegroundColor Yellow
}

# === TACITRED ===
Write-Host "`n=== TacitRed Solution ===" -ForegroundColor Cyan
$tacitRedPackage = Join-Path $repoRoot "Tacitred-CCF-Hub/Package"
$tacitRedLog = Join-Path $logsPath "TacitRed-e2e-$timestamp.log"

if (Test-Path $tacitRedPackage) {
    Write-Host "Validating: $tacitRedPackage" -ForegroundColor Gray
    $tacitRedResults = Test-AzTemplate -TemplatePath $tacitRedPackage
    $tacitRedResults | Out-File -FilePath $tacitRedLog -Encoding utf8
    
    $tacitRedFail = ($tacitRedResults | Where-Object { $_.Passed -eq $false }).Count
    $tacitRedPass = ($tacitRedResults | Where-Object { $_.Passed -eq $true }).Count
    
    if ($tacitRedFail -eq 0) {
        Write-Host "[PASS] TacitRed: $tacitRedPass tests passed, 0 failures" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] TacitRed: $tacitRedPass passed, $tacitRedFail failures" -ForegroundColor Red
        $tacitRedResults | Where-Object { $_.Passed -eq $false } | ForEach-Object {
            Write-Host "  - $($_.Name)" -ForegroundColor Red
        }
    }
    Write-Host "Log: $tacitRedLog" -ForegroundColor Gray
} else {
    Write-Host "[SKIP] TacitRed package not found: $tacitRedPackage" -ForegroundColor Yellow
}

# === SUMMARY ===
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$totalFail = $cyrenFail + $tacitRedFail
$totalPass = $cyrenPass + $tacitRedPass

if ($totalFail -eq 0) {
    Write-Host "ALL TESTS PASSED: $totalPass total tests" -ForegroundColor Green
    Write-Host "`nBoth solutions are arm-ttk compliant and ready for GitHub PR!" -ForegroundColor Green
} else {
    Write-Host "FAILURES DETECTED: $totalFail failures out of $($totalPass + $totalFail) tests" -ForegroundColor Red
}

Write-Host "`nLogs saved to: $logsPath" -ForegroundColor Gray

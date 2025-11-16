#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive TacitRed API testing script
.DESCRIPTION
    This script tests the TacitRed API connectivity and data availability
    with various time ranges and parameters to diagnose zero records issues.
.PARAMETER TimeRangeHours
    Time range in hours to query (default: 24)
.PARAMETER Detailed
    Show detailed API response information
.PARAMETER SaveResults
    Save API responses to files for analysis
.EXAMPLE
    .\TEST-TACITRED-API.ps1
.EXAMPLE
    .\TEST-TACITRED-API.ps1 -TimeRangeHours 48 -Detailed -SaveResults
#>

param(
    [int]$TimeRangeHours = 24,
    [switch]$Detailed,
    [switch]$SaveResults
)

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   TACITRED API TESTING TOOL" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Time Range: $TimeRangeHours hours" -ForegroundColor Gray
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')`n" -ForegroundColor Gray

# Test results
$testResults = @{
    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    TimeRangeHours = $TimeRangeHours
    Tests = @()
    OverallStatus = "Unknown"
}

# Function to make API call and capture results
function Test-TacitRedAPI {
    param(
        [string]$TestName,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [string]$Description = ""
    )
    
    Write-Host "`n[$TestName]" -ForegroundColor Yellow
    if($Description){ Write-Host "  Description: $Description" -ForegroundColor Gray }
    
    try {
        # Get API key from Key Vault
        $apiKey = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "tacitred-api-key" --query "value" -o tsv 2>$null
        if(-not $apiKey){
            throw "Could not retrieve API key from Key Vault"
        }
        
        $headers = @{
            'Authorization' = "Bearer $apiKey"
            'Content-Type' = 'application/json'
        }
        
        # Format timestamps for API
        $startTimeStr = $StartTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $endTimeStr = $EndTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $apiUrl = "https://app.tacitred.com/api/v1/findings?startTime=$startTimeStr&endTime=$endTimeStr"
        
        Write-Host "  URL: $apiUrl" -ForegroundColor Gray
        Write-Host "  Time Range: $startTimeStr to $endTimeStr" -ForegroundColor Gray
        
        # Make API call
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 60
        $stopwatch.Stop()
        
        Write-Host ("  ✓ Response Time: {0}ms" -f $stopwatch.ElapsedMilliseconds) -ForegroundColor Green
        Write-Host ("  ✓ HTTP Status: {0}" -f $response.status) -ForegroundColor Green
        Write-Host ("  ✓ Result Count: {0}" -f $response.resultCount) -ForegroundColor $(if($response.resultCount -gt 0){'Green'}else{'Yellow'})
        
        if($response.resultCount -gt 0){
            Write-Host ("  ✓ First Record ID: {0}" -f $response.results[0].id) -ForegroundColor Green
            Write-Host ("  ✓ First Record Type: {0}" -f $response.results[0].type) -ForegroundColor Green
            
            if($Detailed){
                Write-Host "  Sample records:" -ForegroundColor Gray
                $response.results | Select-Object -First 3 | ForEach-Object {
                    Write-Host ("    ID: {0}, Type: {1}, Severity: {2}" -f $_.id, $_.type, $_.severity) -ForegroundColor DarkGray
                    if($_.indicators){
                        Write-Host ("      Indicators: {0}" -f ($_.indicators.PSObject.Properties.Count)) -ForegroundColor DarkGray
                    }
                }
            }
        }else{
            Write-Host "  ⚠ No records found in this time range" -ForegroundColor Yellow
        }
        
        # Save results if requested
        if($SaveResults){
            $filename = ".\docs\tacitred-api-test-$TestName-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
            $response | ConvertTo-Json -Depth 10 | Out-File $filename -Encoding UTF8
            Write-Host "  📄 Response saved: $filename" -ForegroundColor Gray
        }
        
        $testResults.Tests += @{
            Name = $TestName
            Description = $Description
            StartTime = $startTimeStr
            EndTime = $endTimeStr
            Status = "Success"
            HTTPStatus = $response.status
            ResultCount = $response.resultCount
            ResponseTimeMs = $stopwatch.ElapsedMilliseconds
            HasData = $response.resultCount -gt 0
            FirstRecordId = if($response.resultCount -gt 0) { $response.results[0].id } else { $null }
            FirstRecordType = if($response.resultCount -gt 0) { $response.results[0].type } else { $null }
        }
        
        return $response
        
    } catch {
        Write-Host "  ✗ API test failed: $($_.Exception.Message)" -ForegroundColor Red
        if($_.Exception.Response){
            Write-Host ("  ✗ HTTP Status: {0}" -f $_.Exception.Response.StatusCode) -ForegroundColor Red
        }
        
        $testResults.Tests += @{
            Name = $TestName
            Description = $Description
            StartTime = if($StartTime){ $StartTime.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }
            EndTime = if($EndTime){ $EndTime.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }
            Status = "Error"
            Error = $_.Exception.Message
            HTTPStatus = if($_.Exception.Response){ $_.Exception.Response.StatusCode } else { $null }
            ResultCount = 0
            ResponseTimeMs = $null
            HasData = $false
        }
        
        return $null
    }
}

# ============================================================================
# API TESTS
# ============================================================================

$now = Get-Date

# Test 1: Recent 5 minutes (current polling window)
Test-TacitRedAPI -TestName "Recent5Minutes" -StartTime $now.AddMinutes(-5) -EndTime $now -Description "Recent 5 minutes - matches Logic App polling window"

# Test 2: Recent 1 hour
Test-TacitRedAPI -TestName "Recent1Hour" -StartTime $now.AddHours(-1) -EndTime $now -Description "Recent 1 hour - check for recent activity"

# Test 3: Last 6 hours
Test-TacitRedAPI -TestName "Last6Hours" -StartTime $now.AddHours(-6) -EndTime $now -Description "Last 6 hours - typical polling period"

# Test 4: Last 24 hours (default)
Test-TacitRedAPI -TestName "Last24Hours" -StartTime $now.AddHours(-24) -EndTime $now -Description "Last 24 hours - standard daily check"

# Test 5: Last 7 days
Test-TacitRedAPI -TestName "Last7Days" -StartTime $now.AddDays(-7) -EndTime $now -Description "Last 7 days - extended historical check"

# Test 6: Custom time range if specified
if($TimeRangeHours -ne 24){
    Test-TacitRedAPI -TestName "CustomRange" -StartTime $now.AddHours(-$TimeRangeHours) -EndTime $now -Description "Custom range: $TimeRangeHours hours"
}

# ============================================================================
# ANALYSIS
# ============================================================================
Write-Host "`n═══ ANALYSIS ═══" -ForegroundColor Cyan

$successfulTests = $testResults.Tests | Where-Object { $_.Status -eq "Success" }
$failedTests = $testResults.Tests | Where-Object { $_.Status -eq "Error" }
$testsWithData = $testResults.Tests | Where-Object { $_.HasData -eq $true }
$testsWithoutData = $testResults.Tests | Where-Object { $_.HasData -eq $false -and $_.Status -eq "Success" }

Write-Host "Test Summary:" -ForegroundColor Gray
Write-Host ("  Total tests: {0}" -f $testResults.Tests.Count) -ForegroundColor Gray
Write-Host ("  Successful: {0}" -f $successfulTests.Count) -ForegroundColor Green
Write-Host ("  Failed: {0}" -f $failedTests.Count) -ForegroundColor Red
Write-Host ("  With data: {0}" -f $testsWithData.Count) -ForegroundColor Green
Write-Host ("  Without data: {0}" -f $testsWithoutData.Count) -ForegroundColor Yellow

if($failedTests.Count -gt 0){
    Write-Host "`n❌ FAILED TESTS:" -ForegroundColor Red
    foreach($test in $failedTests){
        Write-Host ("  • {0}: {1}" -f $test.Name, $test.Error) -ForegroundColor Red
    }
    $testResults.OverallStatus = "APIError"
}

if($testsWithData.Count -gt 0){
    Write-Host "`n✅ TESTS WITH DATA:" -ForegroundColor Green
    foreach($test in $testsWithData){
        Write-Host ("  • {0}: {1} records (first: {2})" -f $test.Name, $test.ResultCount, $test.FirstRecordId) -ForegroundColor Green
    }
    $testResults.OverallStatus = "HasData"
}

if($testsWithoutData.Count -gt 0 -and $testsWithData.Count -eq 0){
    Write-Host "`n⚠ ALL SUCCESSFUL TESTS RETURNED NO DATA:" -ForegroundColor Yellow
    foreach($test in $testsWithoutData){
        Write-Host ("  • {0}: {1} records" -f $test.Name, $test.ResultCount) -ForegroundColor Yellow
    }
    
    Write-Host "`n🔍 POSSIBLE REASONS:" -ForegroundColor Yellow
    Write-Host "  • No threat intelligence data in the queried time ranges" -ForegroundColor Gray
    Write-Host "  • TacitRed feed may be temporarily inactive" -ForegroundColor Gray
    Write-Host "  • API key may have limited access to historical data" -ForegroundColor Gray
    Write-Host "  • This could be normal if no threats were detected" -ForegroundColor Gray
    
    $testResults.OverallStatus = "NoUpstreamData"
}

if($testsWithData.Count -gt 0 -and $testsWithoutData.Count -gt 0){
    Write-Host "`n🔍 MIXED RESULTS:" -ForegroundColor Yellow
    Write-Host "Some time ranges have data, others don't. This is normal behavior." -ForegroundColor Gray
    $testResults.OverallStatus = "PartialData"
}

# ============================================================================
# RECOMMENDATIONS
# ============================================================================
Write-Host "`n═══ RECOMMENDATIONS ═══" -ForegroundColor Cyan

if($testResults.OverallStatus -eq "APIError"){
    Write-Host "🔧 IMMEDIATE ACTIONS:" -ForegroundColor Red
    Write-Host "  1. Verify API key is valid and not expired" -ForegroundColor White
    Write-Host "  2. Check network connectivity to app.tacitred.com" -ForegroundColor White
    Write-Host "  3. Verify Key Vault access permissions" -ForegroundColor White
}elseif($testResults.OverallStatus -eq "NoUpstreamData"){
    Write-Host "📋 NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. This explains why tables show 0 records" -ForegroundColor White
    Write-Host "  2. Check with TacitRed about feed activity" -ForegroundColor White
    Write-Host "  3. Monitor API over longer time periods" -ForegroundColor White
    Write-Host "  4. Verify Logic Apps are configured correctly" -ForegroundColor White
}elseif($testResults.OverallStatus -eq "HasData" -or $testResults.OverallStatus -eq "PartialData"){
    Write-Host "✅ POSITIVE INDICATORS:" -ForegroundColor Green
    Write-Host "  1. API is working and returning data" -ForegroundColor White
    Write-Host "  2. Issue is likely in Logic Apps or DCR configuration" -ForegroundColor White
    Write-Host "  3. Run DIAGNOSE-ZERO-RECORDS.ps1 to check ingestion pipeline" -ForegroundColor White
}

# Save test results
$reportFile = ".\docs\tacitred-api-test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$testResults | ConvertTo-Json -Depth 10 | Out-File $reportFile -Encoding UTF8
Write-Host "`n📄 Test results saved: $reportFile" -ForegroundColor Gray

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

exit $(if($testResults.OverallStatus -eq "APIError"){1}else{0})
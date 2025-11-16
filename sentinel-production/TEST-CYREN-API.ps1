#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive Cyren API testing script
.DESCRIPTION
    This script tests the Cyren API connectivity and data availability
    for both IP reputation and malware URLs feeds to diagnose zero records issues.
.PARAMETER RecordCount
    Number of records to fetch (default: 100)
.PARAMETER Detailed
    Show detailed API response information
.PARAMETER SaveResults
    Save API responses to files for analysis
.EXAMPLE
    .\TEST-CYREN-API.ps1
.EXAMPLE
    .\TEST-CYREN-API.ps1 -RecordCount 200 -Detailed -SaveResults
#>

param(
    [int]$RecordCount = 100,
    [switch]$Detailed,
    [switch]$SaveResults
)

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   CYREN API TESTING TOOL" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Record Count: $RecordCount" -ForegroundColor Gray
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')`n" -ForegroundColor Gray

# Test results
$testResults = @{
    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    RecordCount = $RecordCount
    Tests = @()
    OverallStatus = "Unknown"
}

# Function to make Cyren API call and capture results
function Test-CyrenAPI {
    param(
        [string]$TestName,
        [string]$FeedId,
        [string]$JWTSecretName,
        [string]$Description = "",
        [int]$Offset = 0
    )
    
    Write-Host "`n[$TestName]" -ForegroundColor Yellow
    if($Description){ Write-Host "  Description: $Description" -ForegroundColor Gray }
    
    try {
        # Get JWT token from Key Vault
        $jwtToken = az keyvault secret show --vault-name "kv-tacitred-secure01" --name $JWTSecretName --query "value" -o tsv 2>$null
        if(-not $jwtToken){
            throw "Could not retrieve JWT token from Key Vault"
        }
        
        $headers = @{
            'Authorization' = "Bearer $jwtToken"
            'Content-Type' = 'application/json'
        }
        
        # Build API URL
        $apiUrl = "https://api-feeds.cyren.com/v1/feed/data?feedId=$FeedId&offset=$Offset&count=$RecordCount&format=jsonl"
        
        Write-Host "  URL: $apiUrl" -ForegroundColor Gray
        Write-Host "  Feed ID: $FeedId" -ForegroundColor Gray
        Write-Host "  Offset: $Offset, Count: $RecordCount" -ForegroundColor Gray
        
        # Make API call
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 60
        $stopwatch.Stop()
        
        Write-Host ("  ✓ Response Time: {0}ms" -f $stopwatch.ElapsedMilliseconds) -ForegroundColor Green
        Write-Host ("  ✓ HTTP Status: 200") -ForegroundColor Green
        Write-Host ("  ✓ Records returned: {0}" -f $response.Count) -ForegroundColor $(if($response.Count -gt 0){'Green'}else{'Yellow'})
        
        if($response.Count -gt 0){
            # Analyze first few records
            $firstRecord = $response[0]
            Write-Host ("  ✓ First record keys: {0}" -f ($firstRecord.PSObject.Properties.Count)) -ForegroundColor Green
            
            if($Detailed){
                Write-Host "  First record structure:" -ForegroundColor Gray
                $firstRecord.PSObject.Properties | ForEach-Object {
                    Write-Host ("    {0}: {1}" -f $_.Name, $_.Value) -ForegroundColor DarkGray
                }
                
                Write-Host "  Sample records:" -ForegroundColor Gray
                $response | Select-Object -First 3 | ForEach-Object {
                    if($_.ip){
                        Write-Host ("    IP: {0}, Threat: {1}" -f $_.ip, $_.threat_type) -ForegroundColor DarkGray
                    }elseif($_.url){
                        Write-Host ("    URL: {0}, Threat: {1}" -f $_.url, $_.threat_type) -ForegroundColor DarkGray
                    }else{
                        Write-Host ("    Type: {0}, Keys: {1}" -f $_.type, ($_.PSObject.Properties.Count)) -ForegroundColor DarkGray
                    }
                }
            }
            
            # Check for common fields
            $hasIP = $response | Where-Object { $_.ip }
            $hasURL = $response | Where-Object { $_.url }
            $hasThreatType = $response | Where-Object { $_.threat_type }
            $hasConfidence = $response | Where-Object { $_.confidence }
            
            Write-Host "  Field analysis:" -ForegroundColor Gray
            Write-Host ("    Records with IP: {0}" -f $hasIP.Count) -ForegroundColor DarkGray
            Write-Host ("    Records with URL: {0}" -f $hasURL.Count) -ForegroundColor DarkGray
            Write-Host ("    Records with threat_type: {0}" -f $hasThreatType.Count) -ForegroundColor DarkGray
            Write-Host ("    Records with confidence: {0}" -f $hasConfidence.Count) -ForegroundColor DarkGray
        }else{
            Write-Host "  ⚠ No records found" -ForegroundColor Yellow
        }
        
        # Save results if requested
        if($SaveResults){
            $filename = ".\docs\cyren-api-test-$TestName-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
            $response | ConvertTo-Json -Depth 10 | Out-File $filename -Encoding UTF8
            Write-Host "  📄 Response saved: $filename" -ForegroundColor Gray
        }
        
        $testResults.Tests += @{
            Name = $TestName
            Description = $Description
            FeedId = $FeedId
            Offset = $Offset
            Status = "Success"
            HTTPStatus = 200
            RecordCount = $response.Count
            ResponseTimeMs = $stopwatch.ElapsedMilliseconds
            HasData = $response.Count -gt 0
            HasIP = if($hasIP) { $hasIP.Count } else { 0 }
            HasURL = if($hasURL) { $hasURL.Count } else { 0 }
            HasThreatType = if($hasThreatType) { $hasThreatType.Count } else { 0 }
            HasConfidence = if($hasConfidence) { $hasConfidence.Count } else { 0 }
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
            FeedId = $FeedId
            Offset = $Offset
            Status = "Error"
            Error = $_.Exception.Message
            HTTPStatus = if($_.Exception.Response){ $_.Exception.Response.StatusCode } else { $null }
            RecordCount = 0
            ResponseTimeMs = $null
            HasData = $false
        }
        
        return $null
    }
}

# ============================================================================
# API TESTS
# ============================================================================

# Test 1: Cyren IP Reputation - First batch
Test-CyrenAPI -TestName "IP-Reputation-First" -FeedId "ip_reputation" -JWTSecretName "cyren-ip-jwt-token" -Description "IP Reputation feed - first batch of records"

# Test 2: Cyren IP Reputation - Offset test (to see if there's more data)
Test-CyrenAPI -TestName "IP-Reputation-Offset" -FeedId "ip_reputation" -JWTSecretName "cyren-ip-jwt-token" -Offset 100 -Description "IP Reputation feed - offset 100 to test pagination"

# Test 3: Cyren Malware URLs - First batch
Test-CyrenAPI -TestName "Malware-URLs-First" -FeedId "malware_urls" -JWTSecretName "cyren-malware-jwt-token" -Description "Malware URLs feed - first batch of records"

# Test 4: Cyren Malware URLs - Offset test
Test-CyrenAPI -TestName "Malware-URLs-Offset" -FeedId "malware_urls" -JWTSecretName "cyren-malware-jwt-token" -Offset 100 -Description "Malware URLs feed - offset 100 to test pagination"

# Test 5: Smaller batch test (in case large batches cause issues)
Test-CyrenAPI -TestName "IP-Reputation-Small" -FeedId "ip_reputation" -JWTSecretName "cyren-ip-jwt-token" -RecordCount 10 -Description "IP Reputation feed - small batch test (10 records)"

# Test 6: Malware URLs small batch
Test-CyrenAPI -TestName "Malware-URLs-Small" -FeedId "malware_urls" -JWTSecretName "cyren-malware-jwt-token" -RecordCount 10 -Description "Malware URLs feed - small batch test (10 records)"

# ============================================================================
# JWT TOKEN ANALYSIS
# ============================================================================
Write-Host "`n═══ JWT TOKEN ANALYSIS ═══" -ForegroundColor Cyan

try {
    # Get and analyze IP JWT token
    $ipJWT = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "cyren-ip-jwt-token" --query "value" -o tsv 2>$null
    if($ipJWT){
        # Decode JWT payload (without verification)
        $payload = $ipJWT.Split('.')[1]
        # Pad base64 string if needed
        while($payload.Length % 4 -ne 0){ $payload += "=" }
        $decodedPayload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
        $jwtObject = $decodedPayload | ConvertFrom-Json
        
        Write-Host "IP Reputation JWT Token:" -ForegroundColor Gray
        Write-Host ("  Audience: {0}" -f $jwtObject.aud) -ForegroundColor Gray
        Write-Host ("  Subject: {0}" -f $jwtObject.sub) -ForegroundColor Gray
        Write-Host ("  Issuer: {0}" -f $jwtObject.iss) -ForegroundColor Gray
        Write-Host ("  Expires: {0}" -f [DateTime]::FromUnixTimeSeconds($jwtObject.exp).ToString('yyyy-MM-dd HH:mm:ss UTC')) -ForegroundColor $(if([DateTime]::FromUnixTimeSeconds($jwtObject.exp) -gt (Get-Date)){'Green'}else{'Red'})
    }
    
    # Get and analyze Malware JWT token
    $malwareJWT = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "cyren-malware-jwt-token" --query "value" -o tsv 2>$null
    if($malwareJWT){
        $payload = $malwareJWT.Split('.')[1]
        while($payload.Length % 4 -ne 0){ $payload += "=" }
        $decodedPayload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
        $jwtObject = $decodedPayload | ConvertFrom-Json
        
        Write-Host "`nMalware URLs JWT Token:" -ForegroundColor Gray
        Write-Host ("  Audience: {0}" -f $jwtObject.aud) -ForegroundColor Gray
        Write-Host ("  Subject: {0}" -f $jwtObject.sub) -ForegroundColor Gray
        Write-Host ("  Issuer: {0}" -f $jwtObject.iss) -ForegroundColor Gray
        Write-Host ("  Expires: {0}" -f [DateTime]::FromUnixTimeSeconds($jwtObject.exp).ToString('yyyy-MM-dd HH:mm:ss UTC')) -ForegroundColor $(if([DateTime]::FromUnixTimeSeconds($jwtObject.exp) -gt (Get-Date)){'Green'}else{'Red'})
    }
} catch {
    Write-Host "  ⚠ Could not analyze JWT tokens: $($_.Exception.Message)" -ForegroundColor Yellow
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
        Write-Host ("  • {0}: {1} records" -f $test.Name, $test.RecordCount) -ForegroundColor Green
    }
    $testResults.OverallStatus = "HasData"
}

if($testsWithoutData.Count -gt 0 -and $testsWithData.Count -eq 0){
    Write-Host "`n⚠ ALL SUCCESSFUL TESTS RETURNED NO DATA:" -ForegroundColor Yellow
    foreach($test in $testsWithoutData){
        Write-Host ("  • {0}: {1} records" -f $test.Name, $test.RecordCount) -ForegroundColor Yellow
    }
    
    Write-Host "`n🔍 POSSIBLE REASONS:" -ForegroundColor Yellow
    Write-Host "  • No threat intelligence data in the feeds currently" -ForegroundColor Gray
    Write-Host "  • JWT tokens may have limited access or permissions" -ForegroundColor Gray
    Write-Host "  • Feeds may be temporarily inactive or empty" -ForegroundColor Gray
    Write-Host "  • Offset may be beyond available data range" -ForegroundColor Gray
    
    $testResults.OverallStatus = "NoUpstreamData"
}

if($testsWithData.Count -gt 0 -and $testsWithoutData.Count -gt 0){
    Write-Host "`n🔍 MIXED RESULTS:" -ForegroundColor Yellow
    Write-Host "Some feeds have data, others don't. This is normal behavior." -ForegroundColor Gray
    $testResults.OverallStatus = "PartialData"
}

# ============================================================================
# RECOMMENDATIONS
# ============================================================================
Write-Host "`n═══ RECOMMENDATIONS ═══" -ForegroundColor Cyan

if($testResults.OverallStatus -eq "APIError"){
    Write-Host "🔧 IMMEDIATE ACTIONS:" -ForegroundColor Red
    Write-Host "  1. Verify JWT tokens are valid and not expired" -ForegroundColor White
    Write-Host "  2. Check network connectivity to api-feeds.cyren.com" -ForegroundColor White
    Write-Host "  3. Verify Key Vault access permissions" -ForegroundColor White
    Write-Host "  4. Contact Cyren support if tokens appear invalid" -ForegroundColor White
}elseif($testResults.OverallStatus -eq "NoUpstreamData"){
    Write-Host "📋 NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. This explains why tables show 0 records" -ForegroundColor White
    Write-Host "  2. Check with Cyren about feed activity and availability" -ForegroundColor White
    Write-Host "  3. Verify JWT token permissions and scope" -ForegroundColor White
    Write-Host "  4. Monitor feeds over longer time periods" -ForegroundColor White
}elseif($testResults.OverallStatus -eq "HasData" -or $testResults.OverallStatus -eq "PartialData"){
    Write-Host "✅ POSITIVE INDICATORS:" -ForegroundColor Green
    Write-Host "  1. APIs are working and returning data" -ForegroundColor White
    Write-Host "  2. JWT tokens are valid and have proper permissions" -ForegroundColor White
    Write-Host "  3. Issue is likely in Logic Apps or DCR configuration" -ForegroundColor White
    Write-Host "  4. Run DIAGNOSE-ZERO-RECORDS.ps1 to check ingestion pipeline" -ForegroundColor White
}

# Save test results
$reportFile = ".\docs\cyren-api-test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$testResults | ConvertTo-Json -Depth 10 | Out-File $reportFile -Encoding UTF8
Write-Host "`n📄 Test results saved: $reportFile" -ForegroundColor Gray

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

exit $(if($testResults.OverallStatus -eq "APIError"){1}else{0})
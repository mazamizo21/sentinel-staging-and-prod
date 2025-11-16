# ============================================================================
# Test Cyren API - Verify Data Availability
# ============================================================================
# This script tests both Cyren feeds to confirm they return current data
# before deploying the CCF connector.
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$CyrenIPJwtToken = "",
    
    [Parameter(Mandatory=$false)]
    [string]$CyrenMalwareJwtToken = ""
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Cyren API Data Availability Test ===" -ForegroundColor Cyan
Write-Host "This will test both Cyren feeds to verify they return current data`n" -ForegroundColor Yellow

# Prompt for tokens if not provided
if ([string]::IsNullOrEmpty($CyrenIPJwtToken)) {
    $CyrenIPJwtToken = Read-Host "Enter Cyren IP Reputation JWT Token"
}

if ([string]::IsNullOrEmpty($CyrenMalwareJwtToken)) {
    $CyrenMalwareJwtToken = Read-Host "Enter Cyren Malware URLs JWT Token"
}

# Test IP Reputation Feed
Write-Host "`n--- Testing IP Reputation Feed ---" -ForegroundColor Cyan

$ipHeaders = @{
    "Authorization" = "Bearer $CyrenIPJwtToken"
    "Accept" = "application/json"
    "User-Agent" = "Microsoft-Sentinel-Cyren-Test/1.0"
}

$ipParams = @{
    "feedId" = "ip_reputation"
    "count" = "10"
    "offset" = "0"
    "format" = "json"
}

try {
    $ipResponse = Invoke-RestMethod -Uri "https://api-feeds.cyren.com/v1/feed/data" `
        -Method Get `
        -Headers $ipHeaders `
        -Body $ipParams `
        -ErrorAction Stop
    
    Write-Host "✅ IP Reputation API Response:" -ForegroundColor Green
    
    if ($ipResponse -is [array]) {
        $count = $ipResponse.Count
        Write-Host "  Records returned: $count" -ForegroundColor White
        
        if ($count -gt 0) {
            Write-Host "`n  Sample record:" -ForegroundColor Yellow
            $ipResponse[0] | ConvertTo-Json -Depth 3 | Write-Host
            
            # Check for timestamps to determine data freshness
            $firstRecord = $ipResponse[0]
            if ($firstRecord.PSObject.Properties.Name -contains 'lastSeen') {
                $lastSeen = $firstRecord.lastSeen
                Write-Host "`n  Last seen timestamp: $lastSeen" -ForegroundColor Cyan
            } elseif ($firstRecord.PSObject.Properties.Name -contains 'detection_ts') {
                $detectionTs = $firstRecord.detection_ts
                Write-Host "`n  Detection timestamp: $detectionTs" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "  Response:" -ForegroundColor White
        $ipResponse | ConvertTo-Json -Depth 3 | Write-Host
    }
    
    # Save to file
    $ipResponse | ConvertTo-Json -Depth 10 | Out-File "cyren-ip-sample.json" -Encoding UTF8
    Write-Host "`n  ✅ Full response saved to: cyren-ip-sample.json" -ForegroundColor Green
    
} catch {
    Write-Host "❌ IP Reputation API Error:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}

# Test Malware URLs Feed
Write-Host "`n--- Testing Malware URLs Feed ---" -ForegroundColor Cyan

$malwareHeaders = @{
    "Authorization" = "Bearer $CyrenMalwareJwtToken"
    "Accept" = "application/json"
    "User-Agent" = "Microsoft-Sentinel-Cyren-Test/1.0"
}

$malwareParams = @{
    "feedId" = "malware_urls"
    "count" = "10"
    "offset" = "0"
    "format" = "json"
}

try {
    $malwareResponse = Invoke-RestMethod -Uri "https://api-feeds.cyren.com/v1/feed/data" `
        -Method Get `
        -Headers $malwareHeaders `
        -Body $malwareParams `
        -ErrorAction Stop
    
    Write-Host "✅ Malware URLs API Response:" -ForegroundColor Green
    
    if ($malwareResponse -is [array]) {
        $count = $malwareResponse.Count
        Write-Host "  Records returned: $count" -ForegroundColor White
        
        if ($count -gt 0) {
            Write-Host "`n  Sample record:" -ForegroundColor Yellow
            $malwareResponse[0] | ConvertTo-Json -Depth 3 | Write-Host
            
            # Check for timestamps
            $firstRecord = $malwareResponse[0]
            if ($firstRecord.PSObject.Properties.Name -contains 'lastSeen') {
                $lastSeen = $firstRecord.lastSeen
                Write-Host "`n  Last seen timestamp: $lastSeen" -ForegroundColor Cyan
            } elseif ($firstRecord.PSObject.Properties.Name -contains 'detection_ts') {
                $detectionTs = $firstRecord.detection_ts
                Write-Host "`n  Detection timestamp: $detectionTs" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "  Response:" -ForegroundColor White
        $malwareResponse | ConvertTo-Json -Depth 3 | Write-Host
    }
    
    # Save to file
    $malwareResponse | ConvertTo-Json -Depth 10 | Out-File "cyren-malware-sample.json" -Encoding UTF8
    Write-Host "`n  ✅ Full response saved to: cyren-malware-sample.json" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Malware URLs API Error:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Review the sample JSON files to check data freshness" -ForegroundColor White
Write-Host "2. Look for recent timestamps (within last few days/weeks)" -ForegroundColor White
Write-Host "3. If data is current → proceed with CCF deployment" -ForegroundColor White
Write-Host "4. If data is old (like TacitRed Oct 26) → same issue exists`n" -ForegroundColor White

Read-Host "Press Enter to exit"

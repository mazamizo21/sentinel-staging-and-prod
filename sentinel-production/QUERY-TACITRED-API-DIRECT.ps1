# QUERY-TACITRED-API-DIRECT.ps1
# Direct query to TacitRed API to check for actual data

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   TACITRED API DIRECT QUERY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

# Get API key from config
$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$apiKey = $config.parameters.tacitRed.value.apiKey

Write-Host "API Key: $($apiKey.Substring(0,8))..." -ForegroundColor Gray
Write-Host "API Endpoint: https://app.tacitred.com/api/v1/findings`n" -ForegroundColor Gray

$headers = @{
    'Authorization' = "Bearer $apiKey"
    'Accept' = 'application/json'
    'User-Agent' = 'Microsoft-Sentinel-TacitRed/1.0'
}

# Test different time windows
$timeWindows = @(
    @{Name="Last 1 hour"; Hours=1},
    @{Name="Last 6 hours"; Hours=6},
    @{Name="Last 24 hours"; Hours=24},
    @{Name="Last 7 days"; Hours=168},
    @{Name="Last 30 days"; Hours=720}
)

$foundData = $false

foreach($window in $timeWindows){
    Write-Host "═══ Testing: $($window.Name) ═══" -ForegroundColor Cyan
    
    $endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $startTime = (Get-Date).AddHours(-$window.Hours).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    $url = "https://app.tacitred.com/api/v1/findings?from=$startTime&until=$endTime&page_size=100"
    
    Write-Host "  From: $startTime" -ForegroundColor Gray
    Write-Host "  Until: $endTime" -ForegroundColor Gray
    Write-Host "  Querying..." -ForegroundColor Yellow
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -TimeoutSec 30
        
        $resultCount = if($response.results){$response.results.Count}else{0}
        
        if($resultCount -gt 0){
            Write-Host "  ✅ FOUND $resultCount RESULTS!" -ForegroundColor Green
            $foundData = $true
            
            Write-Host "`n  📊 Sample Data:" -ForegroundColor Cyan
            $sample = $response.results[0]
            Write-Host "    Email: $($sample.email)" -ForegroundColor Gray
            Write-Host "    Domain: $($sample.domain)" -ForegroundColor Gray
            Write-Host "    Finding Type: $($sample.findingType)" -ForegroundColor Gray
            Write-Host "    Confidence: $($sample.confidence)" -ForegroundColor Gray
            Write-Host "    First Seen: $($sample.firstSeen)" -ForegroundColor Gray
            Write-Host "    Last Seen: $($sample.lastSeen)" -ForegroundColor Gray
            Write-Host "    Source: $($sample.source)" -ForegroundColor Gray
            
            # Show all fields available
            Write-Host "`n  📋 All Available Fields:" -ForegroundColor Cyan
            $sample.PSObject.Properties | ForEach-Object {
                Write-Host "    - $($_.Name): $($_.Value)" -ForegroundColor DarkGray
            }
            
            # If we found data, we can stop
            break
            
        }else{
            Write-Host "  ⚠ 0 results in this window" -ForegroundColor Yellow
        }
        
    } catch {
        $statusCode = if($_.Exception.Response){$_.Exception.Response.StatusCode.value__}else{"Unknown"}
        Write-Host "  ✗ API Error: Status $statusCode" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        
        if($statusCode -eq 401){
            Write-Host "`n  🔴 API KEY IS INVALID!" -ForegroundColor Red
            Write-Host "  This API key returns 401 Unauthorized from TacitRed" -ForegroundColor Red
            Write-Host "  You need to get a valid API key from TacitRed support" -ForegroundColor Red
            break
        }
    }
    
    Write-Host ""
}

# Summary
Write-Host "═══ SUMMARY ═══" -ForegroundColor Cyan

if($foundData){
    Write-Host "✅ TacitRed API has data available!" -ForegroundColor Green
    Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. CCF connector should ingest this data" -ForegroundColor White
    Write-Host "  2. If CCF still not ingesting, check:" -ForegroundColor White
    Write-Host "     - CCF connector has API key set" -ForegroundColor DarkGray
    Write-Host "     - DCR/DCE configuration correct" -ForegroundColor DarkGray
    Write-Host "     - Wait for next poll cycle (every 60 min)" -ForegroundColor DarkGray
}else{
    Write-Host "⚠ NO DATA FOUND in any time window tested" -ForegroundColor Yellow
    Write-Host "`n💡 POSSIBLE REASONS:" -ForegroundColor Cyan
    Write-Host "  1. TacitRed has no findings in your subscription" -ForegroundColor White
    Write-Host "  2. API key is invalid (401 error)" -ForegroundColor White
    Write-Host "  3. Account/subscription issue with TacitRed" -ForegroundColor White
    Write-Host "`n📋 RECOMMENDED ACTIONS:" -ForegroundColor Yellow
    Write-Host "  1. Contact TacitRed support to verify:" -ForegroundColor White
    Write-Host "     - API key is valid and active" -ForegroundColor DarkGray
    Write-Host "     - Your account has access to findings data" -ForegroundColor DarkGray
    Write-Host "     - Subscription is active" -ForegroundColor DarkGray
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

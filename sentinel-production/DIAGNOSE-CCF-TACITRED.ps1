# DIAGNOSE-CCF-TACITRED.ps1
# Focused diagnostic for TacitRed CCF connector

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   TACITRED CCF CONNECTOR DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$ws = $config.parameters.azure.value.workspaceName

Write-Host "Subscription: $sub" -ForegroundColor Gray
Write-Host "Resource Group: $rg" -ForegroundColor Gray
Write-Host "Workspace: $ws`n" -ForegroundColor Gray

az account set --subscription $sub | Out-Null

# ============================================================================
# SECTION 1: CCF CONNECTOR CONFIGURATION
# ============================================================================
Write-Host "═══ SECTION 1: CCF CONNECTOR CONFIGURATION ═══" -ForegroundColor Cyan

$connectorName = "TacitRedFindings"
$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/$connectorName`?api-version=2024-09-01"

try {
    $connector = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json
    
    if(-not $connector){
        Write-Host "✗ CCF Connector '$connectorName' NOT FOUND" -ForegroundColor Red
        Write-Host "`n📋 ACTION REQUIRED:" -ForegroundColor Yellow
        Write-Host "  Deploy the CCF connector for TacitRed" -ForegroundColor White
        exit 1
    }
    
    Write-Host "✓ CCF Connector exists" -ForegroundColor Green
    Write-Host "  Name: $($connector.name)" -ForegroundColor Gray
    Write-Host "  Kind: $($connector.kind)" -ForegroundColor Gray
    Write-Host "  Data Type: $($connector.properties.dataType)" -ForegroundColor Gray
    
    # Check auth configuration
    Write-Host "`n[Authentication]" -ForegroundColor Yellow
    if($connector.properties.auth){
        Write-Host "  Type: $($connector.properties.auth.type)" -ForegroundColor Gray
        Write-Host "  API Key Name Header: $($connector.properties.auth.ApiKeyName)" -ForegroundColor Gray
        
        # Check if API key is actually set (will show as masked)
        if($connector.properties.auth.ApiKey){
            Write-Host "  API Key: [SET - value hidden]" -ForegroundColor Green
        }else{
            Write-Host "  ✗ API Key: NOT SET!" -ForegroundColor Red
        }
    }else{
        Write-Host "  ✗ NO AUTHENTICATION CONFIGURED" -ForegroundColor Red
    }
    
    # Check request configuration
    Write-Host "`n[Request Configuration]" -ForegroundColor Yellow
    if($connector.properties.request){
        $req = $connector.properties.request
        Write-Host "  API Endpoint: $($req.apiEndpoint)" -ForegroundColor Gray
        Write-Host "  HTTP Method: $($req.httpMethod)" -ForegroundColor Gray
        Write-Host "  Query Window: $($req.queryWindowInMin) minutes" -ForegroundColor Gray
        Write-Host "  Time Format: $($req.queryTimeFormat)" -ForegroundColor Gray
        Write-Host "  Start Time Param: $($req.startTimeAttributeName)" -ForegroundColor Gray
        Write-Host "  End Time Param: $($req.endTimeAttributeName)" -ForegroundColor Gray
        Write-Host "  Rate Limit: $($req.rateLimitQps) QPS" -ForegroundColor Gray
        Write-Host "  Retry Count: $($req.retryCount)" -ForegroundColor Gray
        Write-Host "  Timeout: $($req.timeoutInSeconds)s" -ForegroundColor Gray
        
        # Check headers
        if($req.headers){
            Write-Host "  Headers:" -ForegroundColor Gray
            $req.headers.PSObject.Properties | ForEach-Object {
                Write-Host "    $($_.Name): $($_.Value)" -ForegroundColor DarkGray
            }
        }
        
        # Check query parameters
        if($req.queryParameters){
            Write-Host "  Query Parameters:" -ForegroundColor Gray
            $req.queryParameters.PSObject.Properties | ForEach-Object {
                Write-Host "    $($_.Name): $($_.Value)" -ForegroundColor DarkGray
            }
        }
        
        # Critical check: Query window
        if($req.queryWindowInMin -eq 1){
            Write-Host "`n  ⚠️  WARNING: Query window is 1 minute (TEST MODE)" -ForegroundColor Yellow
            Write-Host "  This is for testing only. Production should be 60 minutes." -ForegroundColor Yellow
        }elseif($req.queryWindowInMin -eq 60){
            Write-Host "`n  ✓ Query window is 60 minutes (PRODUCTION)" -ForegroundColor Green
        }
    }
    
    # Check DCR configuration
    Write-Host "`n[DCR Configuration]" -ForegroundColor Yellow
    if($connector.properties.dcrConfig){
        $dcr = $connector.properties.dcrConfig
        Write-Host "  ✓ DCR Config present" -ForegroundColor Green
        Write-Host "  Stream Name: $($dcr.streamName)" -ForegroundColor Gray
        Write-Host "  DCR Immutable ID: $($dcr.dataCollectionRuleImmutableId)" -ForegroundColor Gray
        Write-Host "  DCE Endpoint: $($dcr.dataCollectionEndpoint)" -ForegroundColor Gray
        
        # Verify this matches expected values
        if($dcr.streamName -ne "Custom-TacitRed_Findings_CL"){
            Write-Host "  ⚠️  Stream name unexpected! Should be Custom-TacitRed_Findings_CL" -ForegroundColor Yellow
        }
    }else{
        Write-Host "  ✗ NO DCR CONFIGURATION" -ForegroundColor Red
        Write-Host "  CCF cannot send data without DCR config!" -ForegroundColor Red
    }
    
    # Check paging
    Write-Host "`n[Paging Configuration]" -ForegroundColor Yellow
    if($connector.properties.paging){
        $paging = $connector.properties.paging
        Write-Host "  Type: $($paging.pagingType)" -ForegroundColor Gray
        if($paging.linkHeaderRelLinkName){
            Write-Host "  Link Header: $($paging.linkHeaderRelLinkName)" -ForegroundColor Gray
        }
    }
    
    # Check response configuration
    Write-Host "`n[Response Configuration]" -ForegroundColor Yellow
    if($connector.properties.response){
        $resp = $connector.properties.response
        Write-Host "  Format: $($resp.format)" -ForegroundColor Gray
        Write-Host "  Events JSON Path: $($resp.eventsJsonPaths -join ', ')" -ForegroundColor Gray
    }
    
    # Full connector object for debugging
    Write-Host "`n[Full Configuration]" -ForegroundColor Yellow
    Write-Host "Saving full connector config to: .\docs\ccf-tacitred-config.json" -ForegroundColor Gray
    $connector | ConvertTo-Json -Depth 20 | Out-File ".\docs\ccf-tacitred-config.json" -Encoding UTF8
    
} catch {
    Write-Host "✗ Error checking CCF connector: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================================================
# SECTION 2: CCF CONNECTOR STATUS/LOGS
# ============================================================================
Write-Host "`n═══ SECTION 2: CCF CONNECTOR STATUS ═══" -ForegroundColor Cyan

Write-Host "Checking if CCF has attempted any polling..." -ForegroundColor Yellow

# CCF connectors don't have run history like Logic Apps
# But we can check if data has been written to the table
$query = "TacitRed_Findings_CL | summarize Count=count(), Latest=max(TimeGenerated), Earliest=min(TimeGenerated)"

try {
    $result = az monitor log-analytics query -w $ws --analytics-query $query 2>$null | ConvertFrom-Json
    
    if($result.tables -and $result.tables[0].rows.Count -gt 0){
        $count = $result.tables[0].rows[0][0]
        
        if($count -gt 0){
            Write-Host "✓ Table has $count records!" -ForegroundColor Green
            Write-Host "  Latest: $($result.tables[0].rows[0][1])" -ForegroundColor Gray
            Write-Host "  Earliest: $($result.tables[0].rows[0][2])" -ForegroundColor Gray
        }else{
            Write-Host "⚠ Table exists but has 0 records" -ForegroundColor Yellow
        }
    }else{
        Write-Host "⚠ Table query returned no results" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Table query failed: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# SECTION 3: TEST API AUTHENTICATION
# ============================================================================
Write-Host "`n═══ SECTION 3: TEST API AUTHENTICATION ═══" -ForegroundColor Cyan

Write-Host "Testing TacitRed API with same auth as CCF uses..." -ForegroundColor Yellow

# Get API key from connector config (if visible) or Key Vault
$apiKeyToTest = $null

# Try to get from Key Vault
try {
    $apiKeyToTest = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "tacitred-api-key" --query "value" -o tsv 2>$null
    
    if($apiKeyToTest){
        Write-Host "✓ Retrieved API key from Key Vault" -ForegroundColor Green
        Write-Host "  Length: $($apiKeyToTest.Length) chars" -ForegroundColor Gray
    }
} catch {
    Write-Host "⚠ Could not retrieve API key from Key Vault" -ForegroundColor Yellow
}

if($apiKeyToTest){
    # Test with CCF's configuration
    $headers = @{
        'Authorization' = "Bearer $apiKeyToTest"
        'Accept' = 'application/json'
        'User-Agent' = 'Microsoft-Sentinel-TacitRed/1.0'
    }
    
    # Use same time window as CCF would
    $queryWindow = if($connector.properties.request.queryWindowInMin){$connector.properties.request.queryWindowInMin}else{60}
    $endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $startTime = (Get-Date).AddMinutes(-$queryWindow).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    $apiUrl = "$($connector.properties.request.apiEndpoint)?from=$startTime&until=$endTime"
    if($connector.properties.request.queryParameters.page_size){
        $apiUrl += "&page_size=$($connector.properties.request.queryParameters.page_size)"
    }
    
    Write-Host "`nTesting API call:" -ForegroundColor Gray
    Write-Host "  URL: $apiUrl" -ForegroundColor DarkGray
    Write-Host "  Time Window: Last $queryWindow minutes" -ForegroundColor DarkGray
    
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
        
        Write-Host "`n✓ API Call Succeeded!" -ForegroundColor Green
        Write-Host "  Result Count: $($response.results.Count)" -ForegroundColor Gray
        
        if($response.results.Count -gt 0){
            Write-Host "  ✓ API HAS DATA!" -ForegroundColor Green
            Write-Host "`n  Sample Finding:" -ForegroundColor Cyan
            $sample = $response.results[0]
            Write-Host "    Email: $($sample.email)" -ForegroundColor Gray
            Write-Host "    Type: $($sample.findingType)" -ForegroundColor Gray
            Write-Host "    Confidence: $($sample.confidence)" -ForegroundColor Gray
            
            Write-Host "`n  🔴 ISSUE IDENTIFIED:" -ForegroundColor Red
            Write-Host "  API has data BUT CCF is not ingesting it!" -ForegroundColor Red
            Write-Host "  This indicates a CCF connector or DCR issue." -ForegroundColor Red
        }else{
            Write-Host "  ⚠ API returned 0 results in this time window" -ForegroundColor Yellow
            Write-Host "  This is WHY CCF has no data to ingest" -ForegroundColor Yellow
            Write-Host "`n  💡 EXPLANATION:" -ForegroundColor Cyan
            Write-Host "  TacitRed API has no findings in the last $queryWindow minutes" -ForegroundColor White
            Write-Host "  This is normal if no new compromises occurred recently" -ForegroundColor White
        }
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "`n✗ API Call Failed!" -ForegroundColor Red
        Write-Host "  Status Code: $statusCode" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if($statusCode -eq 401){
            Write-Host "`n  🔴 AUTHENTICATION ISSUE:" -ForegroundColor Red
            Write-Host "  API key is invalid or expired" -ForegroundColor Red
            Write-Host "  CCF is using the same key and CANNOT authenticate" -ForegroundColor Red
            Write-Host "`n  📋 ACTION REQUIRED:" -ForegroundColor Yellow
            Write-Host "  1. Get a valid API key from TacitRed" -ForegroundColor White
            Write-Host "  2. Update Key Vault secret: tacitred-api-key" -ForegroundColor White
            Write-Host "  3. Redeploy CCF connector with new key" -ForegroundColor White
        }
    }
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n═══ SUMMARY & RECOMMENDATIONS ═══" -ForegroundColor Cyan

Write-Host "`n📋 CCF CONNECTOR CHECKLIST:" -ForegroundColor Yellow
Write-Host "  [$(if($connector){'✓'}else{'✗'})] CCF connector exists" -ForegroundColor $(if($connector){'Green'}else{'Red'})
Write-Host "  [$(if($connector.properties.auth){'✓'}else{'✗'})] Authentication configured" -ForegroundColor $(if($connector.properties.auth){'Green'}else{'Red'})
Write-Host "  [$(if($connector.properties.dcrConfig){'✓'}else{'✗'})] DCR configuration present" -ForegroundColor $(if($connector.properties.dcrConfig){'Green'}else{'Red'})
Write-Host "  [$(if($connector.properties.request){'✓'}else{'✗'})] Request configuration present" -ForegroundColor $(if($connector.properties.request){'Green'}else{'Red'})

Write-Host "`n📁 Full connector configuration saved at:" -ForegroundColor Cyan
Write-Host "  .\docs\ccf-tacitred-config.json" -ForegroundColor Gray

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

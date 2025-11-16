#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive diagnostic script for zero records issue in Sentinel Threat Intelligence deployment
.DESCRIPTION
    This script helps identify which tables are showing 0 records and investigates the root cause
    for both TacitRed and Cyren connectors. It performs the following checks:
    1. Table status and record counts
    2. API connectivity and authentication
    3. Logic App execution status
    4. DCR/DCE configuration
    5. CCF connector configuration (if applicable)
.PARAMETER Detailed
    Show detailed diagnostic information
.PARAMETER TestAPIs
    Perform live API tests against TacitRed and Cyren endpoints
.EXAMPLE
    .\DIAGNOSE-ZERO-RECORDS.ps1
.EXAMPLE
    .\DIAGNOSE-ZERO-RECORDS.ps1 -Detailed -TestAPIs
#>

param(
    [switch]$Detailed,
    [switch]$TestAPIs
)

$ErrorActionPreference = 'Stop'

# Load config
if(-not (Test-Path ".\client-config-COMPLETE.json")){
    Write-Host "ERROR: client-config-COMPLETE.json not found" -ForegroundColor Red
    exit 1
}

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$ws = $config.parameters.azure.value.workspaceName

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   ZERO RECORDS DIAGNOSTIC TOOL" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Subscription: $sub" -ForegroundColor Gray
Write-Host "Resource Group: $rg" -ForegroundColor Gray
Write-Host "Workspace: $ws" -ForegroundColor Gray
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')`n" -ForegroundColor Gray

az account set --subscription $sub | Out-Null

# Diagnostic results
$diagnosticResults = @{
    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Tables = @()
    APIConnectivity = @()
    LogicApps = @()
    DCRs = @()
    CCFConnectors = @()
    OverallStatus = "Unknown"
    Recommendations = @()
}

# ============================================================================
# SECTION 1: TABLE STATUS ANALYSIS
# ============================================================================
Write-Host "═══ SECTION 1: TABLE STATUS ANALYSIS ═══" -ForegroundColor Cyan

# Based on the config, we have separate tables for each feed
$tables = @(
    @{Name='TacitRed_Findings_CL'; Type='TacitRed'; Description='Main TacitRed findings table'},
    @{Name='Cyren_IpReputation_CL'; Type='Cyren'; Description='Cyren IP reputation indicators'},
    @{Name='Cyren_MalwareUrls_CL'; Type='Cyren'; Description='Cyren malware URLs indicators'}
)

# Also check for any test tables that might exist
$testTables = @(
    @{Name='TacitRed_Findings_Test_CL'; Type='TacitRed'; Description='Test TacitRed findings table'},
    @{Name='Cyren_Indicators_Test_CL'; Type='Cyren'; Description='Test Cyren indicators table'}
)

$allTables = $tables + $testTables

foreach($table in $allTables){
    Write-Host "`n[$($table.Name)]" -ForegroundColor Yellow
    Write-Host "  Type: $($table.Type)" -ForegroundColor Gray
    Write-Host "  Description: $($table.Description)" -ForegroundColor Gray
    
    try {
        # Check if table exists and get basic stats
        $query = "$($table.Name) | summarize Count=count(), Latest=max(TimeGenerated), Earliest=min(TimeGenerated)"
        $result = az monitor log-analytics query -w $ws --analytics-query $query 2>$null | ConvertFrom-Json
        
        if($result.tables -and $result.tables[0].rows.Count -gt 0){
            $count = $result.tables[0].rows[0][0]
            $latest = $result.tables[0].rows[0][1]
            $earliest = $result.tables[0].rows[0][2]
            
            if($count -gt 0){
                Write-Host ("  ✓ {0} records found" -f $count) -ForegroundColor Green
                Write-Host ("    Latest: {0}" -f $latest) -ForegroundColor Gray
                Write-Host ("    Earliest: {0}" -f $earliest) -ForegroundColor Gray
                $tableStatus = "HasData"
            }else{
                Write-Host "  ⚠ Table exists but has 0 records" -ForegroundColor Yellow
                $tableStatus = "Empty"
            }
        }else{
            Write-Host "  ✗ Table not found or inaccessible" -ForegroundColor Red
            $tableStatus = "NotFound"
        }
        
        # Get detailed schema if table exists and Detailed mode
        if($Detailed -and $tableStatus -ne "NotFound"){
            $schemaQuery = "$($table.Name) | getschema"
            $schemaResult = az monitor log-analytics query -w $ws --analytics-query $schemaQuery 2>$null | ConvertFrom-Json
            
            if($schemaResult.tables -and $schemaResult.tables[0].rows.Count -gt 0){
                Write-Host "  Schema columns: $($schemaResult.tables[0].rows.Count)" -ForegroundColor Gray
                if($Detailed){
                    $schemaResult.tables[0].rows | ForEach-Object {
                        Write-Host ("    - {0} ({1})" -f $_[0], $_[1]) -ForegroundColor DarkGray
                    }
                }
            }
        }
        
        $diagnosticResults.Tables += @{
            Name = $table.Name
            Type = $table.Type
            Description = $table.Description
            Status = $tableStatus
            Count = if($count) {$count} else {0}
            Latest = if($latest) {$latest} else {$null}
            Earliest = if($earliest) {$earliest} else {$null}
        }
        
    } catch {
        Write-Host "  ✗ Query failed: $($_.Exception.Message)" -ForegroundColor Red
        $diagnosticResults.Tables += @{
            Name = $table.Name
            Type = $table.Type
            Description = $table.Description
            Status = "Error"
            Count = 0
            Latest = $null
            Earliest = $null
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# SECTION 2: API CONNECTIVITY TESTS
# ============================================================================
Write-Host "`n═══ SECTION 2: API CONNECTIVITY TESTS ═══" -ForegroundColor Cyan

if($TestAPIs){
    # Test TacitRed API
    Write-Host "`n[TacitRed API Test]" -ForegroundColor Yellow
    try {
        $tacitRedKey = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "tacitred-api-key" --query "value" -o tsv 2>$null
        if($tacitRedKey){
            $headers = @{
                'Authorization' = "Bearer $tacitRedKey"
                'Content-Type' = 'application/json'
            }
            
            # Test with 5-minute window
            $endTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            $startTime = (Get-Date).AddMinutes(-5).ToString("yyyy-MM-ddTHH:mm:ssZ")
            $apiUrl = "https://app.tacitred.com/api/v1/findings?startTime=$startTime&endTime=$endTime"
            
            Write-Host "  Testing: $apiUrl" -ForegroundColor Gray
            $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
            
            Write-Host ("  ✓ API Response: HTTP {0}" -f $response.status) -ForegroundColor Green
            Write-Host ("  ✓ Result Count: {0}" -f $response.resultCount) -ForegroundColor $(if($response.resultCount -gt 0){'Green'}else{'Yellow'})
            
            if($response.resultCount -gt 0 -and $Detailed){
                Write-Host "  Sample data:" -ForegroundColor Gray
                $response.results | Select-Object -First 2 | ForEach-Object {
                    Write-Host ("    ID: {0}, Type: {1}" -f $_.id, $_.type) -ForegroundColor DarkGray
                }
            }
            
            $diagnosticResults.APIConnectivity += @{
                Service = "TacitRed"
                Status = "Success"
                HTTPStatus = $response.status
                ResultCount = $response.resultCount
                HasData = $response.resultCount -gt 0
            }
        }else{
            Write-Host "  ✗ Could not retrieve TacitRed API key from Key Vault" -ForegroundColor Red
            $diagnosticResults.APIConnectivity += @{
                Service = "TacitRed"
                Status = "KeyVaultError"
                Error = "Could not retrieve API key"
            }
        }
    } catch {
        Write-Host "  ✗ API test failed: $($_.Exception.Message)" -ForegroundColor Red
        $diagnosticResults.APIConnectivity += @{
            Service = "TacitRed"
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
    
    # Test Cyren APIs
    Write-Host "`n[Cyren API Test - IP Reputation]" -ForegroundColor Yellow
    try {
        $cyrenIPJWT = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "cyren-ip-jwt-token" --query "value" -o tsv 2>$null
        if($cyrenIPJWT){
            $headers = @{
                'Authorization' = "Bearer $cyrenIPJWT"
                'Content-Type' = 'application/json'
            }
            
            $apiUrl = "https://api-feeds.cyren.com/v1/feed/data?feedId=ip_reputation&offset=0&count=10&format=jsonl"
            Write-Host "  Testing: $apiUrl" -ForegroundColor Gray
            
            $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
            
            Write-Host ("  ✓ API Response: HTTP 200") -ForegroundColor Green
            Write-Host ("  ✓ Records returned: {0}" -f $response.Count) -ForegroundColor $(if($response.Count -gt 0){'Green'}else{'Yellow'})
            
            if($response.Count -gt 0 -and $Detailed){
                Write-Host "  Sample data:" -ForegroundColor Gray
                $response | Select-Object -First 2 | ForEach-Object {
                    Write-Host ("    IP: {0}, Threat: {1}" -f $_.ip, $_.threat_type) -ForegroundColor DarkGray
                }
            }
            
            $diagnosticResults.APIConnectivity += @{
                Service = "Cyren-IP"
                Status = "Success"
                HTTPStatus = 200
                ResultCount = $response.Count
                HasData = $response.Count -gt 0
            }
        }else{
            Write-Host "  ✗ Could not retrieve Cyren IP JWT from Key Vault" -ForegroundColor Red
            $diagnosticResults.APIConnectivity += @{
                Service = "Cyren-IP"
                Status = "KeyVaultError"
                Error = "Could not retrieve JWT token"
            }
        }
    } catch {
        Write-Host "  ✗ API test failed: $($_.Exception.Message)" -ForegroundColor Red
        $diagnosticResults.APIConnectivity += @{
            Service = "Cyren-IP"
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
    
    Write-Host "`n[Cyren API Test - Malware URLs]" -ForegroundColor Yellow
    try {
        $cyrenMalwareJWT = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "cyren-malware-jwt-token" --query "value" -o tsv 2>$null
        if($cyrenMalwareJWT){
            $headers = @{
                'Authorization' = "Bearer $cyrenMalwareJWT"
                'Content-Type' = 'application/json'
            }
            
            $apiUrl = "https://api-feeds.cyren.com/v1/feed/data?feedId=malware_urls&offset=0&count=10&format=jsonl"
            Write-Host "  Testing: $apiUrl" -ForegroundColor Gray
            
            $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
            
            Write-Host ("  ✓ API Response: HTTP 200") -ForegroundColor Green
            Write-Host ("  ✓ Records returned: {0}" -f $response.Count) -ForegroundColor $(if($response.Count -gt 0){'Green'}else{'Yellow'})
            
            if($response.Count -gt 0 -and $Detailed){
                Write-Host "  Sample data:" -ForegroundColor Gray
                $response | Select-Object -First 2 | ForEach-Object {
                    Write-Host ("    URL: {0}, Threat: {1}" -f $_.url, $_.threat_type) -ForegroundColor DarkGray
                }
            }
            
            $diagnosticResults.APIConnectivity += @{
                Service = "Cyren-Malware"
                Status = "Success"
                HTTPStatus = 200
                ResultCount = $response.Count
                HasData = $response.Count -gt 0
            }
        }else{
            Write-Host "  ✗ Could not retrieve Cyren Malware JWT from Key Vault" -ForegroundColor Red
            $diagnosticResults.APIConnectivity += @{
                Service = "Cyren-Malware"
                Status = "KeyVaultError"
                Error = "Could not retrieve JWT token"
            }
        }
    } catch {
        Write-Host "  ✗ API test failed: $($_.Exception.Message)" -ForegroundColor Red
        $diagnosticResults.APIConnectivity += @{
            Service = "Cyren-Malware"
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
}else{
    Write-Host "  Skipping API tests (use -TestAPIs to enable)" -ForegroundColor Gray
}

# ============================================================================
# SECTION 3: LOGIC APP STATUS
# ============================================================================
Write-Host "`n═══ SECTION 3: LOGIC APP STATUS ═══" -ForegroundColor Cyan

$logicApps = @(
    @{Name='logic-tacitred-findings'; Type='TacitRed'; Description='TacitRed data ingestion'},
    @{Name='logicapp-cyren-ip-reputation'; Type='Cyren'; Description='Cyren IP reputation ingestion'},
    @{Name='logicapp-cyren-malware-urls'; Type='Cyren'; Description='Cyren malware URLs ingestion'}
)

foreach($la in $logicApps){
    Write-Host "`n[$($la.Name)]" -ForegroundColor Yellow
    Write-Host "  Type: $($la.Type)" -ForegroundColor Gray
    Write-Host "  Description: $($la.Description)" -ForegroundColor Gray
    
    try {
        # Get Logic App details
        $laInfo = az logic workflow show -g $rg -n $la.Name 2>$null | ConvertFrom-Json
        if($laInfo){
            Write-Host "  ✓ Logic App exists" -ForegroundColor Green
            Write-Host ("  State: {0}" -f $laInfo.properties.state) -ForegroundColor Gray
            
            # Get latest runs
            $runsUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$($la.Name)/runs?`$top=5&api-version=2019-05-01"
            $runs = az rest --method GET --uri $runsUri 2>$null | ConvertFrom-Json
            
            if($runs.value -and $runs.value.Count -gt 0){
                Write-Host ("  ✓ {0} recent runs found" -f $runs.value.Count) -ForegroundColor Green
                
                foreach($run in $runs.value | Select-Object -First 3){
                    $runTime = [DateTime]::Parse($run.properties.startTime).ToString('yyyy-MM-dd HH:mm:ss')
                    $runStatus = $run.properties.status
                    
                    Write-Host ("    Run: {0} - {1}" -f $runTime, $runStatus) -ForegroundColor $(if($runStatus -eq 'Succeeded'){'Green'}elseif($runStatus -match 'Running'){'Yellow'}else{'Red'})
                    
                    # Check Send_to_DCE action if detailed
                    if($Detailed){
                        $sendUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$($la.Name)/runs/$($run.name)/actions/Send_to_DCE?api-version=2019-05-01"
                        $send = az rest --method GET --uri $sendUri 2>$null | ConvertFrom-Json
                        
                        if($send){
                            $sendStatus = $send.properties.status
                            Write-Host ("      Send_to_DCE: {0}" -f $sendStatus) -ForegroundColor $(if($sendStatus -eq 'Succeeded'){'Green'}else{'Red'})
                            
                            if($send.properties.error){
                                Write-Host ("      Error: {0}" -f $send.properties.error.code) -ForegroundColor Red
                            }
                        }
                    }
                }
                
                $diagnosticResults.LogicApps += @{
                    Name = $la.Name
                    Type = $la.Type
                    Status = "Exists"
                    State = $laInfo.properties.state
                    RecentRuns = $runs.value.Count
                    LastRunStatus = $runs.value[0].properties.status
                    LastRunTime = $runs.value[0].properties.startTime
                }
            }else{
                Write-Host "  ⚠ No runs found" -ForegroundColor Yellow
                $diagnosticResults.LogicApps += @{
                    Name = $la.Name
                    Type = $la.Type
                    Status = "Exists"
                    State = $laInfo.properties.state
                    RecentRuns = 0
                    LastRunStatus = "NoRuns"
                    LastRunTime = $null
                }
            }
        }else{
            Write-Host "  ✗ Logic App not found" -ForegroundColor Red
            $diagnosticResults.LogicApps += @{
                Name = $la.Name
                Type = $la.Type
                Status = "NotFound"
                State = $null
                RecentRuns = 0
                LastRunStatus = "NotFound"
                LastRunTime = $null
            }
        }
        
    } catch {
        Write-Host "  ✗ Error checking Logic App: $($_.Exception.Message)" -ForegroundColor Red
        $diagnosticResults.LogicApps += @{
            Name = $la.Name
            Type = $la.Type
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# SECTION 4: DCR/DCE CONFIGURATION
# ============================================================================
Write-Host "`n═══ SECTION 4: DCR/DCE CONFIGURATION ═══" -ForegroundColor Cyan

$dcrs = @(
    @{Name='dcr-tacitred-findings'; Type='TacitRed'},
    @{Name='dcr-cyren-ip-reputation'; Type='Cyren'},
    @{Name='dcr-cyren-malware-urls'; Type='Cyren'}
)

foreach($dcr in $dcrs){
    Write-Host "`n[$($dcr.Name)]" -ForegroundColor Yellow
    Write-Host "  Type: $($dcr.Type)" -ForegroundColor Gray
    
    try {
        $dcrInfo = az monitor data-collection rule show -g $rg -n $dcr.Name 2>$null | ConvertFrom-Json
        if($dcrInfo){
            Write-Host "  ✓ DCR exists" -ForegroundColor Green
            Write-Host ("  Immutable ID: {0}" -f $dcrInfo.properties.immutableId) -ForegroundColor Gray
            
            # Check stream declarations
            if($dcrInfo.properties.streamDeclarations){
                $streamCount = $dcrInfo.properties.streamDeclarations.PSObject.Properties.Count
                Write-Host ("  Stream declarations: {0}" -f $streamCount) -ForegroundColor Gray
                
                if($Detailed){
                    $dcrInfo.properties.streamDeclarations.PSObject.Properties | ForEach-Object {
                        Write-Host ("    - {0}" -f $_.Name) -ForegroundColor DarkGray
                    }
                }
            }
            
            # Check data sources
            if($dcrInfo.properties.dataSources){
                $dsCount = $dcrInfo.properties.dataSources.PSObject.Properties.Count
                Write-Host ("  Data sources: {0}" -f $dsCount) -ForegroundColor Gray
            }
            
            # Check destinations
            if($dcrInfo.properties.destinations){
                $destCount = $dcrInfo.properties.destinations.PSObject.Properties.Count
                Write-Host ("  Destinations: {0}" -f $destCount) -ForegroundColor Gray
            }
            
            $diagnosticResults.DCRs += @{
                Name = $dcr.Name
                Type = $dcr.Type
                Status = "Exists"
                ImmutableId = $dcrInfo.properties.immutableId
                StreamCount = $streamCount
                DataSourceCount = $dsCount
                DestinationCount = $destCount
            }
        }else{
            Write-Host "  ✗ DCR not found" -ForegroundColor Red
            $diagnosticResults.DCRs += @{
                Name = $dcr.Name
                Type = $dcr.Type
                Status = "NotFound"
            }
        }
        
    } catch {
        Write-Host "  ✗ Error checking DCR: $($_.Exception.Message)" -ForegroundColor Red
        $diagnosticResults.DCRs += @{
            Name = $dcr.Name
            Type = $dcr.Type
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
}

# Check DCE
Write-Host "`n[dce-sentinel-threatintel]" -ForegroundColor Yellow
try {
    $dceInfo = az monitor data-collection endpoint show -g $rg -n "dce-sentinel-threatintel" 2>$null | ConvertFrom-Json
    if($dceInfo){
        Write-Host "  ✓ DCE exists" -ForegroundColor Green
        Write-Host ("  Logs Ingestion Endpoint: {0}" -f $dceInfo.properties.logsIngestion.endpoint) -ForegroundColor Gray
    }else{
        Write-Host "  ✗ DCE not found" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ Error checking DCE: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# SECTION 5: CCF CONNECTOR STATUS (if applicable)
# ============================================================================
Write-Host "`n═══ SECTION 5: CCF CONNECTOR STATUS ═══" -ForegroundColor Cyan

$ccfConnectors = @(
    @{Name='TacitRedFindings'; Type='TacitRed'},
    @{Name='CyrenIPReputation'; Type='Cyren'},
    @{Name='CyrenMalwareURLs'; Type='Cyren'}
)

foreach($ccf in $ccfConnectors){
    Write-Host "`n[$($ccf.Name)]" -ForegroundColor Yellow
    Write-Host "  Type: $($ccf.Type)" -ForegroundColor Gray
    
    try {
        $connectorUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/$($ccf.Name)?api-version=2024-09-01"
        $connectorInfo = az rest --method GET --uri $connectorUri 2>$null | ConvertFrom-Json
        
        if($connectorInfo){
            Write-Host "  ✓ CCF connector exists" -ForegroundColor Green
            
            # Check if it has dcrConfig
            if($connectorInfo.properties.dcrConfig){
                Write-Host "  ✓ Has DCR configuration" -ForegroundColor Green
                $dcrConfig = $connectorInfo.properties.dcrConfig
                
                if($dcrConfig.dataCollectionRuleImmutableId){
                    Write-Host ("    DCR Immutable ID: {0}" -f $dcrConfig.dataCollectionRuleImmutableId) -ForegroundColor Gray
                }
                if($dcrConfig.dataCollectionEndpoint){
                    Write-Host ("    DCE Endpoint: {0}" -f $dcrConfig.dataCollectionEndpoint) -ForegroundColor Gray
                }
                if($dcrConfig.streamName){
                    Write-Host ("    Stream Name: {0}" -f $dcrConfig.streamName) -ForegroundColor Gray
                }
                
                $diagnosticResults.CCFConnectors += @{
                    Name = $ccf.Name
                    Type = $ccf.Type
                    Status = "Exists"
                    HasDcrConfig = $true
                    DcrConfig = $dcrConfig
                }
            }else{
                Write-Host "  ⚠ Missing DCR configuration" -ForegroundColor Yellow
                $diagnosticResults.CCFConnectors += @{
                    Name = $ccf.Name
                    Type = $ccf.Type
                    Status = "Exists"
                    HasDcrConfig = $false
                }
            }
        }else{
            Write-Host "  ✗ CCF connector not found" -ForegroundColor Red
            $diagnosticResults.CCFConnectors += @{
                Name = $ccf.Name
                Type = $ccf.Type
                Status = "NotFound"
            }
        }
        
    } catch {
        Write-Host "  ✗ Error checking CCF connector: $($_.Exception.Message)" -ForegroundColor Red
        $diagnosticResults.CCFConnectors += @{
            Name = $ccf.Name
            Type = $ccf.Type
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# ANALYSIS AND RECOMMENDATIONS
# ============================================================================
Write-Host "`n═══ ANALYSIS AND RECOMMENDATIONS ═══" -ForegroundColor Cyan

# Analyze results
$emptyTables = $diagnosticResults.Tables | Where-Object { $_.Status -eq "Empty" }
$notFoundTables = $diagnosticResults.Tables | Where-Object { $_.Status -eq "NotFound" }
$failedLogicApps = $diagnosticResults.LogicApps | Where-Object { $_.LastRunStatus -notin @('Succeeded', 'NoRuns') }
$noRunLogicApps = $diagnosticResults.LogicApps | Where-Object { $_.RecentRuns -eq 0 }
$failedAPIs = $diagnosticResults.APIConnectivity | Where-Object { $_.Status -eq "Error" }
$emptyAPIs = $diagnosticResults.APIConnectivity | Where-Object { $_.HasData -eq $false -and $_.Status -eq "Success" }
$brokenCCF = $diagnosticResults.CCFConnectors | Where-Object { $_.HasDcrConfig -eq $false }

# Generate recommendations
if($emptyTables.Count -gt 0){
    Write-Host "`n🔍 EMPTY TABLES FOUND:" -ForegroundColor Yellow
    foreach($table in $emptyTables){
        Write-Host ("  • {0} ({1})" -f $table.Name, $table.Type) -ForegroundColor Yellow
        
        # Add specific recommendations based on type
        if($table.Type -eq "TacitRed"){
            $diagnosticResults.Recommendations += "Check TacitRed API data availability - API may have no data in queried time range"
            $diagnosticResults.Recommendations += "Verify TacitRed Logic App is running and polling correctly"
        }elseif($table.Type -eq "Cyren"){
            $diagnosticResults.Recommendations += "Check Cyren API data availability - feeds may be empty"
            $diagnosticResults.Recommendations += "Verify Cyren Logic Apps are running and polling correctly"
        }
    }
}

if($notFoundTables.Count -gt 0){
    Write-Host "`n❌ MISSING TABLES:" -ForegroundColor Red
    foreach($table in $notFoundTables){
        Write-Host ("  • {0} ({1})" -f $table.Name, $table.Type) -ForegroundColor Red
        $diagnosticResults.Recommendations += "Create missing table: $($table.Name)"
    }
}

if($failedLogicApps.Count -gt 0){
    Write-Host "`n⚠ FAILED LOGIC APPS:" -ForegroundColor Yellow
    foreach($la in $failedLogicApps){
        Write-Host ("  • {0} - Last run: {1}" -f $la.Name, $la.LastRunStatus) -ForegroundColor Yellow
        $diagnosticResults.Recommendations += "Fix Logic App $($la.Name) - check run history for errors"
    }
}

if($noRunLogicApps.Count -gt 0){
    Write-Host "`n⏰ LOGIC APPS WITH NO RUNS:" -ForegroundColor Yellow
    foreach($la in $noRunLogicApps){
        Write-Host ("  • {0}" -f $la.Name) -ForegroundColor Yellow
        $diagnosticResults.Recommendations += "Trigger Logic App $($la.Name) manually or check trigger configuration"
    }
}

if($failedAPIs.Count -gt 0){
    Write-Host "`n❌ API CONNECTIVITY ISSUES:" -ForegroundColor Red
    foreach($api in $failedAPIs){
        Write-Host ("  • {0}: {1}" -f $api.Service, $api.Error) -ForegroundColor Red
        $diagnosticResults.Recommendations += "Fix $($api.Service) API connectivity: $($api.Error)"
    }
}

if($emptyAPIs.Count -gt 0){
    Write-Host "`n⚠ APIs RETURNING NO DATA:" -ForegroundColor Yellow
    foreach($api in $emptyAPIs){
        Write-Host ("  • {0}: {1} records" -f $api.Service, $api.ResultCount) -ForegroundColor Yellow
        $diagnosticResults.Recommendations += "$($api.Service) API has no data - this may be normal if feed is empty"
    }
}

if($brokenCCF.Count -gt 0){
    Write-Host "`n❌ BROKEN CCF CONNECTORS:" -ForegroundColor Red
    foreach($ccf in $brokenCCF){
        Write-Host ("  • {0} - Missing DCR configuration" -f $ccf.Name) -ForegroundColor Red
        $diagnosticResults.Recommendations += "Reconfigure CCF connector $($ccf.Name) with proper DCR settings"
    }
}

# Overall status
if($emptyTables.Count -eq 0 -and $notFoundTables.Count -eq 0 -and $failedLogicApps.Count -eq 0 -and $failedAPIs.Count -eq 0){
    $diagnosticResults.OverallStatus = "Healthy"
    Write-Host "`n✅ OVERALL STATUS: HEALTHY" -ForegroundColor Green
    Write-Host "All components are functioning correctly. If you're still seeing 0 records," -ForegroundColor Green
    Write-Host "the data sources may simply not have data in the queried time range." -ForegroundColor Green
}elseif($emptyAPIs.Count -gt 0 -and $failedLogicApps.Count -eq 0 -and $failedAPIs.Count -eq 0){
    $diagnosticResults.OverallStatus = "NoUpstreamData"
    Write-Host "`n⚠ OVERALL STATUS: NO UPSTREAM DATA" -ForegroundColor Yellow
    Write-Host "The ingestion pipeline is working correctly, but the upstream APIs" -ForegroundColor Yellow
    Write-Host "are not returning any data. This is likely normal if feeds are empty." -ForegroundColor Yellow
}else{
    $diagnosticResults.OverallStatus = "IssuesFound"
    Write-Host "`n❌ OVERALL STATUS: ISSUES FOUND" -ForegroundColor Red
    Write-Host "There are configuration or connectivity issues that need to be addressed." -ForegroundColor Red
}

# Display recommendations
if($diagnosticResults.Recommendations.Count -gt 0){
    Write-Host "`n📋 RECOMMENDATIONS:" -ForegroundColor Cyan
    $diagnosticResults.Recommendations | ForEach-Object {
        Write-Host ("  • {0}" -f $_) -ForegroundColor White
    }
}

# Save diagnostic results
$reportFile = ".\docs\zero-records-diagnostic-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$diagnosticResults | ConvertTo-Json -Depth 10 | Out-File $reportFile -Encoding UTF8
Write-Host "`n📄 Diagnostic report saved: $reportFile" -ForegroundColor Gray

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

exit $(if($diagnosticResults.OverallStatus -eq "Healthy"){0}else{1})
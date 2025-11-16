#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Enhanced diagnostic script specifically for zero records issue based on RCA analysis
.DESCRIPTION
    This script provides targeted diagnostics for the zero records issue, focusing on:
    1. Identifying which specific tables are empty
    2. Differentiating between TacitRed (upstream data) vs Cyren (config) issues
    3. Checking CCF connector configurations and DCR bindings
    4. Providing actionable recommendations based on findings
.PARAMETER FocusArea
    Specific area to focus on: "All", "TacitRed", "Cyren", "CCF"
.PARAMETER RunAPIs
    Perform live API tests against both services
.PARAMETER GenerateFixes
    Generate PowerShell scripts to fix identified issues
.EXAMPLE
    .\ENHANCED-ZERO-RECORDS-DIAGNOSTIC.ps1
.EXAMPLE
    .\ENHANCED-ZERO-RECORDS-DIAGNOSTIC.ps1 -FocusArea "Cyren" -RunAPIs -GenerateFixes
#>

param(
    [ValidateSet("All", "TacitRed", "Cyren", "CCF")]
    [string]$FocusArea = "All",
    
    [switch]$RunAPIs,
    [switch]$GenerateFixes
)

$ErrorActionPreference = 'Stop'

# Load configuration
if(-not (Test-Path ".\client-config-COMPLETE.json")){
    Write-Host "ERROR: client-config-COMPLETE.json not found" -ForegroundColor Red
    exit 1
}

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$ws = $config.parameters.azure.value.workspaceName

Write-Host "`n═════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   ENHANCED ZERO RECORDS DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Focus Area: $FocusArea" -ForegroundColor Gray
Write-Host "Subscription: $sub" -ForegroundColor Gray
Write-Host "Resource Group: $rg" -ForegroundColor Gray
Write-Host "Workspace: $ws" -ForegroundColor Gray
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')`n" -ForegroundColor Gray

az account set --subscription $sub | Out-Null

# Diagnostic results structure
$diagnosticResults = @{
    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    FocusArea = $FocusArea
    TableAnalysis = @{}
    APIConnectivity = @{}
    CCFConfiguration = @{}
    LogicAppStatus = @{}
    DCRConfiguration = @{}
    RootCauseAnalysis = @{
        TacitRed = $null
        Cyren = $null
        Overall = $null
    }
    Recommendations = @()
    GeneratedFixes = @()
    OverallStatus = "Unknown"
}

# ============================================================================
# SECTION 1: PRECISE TABLE ANALYSIS
# ============================================================================
Write-Host "═══ SECTION 1: PRECISE TABLE ANALYSIS ═══" -ForegroundColor Cyan

# Define all possible table names based on config and common variations
$tableDefinitions = @(
    @{Name='TacitRed_Findings_CL'; Type='TacitRed'; Expected=true; Description='Main TacitRed findings table'},
    @{Name='TacitRed_Findings_Test_CL'; Type='TacitRed'; Expected=false; Description='Test TacitRed findings table'},
    @{Name='Cyren_IpReputation_CL'; Type='Cyren'; Expected=true; Description='Cyren IP reputation table'},
    @{Name='Cyren_MalwareUrls_CL'; Type='Cyren'; Expected=true; Description='Cyren malware URLs table'},
    @{Name='Cyren_Indicators_CL'; Type='Cyren'; Expected=false; Description='Legacy/combined Cyren indicators table'},
    @{Name='Cyren_Indicators_Test_CL'; Type='Cyren'; Expected=false; Description='Test Cyren indicators table'}
)

# Filter by focus area if specified
if($FocusArea -ne "All"){
    $tableDefinitions = $tableDefinitions | Where-Object { $_.Type -eq $FocusArea }
}

foreach($table in $tableDefinitions){
    Write-Host "`n[$($table.Name)]" -ForegroundColor Yellow
    Write-Host "  Type: $($table.Type)" -ForegroundColor Gray
    Write-Host "  Expected: $(if($table.Expected){'✓ Yes'}else{'⚠ No'})" -ForegroundColor $(if($table.Expected){'Green'}else{'Yellow'})
    
    try {
        # Check table existence and get detailed metrics
        $query = "$($table.Name) | summarize Count=count(), Latest=max(TimeGenerated), Earliest=min(TimeGenerated), UniqueFields=dcount(*)"
        $result = az monitor log-analytics query -w $ws --analytics-query $query 2>$null | ConvertFrom-Json
        
        if($result.tables -and $result.tables[0].rows.Count -gt 0){
            $count = $result.tables[0].rows[0][0]
            $latest = $result.tables[0].rows[0][1]
            $earliest = $result.tables[0].rows[0][2]
            $uniqueFields = $result.tables[0].rows[0][3]
            
            $status = if($count -gt 0){ "HasData" }elseif($table.Expected){ "Empty" }else{ "NotFound" }
            $statusColor = if($count -gt 0){ "Green" }elseif($table.Expected){ "Yellow" }else{ "Red" }
            
            Write-Host ("  Status: {0}" -f $status) -ForegroundColor $statusColor
            Write-Host ("  Records: {0}" -f $count) -ForegroundColor Gray
            if($count -gt 0){
                Write-Host ("  Latest: {0}" -f $latest) -ForegroundColor Gray
                Write-Host ("  Earliest: {0}" -f $earliest) -ForegroundColor Gray
                Write-Host ("  Data Freshness: {0} hours old" -f [math]::Round((Get-Date - $latest).TotalHours, 1)) -ForegroundColor Gray
            }
            Write-Host ("  Unique Fields: {0}" -f $uniqueFields) -ForegroundColor Gray
            
            # Store results
            $diagnosticResults.TableAnalysis[$table.Name] = @{
                Type = $table.Type
                Expected = $table.Expected
                Status = $status
                Count = $count
                Latest = if($count -gt 0) { $latest } else { $null }
                Earliest = if($count -gt 0) { $earliest } else { $null }
                UniqueFields = $uniqueFields
                DataFreshnessHours = if($count -gt 0) { [math]::Round((Get-Date - $latest).TotalHours, 1) } else { $null }
            }
        }else{
            Write-Host "  Status: NotFound" -ForegroundColor Red
            $diagnosticResults.TableAnalysis[$table.Name] = @{
                Type = $table.Type
                Expected = $table.Expected
                Status = "NotFound"
                Count = 0
                Latest = $null
                Earliest = $null
                UniqueFields = 0
                DataFreshnessHours = $null
            }
        }
    } catch {
        Write-Host "  Status: QueryFailed" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor DarkGray
        $diagnosticResults.TableAnalysis[$table.Name] = @{
            Type = $table.Type
            Expected = $table.Expected
            Status = "QueryFailed"
            Count = 0
            Latest = $null
            Earliest = $null
            UniqueFields = 0
            DataFreshnessHours = $null
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# SECTION 2: TARGETED API CONNECTIVITY TESTS
# ============================================================================
if($RunAPIs -and ($FocusArea -eq "All" -or $FocusArea -eq "TacitRed" -or $FocusArea -eq "Cyren")){
    Write-Host "`n═══ SECTION 2: TARGETED API CONNECTIVITY TESTS ═══" -ForegroundColor Cyan
    
    # Test TacitRed API if in focus
    if($FocusArea -eq "All" -or $FocusArea -eq "TacitRed"){
        Write-Host "`n[TacitRed API Test]" -ForegroundColor Yellow
        try {
            $apiKey = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "tacitred-api-key" --query "value" -o tsv 2>$null
            if($apiKey){
                $headers = @{
                    'Authorization' = "Bearer $apiKey"
                    'Content-Type' = 'application/json'
                }
                
                # Test multiple time ranges to identify data availability
                $timeRanges = @(
                    @{Name="5min"; Minutes=5},
                    @{Name="1hour"; Minutes=60},
                    @{Name="6hours"; Minutes=360},
                    @{Name="24hours"; Minutes=1440}
                )
                
                foreach($range in $timeRanges){
                    $endTime = Get-Date
                    $startTime = $endTime.AddMinutes(-$range.Minutes)
                    $startTimeStr = $startTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    $endTimeStr = $endTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    $apiUrl = "https://app.tacitred.com/api/v1/findings?startTime=$startTimeStr&endTime=$endTimeStr"
                    
                    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
                    Write-Host ("  {0}: {1} records" -f $range.Name, $response.resultCount) -ForegroundColor $(if($response.resultCount -gt 0){'Green'}else{'Yellow'})
                    
                    if($range.Name -eq "5min"){
                        $diagnosticResults.APIConnectivity["TacitRed_Recent5Min"] = @{
                            Status = "Success"
                            RecordCount = $response.resultCount
                            HasData = $response.resultCount -gt 0
                        }
                    }
                }
            }else{
                Write-Host "  ✗ Could not retrieve API key from Key Vault" -ForegroundColor Red
                $diagnosticResults.APIConnectivity["TacitRed"] = @{
                    Status = "KeyVaultError"
                    Error = "Could not retrieve API key"
                }
            }
        } catch {
            Write-Host "  ✗ API test failed: $($_.Exception.Message)" -ForegroundColor Red
            $diagnosticResults.APIConnectivity["TacitRed"] = @{
                Status = "Error"
                Error = $_.Exception.Message
            }
        }
    }
    
    # Test Cyren APIs if in focus
    if($FocusArea -eq "All" -or $FocusArea -eq "Cyren"){
        $cyrenFeeds = @(
            @{Name="IP_Reputation"; FeedId="ip_reputation"; JWTSecret="cyren-ip-jwt-token"},
            @{Name="Malware_URLs"; FeedId="malware_urls"; JWTSecret="cyren-malware-jwt-token"}
        )
        
        foreach($feed in $cyrenFeeds){
            Write-Host "`n[Cyren API Test - $($feed.Name)]" -ForegroundColor Yellow
            try {
                $jwtToken = az keyvault secret show --vault-name "kv-tacitred-secure01" --name $feed.JWTSecret --query "value" -o tsv 2>$null
                if($jwtToken){
                    $headers = @{
                        'Authorization' = "Bearer $jwtToken"
                        'Content-Type' = 'application/json'
                    }
                    
                    $apiUrl = "https://api-feeds.cyren.com/v1/feed/data?feedId=$($feed.FeedId)&offset=0&count=50&format=jsonl"
                    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
                    
                    Write-Host ("  Records returned: {0}" -f $response.Count) -ForegroundColor $(if($response.Count -gt 0){'Green'}else{'Yellow'})
                    
                    if($response.Count -gt 0){
                        $firstRecord = $response[0]
                        Write-Host ("  Sample record type: {0}" -f $firstRecord.type) -ForegroundColor Gray
                    }
                    
                    $diagnosticResults.APIConnectivity["Cyren_$($feed.Name)"] = @{
                        Status = "Success"
                        RecordCount = $response.Count
                        HasData = $response.Count -gt 0
                    }
                }else{
                    Write-Host "  ✗ Could not retrieve JWT token from Key Vault" -ForegroundColor Red
                    $diagnosticResults.APIConnectivity["Cyren_$($feed.Name)"] = @{
                        Status = "KeyVaultError"
                        Error = "Could not retrieve JWT token"
                    }
                }
            } catch {
                Write-Host "  ✗ API test failed: $($_.Exception.Message)" -ForegroundColor Red
                $diagnosticResults.APIConnectivity["Cyren_$($feed.Name)"] = @{
                    Status = "Error"
                    Error = $_.Exception.Message
                }
            }
        }
    }
}

# ============================================================================
# SECTION 3: CCF CONNECTOR CONFIGURATION ANALYSIS
# ============================================================================
if($FocusArea -eq "All" -or $FocusArea -eq "Cyren" -or $FocusArea -eq "CCF"){
    Write-Host "`n═══ SECTION 3: CCF CONNECTOR CONFIGURATION ANALYSIS ═══" -ForegroundColor Cyan
    
    $ccfConnectors = @(
        @{Name="TacitRedFindings"; Type="TacitRed"},
        @{Name="CyrenIPReputation"; Type="Cyren"},
        @{Name="CyrenMalwareURLs"; Type="Cyren"}
    )
    
    foreach($connector in $ccfConnectors){
        if($FocusArea -ne "All" -and $connector.Type -ne $FocusArea){ continue }
        
        Write-Host "`n[$($connector.Name)]" -ForegroundColor Yellow
        try {
            $connectorUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/$($connector.Name)?api-version=2024-09-01"
            $connectorInfo = az rest --method GET --uri $connectorUri 2>$null | ConvertFrom-Json
            
            if($connectorInfo){
                Write-Host "  ✓ CCF connector exists" -ForegroundColor Green
                
                # Critical: Check dcrConfig
                if($connectorInfo.properties.dcrConfig){
                    Write-Host "  ✓ Has DCR configuration" -ForegroundColor Green
                    $dcrConfig = $connectorInfo.properties.dcrConfig
                    
                    Write-Host ("    DCR Immutable ID: {0}" -f $dcrConfig.dataCollectionRuleImmutableId) -ForegroundColor Gray
                    Write-Host ("    DCE Endpoint: {0}" -f $dcrConfig.dataCollectionEndpoint) -ForegroundColor Gray
                    Write-Host ("    Stream Name: {0}" -f $dcrConfig.streamName) -ForegroundColor Gray
                    Write-Host ("    Data Type: {0}" -f $connectorInfo.properties.dataType) -ForegroundColor Gray
                    
                    # Validate configuration consistency
                    $configIssues = @()
                    if($connectorInfo.properties.dataType -and $dcrConfig.streamName -and $connectorInfo.properties.dataType -ne $dcrConfig.streamName.Replace("Custom-", "").Replace("_CL", "")){
                        $configIssues += "DataType/StreamName mismatch"
                    }
                    
                    if($configIssues.Count -gt 0){
                        Write-Host ("  ⚠ Configuration issues: {0}" -f ($configIssues -join ", ")) -ForegroundColor Yellow
                        $diagnosticResults.CCFConfiguration[$connector.Name] = @{
                            Status = "ExistsWithIssues"
                            Issues = $configIssues
                            DcrConfig = $dcrConfig
                            DataType = $connectorInfo.properties.dataType
                        }
                    }else{
                        Write-Host "  ✓ Configuration appears consistent" -ForegroundColor Green
                        $diagnosticResults.CCFConfiguration[$connector.Name] = @{
                            Status = "ExistsHealthy"
                            DcrConfig = $dcrConfig
                            DataType = $connectorInfo.properties.dataType
                        }
                    }
                }else{
                    Write-Host "  ✗ Missing DCR configuration" -ForegroundColor Red
                    $diagnosticResults.CCFConfiguration[$connector.Name] = @{
                        Status = "MissingDcrConfig"
                        Error = "dcrConfig property not found"
                    }
                }
            }else{
                Write-Host "  ✗ CCF connector not found" -ForegroundColor Red
                $diagnosticResults.CCFConfiguration[$connector.Name] = @{
                    Status = "NotFound"
                }
            }
        } catch {
            Write-Host "  ✗ Error checking CCF connector: $($_.Exception.Message)" -ForegroundColor Red
            $diagnosticResults.CCFConfiguration[$connector.Name] = @{
                Status = "Error"
                Error = $_.Exception.Message
            }
        }
    }
}

# ============================================================================
# SECTION 4: ROOT CAUSE ANALYSIS
# ============================================================================
Write-Host "`n═══ SECTION 4: ROOT CAUSE ANALYSIS ═══" -ForegroundColor Cyan

# Analyze TacitRed situation
$tacitRedTables = $diagnosticResults.TableAnalysis.Keys | Where-Object { $_ -like "TacitRed*" }
$tacitRedEmptyTables = $tacitRedTables | Where-Object { $diagnosticResults.TableAnalysis[$_].Status -eq "Empty" }
$tacitRedAPIStatus = $diagnosticResults.APIConnectivity.Keys | Where-Object { $_ -like "TacitRed*" }

if($tacitRedEmptyTables.Count -gt 0){
    if($tacitRedAPIStatus.Count -gt 0 -and $diagnosticResults.APIConnectivity[$tacitRedAPIStatus[0]].HasData -eq $false){
        $diagnosticResults.RootCauseAnalysis.TacitRed = "UpstreamDataEmpty"
        Write-Host "TacitRed Root Cause: API accessible but returning no data" -ForegroundColor Yellow
        Write-Host "  This is likely normal if no threats are detected in queried time ranges" -ForegroundColor Gray
    }elseif($tacitRedAPIStatus.Count -eq 0){
        $diagnosticResults.RootCauseAnalysis.TacitRed = "APIConnectivityIssue"
        Write-Host "TacitRed Root Cause: API connectivity issues" -ForegroundColor Red
    }else{
        $diagnosticResults.RootCauseAnalysis.TacitRed = "IngestionPipelineIssue"
        Write-Host "TacitRed Root Cause: Data available but not ingesting" -ForegroundColor Red
    }
}else{
    $diagnosticResults.RootCauseAnalysis.TacitRed = "NoIssue"
    Write-Host "TacitRed Root Cause: No issues detected" -ForegroundColor Green
}

# Analyze Cyren situation
$cyrenTables = $diagnosticResults.TableAnalysis.Keys | Where-Object { $_ -like "Cyren*" }
$cyrenEmptyTables = $cyrenTables | Where-Object { $diagnosticResults.TableAnalysis[$_].Status -eq "Empty" }
$cyrenAPIStatus = $diagnosticResults.APIConnectivity.Keys | Where-Object { $_ -like "Cyren*" }
$cyrenCCFIssues = $diagnosticResults.CCFConfiguration.Keys | Where-Object { $diagnosticResults.CCFConfiguration[$_].Status -ne "ExistsHealthy" }

if($cyrenEmptyTables.Count -gt 0){
    if($cyrenCCFIssues.Count -gt 0){
        $diagnosticResults.RootCauseAnalysis.Cyren = "CCFConfigurationIssue"
        Write-Host "Cyren Root Cause: CCF connector configuration problems" -ForegroundColor Red
        Write-Host "  Missing or incorrect dcrConfig bindings" -ForegroundColor Gray
    }elseif($cyrenAPIStatus.Count -gt 0 -and ($diagnosticResults.APIConnectivity[$cyrenAPIStatus[0]].HasData -eq $false)){
        $diagnosticResults.RootCauseAnalysis.Cyren = "UpstreamDataEmpty"
        Write-Host "Cyren Root Cause: APIs accessible but returning no data" -ForegroundColor Yellow
    }else{
        $diagnosticResults.RootCauseAnalysis.Cyren = "IngestionPipelineIssue"
        Write-Host "Cyren Root Cause: Complex ingestion pipeline issue" -ForegroundColor Red
    }
}else{
    $diagnosticResults.RootCauseAnalysis.Cyren = "NoIssue"
    Write-Host "Cyren Root Cause: No issues detected" -ForegroundColor Green
}

# Overall analysis
if($diagnosticResults.RootCauseAnalysis.TacitRed -eq "NoIssue" -and $diagnosticResults.RootCauseAnalysis.Cyren -eq "NoIssue"){
    $diagnosticResults.RootCauseAnalysis.Overall = "Healthy"
    Write-Host "`nOverall Status: ✅ HEALTHY - All components functioning normally" -ForegroundColor Green
}elseif($diagnosticResults.RootCauseAnalysis.TacitRed -eq "UpstreamDataEmpty" -and $diagnosticResults.RootCauseAnalysis.Cyren -eq "NoIssue"){
    $diagnosticResults.RootCauseAnalysis.Overall = "TacitRedNoUpstreamData"
    Write-Host "`nOverall Status: ⚠ TACITRED NO UPSTREAM DATA - APIs working, no threat data available" -ForegroundColor Yellow
}elseif($diagnosticResults.RootCauseAnalysis.Cyren -eq "CCFConfigurationIssue"){
    $diagnosticResults.RootCauseAnalysis.Overall = "CyrenCCFIssue"
    Write-Host "`nOverall Status: ❌ CYREN CCF CONFIGURATION ISSUE - Fixable connector problems" -ForegroundColor Red
}else{
    $diagnosticResults.RootCauseAnalysis.Overall = "ComplexIssues"
    Write-Host "`nOverall Status: ❌ COMPLEX ISSUES - Multiple problems require investigation" -ForegroundColor Red
}

# ============================================================================
# SECTION 5: RECOMMENDATIONS AND FIX GENERATION
# ============================================================================
Write-Host "`n═══ SECTION 5: RECOMMENDATIONS AND FIX GENERATION ═══" -ForegroundColor Cyan

# Generate specific recommendations based on root cause
switch($diagnosticResults.RootCauseAnalysis.Overall){
    "TacitRedNoUpstreamData" {
        $diagnosticResults.Recommendations += "TacitRed: Monitor API over longer time periods (24-168 hours)"
        $diagnosticResults.Recommendations += "TacitRed: Contact TacitRed support about feed activity"
        $diagnosticResults.Recommendations += "TacitRed: Verify API key has access to live threat data"
        $diagnosticResults.Recommendations += "General: This may be normal if no current threats exist"
    }
    
    "CyrenCCFIssue" {
        $diagnosticResults.Recommendations += "Cyren: Fix CCF connector dcrConfig bindings"
        $diagnosticResults.Recommendations += "Cyren: Verify table name mappings in connectors"
        $diagnosticResults.Recommendations += "Cyren: Check DCR immutable IDs and stream names"
        
        if($GenerateFixes){
            $fixScript = @"
# Cyren CCF Connector Fix Script
# Generated: $(Get-Date)

# Fix for CyrenIPReputation connector
`$connectorName = "CyrenIPReputation"
`$dcrImmutableId = "dcr-cyren-ip-reputation-immutable-id-here"
`$dceEndpoint = "https://dce-threatintel-feeds.eastus-1.ingest.monitor.azure.com"
`$streamName = "Custom-Cyren_IpReputation_CL"
`$dataType = "Cyren_IpReputation_CL"

# Update connector with correct dcrConfig
`$body = @{
    properties = @{
        dcrConfig = @{
            streamName = `$streamName
            dataCollectionEndpoint = `$dceEndpoint
            dataCollectionRuleImmutableId = `$dcrImmutableId
        }
    }
} | ConvertTo-Json -Depth 10

az rest --method PATCH --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/`$connectorName)?api-version=2024-09-01" --body "`$body" --headers "Content-Type=application/json"
"@
            $diagnosticResults.GeneratedFixes += @{
                Name = "Fix-Cyren-CCF-Connectors.ps1"
                Content = $fixScript
                Description = "PowerShell script to fix Cyren CCF connector dcrConfig"
            }
        }
    }
    
    "ComplexIssues" {
        $diagnosticResults.Recommendations += "Run comprehensive diagnostic: .\DIAGNOSE-ZERO-RECORDS.ps1 -Detailed -TestAPIs"
        $diagnosticResults.Recommendations += "Check Logic App execution history for errors"
        $diagnosticResults.Recommendations += "Verify DCR/DCE configuration and permissions"
        $diagnosticResults.Recommendations += "Test API connectivity with extended time ranges"
    }
    
    default {
        $diagnosticResults.Recommendations += "Run enhanced diagnostic with -RunAPIs flag for detailed analysis"
        $diagnosticResults.Recommendations += "Check specific table status in Log Analytics"
        $diagnosticResults.Recommendations += "Verify deployment was successful and complete"
    }
}

# Display recommendations
Write-Host "`n📋 RECOMMENDATIONS:" -ForegroundColor Cyan
foreach($rec in $diagnosticResults.Recommendations){
    Write-Host ("  • {0}" -f $rec) -ForegroundColor White
}

# Save generated fix scripts
if($GenerateFixes -and $diagnosticResults.GeneratedFixes.Count -gt 0){
    Write-Host "`n🔧 GENERATED FIX SCRIPTS:" -ForegroundColor Cyan
    foreach($fix in $diagnosticResults.GeneratedFixes){
        $fixPath = ".\generated-fixes\$($fix.Name)"
        $fix.Content | Out-File $fixPath -Encoding UTF8
        Write-Host ("  • {0}" -f $fixPath) -ForegroundColor White
        Write-Host ("    {0}" -f $fix.Description) -ForegroundColor Gray
    }
}

# ============================================================================
# SAVE RESULTS AND SUMMARY
# ============================================================================
$reportFile = ".\docs\enhanced-zero-records-diagnostic-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$diagnosticResults | ConvertTo-Json -Depth 10 | Out-File $reportFile -Encoding UTF8

Write-Host "`n📄 Enhanced diagnostic report saved: $reportFile" -ForegroundColor Gray

# Final status
Write-Host "`n═════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   DIAGNOSTIC COMPLETE" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Overall Status: $($diagnosticResults.RootCauseAnalysis.Overall)" -ForegroundColor $(if($diagnosticResults.RootCauseAnalysis.Overall -eq "Healthy"){'Green'}elseif($diagnosticResults.RootCauseAnalysis.Overall -like "*NoUpstreamData"){'Yellow'}else{'Red'})

exit $(if($diagnosticResults.RootCauseAnalysis.Overall -eq "Healthy"){0}else{1})
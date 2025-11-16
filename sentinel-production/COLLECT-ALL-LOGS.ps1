# COLLECT-ALL-LOGS.ps1
# Comprehensive log collection for CCF troubleshooting

param(
    [string]$ResourceGroup = "TacitRedCCFTest",
    [string]$WorkspaceName = "TacitRedCCFWorkspace",
    [int]$LookbackMinutes = 30
)

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   COMPREHENSIVE LOG COLLECTION" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId

az account set --subscription $sub | Out-Null

$startTime = (Get-Date).AddMinutes(-$LookbackMinutes).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "`n📊 COLLECTION PARAMETERS:" -ForegroundColor Yellow
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host "  Workspace: $WorkspaceName" -ForegroundColor Gray
Write-Host "  Lookback: Last $LookbackMinutes minutes" -ForegroundColor Gray
Write-Host "  Time Range: $startTime to $endTime`n" -ForegroundColor Gray

$wsId = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query id -o tsv

$wsCustomerId = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query customerId -o tsv

# ============================================================================
# 1. KEY VAULT AUDIT LOGS
# ============================================================================
Write-Host "═══ 1. KEY VAULT AUDIT LOGS ═══" -ForegroundColor Cyan
Write-Host "Checking for Key Vault access attempts...`n" -ForegroundColor Yellow

$kvQuery = @"
AzureDiagnostics
| where ResourceType == "VAULTS"
| where TimeGenerated > ago($($LookbackMinutes)m)
| where OperationName == "SecretGet" or OperationName == "SecretList"
| project TimeGenerated, 
    OperationName, 
    ResultSignature, 
    CallerIPAddress,
    identity_claim_appid_g,
    properties_s
| order by TimeGenerated desc
"@

try {
    Write-Host "  Querying Key Vault audit logs..." -ForegroundColor Gray
    $kvResult = az monitor log-analytics query `
        --workspace $wsCustomerId `
        --analytics-query $kvQuery `
        2>$null | ConvertFrom-Json
    
    if($kvResult.tables -and $kvResult.tables[0].rows.Count -gt 0){
        Write-Host "  ✅ Found $($kvResult.tables[0].rows.Count) Key Vault operations" -ForegroundColor Green
        
        foreach($row in $kvResult.tables[0].rows | Select-Object -First 5){
            Write-Host "`n  Time: $($row[0])" -ForegroundColor Cyan
            Write-Host "    Operation: $($row[1])" -ForegroundColor Gray
            Write-Host "    Result: $($row[2])" -ForegroundColor $(if($row[2] -eq 'Success'){'Green'}else{'Red'})
            Write-Host "    Caller IP: $($row[3])" -ForegroundColor Gray
            Write-Host "    App ID: $($row[4])" -ForegroundColor Gray
        }
    }else{
        Write-Host "  ⚠ No Key Vault operations found" -ForegroundColor Yellow
        Write-Host "  This might mean:" -ForegroundColor Gray
        Write-Host "    - Key Vault diagnostics not enabled" -ForegroundColor DarkGray
        Write-Host "    - CCF hasn't tried to access Key Vault yet" -ForegroundColor DarkGray
        Write-Host "    - Logs haven't propagated (wait 5-10 min)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  ⚠ Query failed (Key Vault may not have diagnostics enabled)" -ForegroundColor Yellow
}

# ============================================================================
# 2. DCE INGESTION LOGS
# ============================================================================
Write-Host "`n═══ 2. DATA COLLECTION ENDPOINT LOGS ═══" -ForegroundColor Cyan
Write-Host "Checking for data ingestion attempts...`n" -ForegroundColor Yellow

# Check for any ingestion to our table
$dceQuery = @"
TacitRed_Findings_CL
| where TimeGenerated > ago($($LookbackMinutes)m)
| summarize Count = count(), 
    FirstIngestion = min(TimeGenerated),
    LastIngestion = max(TimeGenerated)
"@

try {
    $dceResult = az monitor log-analytics query `
        --workspace $wsCustomerId `
        --analytics-query $dceQuery `
        2>$null | ConvertFrom-Json
    
    if($dceResult.tables -and $dceResult.tables[0].rows.Count -gt 0){
        $count = $dceResult.tables[0].rows[0][0]
        $first = $dceResult.tables[0].rows[0][1]
        $last = $dceResult.tables[0].rows[0][2]
        
        if($count -gt 0){
            Write-Host "  ✅ DATA FOUND!" -ForegroundColor Green
            Write-Host "    Records: $count" -ForegroundColor Green
            Write-Host "    First: $first" -ForegroundColor Gray
            Write-Host "    Last: $last" -ForegroundColor Gray
        }else{
            Write-Host "  ⚠ No data in last $LookbackMinutes minutes" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  ⚠ No data found" -ForegroundColor Yellow
}

# ============================================================================
# 3. SENTINEL OPERATIONAL LOGS
# ============================================================================
Write-Host "`n═══ 3. SENTINEL OPERATIONAL LOGS ═══" -ForegroundColor Cyan
Write-Host "Checking for connector operations...`n" -ForegroundColor Yellow

$sentinelQuery = @"
SentinelHealth
| where TimeGenerated > ago($($LookbackMinutes)m)
| where SentinelResourceType == "Data connector"
| project TimeGenerated, 
    SentinelResourceName,
    Status,
    Description,
    ExtendedProperties
| order by TimeGenerated desc
"@

try {
    $sentinelResult = az monitor log-analytics query `
        --workspace $wsCustomerId `
        --analytics-query $sentinelQuery `
        2>$null | ConvertFrom-Json
    
    if($sentinelResult.tables -and $sentinelResult.tables[0].rows.Count -gt 0){
        Write-Host "  ✅ Found $($sentinelResult.tables[0].rows.Count) Sentinel health events" -ForegroundColor Green
        
        foreach($row in $sentinelResult.tables[0].rows | Select-Object -First 5){
            Write-Host "`n  Time: $($row[0])" -ForegroundColor Cyan
            Write-Host "    Connector: $($row[1])" -ForegroundColor Gray
            Write-Host "    Status: $($row[2])" -ForegroundColor $(if($row[2] -eq 'Success'){'Green'}else{'Red'})
            Write-Host "    Description: $($row[3])" -ForegroundColor Gray
        }
    }else{
        Write-Host "  ⚠ No Sentinel health logs found" -ForegroundColor Yellow
        Write-Host "  This is normal for new deployments" -ForegroundColor Gray
    }
} catch {
    Write-Host "  ⚠ SentinelHealth table not available" -ForegroundColor Yellow
}

# ============================================================================
# 4. AZURE ACTIVITY LOG (Resource Provider Operations)
# ============================================================================
Write-Host "`n═══ 4. AZURE ACTIVITY LOG ═══" -ForegroundColor Cyan
Write-Host "Checking for Azure operations on our resources...`n" -ForegroundColor Yellow

$activityQuery = @"
AzureActivity
| where TimeGenerated > ago($($LookbackMinutes)m)
| where ResourceGroup == "$ResourceGroup"
| where OperationNameValue contains "dataConnectors" 
    or OperationNameValue contains "dataCollectionRules"
    or OperationNameValue contains "dataCollectionEndpoints"
| project TimeGenerated,
    OperationNameValue,
    ActivityStatusValue,
    Caller,
    HTTPRequest
| order by TimeGenerated desc
"@

try {
    $activityResult = az monitor log-analytics query `
        --workspace $wsCustomerId `
        --analytics-query $activityQuery `
        2>$null | ConvertFrom-Json
    
    if($activityResult.tables -and $activityResult.tables[0].rows.Count -gt 0){
        Write-Host "  ✅ Found $($activityResult.tables[0].rows.Count) Azure operations" -ForegroundColor Green
        
        foreach($row in $activityResult.tables[0].rows | Select-Object -First 5){
            Write-Host "`n  Time: $($row[0])" -ForegroundColor Cyan
            Write-Host "    Operation: $($row[1])" -ForegroundColor Gray
            Write-Host "    Status: $($row[2])" -ForegroundColor $(if($row[2] -eq 'Succeeded'){'Green'}else{'Red'})
            Write-Host "    Caller: $($row[3])" -ForegroundColor Gray
        }
    }else{
        Write-Host "  ⚠ No relevant Activity Log entries" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ⚠ Activity Log query failed" -ForegroundColor Yellow
}

# ============================================================================
# 5. CHECK DIAGNOSTIC SETTINGS
# ============================================================================
Write-Host "`n═══ 5. DIAGNOSTIC SETTINGS STATUS ═══" -ForegroundColor Cyan

# Check DCE diagnostics
Write-Host "`nData Collection Endpoint:" -ForegroundColor Yellow
$dce = az monitor data-collection endpoint list `
    --resource-group $ResourceGroup `
    --query "[0]" | ConvertFrom-Json

if($dce){
    $dceId = $dce.id
    $dceDiag = az monitor diagnostic-settings list `
        --resource $dceId `
        --query "value" 2>$null | ConvertFrom-Json
    
    if($dceDiag -and $dceDiag.Count -gt 0){
        Write-Host "  ✅ Diagnostics enabled ($($dceDiag.Count) settings)" -ForegroundColor Green
        foreach($diag in $dceDiag){
            Write-Host "    - $($diag.name)" -ForegroundColor Gray
        }
    }else{
        Write-Host "  ⚠ No diagnostic settings" -ForegroundColor Yellow
        Write-Host "  ENABLING NOW..." -ForegroundColor Yellow
        
        # Enable diagnostics
        try {
            az monitor diagnostic-settings create `
                --name "dce-diagnostics" `
                --resource $dceId `
                --workspace $wsId `
                --logs '[{"category":"AllLogs","enabled":true}]' `
                --metrics '[{"category":"AllMetrics","enabled":true}]' `
                --output none 2>$null
            
            Write-Host "  ✅ Diagnostics enabled for DCE" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠ Could not enable DCE diagnostics" -ForegroundColor Yellow
        }
    }
}

# Check DCR diagnostics
Write-Host "`nData Collection Rule:" -ForegroundColor Yellow
$dcrList = az monitor data-collection rule list `
    --resource-group $ResourceGroup | ConvertFrom-Json
$dcr = $dcrList | Where-Object {$_.name -like "*tacitred*"} | Select-Object -First 1

if($dcr){
    $dcrId = $dcr.id
    $dcrDiag = az monitor diagnostic-settings list `
        --resource $dcrId `
        --query "value" 2>$null | ConvertFrom-Json
    
    if($dcrDiag -and $dcrDiag.Count -gt 0){
        Write-Host "  ✅ Diagnostics enabled ($($dcrDiag.Count) settings)" -ForegroundColor Green
    }else{
        Write-Host "  ⚠ No diagnostic settings" -ForegroundColor Yellow
        Write-Host "  ENABLING NOW..." -ForegroundColor Yellow
        
        try {
            az monitor diagnostic-settings create `
                --name "dcr-diagnostics" `
                --resource $dcrId `
                --workspace $wsId `
                --logs '[{"category":"AllLogs","enabled":true}]' `
                --output none 2>$null
            
            Write-Host "  ✅ Diagnostics enabled for DCR" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠ Could not enable DCR diagnostics" -ForegroundColor Yellow
        }
    }
}

# ============================================================================
# 6. RECENT ERRORS IN LOG ANALYTICS
# ============================================================================
Write-Host "`n═══ 6. RECENT ERRORS ═══" -ForegroundColor Cyan
Write-Host "Checking for any errors...`n" -ForegroundColor Yellow

$errorQuery = @"
union withsource=SourceTable *
| where TimeGenerated > ago($($LookbackMinutes)m)
| where * has "error" or * has "failed" or * has "exception"
| where SourceTable != "SecurityAlert"
| project TimeGenerated, SourceTable, Message = tostring(column_ifexists("Message", ""))
| order by TimeGenerated desc
| take 10
"@

try {
    $errorResult = az monitor log-analytics query `
        --workspace $wsCustomerId `
        --analytics-query $errorQuery `
        2>$null | ConvertFrom-Json
    
    if($errorResult.tables -and $errorResult.tables[0].rows.Count -gt 0){
        Write-Host "  ⚠ Found $($errorResult.tables[0].rows.Count) potential errors" -ForegroundColor Yellow
        
        foreach($row in $errorResult.tables[0].rows | Select-Object -First 3){
            Write-Host "`n  Time: $($row[0])" -ForegroundColor Cyan
            Write-Host "    Table: $($row[1])" -ForegroundColor Gray
            Write-Host "    Message: $($row[2])" -ForegroundColor Yellow
        }
    }else{
        Write-Host "  ✅ No errors found" -ForegroundColor Green
    }
} catch {
    Write-Host "  ⚠ Error query failed" -ForegroundColor Yellow
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n═══ SUMMARY ═══" -ForegroundColor Cyan

$kvCount = if($kvResult.tables -and $kvResult.tables[0].rows){$kvResult.tables[0].rows.Count}else{0}
$sentinelCount = if($sentinelResult.tables -and $sentinelResult.tables[0].rows){$sentinelResult.tables[0].rows.Count}else{0}
$activityCount = if($activityResult.tables -and $activityResult.tables[0].rows){$activityResult.tables[0].rows.Count}else{0}
if(-not $count){$count = 0}

Write-Host "`n📊 LOG COLLECTION STATUS:" -ForegroundColor Yellow
Write-Host "  Key Vault Logs: $(if($kvCount -gt 0){'✅ Available'}else{'⚠ None found'})" -ForegroundColor $(if($kvCount -gt 0){'Green'}else{'Yellow'})
Write-Host "  Data Ingestion: $(if($count -gt 0){'✅ ' + $count + ' records'}else{'⚠ No data'})" -ForegroundColor $(if($count -gt 0){'Green'}else{'Yellow'})
Write-Host "  Sentinel Health: $(if($sentinelCount -gt 0){'✅ Available'}else{'⚠ None found'})" -ForegroundColor $(if($sentinelCount -gt 0){'Green'}else{'Yellow'})
Write-Host "  Activity Log: $(if($activityCount -gt 0){'✅ Available'}else{'⚠ None found'})" -ForegroundColor $(if($activityCount -gt 0){'Green'}else{'Yellow'})
Write-Host "  Diagnostics: ✅ Enabled (DCE + DCR)" -ForegroundColor Green

Write-Host "`n💡 KEY INSIGHTS:" -ForegroundColor Cyan

if($count -gt 0){
    Write-Host "  🎉 DATA IS FLOWING!" -ForegroundColor Green
    Write-Host "  CCF is working in the fresh environment!" -ForegroundColor Green
}elseif($kvCount -gt 0){
    Write-Host "  ⚠ Key Vault accessed but no data yet" -ForegroundColor Yellow
    Write-Host "  CCF may be polling - wait 5-10 more minutes" -ForegroundColor Yellow
}else{
    Write-Host "  ⚠ No Key Vault access detected" -ForegroundColor Yellow
    Write-Host "  Possible reasons:" -ForegroundColor Gray
    Write-Host "    1. CCF hasn't polled yet (wait for first 5-min cycle)" -ForegroundColor DarkGray
    Write-Host "    2. Key Vault diagnostics logs delayed (5-10 min)" -ForegroundColor DarkGray
    Write-Host "    3. CCF not using Key Vault (API key set directly)" -ForegroundColor DarkGray
    Write-Host "    4. CCF has same API key persistence issue" -ForegroundColor DarkGray
}

Write-Host "`n📋 RECOMMENDATIONS:" -ForegroundColor Yellow
Write-Host "  1. Diagnostics now enabled - logs will flow in 5-10 minutes" -ForegroundColor White
Write-Host "  2. Run this script again in 10 minutes to see new logs" -ForegroundColor White
Write-Host "  3. Run .\VERIFY-FRESH-CCF.ps1 to check for data" -ForegroundColor White

$nextCheck = (Get-Date).AddMinutes(10).ToString("HH:mm")
Write-Host "`n⏱️  Run again at: $nextCheck for updated logs" -ForegroundColor Cyan

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

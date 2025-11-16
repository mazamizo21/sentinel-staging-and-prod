# DEBUG-CCF-NOT-POLLING.ps1
# Deep diagnostic of why CCF is not polling

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   CCF NOT POLLING - DEEP DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$ws = $config.parameters.azure.value.workspaceName

az account set --subscription $sub | Out-Null

Write-Host "User says: Changed to 5 min, waited 1 hour, still no CCF data" -ForegroundColor Yellow
Write-Host "Logic Apps: Working (2300 records)" -ForegroundColor Green
Write-Host "CCF: Not polling`n" -ForegroundColor Red

# Get connector definition AND instance
$connectorDefUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectorDefinitions/TacitRedThreatIntel?api-version=2024-09-01"
$connectorInstUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"

Write-Host "═══ STEP 1: CHECK CONNECTOR DEFINITION ═══" -ForegroundColor Cyan
try {
    $connDef = az rest --method GET --uri $connectorDefUri 2>$null | ConvertFrom-Json
    
    if($connDef){
        Write-Host "✓ Connector Definition exists" -ForegroundColor Green
        Write-Host "  Name: $($connDef.name)" -ForegroundColor Gray
        Write-Host "  Kind: $($connDef.kind)" -ForegroundColor Gray
    }else{
        Write-Host "✗ Connector Definition NOT FOUND!" -ForegroundColor Red
        Write-Host "  This is critical - CCF needs the definition" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Error getting definition: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n═══ STEP 2: CHECK CONNECTOR INSTANCE ═══" -ForegroundColor Cyan
try {
    $connInst = az rest --method GET --uri $connectorInstUri 2>$null | ConvertFrom-Json
    
    if($connInst){
        Write-Host "✓ Connector Instance exists" -ForegroundColor Green
        Write-Host "  Name: $($connInst.name)" -ForegroundColor Gray
        Write-Host "  Kind: $($connInst.kind)" -ForegroundColor Gray
        Write-Host "  Is Active: $($connInst.properties.isActive)" -ForegroundColor $(if($connInst.properties.isActive){'Green'}else{'Red'})
        
        # Save full config
        $connInst | ConvertTo-Json -Depth 20 | Out-File ".\docs\ccf-connector-current-state.json" -Encoding UTF8
        Write-Host "  Full config saved: docs\ccf-connector-current-state.json" -ForegroundColor Gray
        
        # Check polling interval
        Write-Host "`n[Polling Configuration]" -ForegroundColor Yellow
        if($connInst.properties.request){
            $interval = $connInst.properties.request.queryWindowInMin
            Write-Host "  Current queryWindowInMin: $interval minutes" -ForegroundColor Cyan
            
            if($interval -eq 5){
                Write-Host "  ✓ Confirmed: Set to 5 minutes" -ForegroundColor Green
            }elseif($interval -eq 60){
                Write-Host "  ⚠ Still showing 60 minutes!" -ForegroundColor Yellow
                Write-Host "  Your change may not have been applied" -ForegroundColor Yellow
            }else{
                Write-Host "  Interval: $interval minutes" -ForegroundColor Gray
            }
        }
        
        # Check auth
        Write-Host "`n[Authentication]" -ForegroundColor Yellow
        if($connInst.properties.auth){
            Write-Host "  Type: $($connInst.properties.auth.type)" -ForegroundColor Gray
            Write-Host "  Header: $($connInst.properties.auth.ApiKeyName)" -ForegroundColor Gray
            
            if($connInst.properties.auth.ApiKey){
                Write-Host "  API Key: ✓ SET" -ForegroundColor Green
            }else{
                Write-Host "  API Key: ✗ NULL" -ForegroundColor Red
            }
        }else{
            Write-Host "  ✗ NO AUTH CONFIGURED!" -ForegroundColor Red
        }
        
        # Check DCR config
        Write-Host "`n[DCR Configuration]" -ForegroundColor Yellow
        if($connInst.properties.dcrConfig){
            Write-Host "  ✓ DCR Config present" -ForegroundColor Green
            Write-Host "  Stream: $($connInst.properties.dcrConfig.streamName)" -ForegroundColor Gray
            Write-Host "  DCR ID: $($connInst.properties.dcrConfig.dataCollectionRuleImmutableId)" -ForegroundColor Gray
            Write-Host "  DCE: $($connInst.properties.dcrConfig.dataCollectionEndpoint)" -ForegroundColor Gray
        }else{
            Write-Host "  ✗ NO DCR CONFIG!" -ForegroundColor Red
        }
        
    }else{
        Write-Host "✗ Connector Instance NOT FOUND!" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Error getting instance: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n═══ STEP 3: CHECK IF DATA FROM CCF EXISTS ═══" -ForegroundColor Cyan
Write-Host "Checking if ANY data came from CCF (vs Logic Apps)..." -ForegroundColor Yellow

# Logic Apps data has specific timestamps (every 15 min)
# CCF data would have different timestamps (every 5 min if configured)

$query = @"
TacitRed_Findings_CL
| summarize Count=count(), 
    Latest=max(TimeGenerated), 
    Earliest=min(TimeGenerated),
    UniqueMinutes=dcount(bin(TimeGenerated, 1m))
| extend DataSource = case(
    UniqueMinutes > 50, "Likely CCF (many different times)",
    UniqueMinutes < 20, "Likely Logic Apps (batched)",
    "Mixed or Unknown"
)
"@

try {
    $result = az monitor log-analytics query --workspace $ws --analytics-query $query 2>$null | ConvertFrom-Json
    
    if($result.tables -and $result.tables[0].rows.Count -gt 0){
        $row = $result.tables[0].rows[0]
        Write-Host "  Total Records: $($row[0])" -ForegroundColor Gray
        Write-Host "  Latest: $($row[1])" -ForegroundColor Gray  
        Write-Host "  Earliest: $($row[2])" -ForegroundColor Gray
        Write-Host "  Unique Minutes: $($row[3])" -ForegroundColor Gray
        Write-Host "  Assessment: $($row[4])" -ForegroundColor Cyan
    }
} catch {
    Write-Host "  ✗ Query failed" -ForegroundColor Red
}

Write-Host "`n═══ STEP 4: POSSIBLE ISSUES ═══" -ForegroundColor Cyan

$issues = @()

if(-not $connDef){
    $issues += "❌ Connector Definition missing - CCF cannot work without it"
}

if(-not $connInst){
    $issues += "❌ Connector Instance missing - Nothing to poll"
}

if($connInst){
    if(-not $connInst.properties.isActive){
        $issues += "❌ Connector is NOT ACTIVE"
    }
    
    if(-not $connInst.properties.auth.ApiKey){
        $issues += "❌ API Key is NULL - Cannot authenticate"
    }
    
    if(-not $connInst.properties.dcrConfig){
        $issues += "❌ DCR Config missing - Cannot send data"
    }
    
    if($connInst.properties.request.queryWindowInMin -ne 5){
        $issues += "⚠️ queryWindowInMin is NOT 5 (still $($connInst.properties.request.queryWindowInMin))"
    }
}

if($issues.Count -gt 0){
    Write-Host "`n🔴 ISSUES FOUND:" -ForegroundColor Red
    foreach($issue in $issues){
        Write-Host "  $issue" -ForegroundColor Yellow
    }
}else{
    Write-Host "`n✅ No obvious configuration issues" -ForegroundColor Green
    Write-Host "`n💡 POSSIBLE REASONS CCF ISN'T POLLING:" -ForegroundColor Yellow
    Write-Host "  1. CCF polling is disabled at Azure backend (rare bug)" -ForegroundColor White
    Write-Host "  2. API key format issue (Logic Apps work but CCF doesn't recognize it)" -ForegroundColor White
    Write-Host "  3. CCF connector type issue (RestApiPoller might have issues)" -ForegroundColor White
    Write-Host "  4. Azure propagation delay (very unlikely after 1 hour)" -ForegroundColor White
}

Write-Host "`n═══ STEP 5: RECOMMENDATION ═══" -ForegroundColor Cyan

if($issues.Count -gt 0){
    Write-Host "Fix the issues above first, then:" -ForegroundColor Yellow
}

Write-Host "`n📋 WORKAROUND FOR CUSTOMER:" -ForegroundColor Cyan
Write-Host "Since Logic Apps work perfectly:" -ForegroundColor White
Write-Host "  Option 1: Deploy BOTH CCF + Logic Apps in marketplace package" -ForegroundColor Gray
Write-Host "  - Logic Apps as backup/failsafe" -ForegroundColor DarkGray
Write-Host "  - CCF as primary (may work for customers even if not in your test)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Option 2: Deploy CCF only (as planned)" -ForegroundColor Gray  
Write-Host "  - Your test environment may have a specific issue" -ForegroundColor DarkGray
Write-Host "  - Customer environments will be clean deployments" -ForegroundColor DarkGray
Write-Host "  - CCF works in production for many customers" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Option 3: Contact Microsoft Sentinel Support" -ForegroundColor Gray
Write-Host "  - Report CCF RestApiPoller not polling" -ForegroundColor DarkGray
Write-Host "  - Provide connector config from docs\\ccf-connector-current-state.json" -ForegroundColor DarkGray

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

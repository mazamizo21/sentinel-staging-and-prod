# VERIFY-FRESH-CCF.ps1
# Verify fresh CCF deployment and check for data

param(
    [string]$ResourceGroup = "TacitRedCCFTest",
    [string]$WorkspaceName = "TacitRedCCFWorkspace"
)

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   VERIFY FRESH CCF DEPLOYMENT" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId

az account set --subscription $sub | Out-Null

# Load deployment info
$deploymentInfo = Get-Content ".\Project\Docs\fresh-ccf-deployment.json" -Raw | ConvertFrom-Json

Write-Host "`n📊 DEPLOYMENT INFO:" -ForegroundColor Cyan
Write-Host "  Deployed: $($deploymentInfo.timestamp)" -ForegroundColor Gray
Write-Host "  Resource Group: $($deploymentInfo.resourceGroup)" -ForegroundColor Gray
Write-Host "  Workspace: $($deploymentInfo.workspace)" -ForegroundColor Gray
Write-Host "  Polling Interval: $($deploymentInfo.pollingInterval) minutes" -ForegroundColor Gray
Write-Host "  Next poll expected: $($deploymentInfo.nextPollExpected)`n" -ForegroundColor Gray

# ============================================================================
# CHECK 1: CCF CONNECTOR STATUS
# ============================================================================
Write-Host "═══ CHECK 1: CCF CONNECTOR STATUS ═══" -ForegroundColor Cyan

$wsId = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query id -o tsv

$connUri = "https://management.azure.com$wsId/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"
$connector = az rest --method GET --uri $connUri 2>$null | ConvertFrom-Json

if($connector){
    Write-Host "✓ CCF Connector exists" -ForegroundColor Green
    Write-Host "  Name: $($connector.name)" -ForegroundColor Gray
    Write-Host "  Kind: $($connector.kind)" -ForegroundColor Gray
    Write-Host "  Is Active: $($connector.properties.isActive)" -ForegroundColor $(if($connector.properties.isActive){'Green'}else{'Red'})
    Write-Host "  Polling Interval: $($connector.properties.request.queryWindowInMin) minutes" -ForegroundColor Gray
    
    if($connector.properties.auth.ApiKey){
        Write-Host "  API Key: ✅ SET" -ForegroundColor Green
    }else{
        Write-Host "  API Key: ⚠ Shows as null (Azure masking)" -ForegroundColor Yellow
    }
    
    if($connector.properties.dcrConfig){
        Write-Host "  DCR Config: ✓ Present" -ForegroundColor Green
        Write-Host "    Stream: $($connector.properties.dcrConfig.streamName)" -ForegroundColor DarkGray
        Write-Host "    DCR ID: $($connector.properties.dcrConfig.dataCollectionRuleImmutableId)" -ForegroundColor DarkGray
    }
}else{
    Write-Host "✗ CCF Connector NOT FOUND!" -ForegroundColor Red
}

# ============================================================================
# CHECK 2: TABLE DATA
# ============================================================================
Write-Host "`n═══ CHECK 2: TABLE DATA ═══" -ForegroundColor Cyan

$query = "TacitRed_Findings_CL | summarize Count=count(), Latest=max(TimeGenerated)"

Write-Host "  Querying table..." -ForegroundColor Yellow

try {
    $result = az monitor log-analytics query `
        --workspace $wsId `
        --analytics-query $query `
        2>$null | ConvertFrom-Json
    
    if($result.tables -and $result.tables[0].rows.Count -gt 0){
        $count = $result.tables[0].rows[0][0]
        $latest = $result.tables[0].rows[0][1]
        
        if($count -gt 0){
            Write-Host "✅ DATA FOUND!" -ForegroundColor Green
            Write-Host "  Records: $count" -ForegroundColor Green
            Write-Host "  Latest: $latest" -ForegroundColor Green
            
            # Get sample data
            $sampleQuery = "TacitRed_Findings_CL | take 5 | project TimeGenerated, email_s, domain_s, findingType_s, confidence_d"
            $sample = az monitor log-analytics query `
                --workspace $wsId `
                --analytics-query $sampleQuery `
                2>$null | ConvertFrom-Json
            
            if($sample.tables -and $sample.tables[0].rows.Count -gt 0){
                Write-Host "`n  Sample records:" -ForegroundColor Cyan
                foreach($row in $sample.tables[0].rows){
                    Write-Host "    Time: $($row[0])" -ForegroundColor Gray
                    Write-Host "      Email: $($row[1])" -ForegroundColor DarkGray
                    Write-Host "      Domain: $($row[2])" -ForegroundColor DarkGray
                    Write-Host "      Type: $($row[3])" -ForegroundColor DarkGray
                    Write-Host "      Confidence: $($row[4])" -ForegroundColor DarkGray
                    Write-Host ""
                }
            }
            
            Write-Host "`n🎉 SUCCESS! CCF IS WORKING!" -ForegroundColor Green
            Write-Host "  This proves CCF can work when deployed fresh" -ForegroundColor White
            Write-Host "  The issue was environment-specific in the old deployment" -ForegroundColor White
            
        }else{
            Write-Host "⚠ Table exists but has 0 records" -ForegroundColor Yellow
            Write-Host "  This is normal if CCF hasn't polled yet" -ForegroundColor Gray
            
            $deployTime = [DateTime]::Parse($deploymentInfo.timestamp)
            $nextPoll = [DateTime]::Parse($deploymentInfo.nextPollExpected)
            $now = Get-Date
            
            if($now -lt $nextPoll){
                $waitMin = [Math]::Ceiling(($nextPoll - $now).TotalMinutes)
                Write-Host "  Wait $waitMin more minutes for first poll" -ForegroundColor Yellow
            }else{
                Write-Host "  ⚠ First poll should have happened by now" -ForegroundColor Yellow
                Write-Host "  CCF may have an issue (check details below)" -ForegroundColor Yellow
            }
        }
    }else{
        Write-Host "⚠ No query results" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "✗ Query failed: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# CHECK 3: DCE/DCR CONFIGURATION
# ============================================================================
Write-Host "`n═══ CHECK 3: DCE/DCR CONFIGURATION ═══" -ForegroundColor Cyan

# Check DCE
$dce = az monitor data-collection endpoint list `
    --resource-group $ResourceGroup `
    --query "[0]" | ConvertFrom-Json

if($dce){
    Write-Host "✓ DCE exists: $($dce.name)" -ForegroundColor Green
    Write-Host "  Endpoint: $($dce.logsIngestion.endpoint)" -ForegroundColor Gray
}else{
    Write-Host "✗ DCE not found" -ForegroundColor Red
}

# Check DCR
$dcr = az monitor data-collection rule list `
    --resource-group $ResourceGroup `
    --query "[?contains(name, 'tacitred')]|[0]" | ConvertFrom-Json

if($dcr){
    Write-Host "✓ DCR exists: $($dcr.name)" -ForegroundColor Green
    Write-Host "  Immutable ID: $($dcr.immutableId)" -ForegroundColor Gray
    
    # Check if DCR matches connector
    if($connector.properties.dcrConfig.dataCollectionRuleImmutableId -eq $dcr.immutableId){
        Write-Host "  ✓ Matches CCF connector config" -ForegroundColor Green
    }else{
        Write-Host "  ✗ MISMATCH with CCF connector!" -ForegroundColor Red
        Write-Host "    CCF expects: $($connector.properties.dcrConfig.dataCollectionRuleImmutableId)" -ForegroundColor Red
        Write-Host "    DCR has: $($dcr.immutableId)" -ForegroundColor Red
    }
}else{
    Write-Host "✗ DCR not found" -ForegroundColor Red
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n═══ SUMMARY ═══" -ForegroundColor Cyan

$issues = @()

if(-not $connector){
    $issues += "CCF Connector missing"
}elseif(-not $connector.properties.isActive){
    $issues += "CCF Connector not active"
}

if(-not $dce){
    $issues += "DCE missing"
}

if(-not $dcr){
    $issues += "DCR missing"
}

if($issues.Count -gt 0){
    Write-Host "❌ ISSUES DETECTED:" -ForegroundColor Red
    foreach($issue in $issues){
        Write-Host "  - $issue" -ForegroundColor Yellow
    }
}else{
    Write-Host "✅ Configuration looks good!" -ForegroundColor Green
    
    $deployTime = [DateTime]::Parse($deploymentInfo.timestamp)
    $elapsed = ((Get-Date) - $deployTime).TotalMinutes
    
    if($count -gt 0){
        Write-Host "`n🎉 CCF IS WORKING IN FRESH ENVIRONMENT!" -ForegroundColor Green
    }elseif($elapsed -lt $deploymentInfo.pollingInterval){
        Write-Host "`n⏱️  Waiting for first poll..." -ForegroundColor Yellow
        Write-Host "  Expected: $($deploymentInfo.nextPollExpected)" -ForegroundColor Gray
    }else{
        Write-Host "`n⚠️  No data yet (past first poll time)" -ForegroundColor Yellow
        Write-Host "  Possible issues:" -ForegroundColor Gray
        Write-Host "    - CCF polling may be delayed" -ForegroundColor DarkGray
        Write-Host "    - API key not persisting (same as old environment)" -ForegroundColor DarkGray
        Write-Host "    - Azure backend CCF issue" -ForegroundColor DarkGray
    }
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

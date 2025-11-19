# Validate TacitRed CCF Fix - Quick Status Check
# Run this script to verify the fix is working

$workspaceId = "72e125d2-4f75-4497-a6b5-90241feb387a"

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     TACITRED CCF FIX VALIDATION                              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Check 1: Record Count
Write-Host "[1] Checking record count..." -ForegroundColor Yellow
$countResult = az monitor log-analytics query --workspace $workspaceId --analytics-query "TacitRed_Findings_CL | count" -o json | ConvertFrom-Json
$recordCount = if ($countResult.tables[0].rows) { [int]$countResult.tables[0].rows[0][0] } else { 0 }

if ($recordCount -gt 0) {
    Write-Host "    ✅ SUCCESS: $recordCount records found!" -ForegroundColor Green
} else {
    Write-Host "    ⏳ No records yet - expected if less than 60 min since deployment" -ForegroundColor Gray
}

# Check 2: Connector Status
Write-Host "`n[2] Checking connector status..." -ForegroundColor Yellow
$connectorUri = "https://management.azure.com/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/TacitRed-Production-Test-RG/providers/Microsoft.OperationalInsights/workspaces/TacitRed-Production-Test-Workspace/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview"
$connector = az rest --method get --uri $connectorUri -o json | ConvertFrom-Json

Write-Host "    Active: $($connector.properties.isActive)" -ForegroundColor $(if($connector.properties.isActive){'Green'}else{'Red'})
Write-Host "    Stream: $($connector.properties.dcrConfig.streamName)" -ForegroundColor $(if($connector.properties.dcrConfig.streamName -eq 'Custom-TacitRed_Findings_Raw'){'Green'}else{'Red'})
Write-Host "    Polling: $($connector.properties.request.queryWindowInMin) minutes" -ForegroundColor Gray

# Check 3: DCR Configuration
Write-Host "`n[3] Checking DCR configuration..." -ForegroundColor Yellow
$dcrStream = az monitor data-collection rule show -g TacitRed-Production-Test-RG -n dcr-tacitred-findings --query "dataFlows[0].streams[0]" -o tsv
Write-Host "    Input Stream: $dcrStream" -ForegroundColor $(if($dcrStream -eq 'Custom-TacitRed_Findings_Raw'){'Green'}else{'Red'})

# Check 4: Type Conversions (if data exists)
if ($recordCount -gt 0) {
    Write-Host "`n[4] Validating type conversions..." -ForegroundColor Yellow
    $typeQuery = 'TacitRed_Findings_CL | take 1 | project conf_type=gettype(confidence_d), first_type=gettype(firstSeen_t), det_type=gettype(detection_ts_t)'
    $typeResult = az monitor log-analytics query --workspace $workspaceId --analytics-query $typeQuery -o json | ConvertFrom-Json
    
    if ($typeResult.tables[0].rows) {
        $confType = $typeResult.tables[0].rows[0][0]
        $firstType = $typeResult.tables[0].rows[0][1]
        $detType = $typeResult.tables[0].rows[0][2]
        
        Write-Host "    confidence_d: $confType" -ForegroundColor $(if($confType -eq 'int'){'Green'}else{'Red'})
        Write-Host "    firstSeen_t: $firstType" -ForegroundColor $(if($firstType -eq 'datetime'){'Green'}else{'Red'})
        Write-Host "    detection_ts_t: $detType" -ForegroundColor $(if($detType -eq 'datetime'){'Green'}else{'Red'})
    }
}

# Summary
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     VALIDATION SUMMARY                                       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$allGood = $true

if ($connector.properties.isActive -ne $true) {
    Write-Host "❌ Connector is not active" -ForegroundColor Red
    $allGood = $false
}

if ($connector.properties.dcrConfig.streamName -ne 'Custom-TacitRed_Findings_Raw') {
    Write-Host "❌ Stream name is incorrect (should be Custom-TacitRed_Findings_Raw)" -ForegroundColor Red
    $allGood = $false
}

if ($dcrStream -ne 'Custom-TacitRed_Findings_Raw') {
    Write-Host "❌ DCR input stream is incorrect" -ForegroundColor Red
    $allGood = $false
}

if ($recordCount -eq 0) {
    Write-Host "⏳ No data yet - wait for first poll cycle (up to 60 min)" -ForegroundColor Yellow
    Write-Host "   Next poll expected at: $(((Get-Date).AddMinutes(60 - ((Get-Date).Minute % 60))).ToString('HH:mm'))" -ForegroundColor Gray
} else {
    Write-Host "✅ Data ingestion working: $recordCount records" -ForegroundColor Green
}

if ($allGood -and $recordCount -gt 0) {
    Write-Host "`n🎉 ALL CHECKS PASSED - CCF FIX SUCCESSFUL!" -ForegroundColor Green
} elseif ($allGood) {
    Write-Host "`n✅ Configuration correct - awaiting first data poll" -ForegroundColor Green
} else {
    Write-Host "`n⚠️  Issues detected - review output above" -ForegroundColor Yellow
}

Write-Host ""

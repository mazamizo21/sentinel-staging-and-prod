# Monitor TacitRed CCF Ingestion - Real-time polling verification
[CmdletBinding()]
param(
    [int]$DurationMinutes = 10,
    [int]$CheckIntervalSeconds = 30
)

$workspaceId = "72e125d2-4f75-4497-a6b5-90241feb387a"
$startTime = Get-Date
$endTime = $startTime.AddMinutes($DurationMinutes)

Write-Host "=== TacitRed CCF Ingestion Monitor ===" -ForegroundColor Cyan
Write-Host "Workspace ID: $workspaceId" -ForegroundColor Gray
Write-Host "Monitoring for: $DurationMinutes minutes" -ForegroundColor Gray
Write-Host "Check interval: $CheckIntervalSeconds seconds`n" -ForegroundColor Gray

$iteration = 0
while ((Get-Date) -lt $endTime) {
    $iteration++
    $now = Get-Date -Format "HH:mm:ss"
    
    Write-Host "[$now] Check #$iteration" -ForegroundColor Yellow
    
    # Check record count
    $countQuery = "TacitRed_Findings_CL | count"
    $countResult = az monitor log-analytics query --workspace $workspaceId --analytics-query $countQuery -o json | ConvertFrom-Json
    $recordCount = if ($countResult -and $countResult.tables -and $countResult.tables[0].rows) { 
        [int]$countResult.tables[0].rows[0][0] 
    } else { 
        0 
    }
    
    if ($recordCount -gt 0) {
        Write-Host "  ✅ SUCCESS: $recordCount records found!" -ForegroundColor Green
        
        # Get latest records
        $latestQuery = "TacitRed_Findings_CL | sort by TimeGenerated desc | take 5 | project TimeGenerated, email_s, domain_s, confidence_d, source_s"
        $latestResult = az monitor log-analytics query --workspace $workspaceId --analytics-query $latestQuery -o json | ConvertFrom-Json
        
        Write-Host "`n  Latest Records:" -ForegroundColor Cyan
        foreach ($row in $latestResult.tables[0].rows) {
            Write-Host "    - $($row[0]) | $($row[1]) | $($row[2]) | Confidence: $($row[3])" -ForegroundColor Gray
        }
        
        Write-Host "`n✅ Data ingestion confirmed. Monitoring complete." -ForegroundColor Green
        break
    } else {
        Write-Host "  ⏳ No records yet (0)" -ForegroundColor Gray
        
        # Check connector health
        $connectorUri = "https://management.azure.com/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/TacitRed-Production-Test-RG/providers/Microsoft.OperationalInsights/workspaces/TacitRed-Production-Test-Workspace/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview"
        $connector = az rest --method get --uri $connectorUri -o json | ConvertFrom-Json
        $isActive = $connector.properties.isActive
        
        Write-Host "     Connector Active: $isActive" -ForegroundColor Gray
    }
    
    $remainingMinutes = [math]::Round((New-TimeSpan -Start (Get-Date) -End $endTime).TotalMinutes, 1)
    Write-Host "     Waiting $CheckIntervalSeconds seconds... ($remainingMinutes min remaining)`n" -ForegroundColor DarkGray
    
    Start-Sleep -Seconds $CheckIntervalSeconds
}

if ($recordCount -eq 0) {
    Write-Host "`n⚠️  No data after $DurationMinutes minutes of monitoring." -ForegroundColor Yellow
    Write-Host "   Next steps:" -ForegroundColor Cyan
    Write-Host "   1. Check TacitRed API has data in the 1-minute window" -ForegroundColor Gray
    Write-Host "   2. Review AzureDiagnostics for DCR errors" -ForegroundColor Gray
    Write-Host "   3. Verify API key is valid" -ForegroundColor Gray
}

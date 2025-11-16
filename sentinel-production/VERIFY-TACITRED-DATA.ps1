# VERIFY-TACITRED-DATA.ps1
# Check for TacitRed data ingestion

$ErrorActionPreference = 'Stop'

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$ws = $config.parameters.azure.value.workspaceName

Write-Host "`n═══ VERIFYING TACITRED DATA INGESTION ═══" -ForegroundColor Cyan
Write-Host "Workspace: $ws`n" -ForegroundColor Gray

az account set --subscription $sub | Out-Null

$query = "TacitRed_Findings_CL | summarize Count=count(), Latest=max(TimeGenerated), Earliest=min(TimeGenerated)"

Write-Host "Querying TacitRed_Findings_CL table..." -ForegroundColor Yellow

try {
    $result = az monitor log-analytics query -w $ws --analytics-query $query 2>$null | ConvertFrom-Json
    
    if($result.tables -and $result.tables[0].rows.Count -gt 0){
        $count = $result.tables[0].rows[0][0]
        $latest = $result.tables[0].rows[0][1]
        $earliest = $result.tables[0].rows[0][2]
        
        if($count -gt 0){
            Write-Host "✅ SUCCESS! Data found in table!" -ForegroundColor Green
            Write-Host "  Total Records: $count" -ForegroundColor Green
            Write-Host "  Latest: $latest" -ForegroundColor Gray
            Write-Host "  Earliest: $earliest" -ForegroundColor Gray
            
            # Sample query
            Write-Host "`n📊 Sample Data:" -ForegroundColor Cyan
            $sampleQuery = "TacitRed_Findings_CL | take 5 | project TimeGenerated, email_s, domain_s, findingType_s, confidence_d"
            $sample = az monitor log-analytics query -w $ws --analytics-query $sampleQuery 2>$null | ConvertFrom-Json
            
            if($sample.tables -and $sample.tables[0].rows.Count -gt 0){
                foreach($row in $sample.tables[0].rows){
                    Write-Host "  Email: $($row[1])" -ForegroundColor Gray
                    Write-Host "    Domain: $($row[2])" -ForegroundColor DarkGray
                    Write-Host "    Type: $($row[3])" -ForegroundColor DarkGray
                    Write-Host "    Confidence: $($row[4])" -ForegroundColor DarkGray
                    Write-Host ""
                }
            }
        }else{
            Write-Host "⚠ Table exists but has 0 records" -ForegroundColor Yellow
            Write-Host "`n💡 POSSIBLE REASONS:" -ForegroundColor Cyan
            Write-Host "  1. Data hasn't propagated yet (wait 5-10 minutes total)" -ForegroundColor White
            Write-Host "  2. TacitRed API had no findings in the queried time window" -ForegroundColor White
            Write-Host "  3. Data sent but ingestion still processing" -ForegroundColor White
            Write-Host "`n📋 ACTION:" -ForegroundColor Cyan
            Write-Host "  Re-run this script in 5 minutes" -ForegroundColor White
        }
    }else{
        Write-Host "⚠ Table query returned no results" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "✗ Query failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

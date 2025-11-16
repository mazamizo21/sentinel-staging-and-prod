# CHECK-TABLE-AT-EXACT-TIME.ps1
# Query for data at the exact time the Logic App ran

$ErrorActionPreference = 'Stop'

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$ws = $config.parameters.azure.value.workspaceName

az account set --subscription $sub | Out-Null

Write-Host "`n═══ CHECKING FOR DATA AT EXACT TIME ═══" -ForegroundColor Cyan
Write-Host "Logic App ran at: 2025-11-14 20:41:47 UTC" -ForegroundColor Gray
Write-Host "Workspace: $ws`n" -ForegroundColor Gray

# Query for data around that time (+/- 1 hour for propagation delay)
$query = @"
TacitRed_Findings_CL
| where TimeGenerated between (datetime(2025-11-14T19:41:00Z) .. datetime(2025-11-14T21:45:00Z))
| summarize Count=count(), 
    Earliest=min(TimeGenerated), 
    Latest=max(TimeGenerated)
"@

Write-Host "Querying for data between 19:41 and 21:45 UTC..." -ForegroundColor Yellow

try {
    $result = az monitor log-analytics query -w $ws --analytics-query $query 2>$null | ConvertFrom-Json
    
    if($result.tables -and $result.tables[0].rows.Count -gt 0){
        $count = $result.tables[0].rows[0][0]
        
        if($count -gt 0){
            Write-Host "✅ FOUND $count RECORDS!" -ForegroundColor Green
            Write-Host "  Earliest: $($result.tables[0].rows[0][1])" -ForegroundColor Gray
            Write-Host "  Latest: $($result.tables[0].rows[0][2])" -ForegroundColor Gray
            
            # Get sample data
            $sampleQuery = @"
TacitRed_Findings_CL
| where TimeGenerated between (datetime(2025-11-14T19:41:00Z) .. datetime(2025-11-14T21:45:00Z))
| take 5
| project TimeGenerated, email_s, domain_s, findingType_s, confidence_d
"@
            
            Write-Host "`n📊 Sample Records:" -ForegroundColor Cyan
            $sample = az monitor log-analytics query -w $ws --analytics-query $sampleQuery 2>$null | ConvertFrom-Json
            
            if($sample.tables -and $sample.tables[0].rows.Count -gt 0){
                foreach($row in $sample.tables[0].rows){
                    Write-Host "  Time: $($row[0])" -ForegroundColor Gray
                    Write-Host "    Email: $($row[1])" -ForegroundColor DarkGray
                    Write-Host "    Domain: $($row[2])" -ForegroundColor DarkGray
                    Write-Host "    Type: $($row[3])" -ForegroundColor DarkGray
                    Write-Host "    Confidence: $($row[4])" -ForegroundColor DarkGray
                    Write-Host ""
                }
            }
            
        }else{
            Write-Host "⚠ Table exists but 0 records in this time range" -ForegroundColor Yellow
        }
    }else{
        Write-Host "⚠ No results found" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "✗ Query failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Also check ANY data in the table
Write-Host "`n═══ CHECKING FOR ANY DATA (ALL TIME) ═══" -ForegroundColor Cyan

$query2 = "TacitRed_Findings_CL | summarize Count=count(), Latest=max(TimeGenerated)"

try {
    $result2 = az monitor log-analytics query -w $ws --analytics-query $query2 2>$null | ConvertFrom-Json
    
    if($result2.tables -and $result2.tables[0].rows.Count -gt 0){
        $count = $result2.tables[0].rows[0][0]
        $latest = $result2.tables[0].rows[0][1]
        
        if($count -gt 0){
            Write-Host "✅ Total records in table: $count" -ForegroundColor Green
            Write-Host "  Latest data: $latest" -ForegroundColor Gray
        }else{
            Write-Host "⚠ Table has 0 records total" -ForegroundColor Yellow
        }
    }
    
} catch {
    Write-Host "✗ Query failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

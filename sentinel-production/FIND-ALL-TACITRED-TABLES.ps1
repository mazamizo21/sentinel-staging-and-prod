# FIND-ALL-TACITRED-TABLES.ps1
# Search for ALL tables with TacitRed data

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   SEARCHING ALL TABLES FOR TACITRED DATA" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$ws = $config.parameters.azure.value.workspaceName

az account set --subscription $sub | Out-Null

Write-Host "Workspace: $ws`n" -ForegroundColor Gray

# Search for ANY table containing "tacitred" in name or with TacitRed data
$searchQuery = @"
search *
| where TimeGenerated > ago(7d)
| where * contains "tacitred" or * contains "TacitRed" or * contains "email" or * contains "findingType"
| summarize Count = count(), 
    Latest = max(TimeGenerated),
    Earliest = min(TimeGenerated)
  by `$table
| order by Count desc
"@

Write-Host "Searching for TacitRed-related data in ALL tables..." -ForegroundColor Yellow

try {
    $result = az monitor log-analytics query -w $ws --analytics-query $searchQuery 2>$null | ConvertFrom-Json
    
    if($result.tables -and $result.tables[0].rows.Count -gt 0){
        Write-Host "✅ FOUND DATA IN TABLES!" -ForegroundColor Green
        Write-Host ""
        
        foreach($row in $result.tables[0].rows){
            $tableName = $row[0]
            $count = $row[1]
            $latest = $row[2]
            $earliest = $row[3]
            
            Write-Host "📊 TABLE: $tableName" -ForegroundColor Cyan
            Write-Host "   Records: $count" -ForegroundColor Green
            Write-Host "   Latest: $latest" -ForegroundColor Gray
            Write-Host "   Earliest: $earliest" -ForegroundColor Gray
            Write-Host ""
            
            # Get sample data from this table
            $sampleQuery = @"
$tableName
| where TimeGenerated > ago(7d)
| take 3
| project TimeGenerated, *
"@
            
            Write-Host "   Sample data:" -ForegroundColor Yellow
            $sample = az monitor log-analytics query -w $ws --analytics-query $sampleQuery 2>$null | ConvertFrom-Json
            
            if($sample.tables -and $sample.tables[0].columns){
                $columns = $sample.tables[0].columns | ForEach-Object {$_.name}
                Write-Host "   Columns: $($columns -join ', ')" -ForegroundColor DarkGray
            }
            
            Write-Host ""
        }
        
    }else{
        Write-Host "⚠ No data found in any tables" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "✗ Search failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Also specifically check these table names
Write-Host "═══ CHECKING SPECIFIC TABLE NAMES ═══" -ForegroundColor Cyan

$tableNames = @(
    'TacitRed_Findings_CL',
    'TacitRed_Findings_Test_CL',
    'TacitRed_CL',
    'TacitRedFindings_CL',
    'Custom_TacitRed_CL',
    'TacitRed_Findings_Raw_CL'
)

foreach($tableName in $tableNames){
    Write-Host "`n[$tableName]" -ForegroundColor Yellow
    
    $query = "$tableName | summarize Count=count(), Latest=max(TimeGenerated)"
    
    try {
        $result = az monitor log-analytics query -w $ws --analytics-query $query 2>$null | ConvertFrom-Json
        
        if($result.tables -and $result.tables[0].rows.Count -gt 0){
            $count = $result.tables[0].rows[0][0]
            $latest = $result.tables[0].rows[0][1]
            
            if($count -gt 0){
                Write-Host "  ✅ $count records" -ForegroundColor Green
                Write-Host "  Latest: $latest" -ForegroundColor Gray
            }else{
                Write-Host "  ⚠ 0 records" -ForegroundColor Yellow
            }
        }else{
            Write-Host "  ✗ Table not found" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "  ✗ Query failed" -ForegroundColor Red
    }
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

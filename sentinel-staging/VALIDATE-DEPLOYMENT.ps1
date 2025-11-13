#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates Azure Sentinel Threat Intelligence deployment status
.DESCRIPTION
    Checks RBAC assignments, Logic App health, and data ingestion status.
    Run this 30-60 minutes after DEPLOY-COMPLETE.ps1 to verify RBAC propagation.
.EXAMPLE
    .\VALIDATE-DEPLOYMENT.ps1
#>

param(
    [switch]$Detailed
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
Write-Host "   AZURE SENTINEL TI DEPLOYMENT VALIDATION" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Subscription: $sub" -ForegroundColor Gray
Write-Host "Resource Group: $rg" -ForegroundColor Gray
Write-Host "Workspace: $ws`n" -ForegroundColor Gray

az account set --subscription $sub | Out-Null

# Validation results
$validationResults = @{
    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    LogicApps = @()
    Tables = @()
    OverallStatus = "Unknown"
}

# Check Logic Apps
Write-Host "═══ LOGIC APPS STATUS ═══" -ForegroundColor Cyan

$laNames = @('logic-cyren-ip-reputation','logic-cyren-malware-urls','logic-tacitred-ingestion')
$allSuccess = $true

foreach($laName in $laNames){
    Write-Host "`n[$laName]" -ForegroundColor Yellow
    
    try {
        # Get Logic App
        $la = az logic workflow show -g $rg -n $laName 2>$null | ConvertFrom-Json
        if(-not $la){
            Write-Host "  ✗ Logic App not found" -ForegroundColor Red
            $allSuccess = $false
            continue
        }
        
        $principal = $la.identity.principalId
        $dcrImm = $la.properties.parameters.dcrImmutableId.value
        
        # Check RBAC
        $dcrs = az rest --method GET --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Insights/dataCollectionRules?api-version=2022-06-01" 2>$null | ConvertFrom-Json
        $dcr = $dcrs.value | Where-Object { $_.properties.immutableId -eq $dcrImm } | Select-Object -First 1
        
        $dceEndpoint = $la.properties.parameters.dceEndpoint.value
        $dceHost = ([uri]$dceEndpoint).Host
        $dces = az rest --method GET --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Insights/dataCollectionEndpoints?api-version=2022-06-01" 2>$null | ConvertFrom-Json
        $dce = $dces.value | Where-Object { $_.properties.logsIngestion.endpoint -like "*${dceHost}*" } | Select-Object -First 1
        
        # Check all RBAC for this principal
        $allRoles = az role assignment list --all --assignee $principal 2>$null | ConvertFrom-Json
        $dcrRole = $allRoles | Where-Object { $_.scope -eq $dcr.id }
        $dceRole = $allRoles | Where-Object { $_.scope -eq $dce.id }
        
        $dcrOK = $null -ne $dcrRole
        $dceOK = $null -ne $dceRole
        
        Write-Host "  RBAC Status:" -ForegroundColor Gray
        Write-Host ("    DCR ({0}): {1}" -f $dcr.name, $(if($dcrOK){"✓"}else{"✗ MISSING"})) -ForegroundColor $(if($dcrOK){'Green'}else{'Red'})
        Write-Host ("    DCE ({0}): {1}" -f $dce.name, $(if($dceOK){"✓"}else{"✗ MISSING"})) -ForegroundColor $(if($dceOK){'Green'}else{'Red'})
        
        if($Detailed -and $dcrRole){
            Write-Host ("      Created: {0}" -f $dcrRole.properties.createdOn) -ForegroundColor Gray
        }
        
        # Get latest run
        $runsUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/runs?api-version=2019-05-01"
        $runs = az rest --method GET --uri $runsUri 2>$null | ConvertFrom-Json
        
        $sendStatus = "N/A"
        $errorCode = "None"
        
        if($runs.value -and $runs.value.Count -gt 0){
            $latestRun = $runs.value[0]
            $runTime = [DateTime]::Parse($latestRun.properties.startTime).ToString('yyyy-MM-dd HH:mm:ss')
            
            $sendUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/runs/$($latestRun.name)/actions/Send_to_DCE?api-version=2019-05-01"
            $send = az rest --method GET --uri $sendUri 2>$null | ConvertFrom-Json
            
            if($send){
                $sendStatus = $send.properties.status
                if($send.properties.error){
                    $errorCode = $send.properties.error.code
                }
                
                Write-Host "  Latest Run:" -ForegroundColor Gray
                Write-Host ("    Time: {0}" -f $runTime) -ForegroundColor Gray
                Write-Host ("    Send_to_DCE: {0}" -f $sendStatus) -ForegroundColor $(if($sendStatus -eq 'Succeeded'){'Green'}elseif($sendStatus -match 'Running'){'Yellow'}else{'Red'})
                
                if($errorCode -ne "None"){
                    Write-Host ("    Error: {0}" -f $errorCode) -ForegroundColor Red
                    $allSuccess = $false
                }
            }
        }else{
            Write-Host "  Latest Run: No runs found" -ForegroundColor Gray
        }
        
        # Overall status for this LA
        $laOK = $dcrOK -and $dceOK -and $sendStatus -eq 'Succeeded'
        
        $validationResults.LogicApps += @{
            Name = $laName
            DCR_RBAC = $dcrOK
            DCE_RBAC = $dceOK
            LastRunStatus = $sendStatus
            Error = $errorCode
            Healthy = $laOK
        }
        
        if(-not $laOK){ $allSuccess = $false }
        
    } catch {
        Write-Host "  ✗ Validation error: $($_.Exception.Message)" -ForegroundColor Red
        $allSuccess = $false
    }
}

# Check Tables
Write-Host "`n═══ DATA INGESTION STATUS ═══" -ForegroundColor Cyan

$tables = @(
    @{Name='Cyren_Indicators_CL'; MinRows=1},
    @{Name='TacitRed_Findings_CL'; MinRows=1}
)

foreach($table in $tables){
    Write-Host "`n[$($table.Name)]" -ForegroundColor Yellow
    
    try {
        $query = "$($table.Name) | summarize Count=count(), Latest=max(TimeGenerated)"
        $result = az monitor log-analytics query -w $ws --analytics-query $query 2>$null | ConvertFrom-Json
        
        if($result.tables -and $result.tables[0].rows.Count -gt 0){
            $count = $result.tables[0].rows[0][0]
            $latest = $result.tables[0].rows[0][1]
            
            if($count -ge $table.MinRows){
                Write-Host ("  ✓ {0} rows (latest: {1})" -f $count, $latest) -ForegroundColor Green
                $validationResults.Tables += @{Table=$table.Name; RowCount=$count; Healthy=$true}
            }else{
                Write-Host ("  ⚠ Only {0} rows (expected at least {1})" -f $count, $table.MinRows) -ForegroundColor Yellow
                $validationResults.Tables += @{Table=$table.Name; RowCount=$count; Healthy=$false}
                $allSuccess = $false
            }
        }else{
            Write-Host "  ⚠ No data found" -ForegroundColor Yellow
            $validationResults.Tables += @{Table=$table.Name; RowCount=0; Healthy=$false}
            $allSuccess = $false
        }
    } catch {
        Write-Host "  ✗ Query failed: $($_.Exception.Message)" -ForegroundColor Red
        $validationResults.Tables += @{Table=$table.Name; RowCount=0; Healthy=$false}
        $allSuccess = $false
    }
}

# Summary
Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
if($allSuccess){
    Write-Host "✅ DEPLOYMENT VALIDATION PASSED" -ForegroundColor Green
    Write-Host "All Logic Apps are operational and data is flowing." -ForegroundColor Green
    $validationResults.OverallStatus = "Passed"
}else{
    Write-Host "⚠ DEPLOYMENT VALIDATION INCOMPLETE" -ForegroundColor Yellow
    Write-Host "`nPossible Issues:" -ForegroundColor Yellow
    
    $missingRbac = $validationResults.LogicApps | Where-Object { -not $_.DCR_RBAC -or -not $_.DCE_RBAC }
    if($missingRbac){
        Write-Host "  • Missing RBAC assignments (may still be propagating)" -ForegroundColor Gray
    }
    
    $failedRuns = $validationResults.LogicApps | Where-Object { $_.LastRunStatus -ne 'Succeeded' -and $_.LastRunStatus -ne 'N/A' }
    if($failedRuns){
        Write-Host "  • Failed Logic App runs (check errors above)" -ForegroundColor Gray
    }
    
    $emptyTables = $validationResults.Tables | Where-Object { $_.RowCount -eq 0 }
    if($emptyTables){
        Write-Host "  • No data in some tables (Logic Apps may not have run successfully)" -ForegroundColor Gray
    }
    
    Write-Host "`nRecommended Actions:" -ForegroundColor Yellow
    Write-Host "  1. If RBAC is missing, wait 30-60 minutes for Azure propagation" -ForegroundColor Gray
    Write-Host "  2. Re-run this validation script after waiting" -ForegroundColor Gray
    Write-Host "  3. Manually trigger Logic Apps from Azure Portal" -ForegroundColor Gray
    Write-Host "  4. Check Logic App run history for detailed errors" -ForegroundColor Gray
    
    $validationResults.OverallStatus = "Incomplete"
}
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Save results
$reportFile = ".\Docs\validation-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$validationResults | ConvertTo-Json -Depth 5 | Out-File $reportFile -Encoding UTF8
Write-Host "Validation report saved: $reportFile`n" -ForegroundColor Gray

exit $(if($allSuccess){0}else{1})

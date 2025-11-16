# TRIGGER-TACITRED.ps1
# Manually trigger TacitRed Logic App and monitor execution

$ErrorActionPreference = 'Stop'

Write-Host "`n═══ TRIGGERING TACITRED LOGIC APP ═══" -ForegroundColor Cyan

# Load config
$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName

$laName = "logic-tacitred-ingestion"

Write-Host "Subscription: $sub" -ForegroundColor Gray
Write-Host "Resource Group: $rg" -ForegroundColor Gray
Write-Host "Logic App: $laName`n" -ForegroundColor Gray

az account set --subscription $sub | Out-Null

# Trigger via REST API
Write-Host "Triggering Logic App..." -ForegroundColor Yellow
$triggerUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/triggers/Recurrence/run?api-version=2019-05-01"

try {
    $triggerResult = az rest --method POST --uri $triggerUri 2>&1
    
    if($LASTEXITCODE -eq 0){
        Write-Host "✓ Logic App triggered successfully!" -ForegroundColor Green
    }else{
        Write-Host "⚠ Trigger command completed with warnings (this is usually normal)" -ForegroundColor Yellow
        Write-Host "  Result: $triggerResult" -ForegroundColor Gray
    }
} catch {
    Write-Host "✗ Failed to trigger: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Wait for run to start
Write-Host "`nWaiting 10 seconds for run to start..." -ForegroundColor Gray
Start-Sleep -Seconds 10

# Check for recent runs
Write-Host "`nChecking execution status..." -ForegroundColor Yellow
$runsUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/runs?api-version=2019-05-01&`$top=1"
$runs = az rest --method GET --uri $runsUri 2>$null | ConvertFrom-Json

if($runs.value -and $runs.value.Count -gt 0){
    $latestRun = $runs.value[0]
    $runName = $latestRun.name
    $runStatus = $latestRun.properties.status
    $runStartTime = [DateTime]::Parse($latestRun.properties.startTime).ToString('yyyy-MM-dd HH:mm:ss')
    
    Write-Host "✓ Run started!" -ForegroundColor Green
    Write-Host "  Run Name: $runName" -ForegroundColor Gray
    Write-Host "  Start Time: $runStartTime" -ForegroundColor Gray
    Write-Host "  Status: $runStatus" -ForegroundColor $(if($runStatus -eq 'Succeeded'){'Green'}elseif($runStatus -match 'Running'){'Yellow'}else{'Red'})
    
    # If still running, wait and check again
    if($runStatus -match 'Running'){
        Write-Host "`nWaiting 60 seconds for execution to complete..." -ForegroundColor Yellow
        Start-Sleep -Seconds 60
        
        $runs = az rest --method GET --uri $runsUri 2>$null | ConvertFrom-Json
        $latestRun = $runs.value[0]
        $runStatus = $latestRun.properties.status
        
        Write-Host "Updated Status: $runStatus" -ForegroundColor $(if($runStatus -eq 'Succeeded'){'Green'}else{'Red'})
    }
    
    # Get detailed action status
    Write-Host "`nChecking action details..." -ForegroundColor Yellow
    $actionsUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/runs/$runName/actions?api-version=2019-05-01"
    $actions = az rest --method GET --uri $actionsUri 2>$null | ConvertFrom-Json
    
    if($actions.value){
        Write-Host "`nAction Status:" -ForegroundColor Cyan
        foreach($action in $actions.value){
            $actionStatus = $action.properties.status
            $color = if($actionStatus -eq 'Succeeded'){'Green'}elseif($actionStatus -match 'Running'){'Yellow'}else{'Red'}
            Write-Host "  $($action.name): $actionStatus" -ForegroundColor $color
            
            # Special handling for Send_to_DCE
            if($action.name -eq 'Send_to_DCE'){
                if($action.properties.outputs){
                    $outputs = $action.properties.outputs
                    if($outputs.statusCode){
                        Write-Host "    HTTP Status: $($outputs.statusCode)" -ForegroundColor $(if($outputs.statusCode -eq 204){'Green'}else{'Red'})
                    }
                }
                if($action.properties.error){
                    Write-Host "    Error: $($action.properties.error.code) - $($action.properties.error.message)" -ForegroundColor Red
                }
            }
        }
    }
    
    # Summary
    if($runStatus -eq 'Succeeded'){
        Write-Host "`n✅ LOGIC APP RUN COMPLETED SUCCESSFULLY!" -ForegroundColor Green
        Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Cyan
        Write-Host "  1. Wait 5-10 minutes for data to appear in Log Analytics" -ForegroundColor White
        Write-Host "  2. Query the table:" -ForegroundColor White
        Write-Host "     TacitRed_Findings_CL | summarize count()" -ForegroundColor Gray
        Write-Host "  3. If no data, check if TacitRed API has findings in the time window" -ForegroundColor White
    }else{
        Write-Host "`n⚠ LOGIC APP RUN DID NOT SUCCEED" -ForegroundColor Yellow
        Write-Host "  Status: $runStatus" -ForegroundColor Red
        Write-Host "`n📋 TROUBLESHOOTING:" -ForegroundColor Cyan
        Write-Host "  1. Review action errors above" -ForegroundColor White
        Write-Host "  2. Check Azure Portal > Logic Apps > $laName > Run history" -ForegroundColor White
        Write-Host "  3. Verify TacitRed API key is valid" -ForegroundColor White
    }
    
}else{
    Write-Host "⚠ No runs found yet" -ForegroundColor Yellow
    Write-Host "  The trigger may take a few moments to initiate" -ForegroundColor Gray
    Write-Host "  Check Azure Portal > Logic Apps > $laName > Run history" -ForegroundColor Gray
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

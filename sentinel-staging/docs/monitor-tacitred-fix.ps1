# Monitor TacitRed Logic App until RBAC propagates and it succeeds
# This script will retry every 2 minutes until success

$ErrorActionPreference = "Continue"
$sub = "774bee0e-b281-4f70-8e40-199e35b65117"
$rg = "SentinelTestStixImport"
$laName = "logic-tacitred-ingestion"
$maxAttempts = 15
$attempt = 0

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     TACITRED RBAC PROPAGATION MONITOR                       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Check RBAC age
$principal = 'e3628e94-3565-4ef8-901b-6d296ed5a808'
$assignments = az role assignment list --all --query "[?principalId=='$principal']" | ConvertFrom-Json
$created = [DateTime]::Parse($assignments[0].createdOn)
$age = [Math]::Round(((Get-Date) - $created).TotalMinutes, 1)

Write-Host "RBAC Assignments Created: $($created.ToString('HH:mm:ss')) ($age minutes ago)" -ForegroundColor Gray
Write-Host "Expected propagation: 15-30 minutes`n" -ForegroundColor Gray

while ($attempt -lt $maxAttempts) {
    $attempt++
    $currentAge = [Math]::Round(((Get-Date) - $created).TotalMinutes, 1)
    
    Write-Host "[$attempt/$maxAttempts] Testing at $currentAge minutes..." -ForegroundColor Yellow
    
    # Trigger the Logic App
    $triggerUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/triggers/Recurrence/run?api-version=2016-06-01"
    az rest --method POST --uri $triggerUri 2>&1 | Out-Null
    
    # Wait for run to complete
    Start-Sleep -Seconds 10
    
    # Get latest run
    $runsUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/runs?api-version=2016-06-01"
    $runs = az rest --method GET --uri $runsUri --uri-parameters '$top=1' | ConvertFrom-Json
    $latestRun = $runs.value[0]
    $runId = $latestRun.name
    
    # Get Send_to_DCE action status
    $actionUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/runs/$runId/actions/Send_to_DCE?api-version=2016-06-01"
    $sendAction = az rest --method GET --uri $actionUri | ConvertFrom-Json
    
    $status = $sendAction.properties.status
    $code = $sendAction.properties.code
    
    if ($status -eq "Succeeded") {
        Write-Host "`n✅ SUCCESS! TacitRed Logic App authenticated successfully!" -ForegroundColor Green
        Write-Host "   RBAC propagation completed after $currentAge minutes" -ForegroundColor Green
        Write-Host "   Run ID: $runId`n" -ForegroundColor Gray
        exit 0
    }
    elseif ($code -eq "Forbidden") {
        Write-Host "   Status: $status (Forbidden - RBAC still propagating)" -ForegroundColor Yellow
    }
    else {
        Write-Host "   Status: $status" -ForegroundColor Red
        if ($sendAction.properties.error) {
            Write-Host "   Error: $($sendAction.properties.error.message)" -ForegroundColor Red
        }
    }
    
    if ($attempt -lt $maxAttempts) {
        Write-Host "   Waiting 2 minutes before next attempt...`n" -ForegroundColor Gray
        Start-Sleep -Seconds 120
    }
}

Write-Host "`n⚠ Maximum attempts reached. RBAC may need more time to propagate." -ForegroundColor Yellow
Write-Host "Current age: $currentAge minutes (expected: 15-30 minutes)`n" -ForegroundColor Yellow

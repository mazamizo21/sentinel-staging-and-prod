# Quick TacitRed Logic App Status Checker
# Checks the last 5 runs and shows success/failure pattern

$subscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117"
$resourceGroup = "SentinelTestStixImport"
$logicAppName = "logic-tacitred-ingestion"

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     TACITRED LOGIC APP - QUICK STATUS CHECK                 ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Get last 5 runs
Write-Host "Fetching last 5 runs..." -ForegroundColor Gray
$uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$logicAppName/runs?api-version=2016-06-01"
$runs = az rest --method GET --uri $uri --uri-parameters '$top=5' | ConvertFrom-Json

if (-not $runs.value) {
    Write-Host "❌ No runs found or error fetching runs" -ForegroundColor Red
    exit 1
}

Write-Host "`nLast 5 Runs:" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Gray

$successCount = 0
$failCount = 0

foreach ($run in $runs.value) {
    $runId = $run.name
    $status = $run.properties.status
    $startTime = [DateTime]::Parse($run.properties.startTime).ToLocalTime()
    $timeAgo = (Get-Date) - $startTime
    
    # Get Send_to_DCE action status
    $actionUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$logicAppName/runs/$runId/actions/Send_to_DCE?api-version=2016-06-01"
    $action = az rest --method GET --uri $actionUri 2>$null | ConvertFrom-Json
    
    $actionStatus = $action.properties.status
    $actionCode = $action.properties.code
    
    # Format output
    $timeAgoStr = "{0:hh\:mm\:ss}" -f $timeAgo
    
    if ($status -eq "Succeeded" -and $actionStatus -eq "Succeeded") {
        Write-Host "  ✅ " -ForegroundColor Green -NoNewline
        Write-Host "SUCCEEDED" -ForegroundColor Green -NoNewline
        Write-Host " - $timeAgoStr ago" -ForegroundColor Gray
        $successCount++
    } elseif ($actionCode -eq "Forbidden") {
        Write-Host "  ⏳ " -ForegroundColor Yellow -NoNewline
        Write-Host "FORBIDDEN" -ForegroundColor Yellow -NoNewline
        Write-Host " - $timeAgoStr ago (RBAC propagating)" -ForegroundColor Gray
        $failCount++
    } else {
        Write-Host "  ❌ " -ForegroundColor Red -NoNewline
        Write-Host "FAILED ($actionCode)" -ForegroundColor Red -NoNewline
        Write-Host " - $timeAgoStr ago" -ForegroundColor Gray
        $failCount++
    }
}

# Summary
Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Gray
Write-Host "`nSummary:" -ForegroundColor Yellow
Write-Host "  Success: $successCount/5" -ForegroundColor $(if($successCount -gt 0){"Green"}else{"Gray"})
Write-Host "  Failed:  $failCount/5" -ForegroundColor $(if($failCount -gt 0){"Yellow"}else{"Gray"})

$successRate = [math]::Round(($successCount / 5) * 100)
Write-Host "`n  Success Rate: $successRate%" -ForegroundColor $(
    if($successRate -eq 100){"Green"}
    elseif($successRate -ge 50){"Yellow"}
    else{"Red"}
)

# Recommendation
Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Gray
if ($successRate -eq 100) {
    Write-Host "`n✅ RBAC FULLY PROPAGATED - Logic App is working!" -ForegroundColor Green
} elseif ($successRate -gt 0) {
    Write-Host "`n⏳ RBAC PARTIALLY PROPAGATED - $successRate% success rate" -ForegroundColor Yellow
    Write-Host "   Wait a few more minutes for full propagation" -ForegroundColor Gray
} else {
    Write-Host "`n⏳ RBAC STILL PROPAGATING - 0% success rate" -ForegroundColor Yellow
    Write-Host "   This is normal! RBAC propagation takes 15-30 minutes" -ForegroundColor Gray
    Write-Host "   Run this script again in 5 minutes" -ForegroundColor Gray
}

Write-Host "`n═══════════════════════════════════════════════════════════════`n" -ForegroundColor Gray

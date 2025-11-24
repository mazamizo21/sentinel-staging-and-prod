# Monitor TacitRed CCF Deployment
# Usage: .\MONITOR-DEPLOYMENT.ps1 -DeploymentName "tacitred-ccf-clean-20251119115045"

param(
    [Parameter(Mandatory=$false)]
    [string]$DeploymentName = "tacitred-ccf-clean-20251119115045",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "TacitRed-Production-Test-RG",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxMinutes = 20
)

Write-Host "Monitoring deployment: $DeploymentName" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host "Max wait: $MaxMinutes minutes" -ForegroundColor Gray
Write-Host ""

$startTime = Get-Date
$maxWait = $MaxMinutes * 60

while ($true) {
    $elapsed = ((Get-Date) - $startTime).TotalSeconds
    
    if ($elapsed -gt $maxWait) {
        Write-Host ""
        Write-Host "⏱️ Timeout reached ($MaxMinutes minutes). Deployment may still be running." -ForegroundColor Yellow
        break
    }
    
    $state = az deployment group show -g $ResourceGroup -n $DeploymentName --query "properties.{state:provisioningState, duration:duration}" -o json 2>$null
    
    if ($state) {
        $s = $state | ConvertFrom-Json
        $elapsedMin = [math]::Round($elapsed / 60, 1)
        
        Write-Host "[$elapsedMin min] State: $($s.state) | Duration: $($s.duration)" -ForegroundColor $(
            if ($s.state -eq 'Succeeded') { 'Green' }
            elseif ($s.state -eq 'Running') { 'Yellow' }
            else { 'Red' }
        )
        
        if ($s.state -eq 'Succeeded') {
            Write-Host ""
            Write-Host "DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green -BackgroundColor Black
            Write-Host ""
            
            Write-Host "Verifying CCF connector configuration..." -ForegroundColor Cyan
            $connector = az rest --method GET `
                --uri "https://management.azure.com/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/TacitRed-Production-Test-Workspace/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview" `
                2>$null | ConvertFrom-Json
            
            if ($connector) {
                Write-Host ""
                Write-Host "Connector Status:" -ForegroundColor Cyan
                Write-Host "  Active: $($connector.properties.isActive)" -ForegroundColor White
                Write-Host "  Query Window: $($connector.properties.request.queryWindowInMin) minutes" -ForegroundColor White
                Write-Host "  Stream: $($connector.properties.dcrConfig.streamName)" -ForegroundColor White
                Write-Host "  Last Data Received: $($connector.properties.lastDataReceived)" -ForegroundColor White
                
                Write-Host ""
                Write-Host "Next Steps:" -ForegroundColor Cyan
                Write-Host "1. Connector will poll TacitRed API within 2-5 minutes" -ForegroundColor White
                Write-Host "2. Run: .\QUICK-CHECK.ps1 to verify data ingestion" -ForegroundColor White
                Write-Host "3. Query: TacitRed_Findings_CL | where TimeGenerated > ago(10m)" -ForegroundColor White
            }
            break
        }
        elseif ($s.state -eq 'Failed') {
            Write-Host ""
            Write-Host "DEPLOYMENT FAILED!" -ForegroundColor Red
            Write-Host ""
            Write-Host "Error details:" -ForegroundColor Yellow
            az deployment group show -g $ResourceGroup -n $DeploymentName --query "properties.error" -o json
            break
        }
    }
    else {
        Write-Host "[$elapsedMin min] Checking..." -ForegroundColor Gray
    }
    
    Start-Sleep -Seconds 30
}

Write-Host ""
Write-Host "Monitoring completed." -ForegroundColor Cyan

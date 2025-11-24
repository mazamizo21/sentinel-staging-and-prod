# Quick Check - TacitRed CCF Status

Write-Host "`n=== TACITRED CCF STATUS CHECK ===`n" -ForegroundColor Cyan

# Check record count
Write-Host "[1] Record Count:" -ForegroundColor Yellow
az monitor log-analytics query --workspace 72e125d2-4f75-4497-a6b5-90241feb387a --analytics-query 'TacitRed_Findings_CL | count'

# Check connector
Write-Host "`n[2] Connector Status:" -ForegroundColor Yellow
az rest --method get --uri "https://management.azure.com/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/TacitRed-Production-Test-RG/providers/Microsoft.OperationalInsights/workspaces/TacitRed-Production-Test-Workspace/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview" --query "properties.{isActive:isActive,streamName:dcrConfig.streamName,pollingMinutes:request.queryWindowInMin}"

# Check DCR stream
Write-Host "`n[3] DCR Input Stream:" -ForegroundColor Yellow
az monitor data-collection rule show -g TacitRed-Production-Test-RG -n dcr-tacitred-findings --query "dataFlows[0].streams[0]"

Write-Host "`n=== END CHECK ===`n" -ForegroundColor Cyan

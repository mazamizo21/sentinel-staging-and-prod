$ErrorActionPreference = 'Stop'

$subscriptionId = '774bee0e-b281-4f70-8e40-199e35b65117'
$resourceGroup  = 'Tacitred-CCF-Hub-v2'
$workspaceName  = 'Tacitred-CCF-Hub-v2-ws'

$ts      = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $PSScriptRoot "TacitRed-CCF-Ingestion-Check-$ts.log"

function Write-Log {
    param(
        [string] $Message,
        [string] $Color = 'Gray'
    )
    $line = "$(Get-Date -Format o) $Message"
    Write-Host $line -ForegroundColor $Color
    $line | Out-File -FilePath $logFile -Encoding UTF8 -Append
}

Write-Log "Checking TacitRed_Findings_CL ingestion in workspace '$workspaceName'" 'Cyan'

az account set --subscription $subscriptionId | Out-Null

$ws = az monitor log-analytics workspace show -g $resourceGroup -n $workspaceName -o json | ConvertFrom-Json
$workspaceId = $ws.customerId
Write-Log "WorkspaceId: $workspaceId" 'Gray'

$query1 = @"
TacitRed_Findings_CL
| summarize Count = count(), MinTime = min(TimeGenerated), MaxTime = max(TimeGenerated)
"@

$query2 = @"
TacitRed_Findings_CL
| summarize Count = count() by findingType_s
| top 10 by Count desc
"@

Write-Log "Running ingestion summary query..." 'Yellow'
$summary = az monitor log-analytics query --workspace $workspaceId --analytics-query "$query1" --timespan P7D -o json
Write-Log "Summary result: $summary" 'Gray'

Write-Log "Running type breakdown query..." 'Yellow'
$types = az monitor log-analytics query --workspace $workspaceId --analytics-query "$query2" --timespan P7D -o json
Write-Log "Type breakdown result: $types" 'Gray'

Write-Log "Ingestion check finished" 'Cyan'

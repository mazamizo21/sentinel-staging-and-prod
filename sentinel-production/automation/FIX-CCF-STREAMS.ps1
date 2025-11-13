<#
  Title: FIX-CCF-STREAMS.ps1
  Purpose: Patch Cyren CCF data connectors to point to DCR INPUT streams so that DCR transformations execute and populate Cyren_Indicators_CL columns.
  Author: AI Security Engineer
  Logs: ./docs/deployment-logs/ccf-connector-stream-fix-<timestamp>/
  Notes:
    - Uses only official Azure resource provider Microsoft.SecurityInsights/dataConnectors (api-version 2024-09-01)
    - Non-destructive: updates the connector body in place
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$SubscriptionId,
  [Parameter(Mandatory=$true)][string]$ResourceGroup = "SentinelTestStixImport",
  [Parameter(Mandatory=$true)][string]$WorkspaceName = "SentinelThreatIntelWorkspace"
)
$ErrorActionPreference = 'Stop'

function New-LogDir {
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $global:LogDir = Join-Path (Resolve-Path '..').Path ("docs/deployment-logs/ccf-connector-stream-fix-$ts")
  New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
  return $ts
}

function Write-Log([string]$Name, [string]$Content){
  $path = Join-Path $LogDir $Name
  $Content | Out-File -FilePath $path -Encoding UTF8
}

function Get-Connector([string]$Name){
  $uri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectors/$Name?api-version=2024-09-01"
  $raw = az rest --method GET --url $uri 2>&1
  Write-Log "${Name}-get.json" $raw
  return $raw | ConvertFrom-Json
}

function Put-Connector([string]$Name, $BodyObj){
  $uri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectors/$Name?api-version=2024-09-01"
  $json = $BodyObj | ConvertTo-Json -Depth 100 -Compress
  Write-Log "${Name}-put-body.json" $json
  $resp = az rest --method PUT --url $uri --headers "Content-Type=application/json" --body $json 2>&1
  Write-Log "${Name}-put-response.json" $resp
  return $resp
}

function Patch-Stream([string]$Name, [string]$TargetStream){
  Write-Host "\nPatching connector: $Name → streamName=$TargetStream" -ForegroundColor Cyan
  $current = Get-Connector -Name $Name
  if(-not $current){ throw "Connector $Name not found" }
  $body = [ordered]@{
    kind       = $current.kind
    properties = $current.properties
  }
  if(-not $body.properties.dcrConfig){ $body.properties.dcrConfig = @{} }
  $body.properties.dcrConfig.streamName = $TargetStream
  # Preserve other properties as-is (auth, request, paging, response, dataType)
  Put-Connector -Name $Name -BodyObj $body | Out-Null
  $after = Get-Connector -Name $Name
  $newStream = $after.properties.dcrConfig.streamName
  if($newStream -ne $TargetStream){ throw "Failed to set streamName for $Name. Expected $TargetStream, found $newStream" }
  Write-Host "✓ $Name patched successfully" -ForegroundColor Green
}

try{
  $ts = New-LogDir
  Write-Log 'context.txt' ("Subscription=$SubscriptionId`nResourceGroup=$ResourceGroup`nWorkspace=$WorkspaceName`nTimestamp=$ts")
  Write-Host "\n=== FIX CCF CONNECTOR STREAMS ===" -ForegroundColor Yellow
  Write-Host "All logs: $LogDir" -ForegroundColor Yellow

  # Patch Cyren connectors to point to DCR INPUT streams
  Patch-Stream -Name 'CyrenIPReputation' -TargetStream 'Custom-Cyren_IpReputation_Raw'
  Patch-Stream -Name 'CyrenMalwareURLs' -TargetStream 'Custom-Cyren_MalwareUrls_Raw'

  # Summarize
  $summary = @()
  foreach($n in 'CyrenIPReputation','CyrenMalwareURLs'){
    $c = Get-Connector -Name $n
    $summary += [pscustomobject]@{
      Name = $n
      Stream = $c.properties.dcrConfig.streamName
      DataType = $c.properties.dataType
      ApiEndpoint = $c.properties.request.apiEndpoint
    }
  }
  $summary | ConvertTo-Json -Depth 5 | Write-Log 'summary.json'
  Write-Host "\n✓ Completed. Wait for next poll (up to 6h) then verify populated columns in Cyren_Indicators_CL." -ForegroundColor Green
}
catch{
  $msg = $_ | Out-String
  Write-Log 'error.log' $msg
  Write-Error $msg
  exit 1
}

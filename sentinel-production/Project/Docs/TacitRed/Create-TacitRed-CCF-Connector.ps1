$ErrorActionPreference = 'Stop'

$subscriptionId = '774bee0e-b281-4f70-8e40-199e35b65117'
$resourceGroup  = 'Tacitred-CCF-Hub-v2'
$workspaceName  = 'Tacitred-CCF-Hub-v4-ws'
$dceName        = 'dce-threatintel-feeds'
$dcrName        = 'dcr-tacitred-findings'
$connectorName  = 'TacitRedFindings'

$ts      = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $PSScriptRoot "TacitRed-CCF-Connector-Create-$ts.log"

function Write-Log {
    param(
        [string] $Message,
        [string] $Color = 'Gray'
    )
    $line = "$(Get-Date -Format o) $Message"
    Write-Host $line -ForegroundColor $Color
    $line | Out-File -FilePath $logFile -Encoding UTF8 -Append
}

Write-Log "Creating TacitRed CCF connector in workspace '$workspaceName'" 'Cyan'

az account set --subscription $subscriptionId | Out-Null

# Workspace id
$ws = az monitor log-analytics workspace show -g $resourceGroup -n $workspaceName -o json | ConvertFrom-Json
$workspaceId = $ws.customerId
$workspaceResourceId = $ws.id
Write-Log "WorkspaceId: $workspaceId" 'Gray'

# DCE and DCR
$dce = az monitor data-collection endpoint show --name $dceName --resource-group $resourceGroup -o json | ConvertFrom-Json
$dcr = az monitor data-collection rule show --name $dcrName --resource-group $resourceGroup -o json | ConvertFrom-Json

$dceEndpoint = $dce.logsIngestion.endpoint
$dcrImmutableId = $dcr.immutableId

Write-Log "DCE logsIngestion: $dceEndpoint" 'Gray'
Write-Log "DCR immutableId: $dcrImmutableId" 'Gray'

# API key from root config
$configPath = Join-Path (Resolve-Path "$PSScriptRoot/../../..").Path 'client-config-COMPLETE.json'
$config     = Get-Content $configPath -Raw | ConvertFrom-Json
$apiKey     = $config.parameters.tacitRed.value.apiKey
Write-Log "Using TacitRed API key prefix: $($apiKey.Substring(0,8))..." 'Gray'

$connectorUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/dataConnectors/$connectorName" + '?api-version=2024-09-01'
Write-Log "Connector URI: $connectorUri" 'Gray'

# Connector body: all types, 600-minute window
$body = @{
    kind       = 'RestApiPoller'
    properties = @{
        connectorDefinitionName = 'TacitRedThreatIntel'
        dataType                = 'TacitRed_Findings_CL'
        isActive                = $true
        dcrConfig = @{
            streamName                  = 'Custom-TacitRed_Findings_Raw'
            dataCollectionEndpoint      = $dceEndpoint
            dataCollectionRuleImmutableId = $dcrImmutableId
        }
        auth = @{
            type           = 'APIKey'
            ApiKeyName     = 'Authorization'
            apiKeyIdentifier = ''
            ApiKey         = $apiKey
        }
        request = @{
            apiEndpoint           = 'https://app.tacitred.com/api/v1/findings'
            httpMethod            = 'GET'
            queryParameters       = @{ page_size = 100 }
            queryWindowInMin      = 600
            queryTimeFormat       = 'yyyy-MM-ddTHH:mm:ssZ'
            startTimeAttributeName = 'from'
            endTimeAttributeName   = 'until'
            rateLimitQPS          = 10
            retryCount            = 3
            timeoutInSeconds      = 60
            headers               = @{
                Accept      = 'application/json'
                'User-Agent' = 'Microsoft-Sentinel-TacitRed/1.0'
            }
        }
        paging = @{
            pagingType          = 'LinkHeader'
            linkHeaderRelLinkName = 'next'
            pageSize            = 100
        }
        response = @{
            eventsJsonPaths     = @('$.results')
            format              = 'json'
        }
        shouldJoinNestedData = $false
        stepCollectorConfigs = @{}
    }
}

$tempFile = Join-Path $PSScriptRoot "TacitRed-CCF-Connector-Create-Body-$ts.json"
$body | ConvertTo-Json -Depth 30 | Out-File -FilePath $tempFile -Encoding UTF8 -Force

Write-Log "Sending PUT to create connector..." 'Yellow'
$putResult = az rest --method PUT --uri $connectorUri --headers "Content-Type=application/json" --body "@$tempFile" -o json 2>&1
Write-Log "PUT result: $putResult" 'Gray'

Write-Log "Verifying connector..." 'Yellow'
$verify = az rest --method GET --uri $connectorUri -o json 2>$null | ConvertFrom-Json

if ($verify) {
    Write-Log "Connector name: $($verify.name)" 'Green'
    Write-Log "Active: $($verify.properties.isActive)" 'Green'
    Write-Log "Polling window: $($verify.properties.request.queryWindowInMin) minutes" 'Green'
} else {
    Write-Log "Connector verification failed" 'Red'
}

Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
Write-Log "Connector creation script finished" 'Cyan'

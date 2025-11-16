# DEPLOY-FRESH-CCF-ONLY.ps1
# Deploy completely fresh CCF environment for isolated testing

<#
.SYNOPSIS
    Fresh CCF deployment in isolated resource group
.DESCRIPTION
    Creates new resource group with:
    - Log Analytics workspace + Sentinel
    - DCE (Data Collection Endpoint)
    - DCR (Data Collection Rule)
    - Custom table (TacitRed_Findings_CL)
    - UAMI (User-Assigned Managed Identity)
    - RBAC assignments
    - CCF connector (TacitRedFindings)
    
    NO Logic Apps - pure CCF testing
#>

param(
    [string]$Location = "eastus",
    [string]$ResourceGroup = "TacitRedCCFTest",
    [string]$WorkspaceName = "TacitRedCCFWorkspace",
    [string]$ApiKey = "a2be534e-6231-4fb0-b8b8-15dbc96e83b7",  # KNOWN WORKING from Logic Apps
    [int]$PollingIntervalMin = 5  # For fast testing
)

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   FRESH CCF-ONLY DEPLOYMENT" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "`n📋 DEPLOYMENT PLAN:" -ForegroundColor Yellow
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host "  Location: $Location" -ForegroundColor Gray
Write-Host "  Workspace: $WorkspaceName" -ForegroundColor Gray
Write-Host "  API Key: $($ApiKey.Substring(0,8))... (KNOWN WORKING)" -ForegroundColor Green
Write-Host "  Polling Interval: $PollingIntervalMin minutes" -ForegroundColor Gray
Write-Host "  Components: Workspace, DCE, DCR, Table, UAMI, RBAC, CCF" -ForegroundColor Gray
Write-Host "  NO Logic Apps (pure CCF test)`n" -ForegroundColor Gray

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId

az account set --subscription $sub | Out-Null
Write-Host "✓ Using subscription: $sub`n" -ForegroundColor Green

# ============================================================================
# STEP 1: CREATE RESOURCE GROUP
# ============================================================================
Write-Host "═══ STEP 1: CREATE RESOURCE GROUP ═══" -ForegroundColor Cyan

$rgExists = az group exists --name $ResourceGroup | ConvertFrom-Json

if($rgExists){
    Write-Host "⚠ Resource group exists. Delete it? (y/n): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host
    if($confirm -eq 'y'){
        Write-Host "  Deleting existing resource group..." -ForegroundColor Yellow
        az group delete --name $ResourceGroup --yes --no-wait
        Write-Host "  Waiting 30 seconds for cleanup..." -ForegroundColor Gray
        Start-Sleep -Seconds 30
    }else{
        Write-Host "  Using existing resource group" -ForegroundColor Green
    }
}

if(-not $rgExists -or $confirm -eq 'y'){
    Write-Host "  Creating resource group..." -ForegroundColor Yellow
    az group create --name $ResourceGroup --location $Location --output table
    Write-Host "✓ Resource group created`n" -ForegroundColor Green
}

# ============================================================================
# STEP 2: CREATE LOG ANALYTICS WORKSPACE
# ============================================================================
Write-Host "═══ STEP 2: CREATE LOG ANALYTICS WORKSPACE ═══" -ForegroundColor Cyan

Write-Host "  Creating workspace..." -ForegroundColor Yellow
az monitor log-analytics workspace create `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --location $Location `
    --output table

$wsId = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query id -o tsv

Write-Host "✓ Workspace created: $wsId`n" -ForegroundColor Green

# ============================================================================
# STEP 3: ENABLE SENTINEL
# ============================================================================
Write-Host "═══ STEP 3: ENABLE MICROSOFT SENTINEL ═══" -ForegroundColor Cyan

Write-Host "  Enabling Sentinel on workspace..." -ForegroundColor Yellow

$sentinelUri = "https://management.azure.com$wsId/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2023-02-01"
$sentinelBody = '{"properties":{}}'
$tempFile = "$env:TEMP\sentinel-enable.json"
$sentinelBody | Out-File -FilePath $tempFile -Encoding UTF8 -Force

az rest --method PUT --uri $sentinelUri --headers "Content-Type=application/json" --body "@$tempFile" 2>&1 | Out-Null
Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

Write-Host "✓ Sentinel enabled`n" -ForegroundColor Green

# ============================================================================
# STEP 4: CREATE DATA COLLECTION ENDPOINT (DCE)
# ============================================================================
Write-Host "═══ STEP 4: CREATE DATA COLLECTION ENDPOINT ═══" -ForegroundColor Cyan

$dceName = "dce-tacitred-ccf-test"
Write-Host "  Creating DCE: $dceName..." -ForegroundColor Yellow

az monitor data-collection endpoint create `
    --name $dceName `
    --resource-group $ResourceGroup `
    --location $Location `
    --public-network-access Enabled `
    --output table

$dce = az monitor data-collection endpoint show `
    --name $dceName `
    --resource-group $ResourceGroup `
    --output json | ConvertFrom-Json

$dceId = $dce.id
$dceEndpoint = $dce.logsIngestion.endpoint

Write-Host "✓ DCE created" -ForegroundColor Green
Write-Host "  ID: $dceId" -ForegroundColor Gray
Write-Host "  Endpoint: $dceEndpoint`n" -ForegroundColor Gray

# ============================================================================
# STEP 5: CREATE CUSTOM TABLE
# ============================================================================
Write-Host "═══ STEP 5: CREATE CUSTOM TABLE ═══" -ForegroundColor Cyan

$tableName = "TacitRed_Findings_CL"
Write-Host "  Creating table: $tableName..." -ForegroundColor Yellow

$tableSchema = @{
    properties = @{
        schema = @{
            name = $tableName
            columns = @(
                @{name="TimeGenerated"; type="datetime"}
                @{name="email_s"; type="string"}
                @{name="domain_s"; type="string"}
                @{name="findingType_s"; type="string"}
                @{name="confidence_d"; type="int"}
                @{name="firstSeen_t"; type="datetime"}
                @{name="lastSeen_t"; type="datetime"}
                @{name="notes_s"; type="string"}
                @{name="source_s"; type="string"}
                @{name="severity_s"; type="string"}
                @{name="status_s"; type="string"}
                @{name="campaign_id_s"; type="string"}
                @{name="user_id_s"; type="string"}
                @{name="username_s"; type="string"}
                @{name="detection_ts_t"; type="datetime"}
                @{name="metadata_s"; type="string"}
            )
        }
    }
}

$tableFile = "$env:TEMP\table-schema.json"
$tableSchema | ConvertTo-Json -Depth 10 | Out-File -FilePath $tableFile -Encoding UTF8 -Force

$tableUri = "https://management.azure.com$wsId/tables/$tableName`?api-version=2023-09-01"
az rest --method PUT --uri $tableUri --headers "Content-Type=application/json" --body "@$tableFile" 2>&1 | Out-Null
Remove-Item $tableFile -Force -ErrorAction SilentlyContinue

Write-Host "✓ Table created with 16 columns`n" -ForegroundColor Green

# ============================================================================
# STEP 6: CREATE USER-ASSIGNED MANAGED IDENTITY
# ============================================================================
Write-Host "═══ STEP 6: CREATE MANAGED IDENTITY ═══" -ForegroundColor Cyan

$uamiName = "uami-tacitred-ccf-test"
Write-Host "  Creating UAMI: $uamiName..." -ForegroundColor Yellow

az identity create `
    --name $uamiName `
    --resource-group $ResourceGroup `
    --location $Location `
    --output table

$uami = az identity show `
    --name $uamiName `
    --resource-group $ResourceGroup `
    --output json | ConvertFrom-Json

$uamiId = $uami.id
$uamiPrincipalId = $uami.principalId

Write-Host "✓ UAMI created" -ForegroundColor Green
Write-Host "  Principal ID: $uamiPrincipalId`n" -ForegroundColor Gray

# ============================================================================
# STEP 7: CREATE DATA COLLECTION RULE (DCR)
# ============================================================================
Write-Host "═══ STEP 7: CREATE DATA COLLECTION RULE ═══" -ForegroundColor Cyan

$dcrName = "dcr-tacitred-ccf-test"
Write-Host "  Creating DCR: $dcrName..." -ForegroundColor Yellow

$dcrConfig = @{
    location = $Location
    properties = @{
        dataCollectionEndpointId = $dceId
        streamDeclarations = @{
            "Custom-TacitRed_Findings_Raw" = @{
                columns = @(
                    @{name="email"; type="string"}
                    @{name="domain"; type="string"}
                    @{name="findingType"; type="string"}
                    @{name="confidence"; type="string"}
                    @{name="firstSeen"; type="string"}
                    @{name="lastSeen"; type="string"}
                    @{name="notes"; type="string"}
                    @{name="source"; type="string"}
                    @{name="severity"; type="string"}
                    @{name="status"; type="string"}
                    @{name="campaign_id"; type="string"}
                    @{name="user_id"; type="string"}
                    @{name="username"; type="string"}
                    @{name="detection_ts"; type="string"}
                    @{name="metadata"; type="string"}
                )
            }
        }
        destinations = @{
            logAnalytics = @(
                @{
                    workspaceResourceId = $wsId
                    name = "ws1"
                }
            )
        }
        dataFlows = @(
            @{
                streams = @("Custom-TacitRed_Findings_Raw")
                destinations = @("ws1")
                transformKql = "source | extend tg1=todatetime(detection_ts) | extend tg2=iif(isnull(tg1), todatetime(lastSeen), tg1) | extend tg=iif(isnull(tg2), now(), tg2) | project TimeGenerated=tg, email_s=tostring(email), domain_s=tostring(domain), findingType_s=tostring(findingType), confidence_d=toint(confidence), firstSeen_t=todatetime(firstSeen), lastSeen_t=todatetime(lastSeen), notes_s=tostring(notes), source_s=tostring(source), severity_s=tostring(severity), status_s=tostring(status), campaign_id_s=tostring(campaign_id), user_id_s=tostring(user_id), username_s=tostring(username), detection_ts_t=todatetime(detection_ts), metadata_s=tostring(metadata)"
                outputStream = "Custom-TacitRed_Findings_CL"
            }
        )
    }
}

$dcrFile = "$env:TEMP\dcr-config.json"
$dcrConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $dcrFile -Encoding UTF8 -Force

$dcrUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/dataCollectionRules/$dcrName`?api-version=2022-06-01"
$dcrResult = az rest --method PUT --uri $dcrUri --headers "Content-Type=application/json" --body "@$dcrFile" | ConvertFrom-Json
Remove-Item $dcrFile -Force -ErrorAction SilentlyContinue

$dcrId = $dcrResult.id
$dcrImmutableId = $dcrResult.properties.immutableId

Write-Host "✓ DCR created" -ForegroundColor Green
Write-Host "  ID: $dcrId" -ForegroundColor Gray
Write-Host "  Immutable ID: $dcrImmutableId`n" -ForegroundColor Gray

# ============================================================================
# STEP 8: ASSIGN RBAC ROLES
# ============================================================================
Write-Host "═══ STEP 8: ASSIGN RBAC ROLES ═══" -ForegroundColor Cyan

Write-Host "  Waiting 30 seconds for identity propagation..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

$monitoringPublisherRole = "3913510d-42f4-4e42-8a64-420c390055eb"

Write-Host "  Assigning Monitoring Metrics Publisher on DCR..." -ForegroundColor Yellow
az role assignment create `
    --assignee-object-id $uamiPrincipalId `
    --assignee-principal-type ServicePrincipal `
    --role $monitoringPublisherRole `
    --scope $dcrId `
    --output none 2>$null

Write-Host "  Assigning Monitoring Metrics Publisher on DCE..." -ForegroundColor Yellow
az role assignment create `
    --assignee-object-id $uamiPrincipalId `
    --assignee-principal-type ServicePrincipal `
    --role $monitoringPublisherRole `
    --scope $dceId `
    --output none 2>$null

Write-Host "✓ RBAC assignments complete`n" -ForegroundColor Green

# ============================================================================
# STEP 9: DEPLOY CCF CONNECTOR DEFINITION
# ============================================================================
Write-Host "═══ STEP 9: DEPLOY CCF CONNECTOR DEFINITION ═══" -ForegroundColor Cyan

Write-Host "  Creating connector definition..." -ForegroundColor Yellow

$connDefUri = "https://management.azure.com$wsId/providers/Microsoft.SecurityInsights/dataConnectorDefinitions/TacitRedThreatIntel?api-version=2024-09-01"
$connDefBody = @{
    kind = "Customizable"
    properties = @{
        connectorUiConfig = @{
            title = "TacitRed Threat Intelligence"
            publisher = "TacitRed"
            descriptionMarkdown = "TacitRed connector for compromised credentials"
            graphQueries = @(
                @{
                    metricName = "Total data received"
                    legend = "TacitRed Findings"
                    baseQuery = "TacitRed_Findings_CL"
                }
            )
            dataTypes = @(
                @{
                    name = "TacitRed_Findings_CL"
                    lastDataReceivedQuery = "TacitRed_Findings_CL | summarize Time = max(TimeGenerated) | where isnotempty(Time)"
                }
            )
        }
    }
}

$connDefFile = "$env:TEMP\conn-def.json"
$connDefBody | ConvertTo-Json -Depth 10 | Out-File -FilePath $connDefFile -Encoding UTF8 -Force

az rest --method PUT --uri $connDefUri --headers "Content-Type=application/json" --body "@$connDefFile" 2>&1 | Out-Null
Remove-Item $connDefFile -Force -ErrorAction SilentlyContinue

Write-Host "✓ Connector definition created`n" -ForegroundColor Green

# ============================================================================
# STEP 10: DEPLOY CCF CONNECTOR INSTANCE
# ============================================================================
Write-Host "═══ STEP 10: DEPLOY CCF CONNECTOR INSTANCE ═══" -ForegroundColor Cyan

Write-Host "  Creating CCF connector with API key..." -ForegroundColor Yellow
Write-Host "  API Key: $($ApiKey.Substring(0,8))... (KNOWN WORKING)" -ForegroundColor Green

$connInstUri = "https://management.azure.com$wsId/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview"
$connInstBody = @{
    kind = "RestApiPoller"
    properties = @{
        connectorDefinitionName = "TacitRedThreatIntel"
        dataType = "TacitRed_Findings_CL"
        dcrConfig = @{
            streamName = "Custom-TacitRed_Findings_Raw"
            dataCollectionEndpoint = $dceEndpoint
            dataCollectionRuleImmutableId = $dcrImmutableId
        }
        auth = @{
            type = "APIKey"
            ApiKeyName = "Authorization"
            ApiKey = $ApiKey
        }
        request = @{
            apiEndpoint = "https://app.tacitred.com/api/v1/findings"
            httpMethod = "GET"
            queryParameters = @{
                page_size = 100
            }
            queryWindowInMin = $PollingIntervalMin
            queryTimeFormat = "yyyy-MM-ddTHH:mm:ssZ"
            startTimeAttributeName = "from"
            endTimeAttributeName = "until"
            rateLimitQps = 10
            retryCount = 3
            timeoutInSeconds = 60
            headers = @{
                Accept = "application/json"
                "User-Agent" = "Microsoft-Sentinel-TacitRed-CCF-Test/1.0"
            }
        }
        paging = @{
            pagingType = "LinkHeader"
            linkHeaderRelLinkName = "rel=next"
            pageSize = 0
        }
        response = @{
            eventsJsonPaths = @("$.results")
            format = "json"
        }
        shouldJoinNestedData = $false
    }
}

$connInstFile = "$env:TEMP\conn-inst.json"
$connInstBody | ConvertTo-Json -Depth 10 | Out-File -FilePath $connInstFile -Encoding UTF8 -Force

$connInstResult = az rest --method PUT --uri $connInstUri --headers "Content-Type=application/json" --body "@$connInstFile"
Remove-Item $connInstFile -Force -ErrorAction SilentlyContinue

Write-Host "✓ CCF connector deployed`n" -ForegroundColor Green

# ============================================================================
# VERIFICATION
# ============================================================================
Write-Host "═══ DEPLOYMENT VERIFICATION ═══" -ForegroundColor Cyan

Write-Host "Waiting 10 seconds for propagation..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Verify connector
$connVerify = az rest --method GET --uri $connInstUri 2>$null | ConvertFrom-Json

Write-Host "`n✅ DEPLOYMENT COMPLETE!`n" -ForegroundColor Green

Write-Host "📊 DEPLOYED RESOURCES:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host "  Workspace: $WorkspaceName" -ForegroundColor Gray
Write-Host "  DCE: $dceName" -ForegroundColor Gray
Write-Host "  DCR: $dcrName (Immutable ID: $dcrImmutableId)" -ForegroundColor Gray
Write-Host "  Table: $tableName" -ForegroundColor Gray
Write-Host "  UAMI: $uamiName" -ForegroundColor Gray
Write-Host "  CCF Connector: TacitRedFindings" -ForegroundColor Gray

Write-Host "`n🔍 CONNECTOR STATUS:" -ForegroundColor Cyan
Write-Host "  Name: $($connVerify.name)" -ForegroundColor Gray
Write-Host "  Kind: $($connVerify.kind)" -ForegroundColor Gray
Write-Host "  Is Active: $($connVerify.properties.isActive)" -ForegroundColor $(if($connVerify.properties.isActive){'Green'}else{'Red'})
Write-Host "  Polling Interval: $($connVerify.properties.request.queryWindowInMin) minutes" -ForegroundColor Gray
Write-Host "  API Endpoint: $($connVerify.properties.request.apiEndpoint)" -ForegroundColor Gray

if($connVerify.properties.auth.ApiKey){
    Write-Host "  API Key: ✅ SET" -ForegroundColor Green
}else{
    Write-Host "  API Key: ⚠ Shows as null (may be Azure masking)" -ForegroundColor Yellow
}

Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. CCF will poll within $PollingIntervalMin minutes" -ForegroundColor White
Write-Host "  2. Wait $(($PollingIntervalMin * 2)) minutes total" -ForegroundColor White
Write-Host "  3. Check for data in Azure Portal:" -ForegroundColor White
Write-Host "     - Navigate to: Log Analytics workspace > Logs" -ForegroundColor DarkGray
Write-Host "     - Run query: TacitRed_Findings_CL | summarize count()" -ForegroundColor DarkGray

Write-Host "`n🎯 WHAT TO MONITOR:" -ForegroundColor Cyan
Write-Host "  This is a CLEAN environment - no interference from Logic Apps" -ForegroundColor White
Write-Host "  If CCF works here → Issue was environment-specific" -ForegroundColor White
Write-Host "  If CCF fails here → Issue is with CCF itself" -ForegroundColor White

Write-Host "`n⏱️  Check back at: $((Get-Date).AddMinutes($PollingIntervalMin * 2).ToString('HH:mm'))" -ForegroundColor Cyan

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Save deployment info
$deploymentInfo = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    resourceGroup = $ResourceGroup
    workspace = $WorkspaceName
    dceEndpoint = $dceEndpoint
    dcrImmutableId = $dcrImmutableId
    pollingInterval = $PollingIntervalMin
    apiKey = "$($ApiKey.Substring(0,8))..."
    nextPollExpected = (Get-Date).AddMinutes($PollingIntervalMin).ToString("yyyy-MM-dd HH:mm:ss")
}

$deploymentInfo | ConvertTo-Json | Out-File ".\Project\Docs\fresh-ccf-deployment.json" -Encoding UTF8 -Force
Write-Host "Deployment info saved: Project\Docs\fresh-ccf-deployment.json" -ForegroundColor Gray

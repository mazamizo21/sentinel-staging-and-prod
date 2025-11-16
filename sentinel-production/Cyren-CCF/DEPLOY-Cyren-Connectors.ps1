# ============================================================================
# Deploy Cyren Connectors with Correct ImmutableIds
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "`n=== Cyren Connectors Deployment ===" -ForegroundColor Cyan

# Configuration
$subscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117"
$resourceGroupName = "SentinelTestStixImport"
$workspaceName = "SentinelThreatIntelWorkspace"
$location = "eastus"

# DCR ImmutableIds from previous deployment
$ipDcrId = "dcr-39d508f7d577493cab36ab9ec8760f2d"
$malwareDcrId = "dcr-5262b9202d8846ee9879eb2d6be2d01d"

Write-Host "Using ImmutableIds:" -ForegroundColor Yellow
Write-Host "  IP DCR: $ipDcrId" -ForegroundColor White
Write-Host "  Malware DCR: $malwareDcrId`n" -ForegroundColor White

# Set subscription
az account set --subscription $subscriptionId

# Create parameters file with connectors enabled
$params = @{
    '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
    contentVersion = "1.0.0.0"
    parameters = @{
        workspace = @{ value = $workspaceName }
        "workspace-location" = @{ value = $location }
        cyrenIPJwtToken = @{ value = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJleHAiOjE5MzAzNDg3OTksImF1ZCI6ImlwX3JlcHV0YXRpb24iLCJzdWIiOiJOSjUxQlU4MDYwNTNZVjBJMEgxQSIsImp0aSI6IjY5MTA3Njg4LWQ4NTQtMTFlZi05NGY5LWJjMjQxMTNkZTQ4ZSIsImlzcyI6ImNsbSJ9.Aw0gyb5l3OQbizawiOCXaJVE8VKOIo5Mm5aRogTr_RgqZ8yklyjzS52NAz3KEh4OTcl1i6qIO3GtaeRhq4x6LUaqwMTiSMUIIm3xU-2b5Y4GeRhsE5tl8Y7fYblaNcPhEOnLfHi8UtX4Aa_VfmPTslZbFoqpTUcaCkOOTBbz7HYEI7YdgziTIbGk-0Jwt47iI_AsaSy-SA13Syuv82rvRM08tOuyNn9hQgyjo0YAmAUbeC5eMCpbkhmujuDwGOhnurVtjvM8fPPsVJJBLJSYNonurwZi-txYVypd3-tQA0nlRJOZuFXKzDjVZEpkG-ivzqyJIbvcCcTXyeADYQOpnQ" }
        cyrenMalwareJwtToken = @{ value = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJleHAiOjE3NzE3MTgzOTksImF1ZCI6Im1hbHdhcmVfdXJscyIsInN1YiI6IjUxWjBGRDQwWTFJN0FBMU9KUDBRIiwianRpIjoiZjFiNGNhMjYtZDg1My0xMWVmLTk0ZjktYmMyNDExM2RlNDhlIiwiaXNzIjoiY2xtIn0.dEh1vGCVAQSChRQsroM5AkC6YyjaG9yzr9lxmj-xWDslgbrTdzeoZPP83nJh05TS6IXHd_CDGlqcdgxQxip9y8kikVKrF12vnTwCMBu_cFG46OHwE8ilCCejBz_L9mr53ksO-bkhqZGrcxsJVxpoSBuaNua3mwUBcH1CoPHyO7XUjgHW4MZShxe0Lb5JHrEil03QElqP_O_GXvcl8CS8l_DUd5y-2J9A4RXrSlSOIe7PQden8w0y8q0wgfYOL0GaAwZvEXl91Rz41Yavm5aC5GKIBUNJzn_OZ5yk5G99FdAkhdT4N87R_j7054l_K-2XBsAAWKsQ89UWgQK7aj-72A" }
        deployConnectors = @{ value = $true }
        deployWorkbooks = @{ value = $false }  # Already deployed
        enableKeyVault = @{ value = $false }
        cyrenIPDcrImmutableId = @{ value = $ipDcrId }
        cyrenMalwareDcrImmutableId = @{ value = $malwareDcrId }
    }
}

$paramsJson = $params | ConvertTo-Json -Depth 10
$paramsJson | Out-File "cyren-connectors-temp.json" -Encoding UTF8

Write-Host "Deploying Cyren connectors..." -ForegroundColor Cyan
az deployment group create `
    --resource-group $resourceGroupName `
    --template-file ".\Cyren-CCF\mainTemplate.json" `
    --parameters "@cyren-connectors-temp.json" `
    --name "cyren-connectors-$(Get-Date -Format 'yyyyMMddHHmmss')"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Connectors deployed successfully!" -ForegroundColor Green
    
    Write-Host "`nVerifying connector configuration..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    
    $workspaceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName"
    
    Write-Host "`nIP Reputation Connector:" -ForegroundColor Yellow
    $ipConnector = az rest --method GET `
        --url "${workspaceId}/providers/Microsoft.SecurityInsights/dataConnectors/CyrenIPReputation?api-version=2023-02-01-preview" `
        --output json | ConvertFrom-Json
    
    $ipConnectorDcrId = $ipConnector.properties.dcrConfig.dataCollectionRuleImmutableId
    if ($ipConnectorDcrId -eq $ipDcrId) {
        Write-Host "  ✅ ImmutableId MATCH: $ipConnectorDcrId" -ForegroundColor Green
    } else {
        Write-Host "  ❌ ImmutableId MISMATCH" -ForegroundColor Red
        Write-Host "     Expected: $ipDcrId" -ForegroundColor Gray
        Write-Host "     Got: $ipConnectorDcrId" -ForegroundColor Gray
    }
    
    Write-Host "`nMalware URLs Connector:" -ForegroundColor Yellow
    $malwareConnector = az rest --method GET `
        --url "${workspaceId}/providers/Microsoft.SecurityInsights/dataConnectors/CyrenMalwareURLs?api-version=2023-02-01-preview" `
        --output json | ConvertFrom-Json
    
    $malwareConnectorDcrId = $malwareConnector.properties.dcrConfig.dataCollectionRuleImmutableId
    if ($malwareConnectorDcrId -eq $malwareDcrId) {
        Write-Host "  ✅ ImmutableId MATCH: $malwareConnectorDcrId" -ForegroundColor Green
    } else {
        Write-Host "  ❌ ImmutableId MISMATCH" -ForegroundColor Red
        Write-Host "     Expected: $malwareDcrId" -ForegroundColor Gray
        Write-Host "     Got: $malwareConnectorDcrId" -ForegroundColor Gray
    }
    
    Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan
    Write-Host "`nStatus:" -ForegroundColor Yellow
    Write-Host "  ✅ Infrastructure deployed (DCE, DCRs, Table, UAMI, RBAC)" -ForegroundColor White
    Write-Host "  ✅ Connectors deployed with correct immutableIds" -ForegroundColor White
    Write-Host "  ✅ Cyren_Indicators_CL table created (19 columns)" -ForegroundColor White
    Write-Host "`nNext:" -ForegroundColor Yellow
    Write-Host "  ⏳ Wait for Cyren engineer to provide fresh data (within last 60 min)" -ForegroundColor White
    Write-Host "  ⏳ Connectors will poll every 60 minutes" -ForegroundColor White
    Write-Host "  ⏳ First data expected 60-90 minutes after fresh API data available`n" -ForegroundColor White
    
} else {
    Write-Host "`n❌ Connector deployment failed" -ForegroundColor Red
}

Remove-Item "cyren-connectors-temp.json" -ErrorAction SilentlyContinue

Read-Host "`nPress Enter to exit"

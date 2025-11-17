# ============================================================================
# Deploy Cyren Connectors Only (to CyrenCCFWorkspace)
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "`n=== Deploying Cyren Connectors ===" -ForegroundColor Cyan

# Configuration
$subscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117"
$resourceGroupName = "CyrenCCFTest"
$workspaceName = "CyrenCCFWorkspace"
$location = "eastus"

# DCR ImmutableIds from previous deployment
$ipDcrId = "dcr-d617c437d8d24f70bbfe69cb510bb990"
$malwareDcrId = "dcr-9d58511160fc4315b1723e5c43979bd5"

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group: $resourceGroupName" -ForegroundColor White
Write-Host "  Workspace: $workspaceName" -ForegroundColor White
Write-Host "  IP DCR: $ipDcrId" -ForegroundColor White
Write-Host "  Malware DCR: $malwareDcrId`n" -ForegroundColor White

# Set subscription
az account set --subscription $subscriptionId

# Wait for Sentinel to be fully ready
Write-Host "Waiting 30 seconds for Sentinel to be fully ready..." -ForegroundColor Gray
Start-Sleep -Seconds 30

# Deploy connectors
$connectorParams = @{
    '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
    contentVersion = "1.0.0.0"
    parameters = @{
        workspace = @{ value = $workspaceName }
        "workspace-location" = @{ value = $location }
        cyrenIPJwtToken = @{ value = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJleHAiOjE5MzAzNDg3OTksImF1ZCI6ImlwX3JlcHV0YXRpb24iLCJzdWIiOiJOSjUxQlU4MDYwNTNZVjBJMEgxQSIsImp0aSI6IjY5MTA3Njg4LWQ4NTQtMTFlZi05NGY5LWJjMjQxMTNkZTQ4ZSIsImlzcyI6ImNsbSJ9.Aw0gyb5l3OQbizawiOCXaJVE8VKOIo5Mm5aRogTr_RgqZ8yklyjzS52NAz3KEh4OTcl1i6qIO3GtaeRhq4x6LUaqwMTiSMUIIm3xU-2b5Y4GeRhsE5tl8Y7fYblaNcPhEOnLfHi8UtX4Aa_VfmPTslZbFoqpTUcaCkOOTBbz7HYEI7YdgziTIbGk-0Jwt47iI_AsaSy-SA13Syuv82rvRM08tOuyNn9hQgyjo0YAmAUbeC5eMCpbkhmujuDwGOhnurVtjvM8fPPsVJJBLJSYNonurwZi-txYVypd3-tQA0nlRJOZuFXKzDjVZEpkG-ivzqyJIbvcCcTXyeADYQOpnQ" }
        cyrenMalwareJwtToken = @{ value = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJleHAiOjE3NzE3MTgzOTksImF1ZCI6Im1hbHdhcmVfdXJscyIsInN1YiI6IjUxWjBGRDQwWTFJN0FBMU9KUDBRIiwianRpIjoiZjFiNGNhMjYtZDg1My0xMWVmLTk0ZjktYmMyNDExM2RlNDhlIiwiaXNzIjoiY2xtIn0.dEh1vGCVAQSChRQsroM5AkC6YyjaG9yzr9lxmj-xWDslgbrTdzeoZPP83nJh05TS6IXHd_CDGlqcdgxQxip9y8kikVKrF12vnTwCMBu_cFG46OHwE8ilCCejBz_L9mr53ksO-bkhqZGrcxsJVxpoSBuaNua3mwUBcH1CoPHyO7XUjgHW4MZShxe0Lb5JHrEil03QElqP_O_GXvcl8CS8l_DUd5y-2J9A4RXrSlSOIe7PQden8w0y8q0wgfYOL0GaAwZvEXl91Rz41Yavm5aC5GKIBUNJzn_OZ5yk5G99FdAkhdT4N87R_j7054l_K-2XBsAAWKsQ89UWgQK7aj-72A" }
        deployConnectors = @{ value = $true }
        deployWorkbooks = @{ value = $false }
        enableKeyVault = @{ value = $false }
        cyrenIPDcrImmutableId = @{ value = $ipDcrId }
        cyrenMalwareDcrImmutableId = @{ value = $malwareDcrId }
    }
}

$connectorParamsJson = $connectorParams | ConvertTo-Json -Depth 10
$connectorParamsJson | Out-File "cyren-connectors-only-params.json" -Encoding UTF8

Write-Host "Deploying connectors..." -ForegroundColor Cyan
az deployment group create `
    --resource-group $resourceGroupName `
    --template-file ".\Cyren-CCF\mainTemplate.json" `
    --parameters "@cyren-connectors-only-params.json" `
    --name "cyren-connectors-$(Get-Date -Format 'yyyyMMddHHmmss')"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Connectors deployed successfully!" -ForegroundColor Green
    
    Write-Host "`nVerifying ImmutableId match..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    
    $workspaceResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName"
    
    $ipConnector = az rest --method GET `
        --url "${workspaceResourceId}/providers/Microsoft.SecurityInsights/dataConnectors/CyrenIPReputation?api-version=2023-02-01-preview" `
        --output json | ConvertFrom-Json
    
    $ipConnectorDcrId = $ipConnector.properties.dcrConfig.dataCollectionRuleImmutableId
    
    if ($ipConnectorDcrId -eq $ipDcrId) {
        Write-Host "  ✅ IP Reputation: ImmutableId MATCH" -ForegroundColor Green
    } else {
        Write-Host "  ❌ IP Reputation: ImmutableId MISMATCH" -ForegroundColor Red
    }
    
    $malwareConnector = az rest --method GET `
        --url "${workspaceResourceId}/providers/Microsoft.SecurityInsights/dataConnectors/CyrenMalwareURLs?api-version=2023-02-01-preview" `
        --output json | ConvertFrom-Json
    
    $malwareConnectorDcrId = $malwareConnector.properties.dcrConfig.dataCollectionRuleImmutableId
    
    if ($malwareConnectorDcrId -eq $malwareDcrId) {
        Write-Host "  ✅ Malware URLs: ImmutableId MATCH" -ForegroundColor Green
    } else {
        Write-Host "  ❌ Malware URLs: ImmutableId MISMATCH" -ForegroundColor Red
    }
    
    Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan
    Write-Host "`nAccess your workspace:" -ForegroundColor Yellow
    Write-Host "  Portal: Azure Portal → CyrenCCFWorkspace → Logs" -ForegroundColor White
    Write-Host "  Query: Cyren_Indicators_CL | summarize count()`n" -ForegroundColor White
} else {
    Write-Host "`n❌ Connector deployment failed" -ForegroundColor Red
}

Remove-Item "cyren-connectors-only-params.json" -ErrorAction SilentlyContinue

Read-Host "Press Enter to exit"

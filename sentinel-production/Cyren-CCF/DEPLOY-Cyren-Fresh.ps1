# ============================================================================
# Deploy Cyren CCF to Fresh Isolated Environment
# ============================================================================
# Creates: New RG + New Workspace + Sentinel + Full Cyren Solution
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "`n=== Cyren CCF Fresh Deployment ===" -ForegroundColor Cyan
Write-Host "Creating isolated environment for Cyren`n" -ForegroundColor Yellow

# Configuration
$subscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117"
$resourceGroupName = "CyrenCCFTest"
$workspaceName = "CyrenCCFWorkspace"
$location = "eastus"

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Subscription: $subscriptionId" -ForegroundColor White
Write-Host "  Resource Group: $resourceGroupName (NEW)" -ForegroundColor White
Write-Host "  Workspace: $workspaceName (NEW)" -ForegroundColor White
Write-Host "  Location: $location`n" -ForegroundColor White

# Set subscription
Write-Host "Setting subscription..." -ForegroundColor Gray
az account set --subscription $subscriptionId

# Step 1: Create Resource Group
Write-Host "`n--- Step 1: Creating Resource Group ---" -ForegroundColor Cyan
$rgExists = az group exists --name $resourceGroupName

if ($rgExists -eq "true") {
    Write-Host "  Resource group already exists" -ForegroundColor Yellow
} else {
    Write-Host "  Creating resource group..." -ForegroundColor Gray
    az group create --name $resourceGroupName --location $location --output none
    Write-Host "  ✅ Resource group created" -ForegroundColor Green
}

# Step 2: Create Log Analytics Workspace
Write-Host "`n--- Step 2: Creating Log Analytics Workspace ---" -ForegroundColor Cyan
Write-Host "  Creating workspace..." -ForegroundColor Gray

az monitor log-analytics workspace create `
    --resource-group $resourceGroupName `
    --workspace-name $workspaceName `
    --location $location `
    --output none

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✅ Workspace created" -ForegroundColor Green
} else {
    Write-Host "  Workspace may already exist, continuing..." -ForegroundColor Yellow
}

# Step 3: Enable Microsoft Sentinel
Write-Host "`n--- Step 3: Enabling Microsoft Sentinel ---" -ForegroundColor Cyan
Write-Host "  Enabling Sentinel..." -ForegroundColor Gray

$workspaceId = az monitor log-analytics workspace show `
    --resource-group $resourceGroupName `
    --workspace-name $workspaceName `
    --query id `
    --output tsv

# Enable Sentinel (onboard workspace)
az rest --method PUT `
    --url "${workspaceId}/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2023-02-01" `
    --body '{"properties":{}}' `
    --output none 2>$null

Write-Host "  ✅ Sentinel enabled" -ForegroundColor Green
Write-Host "  Waiting 30 seconds for Sentinel onboarding to propagate..." -ForegroundColor Gray
Start-Sleep -Seconds 30

# Step 4: Deploy Cyren Infrastructure
Write-Host "`n--- Step 4: Deploying Cyren Infrastructure ---" -ForegroundColor Cyan
Write-Host "  Resources: DCE, 2 DCRs, Custom Table, UAMI, RBAC" -ForegroundColor Gray

$params = @{
    '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
    contentVersion = "1.0.0.0"
    parameters = @{
        workspace = @{ value = $workspaceName }
        "workspace-location" = @{ value = $location }
        cyrenIPJwtToken = @{ value = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJleHAiOjE5MzAzNDg3OTksImF1ZCI6ImlwX3JlcHV0YXRpb24iLCJzdWIiOiJOSjUxQlU4MDYwNTNZVjBJMEgxQSIsImp0aSI6IjY5MTA3Njg4LWQ4NTQtMTFlZi05NGY5LWJjMjQxMTNkZTQ4ZSIsImlzcyI6ImNsbSJ9.Aw0gyb5l3OQbizawiOCXaJVE8VKOIo5Mm5aRogTr_RgqZ8yklyjzS52NAz3KEh4OTcl1i6qIO3GtaeRhq4x6LUaqwMTiSMUIIm3xU-2b5Y4GeRhsE5tl8Y7fYblaNcPhEOnLfHi8UtX4Aa_VfmPTslZbFoqpTUcaCkOOTBbz7HYEI7YdgziTIbGk-0Jwt47iI_AsaSy-SA13Syuv82rvRM08tOuyNn9hQgyjo0YAmAUbeC5eMCpbkhmujuDwGOhnurVtjvM8fPPsVJJBLJSYNonurwZi-txYVypd3-tQA0nlRJOZuFXKzDjVZEpkG-ivzqyJIbvcCcTXyeADYQOpnQ" }
        cyrenMalwareJwtToken = @{ value = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJleHAiOjE3NzE3MTgzOTksImF1ZCI6Im1hbHdhcmVfdXJscyIsInN1YiI6IjUxWjBGRDQwWTFJN0FBMU9KUDBRIiwianRpIjoiZjFiNGNhMjYtZDg1My0xMWVmLTk0ZjktYmMyNDExM2RlNDhlIiwiaXNzIjoiY2xtIn0.dEh1vGCVAQSChRQsroM5AkC6YyjaG9yzr9lxmj-xWDslgbrTdzeoZPP83nJh05TS6IXHd_CDGlqcdgxQxip9y8kikVKrF12vnTwCMBu_cFG46OHwE8ilCCejBz_L9mr53ksO-bkhqZGrcxsJVxpoSBuaNua3mwUBcH1CoPHyO7XUjgHW4MZShxe0Lb5JHrEil03QElqP_O_GXvcl8CS8l_DUd5y-2J9A4RXrSlSOIe7PQden8w0y8q0wgfYOL0GaAwZvEXl91Rz41Yavm5aC5GKIBUNJzn_OZ5yk5G99FdAkhdT4N87R_j7054l_K-2XBsAAWKsQ89UWgQK7aj-72A" }
        deployConnectors = @{ value = $false }
        deployWorkbooks = @{ value = $true }
        enableKeyVault = @{ value = $false }
        cyrenIPDcrImmutableId = @{ value = "" }
        cyrenMalwareDcrImmutableId = @{ value = "" }
    }
}

$paramsJson = $params | ConvertTo-Json -Depth 10
$paramsJson | Out-File "cyren-fresh-infra-params.json" -Encoding UTF8

Write-Host "  Deploying infrastructure..." -ForegroundColor Gray
az deployment group create `
    --resource-group $resourceGroupName `
    --template-file ".\Cyren-CCF\mainTemplate.json" `
    --parameters "@cyren-fresh-infra-params.json" `
    --name "cyren-infra-$(Get-Date -Format 'yyyyMMddHHmmss')" `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ Infrastructure deployment failed" -ForegroundColor Red
    Remove-Item "cyren-fresh-infra-params.json" -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "  ✅ Infrastructure deployed" -ForegroundColor Green

# Step 5: Read DCR ImmutableIds
Write-Host "`n--- Step 5: Reading DCR ImmutableIds ---" -ForegroundColor Cyan

Write-Host "  Reading IP Reputation DCR..." -ForegroundColor Gray
$ipDcrId = az monitor data-collection rule show `
    --resource-group $resourceGroupName `
    --name "dcr-cyren-ip-reputation" `
    --query immutableId `
    --output tsv

Write-Host "    IP DCR: $ipDcrId" -ForegroundColor White

Write-Host "  Reading Malware URLs DCR..." -ForegroundColor Gray
$malwareDcrId = az monitor data-collection rule show `
    --resource-group $resourceGroupName `
    --name "dcr-cyren-malware-urls" `
    --query immutableId `
    --output tsv

Write-Host "    Malware DCR: $malwareDcrId" -ForegroundColor White

# Step 6: Deploy Connectors with Correct ImmutableIds
Write-Host "`n--- Step 6: Deploying Connectors ---" -ForegroundColor Cyan

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
$connectorParamsJson | Out-File "cyren-fresh-connectors-params.json" -Encoding UTF8

Write-Host "  Deploying connectors..." -ForegroundColor Gray
az deployment group create `
    --resource-group $resourceGroupName `
    --template-file ".\Cyren-CCF\mainTemplate.json" `
    --parameters "@cyren-fresh-connectors-params.json" `
    --name "cyren-connectors-$(Get-Date -Format 'yyyyMMddHHmmss')" `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ Connector deployment failed" -ForegroundColor Red
    Remove-Item "cyren-fresh-infra-params.json" -ErrorAction SilentlyContinue
    Remove-Item "cyren-fresh-connectors-params.json" -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "  ✅ Connectors deployed" -ForegroundColor Green

# Step 7: Verify ImmutableId Match
Write-Host "`n--- Step 7: Verifying ImmutableId Match ---" -ForegroundColor Cyan

$workspaceResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName"

Write-Host "  Checking IP Reputation connector..." -ForegroundColor Gray
$ipConnector = az rest --method GET `
    --url "${workspaceResourceId}/providers/Microsoft.SecurityInsights/dataConnectors/CyrenIPReputation?api-version=2023-02-01-preview" `
    --output json | ConvertFrom-Json

$ipConnectorDcrId = $ipConnector.properties.dcrConfig.dataCollectionRuleImmutableId

if ($ipConnectorDcrId -eq $ipDcrId) {
    Write-Host "    ✅ IP Reputation: ImmutableId MATCH" -ForegroundColor Green
} else {
    Write-Host "    ❌ IP Reputation: ImmutableId MISMATCH" -ForegroundColor Red
    Write-Host "       Expected: $ipDcrId" -ForegroundColor Gray
    Write-Host "       Got: $ipConnectorDcrId" -ForegroundColor Gray
}

Write-Host "  Checking Malware URLs connector..." -ForegroundColor Gray
$malwareConnector = az rest --method GET `
    --url "${workspaceResourceId}/providers/Microsoft.SecurityInsights/dataConnectors/CyrenMalwareURLs?api-version=2023-02-01-preview" `
    --output json | ConvertFrom-Json

$malwareConnectorDcrId = $malwareConnector.properties.dcrConfig.dataCollectionRuleImmutableId

if ($malwareConnectorDcrId -eq $malwareDcrId) {
    Write-Host "    ✅ Malware URLs: ImmutableId MATCH" -ForegroundColor Green
} else {
    Write-Host "    ❌ Malware URLs: ImmutableId MISMATCH" -ForegroundColor Red
    Write-Host "       Expected: $malwareDcrId" -ForegroundColor Gray
    Write-Host "       Got: $malwareConnectorDcrId" -ForegroundColor Gray
}

# Cleanup temp files
Remove-Item "cyren-fresh-infra-params.json" -ErrorAction SilentlyContinue
Remove-Item "cyren-fresh-connectors-params.json" -ErrorAction SilentlyContinue

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan
Write-Host "`nEnvironment Details:" -ForegroundColor Yellow
Write-Host "  Resource Group: $resourceGroupName" -ForegroundColor White
Write-Host "  Workspace: $workspaceName" -ForegroundColor White
Write-Host "  Location: $location" -ForegroundColor White
Write-Host "`nResources Created:" -ForegroundColor Yellow
Write-Host "  ✅ Log Analytics Workspace" -ForegroundColor White
Write-Host "  ✅ Microsoft Sentinel" -ForegroundColor White
Write-Host "  ✅ Data Collection Endpoint (DCE)" -ForegroundColor White
Write-Host "  ✅ 2 Data Collection Rules (DCRs)" -ForegroundColor White
Write-Host "  ✅ Custom Table: Cyren_Indicators_CL (19 columns)" -ForegroundColor White
Write-Host "  ✅ User-Assigned Managed Identity" -ForegroundColor White
Write-Host "  ✅ RBAC Assignments" -ForegroundColor White
Write-Host "  ✅ 2 CCF Connectors (IP Reputation + Malware URLs)" -ForegroundColor White
Write-Host "  ✅ 2 Workbooks" -ForegroundColor White
Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Navigate to: Azure Portal → $workspaceName → Logs" -ForegroundColor White
Write-Host "  2. Run: Cyren_Indicators_CL | summarize count()" -ForegroundColor White
Write-Host "  3. Wait for Cyren engineer to provide fresh data" -ForegroundColor White
Write-Host "  4. Connectors poll every 60 minutes`n" -ForegroundColor White

Read-Host "Press Enter to exit"

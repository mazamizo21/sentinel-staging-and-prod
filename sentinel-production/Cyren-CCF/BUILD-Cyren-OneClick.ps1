# ============================================================================
# Cyren CCF One-Click Deployment
# ============================================================================
# This script deploys the Cyren CCF solution with correct immutableId wiring
# Pattern: Deploy infra → Read DCR ImmutableIds → Deploy connectors with IDs
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "SentinelTestStixImport",
    
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceName = "SentinelThreatIntelWorkspace",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$false)]
    [string]$CyrenIPJwtToken = "",
    
    [Parameter(Mandatory=$false)]
    [string]$CyrenMalwareJwtToken = ""
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Cyren CCF One-Click Deployment ===" -ForegroundColor Cyan
Write-Host "This will deploy Cyren with correct immutableId wiring`n" -ForegroundColor Yellow

# Prompt for tokens if not provided
if ([string]::IsNullOrEmpty($CyrenIPJwtToken)) {
    $CyrenIPJwtToken = Read-Host "Enter Cyren IP Reputation JWT Token"
}

if ([string]::IsNullOrEmpty($CyrenMalwareJwtToken)) {
    $CyrenMalwareJwtToken = Read-Host "Enter Cyren Malware URLs JWT Token"
}

# Set subscription
Write-Host "Setting subscription..." -ForegroundColor Cyan
az account set --subscription $SubscriptionId

# Step 1: Deploy infrastructure (DCE, DCRs, Table, UAMI, RBAC, optional KV)
Write-Host "`n--- Step 1: Deploying Infrastructure ---" -ForegroundColor Cyan
Write-Host "Resources: DCE, 2 DCRs, Custom Table, UAMI, RBAC, Key Vault (optional)" -ForegroundColor Gray

$infraParams = @{
    workspace = $WorkspaceName
    "workspace-location" = $Location
    cyrenIPJwtToken = $CyrenIPJwtToken
    cyrenMalwareJwtToken = $CyrenMalwareJwtToken
    deployConnectors = $false  # Deploy connectors in step 3
    deployWorkbooks = $true
    enableKeyVault = $false
}

$infraParamsJson = $infraParams | ConvertTo-Json -Depth 10
$infraParamsJson | Out-File "cyren-infra-params.json" -Encoding UTF8

Write-Host "Deploying infrastructure..." -ForegroundColor Gray
$infraDeployment = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file ".\Cyren-CCF\mainTemplate.json" `
    --parameters "@cyren-infra-params.json" `
    --name "cyren-infra-$(Get-Date -Format 'yyyyMMddHHmmss')" `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Infrastructure deployment failed" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Infrastructure deployed successfully" -ForegroundColor Green

# Step 2: Read DCR ImmutableIds
Write-Host "`n--- Step 2: Reading DCR ImmutableIds ---" -ForegroundColor Cyan

Write-Host "Reading IP Reputation DCR..." -ForegroundColor Gray
$ipDcrId = az monitor data-collection rule show `
    --resource-group $ResourceGroupName `
    --name "dcr-cyren-ip-reputation" `
    --query immutableId `
    --output tsv

if ([string]::IsNullOrEmpty($ipDcrId)) {
    Write-Host "❌ Failed to read IP Reputation DCR immutableId" -ForegroundColor Red
    exit 1
}

Write-Host "  IP Reputation DCR ImmutableId: $ipDcrId" -ForegroundColor White

Write-Host "Reading Malware URLs DCR..." -ForegroundColor Gray
$malwareDcrId = az monitor data-collection rule show `
    --resource-group $ResourceGroupName `
    --name "dcr-cyren-malware-urls" `
    --query immutableId `
    --output tsv

if ([string]::IsNullOrEmpty($malwareDcrId)) {
    Write-Host "❌ Failed to read Malware URLs DCR immutableId" -ForegroundColor Red
    exit 1
}

Write-Host "  Malware URLs DCR ImmutableId: $malwareDcrId" -ForegroundColor White

# Step 3: Deploy connectors with correct ImmutableIds
Write-Host "`n--- Step 3: Deploying Connectors with Correct ImmutableIds ---" -ForegroundColor Cyan

$connectorParams = @{
    workspace = $WorkspaceName
    "workspace-location" = $Location
    cyrenIPJwtToken = $CyrenIPJwtToken
    cyrenMalwareJwtToken = $CyrenMalwareJwtToken
    cyrenIPDcrImmutableId = $ipDcrId
    cyrenMalwareDcrImmutableId = $malwareDcrId
    deployConnectors = $true
    deployWorkbooks = $false  # Already deployed
    enableKeyVault = $false
}

$connectorParamsJson = $connectorParams | ConvertTo-Json -Depth 10
$connectorParamsJson | Out-File "cyren-connector-params.json" -Encoding UTF8

Write-Host "Deploying connectors..." -ForegroundColor Gray
$connectorDeployment = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file ".\Cyren-CCF\mainTemplate.json" `
    --parameters "@cyren-connector-params.json" `
    --name "cyren-connectors-$(Get-Date -Format 'yyyyMMddHHmmss')" `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Connector deployment failed" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Connectors deployed successfully" -ForegroundColor Green

# Step 4: Verify ImmutableId Match
Write-Host "`n--- Step 4: Verifying ImmutableId Match ---" -ForegroundColor Cyan

$workspaceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"

Write-Host "Checking IP Reputation connector..." -ForegroundColor Gray
$ipConnectorConfig = az rest --method GET `
    --url "${workspaceId}/providers/Microsoft.SecurityInsights/dataConnectors/CyrenIPReputation?api-version=2023-02-01-preview" `
    --output json | ConvertFrom-Json

$ipConnectorDcrId = $ipConnectorConfig.properties.dcrConfig.dataCollectionRuleImmutableId

if ($ipConnectorDcrId -eq $ipDcrId) {
    Write-Host "  ✅ IP Reputation: ImmutableId MATCH" -ForegroundColor Green
    Write-Host "     Connector: $ipConnectorDcrId" -ForegroundColor Gray
} else {
    Write-Host "  ❌ IP Reputation: ImmutableId MISMATCH" -ForegroundColor Red
    Write-Host "     DCR:       $ipDcrId" -ForegroundColor Gray
    Write-Host "     Connector: $ipConnectorDcrId" -ForegroundColor Gray
}

Write-Host "Checking Malware URLs connector..." -ForegroundColor Gray
$malwareConnectorConfig = az rest --method GET `
    --url "${workspaceId}/providers/Microsoft.SecurityInsights/dataConnectors/CyrenMalwareURLs?api-version=2023-02-01-preview" `
    --output json | ConvertFrom-Json

$malwareConnectorDcrId = $malwareConnectorConfig.properties.dcrConfig.dataCollectionRuleImmutableId

if ($malwareConnectorDcrId -eq $malwareDcrId) {
    Write-Host "  ✅ Malware URLs: ImmutableId MATCH" -ForegroundColor Green
    Write-Host "     Connector: $malwareConnectorDcrId" -ForegroundColor Gray
} else {
    Write-Host "  ❌ Malware URLs: ImmutableId MISMATCH" -ForegroundColor Red
    Write-Host "     DCR:       $malwareDcrId" -ForegroundColor Gray
    Write-Host "     Connector: $malwareConnectorDcrId" -ForegroundColor Gray
}

# Cleanup temp files
Remove-Item "cyren-infra-params.json" -ErrorAction SilentlyContinue
Remove-Item "cyren-connector-params.json" -ErrorAction SilentlyContinue

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Wait for Cyren engineer to provide fresh data (within last 60 minutes)" -ForegroundColor White
Write-Host "2. Connectors will poll every 60 minutes" -ForegroundColor White
Write-Host "3. Check for data ingestion:" -ForegroundColor White
Write-Host "   Cyren_Indicators_CL | summarize count() by bin(TimeGenerated, 1h)" -ForegroundColor Gray
Write-Host "`n4. If no data after fresh API data is available, run:" -ForegroundColor White
Write-Host "   .\Cyren-CCF\FIX-Cyren-DcrImmutableId.ps1`n" -ForegroundColor Gray

Read-Host "Press Enter to exit"

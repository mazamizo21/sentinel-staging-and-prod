#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy Cyren Threat Intelligence Feeds to Azure Sentinel
.DESCRIPTION
    Deploys DCR/DCE and Logic Apps for Cyren IP Reputation and Malware URLs feeds
    with full logging and error handling
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ParametersFile = ".\parameters.dev.json"
)

$ErrorActionPreference = "Stop"

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Cyren Threat Intelligence Deployment" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Load parameters
Write-Host "[1/8] Loading parameters..." -ForegroundColor Yellow
$params = Get-Content $ParametersFile | ConvertFrom-Json
$subscriptionId = $params.parameters.subscriptionId.value
$resourceGroupName = $params.parameters.resourceGroupName.value
$workspaceName = $params.parameters.workspaceName.value
$location = $params.parameters.location.value

Write-Host "✓ Parameters loaded" -ForegroundColor Green
Write-Host "  Subscription: $subscriptionId" -ForegroundColor Gray
Write-Host "  Resource Group: $resourceGroupName" -ForegroundColor Gray
Write-Host "  Workspace: $workspaceName" -ForegroundColor Gray
Write-Host ""

# Connect to Azure
Write-Host "[2/8] Connecting to Azure..." -ForegroundColor Yellow
az account set --subscription $subscriptionId
if($LASTEXITCODE -ne 0){
    Write-Host "✗ Failed to connect to Azure" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Connected to Azure" -ForegroundColor Green
Write-Host ""

# Verify workspace
Write-Host "[3/8] Verifying workspace..." -ForegroundColor Yellow
$workspace = az monitor log-analytics workspace show `
    --resource-group $resourceGroupName `
    --workspace-name $workspaceName `
    -o json | ConvertFrom-Json

if(-not $workspace){
    Write-Host "✗ Workspace not found" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Workspace verified" -ForegroundColor Green
Write-Host "  Workspace ID: $($workspace.customerId)" -ForegroundColor Gray
Write-Host ""

# Deploy Cyren infrastructure
Write-Host "[4/8] Deploying Cyren infrastructure..." -ForegroundColor Yellow
$deploymentName = "cyren-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deployment = az deployment group create `
    --name $deploymentName `
    --resource-group $resourceGroupName `
    --template-file ".\bicep\cyren-main.bicep" `
    --parameters subscriptionId=$subscriptionId `
    --parameters resourceGroupName=$resourceGroupName `
    --parameters workspaceName=$workspaceName `
    --parameters location=$location `
    --parameters cyrenApiBaseUrl="$($params.parameters.cyrenApiBaseUrl.value)" `
    --parameters cyrenIpReputationFeedId="$($params.parameters.cyrenIpReputationFeedId.value)" `
    --parameters cyrenIpReputationToken="$($params.parameters.cyrenIpReputationToken.value)" `
    --parameters cyrenMalwareUrlsFeedId="$($params.parameters.cyrenMalwareUrlsFeedId.value)" `
    --parameters cyrenMalwareUrlsToken="$($params.parameters.cyrenMalwareUrlsToken.value)" `
    --parameters cyrenFetchCount=$($params.parameters.cyrenFetchCount.value) `
    --parameters enableCyrenIpReputation=$($params.parameters.enableCyrenIpReputation.value) `
    --parameters enableCyrenMalwareUrls=$($params.parameters.enableCyrenMalwareUrls.value) `
    -o json | ConvertFrom-Json

if($LASTEXITCODE -ne 0){
    Write-Host "✗ Deployment failed" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Infrastructure deployed" -ForegroundColor Green
Write-Host "  DCE ID: $($deployment.properties.outputs.dceId.value)" -ForegroundColor Gray
Write-Host "  DCE Endpoint: $($deployment.properties.outputs.dceEndpoint.value)" -ForegroundColor Gray
Write-Host ""

# Assign RBAC permissions
Write-Host "[5/8] Assigning RBAC permissions..." -ForegroundColor Yellow

# Get principals from deployment outputs
$ipRepPrincipalId = $deployment.properties.outputs.ipReputationLogicAppPrincipalId.value
$malwarePrincipalId = $deployment.properties.outputs.malwareUrlsLogicAppPrincipalId.value

# Get resource IDs
$ipRepDcrId = $deployment.properties.outputs.ipReputationDcrId.value
$malwareUrlsDcrId = $deployment.properties.outputs.malwareUrlsDcrId.value
$dceId = $deployment.properties.outputs.dceId.value

# Assign Monitoring Metrics Publisher role to Logic Apps for DCR
Write-Host "  Assigning permissions for IP Reputation Logic App..." -ForegroundColor Gray
if($ipRepPrincipalId){
    az role assignment create `
        --assignee $ipRepPrincipalId `
        --role "Monitoring Metrics Publisher" `
        --scope $ipRepDcrId `
        --output none

    az role assignment create `
        --assignee $ipRepPrincipalId `
        --role "Monitoring Metrics Publisher" `
        --scope $dceId `
        --output none
}

Write-Host "  Assigning permissions for Malware URLs Logic App..." -ForegroundColor Gray
if($malwarePrincipalId){
    az role assignment create `
        --assignee $malwarePrincipalId `
        --role "Monitoring Metrics Publisher" `
        --scope $malwareUrlsDcrId `
        --output none

    az role assignment create `
        --assignee $malwarePrincipalId `
        --role "Monitoring Metrics Publisher" `
        --scope $dceId `
        --output none
}

Write-Host "✓ RBAC permissions assigned" -ForegroundColor Green
Write-Host "  Waiting 120 seconds for RBAC propagation..." -ForegroundColor Yellow
Start-Sleep -Seconds 120
Write-Host "✓ RBAC propagation complete" -ForegroundColor Green
Write-Host ""

# Test IP Reputation feed
Write-Host "[6/8] Testing IP Reputation feed..." -ForegroundColor Yellow
Write-Host "  Triggering Logic App run..." -ForegroundColor Gray

az logic workflow run trigger `
    --resource-group $resourceGroupName `
    --name "logicapp-cyren-ip-reputation" `
    --trigger-name "Recurrence" `
    --output none

Write-Host "  Waiting 60 seconds for run to complete..." -ForegroundColor Gray
Start-Sleep -Seconds 60

# Check run status
$runs = az logic workflow run list `
    --resource-group $resourceGroupName `
    --name "logicapp-cyren-ip-reputation" `
    --top 1 `
    -o json | ConvertFrom-Json

if($runs.Count -gt 0 -and $runs[0].status -eq "Succeeded"){
    Write-Host "✓ IP Reputation feed test successful" -ForegroundColor Green
} else {
    Write-Host "⚠ IP Reputation feed test status: $($runs[0].status)" -ForegroundColor Yellow
}
Write-Host ""

# Test Malware URLs feed
Write-Host "[7/8] Testing Malware URLs feed..." -ForegroundColor Yellow
Write-Host "  Triggering Logic App run..." -ForegroundColor Gray

az logic workflow run trigger `
    --resource-group $resourceGroupName `
    --name "logicapp-cyren-malware-urls" `
    --trigger-name "Recurrence" `
    --output none

Write-Host "  Waiting 60 seconds for run to complete..." -ForegroundColor Gray
Start-Sleep -Seconds 60

# Check run status
$runs = az logic workflow run list `
    --resource-group $resourceGroupName `
    --name "logicapp-cyren-malware-urls" `
    --top 1 `
    -o json | ConvertFrom-Json

if($runs.Count -gt 0 -and $runs[0].status -eq "Succeeded"){
    Write-Host "✓ Malware URLs feed test successful" -ForegroundColor Green
} else {
    Write-Host "⚠ Malware URLs feed test status: $($runs[0].status)" -ForegroundColor Yellow
}
Write-Host ""

# Verify data ingestion
Write-Host "[8/8] Verifying data ingestion..." -ForegroundColor Yellow

Write-Host "  Checking IP Reputation data..." -ForegroundColor Gray
$ipRepQuery = "Cyren_IpReputation_CL | take 10 | project TimeGenerated, ip_address, threat_type, risk_score"
$ipRepResult = az monitor log-analytics query `
    --workspace $workspace.customerId `
    --analytics-query $ipRepQuery `
    --output json 2>&1

if($LASTEXITCODE -eq 0){
    $ipRepData = $ipRepResult | ConvertFrom-Json
    if($ipRepData.tables[0].rows.Count -gt 0){
        Write-Host "✓ IP Reputation data ingested: $($ipRepData.tables[0].rows.Count) records" -ForegroundColor Green
    } else {
        Write-Host "⚠ No IP Reputation data found yet (may take a few minutes)" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ IP Reputation table not yet available" -ForegroundColor Yellow
}

Write-Host "  Checking Malware URLs data..." -ForegroundColor Gray
$malwareQuery = "Cyren_MalwareUrls_CL | take 10 | project TimeGenerated, url, domain, threat_type, risk_score"
$malwareResult = az monitor log-analytics query `
    --workspace $workspace.customerId `
    --analytics-query $malwareQuery `
    --output json 2>&1

if($LASTEXITCODE -eq 0){
    $malwareData = $malwareResult | ConvertFrom-Json
    if($malwareData.tables[0].rows.Count -gt 0){
        Write-Host "✓ Malware URLs data ingested: $($malwareData.tables[0].rows.Count) records" -ForegroundColor Green
    } else {
        Write-Host "⚠ No Malware URLs data found yet (may take a few minutes)" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ Malware URLs table not yet available" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✓ Cyren Deployment Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Wait 5-10 minutes for initial data ingestion" -ForegroundColor Gray
Write-Host "  2. Query Cyren data:" -ForegroundColor Gray
Write-Host "     Cyren_IpReputation_CL | take 10" -ForegroundColor Gray
Write-Host "     Cyren_MalwareUrls_CL | take 10" -ForegroundColor Gray
Write-Host "  3. Deploy updated parser functions" -ForegroundColor Gray
Write-Host "  4. Enable cross-feed correlation analytics rule" -ForegroundColor Gray
Write-Host ""

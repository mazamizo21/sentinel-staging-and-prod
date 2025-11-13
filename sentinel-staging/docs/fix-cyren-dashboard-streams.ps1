# Fix Cyren Threat Intelligence Dashboard - Stream Name Mismatch
# This script redeploys Logic Apps with corrected stream names

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus"
)

Write-Host "=== Cyren Dashboard Stream Fix ===" -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName"
Write-Host "Subscription: $SubscriptionId"
Write-Host "Location: $Location"
Write-Host ""

# Set subscription context
Write-Host "Setting subscription context..." -ForegroundColor Yellow
az account set --subscription $SubscriptionId

# Common parameters
$commonParams = @{
    resourceGroupName = $ResourceGroupName
    location = $Location
}

# Get required resource IDs
Write-Host "Getting resource IDs..." -ForegroundColor Yellow
$workspace = az monitor log-analytics workspace show --resource-group $ResourceGroupName --name "sentinel-staging" | ConvertFrom-Json
$workspaceId = $workspace.id

$dcr = az monitor data-collection rule show --resource-group $ResourceGroupName --name "dcr-cyren-indicators" | ConvertFrom-Json
$dcrImmutableId = $dcr.properties.immutableId

$dce = az monitor data-collection endpoint show --resource-group $ResourceGroupName --name "dce-cyren-ingestion" | ConvertFrom-Json
$dceEndpoint = $dce.logsIngestionEndpoint

# Get Cyren API tokens from Key Vault or parameters (replace with actual values)
$cyrenIpReputationToken = "YOUR-CYREN-IP-TOKEN"  # Replace with actual token
$cyrenMalwareUrlsToken = "YOUR-CYREN-MALWARE-TOKEN"  # Replace with actual token

Write-Host "Workspace ID: $workspaceId"
Write-Host "DCR Immutable ID: $dcrImmutableId"
Write-Host "DCE Endpoint: $dceEndpoint"
Write-Host ""

# Deploy Cyren IP Reputation Logic App
Write-Host "Deploying Cyren IP Reputation Logic App..." -ForegroundColor Cyan
$ipParams = @{
    location = $Location
    cyrenIpReputationToken = $cyrenIpReputationToken
    dcrImmutableId = $dcrImmutableId
    dceEndpoint = $dceEndpoint
}

$ipDeployment = az deployment group create `
    --resource-group $ResourceGroupName `
    --name "cyren-ip-fixed-$(Get-Date -Format 'yyyyMMddHHmmss')" `
    --template-file "infrastructure/bicep/logicapp-cyren-ip-reputation.bicep" `
    --parameters $ipParams

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Cyren IP Reputation Logic App deployed successfully" -ForegroundColor Green
} else {
    Write-Host "❌ Failed to deploy Cyren IP Reputation Logic App" -ForegroundColor Red
    exit 1
}

# Deploy Cyren Malware URLs Logic App
Write-Host "Deploying Cyren Malware URLs Logic App..." -ForegroundColor Cyan
$malwareParams = @{
    location = $Location
    cyrenMalwareUrlsToken = $cyrenMalwareUrlsToken
    dcrImmutableId = $dcrImmutableId
    dceEndpoint = $dceEndpoint
}

$malwareDeployment = az deployment group create `
    --resource-group $ResourceGroupName `
    --name "cyren-malware-fixed-$(Get-Date -Format 'yyyyMMddHHmmss')" `
    --template-file "infrastructure/bicep/logicapp-cyren-malware-urls.bicep" `
    --parameters $malwareParams

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Cyren Malware URLs Logic App deployed successfully" -ForegroundColor Green
} else {
    Write-Host "❌ Failed to deploy Cyren Malware URLs Logic App" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Deployment Summary ===" -ForegroundColor Green
Write-Host "✅ Both Logic Apps deployed with corrected stream names"
Write-Host "✅ Stream name set to: Custom-Cyren_Indicators_CL"
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Wait for Logic Apps to run (scheduled every 6 hours)"
Write-Host "2. Or trigger Logic Apps manually for immediate testing"
Write-Host "3. Check Cyren Threat Intelligence Dashboard in Sentinel"
Write-Host "4. Verify data appears in all dashboard sections"
Write-Host ""
Write-Host "To verify data in Log Analytics:" -ForegroundColor Cyan
Write-Host "Cyren_Indicators_CL | take 10"
Write-Host ""
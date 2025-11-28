$ErrorActionPreference = 'Stop'

$subscriptionId = '774bee0e-b281-4f70-8e40-199e35b65117'
$resourceGroup  = 'Tacitred-CCF-Hub-v2'
$workspaceName  = 'Tacitred-CCF-Hub-v4-ws'
$location       = 'eastus'

Write-Host "`n═══ DEPLOYING TACITRED CCF HUB (v4 workspace, NO WORKBOOKS) ═══" -ForegroundColor Cyan
Write-Host "Subscription: $subscriptionId" -ForegroundColor Gray
Write-Host "Resource Group: $resourceGroup" -ForegroundColor Gray
Write-Host "Workspace: $workspaceName" -ForegroundColor Gray
Write-Host "Location: $location`n" -ForegroundColor Gray

az account set --subscription $subscriptionId | Out-Null

# Load TacitRed API key from root config (same key used by Logic App)
$configPath = Join-Path (Resolve-Path "$PSScriptRoot/../../..").Path 'client-config-COMPLETE.json'
$config     = Get-Content $configPath -Raw | ConvertFrom-Json
$apiKey     = $config.parameters.tacitRed.value.apiKey

Write-Host "Using TacitRed API key (masked): $($apiKey.Substring(0,8))..." -ForegroundColor Gray

$templateFile = Join-Path (Resolve-Path "$PSScriptRoot/../../..").Path 'Tacitred-CCF-Hub-v2/Package/mainTemplate.json'

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$deploymentName = "tacitred-ccf-hubv4-" + $ts

Write-Host "Deploying mainTemplate: $templateFile" -ForegroundColor Yellow

az deployment group create `
  --resource-group $resourceGroup `
  --name $deploymentName `
  --template-file $templateFile `
  --parameters workspace=$workspaceName workspace-location=$location location=$location tacitRedApiKey=$apiKey deployAnalytics=false deployWorkbooks=false `
  -o table

Write-Host "`nDeployment complete (check for connector TacitRedFindings in workspace '$workspaceName')." -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

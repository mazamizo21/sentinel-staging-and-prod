# ============================================================================
# Deploy TacitRed CCF using Two-Stage Approach (Cyren pattern)
# ============================================================================
# Stage 1: Infrastructure (DCE, DCR, Table) WITHOUT connectors
# Stage 2: Connectors ONLY with known DCR ImmutableId
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "`n=== TacitRed CCF Two-Stage Deployment ===" -ForegroundColor Cyan

# Load configuration
$configPath = "..\client-config-COMPLETE.json"
$config = (Get-Content $configPath | ConvertFrom-Json).parameters

$sub  = $config.azure.value.subscriptionId
$rg   = "TacitRed-Production-Test-RG"
$ws   = "TacitRed-Production-Test-Workspace"
$loc  = $config.azure.value.location
$apiKey = $config.tacitRed.value.apiKey

Write-Host "Config: $sub | $rg | $ws | $loc" -ForegroundColor Gray

# Set subscription
az account set --subscription $sub

# Ensure RG and workspace
Write-Host "Ensuring resource group..." -ForegroundColor Cyan
az group create --name $rg --location $loc -o none

Write-Host "Ensuring workspace..." -ForegroundColor Cyan
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$wsJson = az monitor log-analytics workspace show -g $rg -n $ws -o json 2>$null
$ErrorActionPreference = $prevEap
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($wsJson)) {
    Write-Host "Workspace not found, creating..." -ForegroundColor Yellow
    az monitor log-analytics workspace create -g $rg -n $ws -l $loc -o none
    $wsJson = az monitor log-analytics workspace show -g $rg -n $ws -o json
}
$wsObj = $wsJson | ConvertFrom-Json

# Onboard to Sentinel
Write-Host "Onboarding to Sentinel..." -ForegroundColor Cyan
$wsId = $wsObj.id
az rest --method PUT --uri "${wsId}/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2024-03-01" --body '{}' -o none 2>$null

Write-Host "Waiting 15 seconds for Sentinel onboarding..." -ForegroundColor Gray
Start-Sleep -Seconds 15

# ============================================================================
# STAGE 1: Deploy Infrastructure WITHOUT Connectors
# ============================================================================
Write-Host "`n--- STAGE 1: Infrastructure (NO Connectors) ---" -ForegroundColor Cyan

$infraParams = @{
    '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
    contentVersion = "1.0.0.0"
    parameters = @{
        workspace = @{ value = $ws }
        "workspace-location" = @{ value = $loc }
        tacitRedApiKey = @{ value = $apiKey }
        deployConnectors = @{ value = $false }   # NO CONNECTORS
        deployWorkbooks  = @{ value = $false }
        tacitRedDcrImmutableId = @{ value = "" }
    }
}

$infraJson = $infraParams | ConvertTo-Json -Depth 10
$infraJson | Out-File "tacitred-infra-params.json" -Encoding UTF8

Write-Host "Deploying DCE, DCR, Table..." -ForegroundColor Yellow
$infraResult = az deployment group create `
    --resource-group $rg `
    --template-file ".\mainTemplate.json" `
    --parameters "@tacitred-infra-params.json" `
    --name "tacitred-infra-$(Get-Date -Format 'yyyyMMddHHmmss')" `
    --output json

if ($LASTEXITCODE -ne 0) {
    Write-Host "Infrastructure deployment failed!" -ForegroundColor Red
    Remove-Item "tacitred-infra-params.json" -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Infrastructure deployed successfully." -ForegroundColor Green

# ============================================================================
# Read DCR ImmutableId from deployed infrastructure
# ============================================================================
Write-Host "`n--- Reading DCR ImmutableId ---" -ForegroundColor Cyan

$dcrId = az monitor data-collection rule show `
    --resource-group $rg `
    --name "dcr-tacitred-findings" `
    --query immutableId `
    --output tsv

Write-Host "DCR ImmutableId: $dcrId" -ForegroundColor White

# ============================================================================
# STAGE 2: Deploy Connectors ONLY with Known ImmutableId
# ============================================================================
Write-Host "`n--- STAGE 2: Connectors (with ImmutableId) ---" -ForegroundColor Cyan

$connectorParams = @{
    '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
    contentVersion = "1.0.0.0"
    parameters = @{
        workspace = @{ value = $ws }
        "workspace-location" = @{ value = $loc }
        tacitRedApiKey = @{ value = $apiKey }
        deployConnectors = @{ value = $true }    # YES CONNECTORS
        deployWorkbooks  = @{ value = $false }
        tacitRedDcrImmutableId = @{ value = $dcrId }  # Pass real ID!
    }
}

$connectorJson = $connectorParams | ConvertTo-Json -Depth 10
$connectorJson | Out-File "tacitred-connector-params.json" -Encoding UTF8

Write-Host "Deploying TacitRedFindings connector (Async)..." -ForegroundColor Yellow
$connectorResult = az deployment group create `
    --resource-group $rg `
    --template-file ".\mainTemplate.json" `
    --parameters "@tacitred-connector-params.json" `
    --name "tacitred-connector-$(Get-Date -Format 'yyyyMMddHHmmss')" `
    --no-wait `
    --output json

Write-Host "Connector deployment started in background." -ForegroundColor Green
Write-Host "It may take 10-15 minutes to complete." -ForegroundColor Yellow

# ============================================================================
# Verification Note
# ============================================================================
Write-Host "`n--- Verification ---" -ForegroundColor Cyan
Write-Host "Since deployment is async, we cannot verify the connector immediately."
Write-Host "Please check the deployment status in the Azure Portal:"
Write-Host "  Resource Group: $rg"
Write-Host "  Deployments:    tacitred-connector-..."
Write-Host "`nOnce finished, verify the connector streamName is 'Custom-TacitRed_Findings_Raw'"

# Cleanup
Remove-Item "tacitred-infra-params.json" -ErrorAction SilentlyContinue
Remove-Item "tacitred-connector-params.json" -ErrorAction SilentlyContinue

Write-Host "`n=== Deployment Initiated ===" -ForegroundColor Cyan

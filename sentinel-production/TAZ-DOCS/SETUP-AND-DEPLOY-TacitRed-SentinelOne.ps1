#pwsh -NoLogo -ExecutionPolicy Bypass -File ./SETUP-AND-DEPLOY-TacitRed-SentinelOne.ps1

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "TacitRed-SentinelOne-RG",
    [string]$WorkspaceName = "TacitRed-SentinelOne-WS",
    [string]$Location = "eastus",
    [string]$SubscriptionId = "12345678-1234-1234-1234-123456789012" # Replace with actual if needed, or rely on current context
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$sentinelProdRoot = Split-Path -Parent $scriptDir
$solutionRoot = Join-Path $sentinelProdRoot "TacitRed-SentinelOne"
$packageRoot = Join-Path $solutionRoot "Package"
$templateFile = Join-Path $packageRoot "mainTemplate.json"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logsRoot = Join-Path $sentinelProdRoot "Project/Docs/Logs/TacitRed-SentinelOne"
if (-not (Test-Path $logsRoot)) { New-Item -ItemType Directory -Force -Path $logsRoot | Out-Null }
$logPath = Join-Path $logsRoot "setup-deploy-$timestamp.log"

Start-Transcript -Path $logPath -Force | Out-Null

try {
    Write-Host "=== Setting up Isolated Environment for TacitRed-SentinelOne ==="
    
    # 1. Create Resource Group
    Write-Host "Creating Resource Group '$ResourceGroupName' in '$Location'..."
    az group create --name $ResourceGroupName --location $Location --output none

    # 2. Create Log Analytics Workspace
    Write-Host "Creating Log Analytics Workspace '$WorkspaceName'..."
    $wsJson = az monitor log-analytics workspace show -g $ResourceGroupName -n $WorkspaceName -o json 2>$null
    if (-not $wsJson) {
        az monitor log-analytics workspace create -g $ResourceGroupName -n $WorkspaceName -l $Location --output none
        $wsJson = az monitor log-analytics workspace show -g $ResourceGroupName -n $WorkspaceName -o json
    }
    $wsObj = $wsJson | ConvertFrom-Json
    $workspaceResourceId = $wsObj.id

    # 3. Enable Microsoft Sentinel
    Write-Host "Onboarding workspace to Microsoft Sentinel..."
    $onboardUri = "https://management.azure.com$workspaceResourceId/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2024-03-01"
    # We use --body '{}' because the PUT requires a body, even if empty for this resource
    az rest --method PUT --uri $onboardUri --body '{}' --output none 2>$null

    # 4. Deploy Solution
    Write-Host "Deploying TacitRed-SentinelOne Solution..."
    if (-not (Test-Path $templateFile)) {
        throw "Template file not found: $templateFile"
    }

    $params = @(
        "workspace=$WorkspaceName",
        "workspace-location=$Location"
    )

    $deployResult = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file $templateFile `
        --parameters $params `
        --output json

    $deployObj = $deployResult | ConvertFrom-Json
    if ($deployObj.properties.provisioningState -eq "Succeeded") {
        Write-Host "Deployment SUCCEEDED!" -ForegroundColor Green
        Write-Host "Resource Group: $ResourceGroupName"
        Write-Host "Workspace: $WorkspaceName"
    }
    else {
        Write-Error "Deployment status: $($deployObj.properties.provisioningState)"
        Write-Host $deployResult
    }

}
catch {
    Write-Error "Setup/Deployment FAILED: $_"
    throw
}
finally {
    Stop-Transcript | Out-Null
    Write-Host "Log saved to $logPath"
}

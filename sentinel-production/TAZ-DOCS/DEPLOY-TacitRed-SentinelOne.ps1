#pwsh -NoLogo -ExecutionPolicy Bypass -File ./DEPLOY-TacitRed-SentinelOne.ps1

[CmdletBinding()]
param(
    [string]$ResourceGroupName = "Sentinel-Staging-RG",
    [string]$WorkspaceName = "Sentinel-Staging-WS",
    [string]$Location = "eastus",
    [string]$LogicAppName = "pb-tacitred-to-sentinelone-test"
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
$logPath = Join-Path $logsRoot "deploy-$timestamp.log"

Start-Transcript -Path $logPath -Force | Out-Null

try {
    Write-Host "=== Starting Deployment of TacitRed-SentinelOne ==="
    Write-Host "Resource Group: $ResourceGroupName"
    Write-Host "Workspace: $WorkspaceName"
    Write-Host "Template: $templateFile"

    if (-not (Test-Path $templateFile)) {
        throw "Template file not found: $templateFile"
    }

    # Check if RG exists, create if not
    $rg = az group show --name $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $rg) {
        Write-Host "Creating Resource Group '$ResourceGroupName'..."
        az group create --name $ResourceGroupName --location $Location | Out-Null
    }

    # Check if Workspace exists (we assume it does for staging, but let's verify)
    # Actually, for a pure template deployment test, we might need to ensure the workspace exists or the template handles it.
    # The template expects an existing workspace name.
    
    # Deploy Solution (Template Spec)
    Write-Host "Deploying Solution (ARM Template)..."
    
    $params = @(
        "workspace=$WorkspaceName",
        "workspace-location=$Location"
    )

    $deployResult = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file $templateFile `
        --parameters $params `
        --output json

    Write-Host "Deployment command finished."
    
    $deployObj = $deployResult | ConvertFrom-Json
    if ($deployObj.properties.provisioningState -eq "Succeeded") {
        Write-Host "Deployment SUCCEEDED!" -ForegroundColor Green
    }
    else {
        Write-Error "Deployment status: $($deployObj.properties.provisioningState)"
        Write-Host $deployResult
    }

}
catch {
    Write-Error "Deployment FAILED: $_"
    if ($null -ne $deployResult) {
        Write-Host "Deployment Output Details:"
        Write-Host $deployResult
    }
    throw
}
finally {
    Stop-Transcript | Out-Null
    Write-Host "Log saved to $logPath"
}

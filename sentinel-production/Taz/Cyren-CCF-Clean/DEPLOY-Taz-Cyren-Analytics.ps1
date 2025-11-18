# Automated deployment of taz-* Cyren analytics rules using client-config-COMPLETE.json
[CmdletBinding()]
param(
    [string]$ConfigFile = "..\..\client-config-COMPLETE.json",
    [string]$ResourceGroupName,
    [string]$WorkspaceName,
    [string]$Location
)

$ErrorActionPreference = "Stop"

# Ensure we run from the script directory
$ScriptDir = Split-Path -Parent $PSCommandPath
Set-Location $ScriptDir
Write-Host "Working directory: $ScriptDir" -ForegroundColor Gray

if (-not (Test-Path $ConfigFile)) {
    throw "Config file not found: $ConfigFile"
}

# Load configuration (subscription/location from config; RG/WS default to Cyren CCF test environment)
$config = (Get-Content $ConfigFile | ConvertFrom-Json).parameters
$sub  = $config.azure.value.subscriptionId

$defaultRg = "CyrenCCFTest"
$defaultWs = "CyrenCCFWorkspace"

$rg   = if ($PSBoundParameters.ContainsKey('ResourceGroupName') -and $ResourceGroupName) { $ResourceGroupName } else { $defaultRg }
$ws   = if ($PSBoundParameters.ContainsKey('WorkspaceName') -and $WorkspaceName) { $WorkspaceName } else { $defaultWs }
$loc  = if ($PSBoundParameters.ContainsKey('Location') -and $Location) { $Location } else { $config.azure.value.location }

Write-Host "Config: $sub | $rg | $ws | $loc" -ForegroundColor Gray

# Prepare logging under Project/Docs
$ts = Get-Date -Format "yyyyMMddHHmmss"
$logDir = "..\..\Project\Docs\Validation\Cyren\taz-cyren-analytics-$ts"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript "$logDir\deploy-taz-cyren-analytics.log" | Out-Null

try {
    Write-Host "Setting subscription..." -ForegroundColor Cyan
    az account set --subscription $sub

    $templateFile = "./taz-cyren-analytics.json"
    if (-not (Test-Path $templateFile)) {
        throw "Template file not found: $templateFile"
    }

    Write-Host "Deploying taz-* Cyren analytics rules to workspace '$ws' in resource group '$rg'..." -ForegroundColor Cyan

    $deploymentName = "taz-cyren-analytics-$ts"

    $deploymentResult = az deployment group create `
        -g $rg `
        -n $deploymentName `
        --template-file $templateFile `
        --parameters workspace=$ws `
        -o json `
        2>&1

    $deploymentResult | Out-File -FilePath "$logDir\arm-deployment-result.json" -Encoding utf8

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ taz-* Cyren analytics deployment succeeded" -ForegroundColor Green
    } else {
        Write-Host "✗ taz-* Cyren analytics deployment failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
    }
}
finally {
    Stop-Transcript | Out-Null
    Write-Host "Logs archived at: $logDir" -ForegroundColor Cyan
}

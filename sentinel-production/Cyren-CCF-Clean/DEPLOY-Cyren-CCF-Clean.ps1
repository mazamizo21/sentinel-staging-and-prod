# Automated deployment of Cyren CCF solution (production) using client-config-COMPLETE.json
[CmdletBinding()]
param(
    [string]$ConfigFile = "..\client-config-COMPLETE.json",
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

# Load configuration
$config = (Get-Content $ConfigFile | ConvertFrom-Json).parameters
$sub  = $config.azure.value.subscriptionId

# Default to Cyren CCF test environment, allow overrides
$defaultRg = "CyrenCCFTest"
$defaultWs = "CyrenCCFWorkspace"

$rg   = if ($PSBoundParameters.ContainsKey('ResourceGroupName') -and $ResourceGroupName) { $ResourceGroupName } else { $defaultRg }
$ws   = if ($PSBoundParameters.ContainsKey('WorkspaceName') -and $WorkspaceName) { $WorkspaceName } else { $defaultWs }
$loc  = if ($PSBoundParameters.ContainsKey('Location') -and $Location) { $Location } else { $config.azure.value.location }

$cyrenIpJwt      = $config.cyren.value.ipReputation.jwtToken
$cyrenMalwareJwt = $config.cyren.value.malwareUrls.jwtToken

Write-Host "Config: $sub | $rg | $ws | $loc" -ForegroundColor Gray

# Prepare logging under Project/Docs
$ts = Get-Date -Format "yyyyMMddHHmmss"
$logDir = "..\Project\Docs\Validation\Cyren\cyren-ccf-clean-$ts"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript "$logDir\deploy-cyren-ccf-clean.log" | Out-Null

try {
    Write-Host "Setting subscription..." -ForegroundColor Cyan
    az account set --subscription $sub

    $templateFile = "./mainTemplate.json"
    if (-not (Test-Path $templateFile)) {
        throw "Template file not found: $templateFile"
    }

    Write-Host "Deploying Cyren CCF solution to workspace '$ws' in resource group '$rg'..." -ForegroundColor Cyan

    $deploymentName = "cyren-ccf-clean-$ts"

    $deploymentResult = az deployment group create `
        -g $rg `
        -n $deploymentName `
        --template-file $templateFile `
        --parameters workspace=$ws workspace-location=$loc cyrenIPJwtToken="$cyrenIpJwt" cyrenMalwareJwtToken="$cyrenMalwareJwt" `
        -o json `
        2>&1

    $deploymentResult | Out-File -FilePath "$logDir\arm-deployment-result.json" -Encoding utf8

    if ($LASTEXITCODE -eq 0) {
        Write-Host " Cyren CCF solution deployment succeeded" -ForegroundColor Green
    } else {
        Write-Host " Cyren CCF solution deployment failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
    }
}
finally {
    Stop-Transcript | Out-Null
    Write-Host "Logs archived at: $logDir" -ForegroundColor Cyan
}

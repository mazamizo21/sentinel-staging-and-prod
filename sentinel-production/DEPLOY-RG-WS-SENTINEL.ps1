[CmdletBinding()]
param(
    [string]$ConfigFile = './client-config-COMPLETE.json'
)

$ErrorActionPreference = 'Stop'

# Ensure we run from the script directory
$ScriptDir = Split-Path -Parent $PSCommandPath
Set-Location $ScriptDir

if (-not (Test-Path $ConfigFile)) {
    throw "Config file not found: $ConfigFile"
}

$config = (Get-Content $ConfigFile | ConvertFrom-Json).parameters
$sub   = $config.azure.value.subscriptionId
$rg    = $config.azure.value.resourceGroupName
$ws    = $config.azure.value.workspaceName
$loc   = $config.azure.value.location

$ts = Get-Date -Format 'yyyyMMddHHmmss'
$logRoot = 'Project/Docs/Infra'
$logDir = Join-Path $logRoot "rg-ws-sentinel-$ts"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$logFile = Join-Path $logDir 'deploy-rg-ws-sentinel.log'
Start-Transcript -Path $logFile | Out-Null

try {
    Write-Host "Using subscription: $sub" -ForegroundColor Cyan
    az account set --subscription $sub

    Write-Host "Ensuring resource group '$rg' in '$loc'..." -ForegroundColor Cyan
    az group create --name $rg --location $loc -o none

    Write-Host "Ensuring Log Analytics workspace '$ws'..." -ForegroundColor Cyan
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $wsJson = az monitor log-analytics workspace show -g $rg -n $ws -o json 2>$null
    $ErrorActionPreference = $prevEap

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($wsJson)) {
        Write-Host "Workspace not found. Creating..." -ForegroundColor Yellow
        az monitor log-analytics workspace create -g $rg -n $ws -l $loc -o none
        $wsJson = az monitor log-analytics workspace show -g $rg -n $ws -o json
    }

    $wsObj = $wsJson | ConvertFrom-Json
    $workspaceId = $wsObj.id

    Write-Host "Onboarding workspace to Microsoft Sentinel..." -ForegroundColor Cyan
    $onboardUri = "https://management.azure.com$workspaceId/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2024-03-01"
    az rest --method PUT --uri $onboardUri --body '{}' -o none 2>$null

    Write-Host "\nDeployment summary:" -ForegroundColor Green
    Write-Host "  Resource Group : $rg" -ForegroundColor Gray
    Write-Host "  Workspace      : $ws" -ForegroundColor Gray
    Write-Host "  Location       : $loc" -ForegroundColor Gray
    Write-Host "  Workspace Id   : $workspaceId" -ForegroundColor Gray

} finally {
    Stop-Transcript | Out-Null
    Write-Host "Logs archived at: $logDir" -ForegroundColor Cyan
}

# FORCE-SET-POLL-5MIN.ps1
# Update TacitRed CCF connector to 5-minute polling with correct API key auth

$ErrorActionPreference = 'Stop'

$sub = "774bee0e-b281-4f70-8e40-199e35b65117"
$rg  = "TacitRedCCFTest"
$ws  = "TacitRedCCFWorkspace"

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   FORCE SET CCF POLLING TO 5 MINUTES" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

az account set --subscription $sub | Out-Null

# Load current API key from config
$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$apiKey = $config.parameters.tacitRed.value.apiKey

Write-Host "Using API key from config (hidden)" -ForegroundColor Gray

# Get workspace id
$wsId = az monitor log-analytics workspace show `
    --resource-group $rg `
    --workspace-name $ws `
    --query id -o tsv

$connectorId = "$wsId/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings"
$apiVersion  = "2024-09-01"
$connUri     = "https://management.azure.com$connectorId?api-version=$apiVersion"

Write-Host "`nGetting current connector..." -ForegroundColor Yellow
$connector = az rest --method GET --uri $connUri 2>$null | ConvertFrom-Json

if(-not $connector){
    Write-Host "✗ Connector TacitRedFindings not found" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Found connector: $($connector.name)" -ForegroundColor Green
Write-Host "  Current polling: $($connector.properties.request.queryWindowInMin) minutes" -ForegroundColor Gray

# Update properties
Write-Host "`nUpdating polling to 5 minutes and auth header to Authorization: <key>..." -ForegroundColor Yellow

$connector.properties.request.queryWindowInMin = 5
$connector.properties.auth = [PSCustomObject]@{
    type            = "APIKey"
    ApiKeyName      = "Authorization"
    ApiKeyIdentifier = ""   # no prefix, matches Logic App
    ApiKey          = $apiKey
}

# Write to temp file
$tempFile = Join-Path $env:TEMP "tacitred-ccf-5min.json"
$connector | ConvertTo-Json -Depth 30 | Out-File -FilePath $tempFile -Encoding UTF8 -Force

Write-Host "Sending PUT to update connector..." -ForegroundColor Yellow
$putResult = az rest --method PUT --uri $connUri --headers "Content-Type=application/json" --body "@$tempFile" 2>&1

if($LASTEXITCODE -ne 0){
    Write-Host "✗ PUT failed" -ForegroundColor Red
    Write-Host $putResult -ForegroundColor Red
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

Write-Host "✓ Connector updated" -ForegroundColor Green

Start-Sleep -Seconds 5

Write-Host "`nReading back connector to confirm..." -ForegroundColor Yellow
$updated = az rest --method GET --uri $connUri 2>$null | ConvertFrom-Json

Write-Host "`n📊 CONNECTOR STATUS" -ForegroundColor Cyan
Write-Host "  Name: $($updated.name)" -ForegroundColor Gray
Write-Host "  Active: $($updated.properties.isActive)" -ForegroundColor $(if($updated.properties.isActive){'Green'}else{'Red'})
Write-Host "  Polling Interval: $($updated.properties.request.queryWindowInMin) minutes" -ForegroundColor $(if($updated.properties.request.queryWindowInMin -eq 5){'Green'}else{'Yellow'})

Write-Host "`n🔐 AUTH CONFIGURATION" -ForegroundColor Cyan
Write-Host "  Type: $($updated.properties.auth.type)" -ForegroundColor Gray
Write-Host "  Header: $($updated.properties.auth.ApiKeyName)" -ForegroundColor Gray
Write-Host "  Prefix: '$($updated.properties.auth.ApiKeyIdentifier)'" -ForegroundColor Gray
Write-Host "  ApiKey present in GET: $([string]::IsNullOrEmpty($updated.properties.auth.ApiKey) -eq $false)" -ForegroundColor Gray

$nextPoll = (Get-Date).AddMinutes(5).ToString("HH:mm")
Write-Host "`n⏱️ Next poll expected by: $nextPoll" -ForegroundColor Cyan
Write-Host "Run your KQL checks a few minutes after that time." -ForegroundColor White

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

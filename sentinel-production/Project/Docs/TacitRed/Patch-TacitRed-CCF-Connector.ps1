$ErrorActionPreference = 'Stop'

# Target: Tacitred-CCF-Hub-v2 resource group and workspace
$subscriptionId = '774bee0e-b281-4f70-8e40-199e35b65117'
$resourceGroup  = 'Tacitred-CCF-Hub-v2'
$workspaceName  = 'Tacitred-CCF-Hub-v2-ws'
$connectorName  = 'TacitRedFindings'

Write-Host "`n═══ PATCHING TACITRED CCF CONNECTOR ═══" -ForegroundColor Cyan
Write-Host "Subscription: $subscriptionId" -ForegroundColor Gray
Write-Host "Resource Group: $resourceGroup" -ForegroundColor Gray
Write-Host "Workspace: $workspaceName" -ForegroundColor Gray

az account set --subscription $subscriptionId | Out-Null

# Build connector URI
$connectorUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/dataConnectors/$connectorName?api-version=2024-09-01"

Write-Host "Reading existing connector..." -ForegroundColor Yellow
$connector = az rest --method GET --uri $connectorUri 2>$null | ConvertFrom-Json

if (-not $connector) {
    Write-Host "✗ Connector '$connectorName' not found" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Connector found (kind: $($connector.kind))" -ForegroundColor Green

# Patch request section: remove types[] and set queryWindowInMin = 600
if (-not $connector.properties.request) {
    Write-Host "✗ Connector has no request configuration" -ForegroundColor Red
    exit 1
}

$request = $connector.properties.request

# Ensure queryParameters exists
if (-not $request.queryParameters) {
    $request | Add-Member -NotePropertyName queryParameters -NotePropertyValue (@{}) -Force
}

# Remove types[] filter if present
if ($request.queryParameters.PSObject.Properties['types[]']) {
    Write-Host "Removing types[] filter from queryParameters" -ForegroundColor Yellow
    $request.queryParameters.PSObject.Properties.Remove('types[]') | Out-Null
}

# Ensure page_size is reasonable
if (-not $request.queryParameters.PSObject.Properties['page_size']) {
    $request.queryParameters | Add-Member -NotePropertyName 'page_size' -NotePropertyValue 50 -Force
} else {
    $request.queryParameters.page_size = 50
}

# Set wider query window for testing
$oldWindow = $request.queryWindowInMin
$request.queryWindowInMin = 600

Write-Host "Old queryWindowInMin: $oldWindow" -ForegroundColor Gray
Write-Host "New queryWindowInMin: $($request.queryWindowInMin)" -ForegroundColor Gray

# Write patched connector back
$tempFile = Join-Path $PSScriptRoot 'TacitRed-CCF-Connector-Patched.json'
$connector | ConvertTo-Json -Depth 50 | Out-File -FilePath $tempFile -Encoding UTF8 -Force

Write-Host "PATCHing connector via PUT..." -ForegroundColor Yellow
az rest --method PUT --uri $connectorUri --headers "Content-Type=application/json" --body "@$tempFile" 2>&1 | Out-Null

Write-Host "✓ Connector updated" -ForegroundColor Green

Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

Write-Host "`nConnector now configured to poll all types with a 600-minute window." -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

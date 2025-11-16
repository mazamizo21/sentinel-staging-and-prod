# FIX-CCF-APIKEY-FROM-KV.ps1
# Updates TacitRed CCF connector with API key from Key Vault

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   FIX TACITRED CCF CONNECTOR API KEY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$ws = $config.parameters.azure.value.workspaceName

Write-Host "Subscription: $sub" -ForegroundColor Gray
Write-Host "Resource Group: $rg" -ForegroundColor Gray
Write-Host "Workspace: $ws`n" -ForegroundColor Gray

az account set --subscription $sub | Out-Null

# Get API key from Key Vault
Write-Host "Retrieving API key from Key Vault..." -ForegroundColor Yellow
$apiKey = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "tacitred-api-key" --query "value" -o tsv 2>$null

if(-not $apiKey){
    Write-Host "✗ Could not retrieve API key" -ForegroundColor Red
    exit 1
}

Write-Host "✓ API key retrieved (length: $($apiKey.Length))" -ForegroundColor Green

# Get current connector
Write-Host "`nGetting current CCF connector configuration..." -ForegroundColor Yellow
$connectorName = "TacitRedFindings"
$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/$connectorName`?api-version=2024-09-01"

$connector = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json

if(-not $connector){
    Write-Host "✗ CCF Connector not found" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Retrieved connector" -ForegroundColor Green

# Update API key - rebuild auth section properly
Write-Host "`nUpdating API key in connector..." -ForegroundColor Yellow

# The auth section needs to be rebuilt with proper structure
$connector.properties.auth = @{
    type = "APIKey"
    ApiKeyName = "Authorization"
    ApiKey = $apiKey
}

# Save and update
$tempFile = "$env:TEMP\ccf-update.json"
$connector | ConvertTo-Json -Depth 20 | Out-File -FilePath $tempFile -Encoding UTF8 -Force

Write-Host "Sending update request..." -ForegroundColor Gray
$result = az rest --method PUT --uri $uri --headers "Content-Type=application/json" --body "@$tempFile" 2>&1

Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

if($LASTEXITCODE -eq 0){
    Write-Host "✓ CCF connector updated!" -ForegroundColor Green
    
    # Wait and verify
    Write-Host "`nWaiting 5 seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    # Check if it's actually set now
    $updated = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json
    
    Write-Host "`nVerification:" -ForegroundColor Cyan
    Write-Host "  Auth Type: $($updated.properties.auth.type)" -ForegroundColor Gray
    Write-Host "  API Key Header: $($updated.properties.auth.ApiKeyName)" -ForegroundColor Gray
    
    if($updated.properties.auth.ApiKey){
        Write-Host "  API Key: ✓ SET (value hidden for security)" -ForegroundColor Green
    }else{
        Write-Host "  API Key: ⚠ Still shows as null (this may be Azure masking it)" -ForegroundColor Yellow
    }
    
    Write-Host "`n✅ UPDATE COMPLETE!" -ForegroundColor Green
    Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "  1. CCF polls every 60 minutes" -ForegroundColor White
    Write-Host "  2. Wait 60-120 minutes for first data" -ForegroundColor White
    Write-Host "  3. Verify with: .\VERIFY-TACITRED-DATA.ps1" -ForegroundColor White
    Write-Host "`n  4. If still no data after 2 hours:" -ForegroundColor White
    Write-Host "     - Check DCR/DCE configuration" -ForegroundColor DarkGray
    Write-Host "     - Check if API actually has data: .\DIAGNOSE-CCF-TACITRED.ps1" -ForegroundColor DarkGray
    
}else{
    Write-Host "✗ Update failed: $result" -ForegroundColor Red
    exit 1
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

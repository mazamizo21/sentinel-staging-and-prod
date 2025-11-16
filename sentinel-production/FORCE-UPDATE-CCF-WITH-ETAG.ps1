# FORCE-UPDATE-CCF-WITH-ETAG.ps1
# Force update CCF connector using etag to ensure persistence

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   FORCE UPDATE CCF CONNECTOR (WITH ETAG)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$ws = $config.parameters.azure.value.workspaceName
$apiKey = $config.parameters.tacitRed.value.apiKey

Write-Host "Forcing CCF connector update with:" -ForegroundColor Yellow
Write-Host "  - API Key from config" -ForegroundColor Gray
Write-Host "  - queryWindowInMin: 5 (for testing)" -ForegroundColor Gray
Write-Host "  - Using etag for concurrency control`n" -ForegroundColor Gray

az account set --subscription $sub | Out-Null

$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"

# Get current connector WITH etag
Write-Host "Step 1: Getting current connector with etag..." -ForegroundColor Yellow
$connector = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json

if(-not $connector){
    Write-Host "✗ Connector not found!" -ForegroundColor Red
    exit 1
}

$etag = $connector.etag
Write-Host "✓ Got connector (etag: $etag)" -ForegroundColor Green

# Update the connector with API key and 5-min interval
Write-Host "`nStep 2: Updating connector configuration..." -ForegroundColor Yellow

# Rebuild auth section with API key
$connector.properties.auth = [PSCustomObject]@{
    type = "APIKey"
    ApiKeyName = "Authorization"
    ApiKey = $apiKey
}

# Update polling interval to 5 minutes
$connector.properties.request.queryWindowInMin = 5

# Remove etag from body (will send as header)
$bodyConnector = $connector | Select-Object -Property * -ExcludeProperty etag

# Save to temp file
$tempFile = "$env:TEMP\ccf-force-update.json"
$bodyConnector | ConvertTo-Json -Depth 20 | Out-File -FilePath $tempFile -Encoding UTF8 -Force

Write-Host "  Sending PUT with etag header..." -ForegroundColor Gray

# Send PUT with etag as header (If-Match)
$headers = @(
    "Content-Type=application/json"
    "If-Match=$etag"
)

$result = az rest --method PUT --uri $uri --headers $headers --body "@$tempFile" 2>&1

Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

if($LASTEXITCODE -eq 0){
    Write-Host "✓ Update command executed" -ForegroundColor Green
    
    # Wait and verify
    Write-Host "`nStep 3: Verifying update (waiting 10 seconds)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    
    $updated = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json
    
    Write-Host "`nVerification Results:" -ForegroundColor Cyan
    Write-Host "  queryWindowInMin: $($updated.properties.request.queryWindowInMin) minutes" -ForegroundColor $(if($updated.properties.request.queryWindowInMin -eq 5){'Green'}else{'Red'})
    
    if($updated.properties.auth.ApiKey){
        Write-Host "  API Key: ✓ SET" -ForegroundColor Green
    }elseif($updated.properties.auth.apiKey){
        Write-Host "  API Key: ✓ SET (lowercase property)" -ForegroundColor Green
    }else{
        Write-Host "  API Key: ✗ STILL NULL!" -ForegroundColor Red
        Write-Host "`n  This suggests Azure is rejecting the API key field" -ForegroundColor Yellow
        Write-Host "  CCF might need Key Vault reference instead of direct value" -ForegroundColor Yellow
    }
    
    if($updated.properties.request.queryWindowInMin -eq 5 -and ($updated.properties.auth.ApiKey -or $updated.properties.auth.apiKey)){
        Write-Host "`n✅ UPDATE SUCCESSFUL!" -ForegroundColor Green
        Write-Host "`n📋 NEXT: Wait 5-10 minutes and check for data" -ForegroundColor Cyan
        Write-Host "  CCF should poll within 5 minutes now" -ForegroundColor White
    }else{
        Write-Host "`n⚠ UPDATE PARTIALLY FAILED" -ForegroundColor Yellow
        Write-Host "`nPossible issues:" -ForegroundColor Red
        Write-Host "  1. Azure REST API doesn't accept ApiKey in connector updates" -ForegroundColor White
        Write-Host "  2. CCF requires Key Vault reference (@Microsoft.KeyVault...)" -ForegroundColor White
        Write-Host "  3. This specific connector instance has an issue" -ForegroundColor White
    }
    
}else{
    Write-Host "✗ Update failed!" -ForegroundColor Red
    Write-Host "  Error: $result" -ForegroundColor Red
    exit 1
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

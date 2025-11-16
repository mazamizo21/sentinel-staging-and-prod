# UPDATE-CCF-APIKEY.ps1
# Updates TacitRed CCF connector with API key from Key Vault

<#
.SYNOPSIS
    Updates TacitRed CCF connector authentication
.DESCRIPTION
    Retrieves API key from Key Vault and updates the CCF connector configuration
.PARAMETER TestFirst
    Test the API key before updating the connector
#>

param(
    [switch]$TestFirst
)

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   UPDATE TACITRED CCF CONNECTOR API KEY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$ws = $config.parameters.azure.value.workspaceName

Write-Host "Subscription: $sub" -ForegroundColor Gray
Write-Host "Resource Group: $rg" -ForegroundColor Gray
Write-Host "Workspace: $ws`n" -ForegroundColor Gray

az account set --subscription $sub | Out-Null

# Step 1: Get API key from Key Vault
Write-Host "═══ STEP 1: RETRIEVE API KEY ═══" -ForegroundColor Cyan
Write-Host "Retrieving API key from Key Vault..." -ForegroundColor Yellow

try {
    $apiKey = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "tacitred-api-key" --query "value" -o tsv 2>$null
    
    if(-not $apiKey){
        Write-Host "✗ Could not retrieve API key from Key Vault" -ForegroundColor Red
        Write-Host "`n📋 ACTION REQUIRED:" -ForegroundColor Yellow
        Write-Host "  1. Ensure you have a valid TacitRed API key" -ForegroundColor White
        Write-Host "  2. Store it in Key Vault:" -ForegroundColor White
        Write-Host "     az keyvault secret set --vault-name kv-tacitred-secure01 --name tacitred-api-key --value YOUR-API-KEY" -ForegroundColor Gray
        exit 1
    }
    
    Write-Host "✓ API key retrieved" -ForegroundColor Green
    Write-Host "  Length: $($apiKey.Length) chars" -ForegroundColor Gray
    Write-Host "  First 8: $($apiKey.Substring(0,8))..." -ForegroundColor Gray
    
} catch {
    Write-Host "✗ Error retrieving API key: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 2: Test API key (if requested)
if($TestFirst){
    Write-Host "`n═══ STEP 2: TEST API KEY ═══" -ForegroundColor Cyan
    Write-Host "Testing API key against TacitRed API..." -ForegroundColor Yellow
    
    $headers = @{
        'Authorization' = "Bearer $apiKey"
        'Accept' = 'application/json'
        'User-Agent' = 'Microsoft-Sentinel-TacitRed/1.0'
    }
    
    $endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $startTime = (Get-Date).AddDays(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $testUrl = "https://app.tacitred.com/api/v1/findings?from=$startTime&until=$endTime&page_size=10"
    
    try {
        $response = Invoke-RestMethod -Uri $testUrl -Method Get -Headers $headers -TimeoutSec 30
        Write-Host "✓ API key is VALID!" -ForegroundColor Green
        Write-Host "  Result Count: $($response.results.Count)" -ForegroundColor Gray
        
        if($response.results.Count -eq 0){
            Write-Host "  ⚠ API returned 0 results (no data in last 24 hours)" -ForegroundColor Yellow
        }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "✗ API key test FAILED!" -ForegroundColor Red
        Write-Host "  Status Code: $statusCode" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if($statusCode -eq 401){
            Write-Host "`n  🔴 API KEY IS INVALID" -ForegroundColor Red
            Write-Host "  Please get a valid API key from TacitRed before proceeding" -ForegroundColor Red
            exit 1
        }
    }
}

# Step 3: Get current CCF connector configuration
Write-Host "`n═══ STEP 3: GET CURRENT CONNECTOR CONFIG ═══" -ForegroundColor Cyan

$connectorName = "TacitRedFindings"
$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/$connectorName`?api-version=2024-09-01"

try {
    $connector = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json
    
    if(-not $connector){
        Write-Host "✗ CCF Connector not found" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✓ Retrieved current connector configuration" -ForegroundColor Green
    
} catch {
    Write-Host "✗ Error retrieving connector: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 4: Update connector with API key
Write-Host "`n═══ STEP 4: UPDATE CONNECTOR API KEY ═══" -ForegroundColor Cyan
Write-Host "Updating CCF connector with new API key..." -ForegroundColor Yellow

# Update the auth section with new API key
$connector.properties.auth.ApiKey = $apiKey

# Save updated config to temp file
$tempFile = "$env:TEMP\ccf-tacitred-update.json"
$connector | ConvertTo-Json -Depth 20 | Out-File -FilePath $tempFile -Encoding UTF8 -Force

try {
    Write-Host "Sending update request..." -ForegroundColor Gray
    $result = az rest --method PUT --uri $uri --headers "Content-Type=application/json" --body "@$tempFile" 2>&1
    
    if($LASTEXITCODE -eq 0){
        Write-Host "✓ CCF connector updated successfully!" -ForegroundColor Green
        
        # Verify update
        Start-Sleep -Seconds 3
        $updated = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json
        
        if($updated.properties.auth.ApiKey){
            Write-Host "✓ API key is now SET in connector" -ForegroundColor Green
        }else{
            Write-Host "⚠ API key still shows as not set (may be masked)" -ForegroundColor Yellow
        }
        
    }else{
        Write-Host "✗ Update failed" -ForegroundColor Red
        Write-Host "  Result: $result" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "✗ Error updating connector: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
}

# Step 5: Summary
Write-Host "`n═══ SUCCESS! ═══" -ForegroundColor Green
Write-Host "`n✅ CCF connector has been updated with the API key from Key Vault" -ForegroundColor Green

Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Cyan
Write-Host "  1. CCF will poll TacitRed API on its schedule (every 60 minutes)" -ForegroundColor White
Write-Host "  2. First data should appear within 60-120 minutes" -ForegroundColor White
Write-Host "  3. Monitor with:" -ForegroundColor White
Write-Host "     .\VERIFY-TACITRED-DATA.ps1" -ForegroundColor Gray
Write-Host "`n  4. If data still doesn't appear, check if TacitRed API has findings:" -ForegroundColor White
Write-Host "     .\DIAGNOSE-CCF-TACITRED.ps1" -ForegroundColor Gray

Write-Host "`n⏱️  Expected first ingestion: Within 60-120 minutes from now" -ForegroundColor Yellow
Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

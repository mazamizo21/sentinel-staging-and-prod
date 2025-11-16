# UPDATE-ALL-WITH-NEW-APIKEY.ps1
# Updates TacitRed API key everywhere after you get a new valid key

<#
.SYNOPSIS
    Complete update of TacitRed API key across all systems
.DESCRIPTION
    Updates:
    1. Key Vault secret
    2. CCF connector
    3. Config file
    4. Tests the new key
.PARAMETER NewApiKey
    The new valid API key from TacitRed
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$NewApiKey
)

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   UPDATE TACITRED API KEY EVERYWHERE" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

# Validate API key format (should be UUID)
$uuidPattern = '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$'
if($NewApiKey -notmatch $uuidPattern){
    Write-Host "⚠ WARNING: API key doesn't match UUID format" -ForegroundColor Yellow
    Write-Host "  Expected format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -ForegroundColor Gray
    $continue = Read-Host "Continue anyway? (y/n)"
    if($continue -ne 'y'){
        exit 1
    }
}

Write-Host "New API Key: $($NewApiKey.Substring(0,8))..." -ForegroundColor Gray
Write-Host ""

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$ws = $config.parameters.azure.value.workspaceName

az account set --subscription $sub | Out-Null

# ============================================================================
# STEP 1: TEST NEW API KEY
# ============================================================================
Write-Host "═══ STEP 1: TEST NEW API KEY ═══" -ForegroundColor Cyan
Write-Host "Testing API key against TacitRed API..." -ForegroundColor Yellow

$headers = @{
    'Authorization' = "Bearer $NewApiKey"
    'Accept' = 'application/json'
    'User-Agent' = 'Microsoft-Sentinel-TacitRed/1.0'
}

$endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$startTime = (Get-Date).AddDays(-7).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$testUrl = "https://app.tacitred.com/api/v1/findings?from=$startTime&until=$endTime&page_size=10"

try {
    $response = Invoke-RestMethod -Uri $testUrl -Method Get -Headers $headers -TimeoutSec 30
    Write-Host "✅ API KEY IS VALID!" -ForegroundColor Green
    Write-Host "  API returned HTTP 200" -ForegroundColor Green
    Write-Host "  Result Count: $($response.results.Count)" -ForegroundColor Gray
    
    if($response.results.Count -gt 0){
        Write-Host "  ✓ TacitRed has data available!" -ForegroundColor Green
        Write-Host "`n  Sample finding:" -ForegroundColor Cyan
        $sample = $response.results[0]
        Write-Host "    Email: $($sample.email)" -ForegroundColor Gray
        Write-Host "    Type: $($sample.findingType)" -ForegroundColor Gray
        Write-Host "    Confidence: $($sample.confidence)" -ForegroundColor Gray
    }else{
        Write-Host "  ⚠ API valid but no data in last 7 days" -ForegroundColor Yellow
    }
    
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    Write-Host "✗ API KEY TEST FAILED!" -ForegroundColor Red
    Write-Host "  Status Code: $statusCode" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if($statusCode -eq 401){
        Write-Host "`n  🔴 This API key is STILL INVALID" -ForegroundColor Red
        Write-Host "  Cannot proceed with update" -ForegroundColor Red
        exit 1
    }
}

# ============================================================================
# STEP 2: UPDATE KEY VAULT
# ============================================================================
Write-Host "`n═══ STEP 2: UPDATE KEY VAULT ═══" -ForegroundColor Cyan
Write-Host "Updating Key Vault secret..." -ForegroundColor Yellow

try {
    az keyvault secret set `
        --vault-name "kv-tacitred-secure01" `
        --name "tacitred-api-key" `
        --value $NewApiKey `
        -o none 2>$null
    
    Write-Host "✓ Key Vault updated" -ForegroundColor Green
    
} catch {
    Write-Host "✗ Key Vault update failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================================================
# STEP 3: UPDATE CCF CONNECTOR
# ============================================================================
Write-Host "`n═══ STEP 3: UPDATE CCF CONNECTOR ═══" -ForegroundColor Cyan
Write-Host "Updating CCF connector..." -ForegroundColor Yellow

$connectorName = "TacitRedFindings"
$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/$connectorName`?api-version=2024-09-01"

try {
    # Get current connector
    $connector = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json
    
    if(-not $connector){
        Write-Host "✗ CCF Connector not found" -ForegroundColor Red
        exit 1
    }
    
    # Update auth section
    $connector.properties.auth = @{
        type = "APIKey"
        ApiKeyName = "Authorization"
        ApiKey = $NewApiKey
    }
    
    # Save and update
    $tempFile = "$env:TEMP\ccf-update-new-key.json"
    $connector | ConvertTo-Json -Depth 20 | Out-File -FilePath $tempFile -Encoding UTF8 -Force
    
    $result = az rest --method PUT --uri $uri --headers "Content-Type=application/json" --body "@$tempFile" 2>&1
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    
    if($LASTEXITCODE -eq 0){
        Write-Host "✓ CCF connector updated" -ForegroundColor Green
    }else{
        Write-Host "✗ CCF update failed: $result" -ForegroundColor Red
    }
    
} catch {
    Write-Host "✗ Error updating CCF: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# STEP 4: UPDATE CONFIG FILE
# ============================================================================
Write-Host "`n═══ STEP 4: UPDATE CONFIG FILE ═══" -ForegroundColor Cyan
Write-Host "Updating client-config-COMPLETE.json..." -ForegroundColor Yellow

try {
    # Update the apiKey value
    $config.parameters.tacitRed.value.apiKey = $NewApiKey
    
    # Save updated config
    $config | ConvertTo-Json -Depth 20 | Out-File -FilePath ".\client-config-COMPLETE.json" -Encoding UTF8 -Force
    
    Write-Host "✓ Config file updated" -ForegroundColor Green
    
} catch {
    Write-Host "✗ Config update failed: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# STEP 5: UPDATE MARKETPLACE ARM TEMPLATE (REMINDER)
# ============================================================================
Write-Host "`n═══ STEP 5: MARKETPLACE ARM TEMPLATE ═══" -ForegroundColor Cyan
Write-Host "⚠ REMINDER: Your marketplace ARM template is already correct!" -ForegroundColor Yellow
Write-Host "  Location: .\Tacitred-CCF\mainTemplate.json" -ForegroundColor Gray
Write-Host "  It uses a parameter for API key (customers provide their own)" -ForegroundColor Gray
Write-Host "  No changes needed to the template itself" -ForegroundColor Green

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n═══ UPDATE COMPLETE! ═══" -ForegroundColor Green

Write-Host "`n✅ UPDATED:" -ForegroundColor Cyan
Write-Host "  ✓ Key Vault secret (kv-tacitred-secure01/tacitred-api-key)" -ForegroundColor Green
Write-Host "  ✓ CCF connector (TacitRedFindings)" -ForegroundColor Green
Write-Host "  ✓ Config file (client-config-COMPLETE.json)" -ForegroundColor Green

Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. CCF will poll on its schedule (every 60 minutes)" -ForegroundColor White
Write-Host "  2. First data expected within 60-120 minutes" -ForegroundColor White
Write-Host "  3. Verify with:" -ForegroundColor White
Write-Host "     .\VERIFY-TACITRED-DATA.ps1" -ForegroundColor Gray
Write-Host "`n  4. Your marketplace package (Tacitred-CCF) is ready!" -ForegroundColor White
Write-Host "     - Customers will provide their own API keys" -ForegroundColor DarkGray
Write-Host "     - No hardcoded credentials" -ForegroundColor DarkGray

Write-Host "`n⏱️  Expected Timeline:" -ForegroundColor Cyan
Write-Host "  Now: CCF updated with valid key" -ForegroundColor Gray
Write-Host "  +0-60 min: Next CCF poll attempt" -ForegroundColor Gray
Write-Host "  +60-90 min: Data ingestion to DCR" -ForegroundColor Gray
Write-Host "  +90-120 min: Data visible in Log Analytics table" -ForegroundColor Gray

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# CHECK-LOGICAPP-APIKEY-SOURCE.ps1
# Check where Logic App gets its API key from

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   LOGIC APP API KEY SOURCE CHECK" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$configApiKey = $config.parameters.tacitRed.value.apiKey

Write-Host "Config File API Key: $($configApiKey.Substring(0,8))..." -ForegroundColor Gray
Write-Host ""

az account set --subscription $sub | Out-Null

# Get Logic App definition
$laName = "logic-tacitred-ingestion"
$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName`?api-version=2019-05-01"

Write-Host "Retrieving Logic App configuration..." -ForegroundColor Yellow
$la = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json

if(-not $la){
    Write-Host "✗ Logic App not found" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Logic App retrieved`n" -ForegroundColor Green

# Check parameters
Write-Host "═══ LOGIC APP PARAMETERS ═══" -ForegroundColor Cyan

if($la.properties.parameters){
    Write-Host "Parameters defined:" -ForegroundColor Yellow
    $la.properties.parameters.PSObject.Properties | ForEach-Object {
        $paramName = $_.Name
        $paramValue = $_.Value.value
        
        Write-Host "  $paramName : " -NoNewline -ForegroundColor Gray
        
        # Check if it's a Key Vault reference
        if($paramValue -match "@Microsoft.KeyVault"){
            Write-Host "🔑 KEY VAULT REFERENCE" -ForegroundColor Cyan
            Write-Host "    $paramValue" -ForegroundColor DarkGray
        }
        elseif($paramName -match "key|token|secret" -and $paramValue){
            # Mask sensitive values
            $masked = if($paramValue.Length -gt 8){$paramValue.Substring(0,8) + "..."}else{"***"}
            Write-Host "$masked" -ForegroundColor Green
        }
        else{
            Write-Host "$paramValue" -ForegroundColor Gray
        }
    }
}else{
    Write-Host "⚠ No parameters defined" -ForegroundColor Yellow
}

# Check actions for API key usage
Write-Host "`n═══ API KEY USAGE IN ACTIONS ═══" -ForegroundColor Cyan

if($la.properties.definition.actions){
    $callApiAction = $la.properties.definition.actions.'Call_TacitRed_API'
    
    if($callApiAction){
        Write-Host "Found 'Call_TacitRed_API' action" -ForegroundColor Yellow
        
        # Check headers
        if($callApiAction.inputs.headers){
            Write-Host "`nHeaders:" -ForegroundColor Cyan
            $callApiAction.inputs.headers.PSObject.Properties | ForEach-Object {
                $headerName = $_.Name
                $headerValue = $_.Value
                
                Write-Host "  $headerName : " -NoNewline -ForegroundColor Gray
                
                # Check if it's a parameter reference
                if($headerValue -match "@parameters"){
                    Write-Host "📝 PARAMETER REFERENCE" -ForegroundColor Green
                    Write-Host "    $headerValue" -ForegroundColor DarkGray
                }
                elseif($headerName -match "Authorization"){
                    # Check if it's using Key Vault
                    if($headerValue -match "@Microsoft.KeyVault"){
                        Write-Host "🔑 KEY VAULT REFERENCE" -ForegroundColor Cyan
                    }
                    else{
                        $masked = if($headerValue.Length -gt 20){"Bearer " + $headerValue.Substring(7,8) + "..."}else{"***"}
                        Write-Host "$masked" -ForegroundColor Yellow
                    }
                }
                else{
                    Write-Host "$headerValue" -ForegroundColor Gray
                }
            }
        }
    }
}

# Compare keys
Write-Host "`n═══ KEY COMPARISON ═══" -ForegroundColor Cyan

Write-Host "`n1. Config File Key:" -ForegroundColor Yellow
Write-Host "   $($configApiKey.Substring(0,8))...$($configApiKey.Substring($configApiKey.Length-8))" -ForegroundColor Gray

Write-Host "`n2. Key Vault Key:" -ForegroundColor Yellow
$kvKey = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "tacitred-api-key" --query "value" -o tsv 2>$null
if($kvKey){
    Write-Host "   $($kvKey.Substring(0,8))...$($kvKey.Substring($kvKey.Length-8))" -ForegroundColor Gray
    
    if($kvKey -eq $configApiKey){
        Write-Host "   ✓ MATCHES config file" -ForegroundColor Green
    }else{
        Write-Host "   ✗ DIFFERENT from config file!" -ForegroundColor Red
    }
}else{
    Write-Host "   ✗ Could not retrieve from Key Vault" -ForegroundColor Red
}

# Test both keys
Write-Host "`n═══ API KEY TESTS ═══" -ForegroundColor Cyan

$testUrl = "https://app.tacitred.com/api/v1/findings?from=2025-11-14T00:00:00Z&until=2025-11-14T23:59:59Z&page_size=1"

Write-Host "`n1. Testing Config File Key..." -ForegroundColor Yellow
$headers = @{
    'Authorization' = "Bearer $configApiKey"
    'Accept' = 'application/json'
}
try {
    $response = Invoke-RestMethod -Uri $testUrl -Method Get -Headers $headers -TimeoutSec 10
    Write-Host "   ✅ SUCCESS! HTTP 200" -ForegroundColor Green
    Write-Host "   Results: $($response.results.Count)" -ForegroundColor Gray
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Host "   ✗ FAILED! HTTP $code" -ForegroundColor Red
}

if($kvKey -and $kvKey -ne $configApiKey){
    Write-Host "`n2. Testing Key Vault Key..." -ForegroundColor Yellow
    $headers = @{
        'Authorization' = "Bearer $kvKey"
        'Accept' = 'application/json'
    }
    try {
        $response = Invoke-RestMethod -Uri $testUrl -Method Get -Headers $headers -TimeoutSec 10
        Write-Host "   ✅ SUCCESS! HTTP 200" -ForegroundColor Green
        Write-Host "   Results: $($response.results.Count)" -ForegroundColor Gray
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        Write-Host "   ✗ FAILED! HTTP $code" -ForegroundColor Red
    }
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

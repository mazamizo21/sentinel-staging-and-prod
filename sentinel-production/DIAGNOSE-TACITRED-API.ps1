# DIAGNOSE-TACITRED-API.ps1
# Focused diagnostic for TacitRed API 401 error

<#
.SYNOPSIS
    Diagnoses TacitRed API authentication issue
.DESCRIPTION
    Tests different authentication methods and formats to identify
    why TacitRed API is returning 401 Unauthorized
#>

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   TACITRED API DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

# Retrieve API key
Write-Host "`n[Step 1: Retrieve API Key from Key Vault]" -ForegroundColor Yellow
$apiKey = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "tacitred-api-key" --query "value" -o tsv 2>$null

if(-not $apiKey){
    Write-Host "✗ Could not retrieve API key from Key Vault" -ForegroundColor Red
    exit 1
}

Write-Host "✓ API Key retrieved" -ForegroundColor Green
Write-Host "  Length: $($apiKey.Length)" -ForegroundColor Gray
Write-Host "  First 8 chars: $($apiKey.Substring(0,8))..." -ForegroundColor Gray
Write-Host "  Last 4 chars: ...$($apiKey.Substring($apiKey.Length-4))" -ForegroundColor Gray

# Check if it's a valid UUID format
$uuidPattern = '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$'
$isUUID = $apiKey -match $uuidPattern
Write-Host "  Is UUID format: $isUUID" -ForegroundColor $(if($isUUID){'Green'}else{'Yellow'})

# Test different authentication methods
Write-Host "`n[Step 2: Test Different Authentication Methods]" -ForegroundColor Yellow

$testEndpoint = "https://app.tacitred.com/api/v1/findings"
$endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$startTime = (Get-Date).AddDays(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$testUrl = "${testEndpoint}?from=${startTime}&until=${endTime}&page_size=10"

$authMethods = @(
    @{
        Name = "Method 1: Bearer token in Authorization header"
        Headers = @{
            'Authorization' = "Bearer $apiKey"
            'Accept' = 'application/json'
            'User-Agent' = 'Microsoft-Sentinel-TacitRed/1.0'
        }
    },
    @{
        Name = "Method 2: API key directly in Authorization header (no Bearer)"
        Headers = @{
            'Authorization' = $apiKey
            'Accept' = 'application/json'
            'User-Agent' = 'Microsoft-Sentinel-TacitRed/1.0'
        }
    },
    @{
        Name = "Method 3: API key in X-API-Key header"
        Headers = @{
            'X-API-Key' = $apiKey
            'Accept' = 'application/json'
            'User-Agent' = 'Microsoft-Sentinel-TacitRed/1.0'
        }
    },
    @{
        Name = "Method 4: API key in api_key query parameter"
        Headers = @{
            'Accept' = 'application/json'
            'User-Agent' = 'Microsoft-Sentinel-TacitRed/1.0'
        }
        UseQueryParam = $true
    }
)

$successMethod = $null

foreach($method in $authMethods){
    Write-Host "`n$($method.Name)" -ForegroundColor Cyan
    
    $url = $testUrl
    if($method.UseQueryParam){
        $url = "${testUrl}&api_key=${apiKey}"
    }
    
    try {
        $response = Invoke-WebRequest -Uri $url -Method Get -Headers $method.Headers -TimeoutSec 30
        
        Write-Host "  ✓ SUCCESS!" -ForegroundColor Green
        Write-Host "  Status Code: $($response.StatusCode)" -ForegroundColor Green
        Write-Host "  Content Length: $($response.Content.Length) bytes" -ForegroundColor Gray
        
        # Try to parse response
        try {
            $data = $response.Content | ConvertFrom-Json
            Write-Host "  Result Count: $($data.results.Count)" -ForegroundColor Green
            
            if($data.results.Count -gt 0){
                Write-Host "`n  Sample Finding:" -ForegroundColor Green
                $sample = $data.results[0]
                $sample | ConvertTo-Json -Depth 2 -Compress | Write-Host -ForegroundColor Gray
            }
        } catch {
            Write-Host "  Response Content:" -ForegroundColor Gray
            Write-Host $response.Content.Substring(0, [Math]::Min(200, $response.Content.Length)) -ForegroundColor DarkGray
        }
        
        $successMethod = $method.Name
        break
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $statusDesc = $_.Exception.Response.StatusDescription
        
        Write-Host "  ✗ Failed" -ForegroundColor Red
        Write-Host "  Status Code: $statusCode ($statusDesc)" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        
        # Try to read error response body
        try {
            $errorStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream)
            $errorBody = $reader.ReadToEnd()
            if($errorBody){
                Write-Host "  Error Body: $errorBody" -ForegroundColor Red
            }
        } catch {
            # Ignore if we can't read error body
        }
    }
}

# Summary
Write-Host "`n[Step 3: Summary]" -ForegroundColor Yellow

if($successMethod){
    Write-Host "✅ AUTHENTICATION METHOD FOUND!" -ForegroundColor Green
    Write-Host "  Working Method: $successMethod" -ForegroundColor Green
    Write-Host "`n📋 ACTION REQUIRED:" -ForegroundColor Cyan
    Write-Host "  Update the CCF connector configuration to use this authentication method" -ForegroundColor White
}else{
    Write-Host "❌ ALL AUTHENTICATION METHODS FAILED" -ForegroundColor Red
    Write-Host "`n🔍 POSSIBLE CAUSES:" -ForegroundColor Yellow
    Write-Host "  1. API key in Key Vault is incorrect or expired" -ForegroundColor White
    Write-Host "  2. API endpoint has changed" -ForegroundColor White
    Write-Host "  3. IP whitelist restriction (API only allows certain IPs)" -ForegroundColor White
    Write-Host "  4. Account/subscription issue with TacitRed service" -ForegroundColor White
    Write-Host "`n📋 RECOMMENDED ACTIONS:" -ForegroundColor Cyan
    Write-Host "  1. Verify API key with TacitRed support" -ForegroundColor White
    Write-Host "  2. Check TacitRed account status and subscription" -ForegroundColor White
    Write-Host "  3. Review TacitRed API documentation for authentication changes" -ForegroundColor White
    Write-Host "  4. Test API key from TacitRed admin console or documentation" -ForegroundColor White
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

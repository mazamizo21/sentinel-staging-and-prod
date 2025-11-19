$ErrorActionPreference = 'Stop'

# Load API key from config
$configPath = "./sentinel-staging/client-config-COMPLETE.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$apiKey = $config.parameters.tacitRed.value.apiKey

Write-Host "`nTesting TacitRed API connection..." -ForegroundColor Cyan
Write-Host "API Key length: $($apiKey.Length)" -ForegroundColor Gray

# Test endpoints
$endpoints = @(
    "https://app.tacitred.com/api/v1/findings",
    "https://api.tacitred.com/v1/findings"
)

# Quick time window (last 24 hours)
$until = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$from  = (Get-Date).AddDays(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

foreach ($endpoint in $endpoints) {
    Write-Host "`nTrying endpoint: $endpoint" -ForegroundColor Yellow
    
    $testUrl = "$endpoint`?from=$from&until=$until&page_size=10"
    
    # Try Bearer token auth (most common)
    try {
        $resp = Invoke-WebRequest -Uri $testUrl -Method Get -Headers @{
            "Authorization" = "Bearer $apiKey"
            "Accept" = "application/json"
        } -TimeoutSec 30
        
        Write-Host "  ✓ SUCCESS with Bearer token!" -ForegroundColor Green
        Write-Host "  Status: $($resp.StatusCode)" -ForegroundColor Green
        
        $data = $resp.Content | ConvertFrom-Json
        Write-Host "  Results count: $($data.results.Count)" -ForegroundColor Green
        
        if ($data.results.Count -gt 0) {
            Write-Host "  Sample finding:" -ForegroundColor Gray
            $data.results[0] | ConvertTo-Json -Depth 2 -Compress | Write-Host -ForegroundColor DarkGray
        }
        
        exit 0
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "  ✗ Failed with Bearer token (Status: $statusCode)" -ForegroundColor Red
        
        if ($statusCode -eq 401) {
            Write-Host "  Error: Unauthorized" -ForegroundColor Red
        }
    }
}

Write-Host "`n❌ All connection attempts failed" -ForegroundColor Red
Write-Host "API key may be invalid or expired" -ForegroundColor Yellow
exit 1

param(
    [string]$ConfigPath = "./sentinel-staging/client-config-COMPLETE.json"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ConfigPath)) {
    Write-Host "Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$tacit  = $config.parameters.tacitRed.value
$apiKey = $tacit.apiKey

if (-not $apiKey) {
    Write-Host "TacitRed apiKey not found in config." -ForegroundColor Red
    exit 1
}

Write-Host ("TacitRed config loaded. API key length: {0}" -f $apiKey.Length) -ForegroundColor Gray

# Last known data was October 26
$fromDate  = Get-Date "2025-10-26T00:00:00Z"  # adjust year if needed
$untilDate = (Get-Date).ToUniversalTime()

$endpoint = "https://app.tacitred.com/api/v1/findings"
$pageSize = 100

$from  = $fromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$until = $untilDate.ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host ("Querying TacitRed findings from {0} to {1} ..." -f $from, $until) -ForegroundColor Cyan

$results = @()
$nextUrl = "{0}?from={1}&until={2}&page_size={3}" -f $endpoint, $from, $until, $pageSize

while ($nextUrl) {
    Write-Host ("Calling: {0}" -f $nextUrl) -ForegroundColor DarkGray

    $resp = Invoke-WebRequest -Uri $nextUrl -Method Get -Headers @{
        "Authorization" = "Bearer $apiKey"
        "Accept"        = "application/json"
        "User-Agent"    = "Microsoft-Sentinel-TacitRed/1.0"
    } -TimeoutSec 60

    $data = $resp.Content | ConvertFrom-Json

    if ($data.results) {
        $results += $data.results
    }

    if ([string]::IsNullOrWhiteSpace($data.next)) {
        $nextUrl = $null
    }
    else {
        $nextUrl = $data.next
    }
}

Write-Host ("Total findings returned in this window: {0}" -f $results.Count) -ForegroundColor Cyan

$latestTime   = $null
$latestRecord = $null
$latestField  = $null

foreach ($entry in $results) {
    foreach ($prop in $entry.PSObject.Properties) {
        $value = $prop.Value
        if (-not $value) { continue }

        $text = $value.ToString()
        $tmp  = $null
        if ([DateTime]::TryParse($text, [ref]$tmp)) {
            if (-not $latestTime -or $tmp -gt $latestTime) {
                $latestTime   = $tmp
                $latestRecord = $entry
                $latestField  = $prop.Name
            }
        }
    }
}

if (-not $latestTime) {
    Write-Host "No date-like fields found in results (or no results at all)." -ForegroundColor Yellow
    exit 0
}

Write-Host ("Latest TacitRed event time: {0:u} (field: {1})" -f $latestTime, $latestField) -ForegroundColor Green

# Log latest record for evidence under Project/Docs
$ts     = Get-Date -Format "yyyyMMddHHmmss"
$logDir = "./sentinel-production/Project/Docs/Validation/TacitRed"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$logFile = Join-Path $logDir "tacitred-api-check-$ts.json"
$latestRecord | ConvertTo-Json -Depth 6 | Out-File $logFile -Encoding utf8

Write-Host ("Latest record saved to: {0}" -f $logFile) -ForegroundColor Cyan

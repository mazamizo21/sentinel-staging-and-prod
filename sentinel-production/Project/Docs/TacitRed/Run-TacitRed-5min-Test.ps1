param(
    [int]$WindowMinutes = 5,
    [string]$TypeFilter = 'compromised_credentials'
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path "$PSScriptRoot/../../..").Path
$configPath = Join-Path $root 'client-config-COMPLETE.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$apiKey = $config.parameters.tacitRed.value.apiKey
$baseUrl = $config.parameters.tacitRed.value.apiBaseUrl

$nowUtc = (Get-Date).ToUniversalTime()
$from = $nowUtc.AddMinutes(-$WindowMinutes).ToString('yyyy-MM-ddTHH:mm:ssZ')
$until = $nowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')

$uri = '{0}/findings?from={1}&until={2}&page_size=50' -f $baseUrl, $from, $until
if ($TypeFilter) {
    $uri += "&types[]=$TypeFilter"
}

$headers = @{
    Authorization = $apiKey
    Accept        = 'application/json'
    'User-Agent'  = 'Microsoft-Sentinel-TacitRed/1.0'
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$typeLabel = if ($TypeFilter) { $TypeFilter } else { 'alltypes' }
$log = Join-Path $PSScriptRoot ("TacitRed-API-{0}min-{1}-{2}.log" -f $WindowMinutes, $typeLabel, $ts)

"Request: $uri" | Tee-Object -FilePath $log

$response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 60 2>&1 |
    Tee-Object -FilePath $log -Append

$results = if ($response.results) { $response.results } else { @() }

"ResultCount: {0}" -f $results.Count | Tee-Object -FilePath $log -Append

if ($results.Count -gt 0) {
    # Per-type breakdown
    $typeStats = @()
    foreach ($r in $results) {
        $foundType = $false

        # Preferred source: nested finding.types array
        if ($r.PSObject.Properties['finding'] -and $r.finding -ne $null) {
            $nested = $r.finding
            if ($nested.PSObject.Properties['types'] -and $nested.types) {
                foreach ($t in $nested.types) {
                    $typeValue = [string]$t
                    if ([string]::IsNullOrWhiteSpace($typeValue)) { $typeValue = 'unknown' }
                    $typeStats += [PSCustomObject]@{ Type = $typeValue }
                    $foundType = $true
                }
            }
        }

        # Fallback: top-level findingType/type
        if (-not $foundType) {
            $typeValue = $null
            if ($r.PSObject.Properties['findingType']) { $typeValue = [string]$r.findingType }
            elseif ($r.PSObject.Properties['type'])    { $typeValue = [string]$r.type }

            if ([string]::IsNullOrWhiteSpace($typeValue)) { $typeValue = 'unknown' }

            $typeStats += [PSCustomObject]@{
                Type = $typeValue
            }
        }
    }

    if ($typeStats.Count -gt 0) {
        "TypeBreakdown:" | Tee-Object -FilePath $log -Append
        $grouped = $typeStats | Group-Object Type | Sort-Object Count -Descending
        foreach ($g in $grouped) {
            "  {0}: {1}" -f $g.Name, $g.Count | Tee-Object -FilePath $log -Append
        }
    }

    # Time range summary
    $withTime = @()
    foreach ($r in $results) {
        $t = $null
        if ($r.PSObject.Properties['time'])          { $t = $r.time }
        elseif ($r.PSObject.Properties['lastSeen'])  { $t = $r.lastSeen }
        elseif ($r.PSObject.Properties['last_seen']) { $t = $r.last_seen }

        if ($t) {
            $withTime += [PSCustomObject]@{
                Record        = $r
                EffectiveTime = [string]$t
            }
        }
    }

    if ($withTime.Count -gt 0) {
        $sorted   = $withTime | Sort-Object EffectiveTime
        $earliest = $sorted | Select-Object -First 1
        $latest   = $sorted | Select-Object -Last 1
        "EarliestEffectiveTime: {0}" -f $earliest.EffectiveTime | Tee-Object -FilePath $log -Append
        "LatestEffectiveTime: {0}" -f $latest.EffectiveTime   | Tee-Object -FilePath $log -Append
    }
}

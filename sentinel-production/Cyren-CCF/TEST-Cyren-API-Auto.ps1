# ============================================================================
# Test Cyren API - Automated (Non-Interactive)
# ============================================================================

$ErrorActionPreference = "Stop"

# Tokens from client-config-COMPLETE.json
$CyrenIPJwtToken = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJleHAiOjE5MzAzNDg3OTksImF1ZCI6ImlwX3JlcHV0YXRpb24iLCJzdWIiOiJOSjUxQlU4MDYwNTNZVjBJMEgxQSIsImp0aSI6IjY5MTA3Njg4LWQ4NTQtMTFlZi05NGY5LWJjMjQxMTNkZTQ4ZSIsImlzcyI6ImNsbSJ9.Aw0gyb5l3OQbizawiOCXaJVE8VKOIo5Mm5aRogTr_RgqZ8yklyjzS52NAz3KEh4OTcl1i6qIO3GtaeRhq4x6LUaqwMTiSMUIIm3xU-2b5Y4GeRhsE5tl8Y7fYblaNcPhEOnLfHi8UtX4Aa_VfmPTslZbFoqpTUcaCkOOTBbz7HYEI7YdgziTIbGk-0Jwt47iI_AsaSy-SA13Syuv82rvRM08tOuyNn9hQgyjo0YAmAUbeC5eMCpbkhmujuDwGOhnurVtjvM8fPPsVJJBLJSYNonurwZi-txYVypd3-tQA0nlRJOZuFXKzDjVZEpkG-ivzqyJIbvcCcTXyeADYQOpnQ"

$CyrenMalwareJwtToken = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJleHAiOjE3NzE3MTgzOTksImF1ZCI6Im1hbHdhcmVfdXJscyIsInN1YiI6IjUxWjBGRDQwWTFJN0FBMU9KUDBRIiwianRpIjoiZjFiNGNhMjYtZDg1My0xMWVmLTk0ZjktYmMyNDExM2RlNDhlIiwiaXNzIjoiY2xtIn0.dEh1vGCVAQSChRQsroM5AkC6YyjaG9yzr9lxmj-xWDslgbrTdzeoZPP83nJh05TS6IXHd_CDGlqcdgxQxip9y8kikVKrF12vnTwCMBu_cFG46OHwE8ilCCejBz_L9mr53ksO-bkhqZGrcxsJVxpoSBuaNua3mwUBcH1CoPHyO7XUjgHW4MZShxe0Lb5JHrEil03QElqP_O_GXvcl8CS8l_DUd5y-2J9A4RXrSlSOIe7PQden8w0y8q0wgfYOL0GaAwZvEXl91Rz41Yavm5aC5GKIBUNJzn_OZ5yk5G99FdAkhdT4N87R_j7054l_K-2XBsAAWKsQ89UWgQK7aj-72A"

Write-Host "`n=== Cyren API Data Availability Test ===" -ForegroundColor Cyan
Write-Host "Testing both feeds for current data availability`n" -ForegroundColor Yellow

# Test IP Reputation Feed
Write-Host "--- Testing IP Reputation Feed ---" -ForegroundColor Cyan

$ipHeaders = @{
    "Authorization" = "Bearer $CyrenIPJwtToken"
    "Accept" = "application/json"
    "User-Agent" = "Microsoft-Sentinel-Cyren-Test/1.0"
}

$ipParams = @{
    "feedId" = "ip_reputation"
    "count" = "10"
    "offset" = "0"
    "format" = "json"
}

try {
    Write-Host "Calling Cyren IP Reputation API..." -ForegroundColor Gray
    $ipResponse = Invoke-RestMethod -Uri "https://api-feeds.cyren.com/v1/feed/data" `
        -Method Get `
        -Headers $ipHeaders `
        -Body $ipParams `
        -ErrorAction Stop
    
    Write-Host "✅ IP Reputation API Response:" -ForegroundColor Green
    
    if ($ipResponse -is [array]) {
        $count = $ipResponse.Count
        Write-Host "  Records returned: $count" -ForegroundColor White
        
        if ($count -gt 0) {
            Write-Host "`n  First record:" -ForegroundColor Yellow
            $ipResponse[0] | ConvertTo-Json -Depth 3 | Write-Host
            
            # Check for timestamps
            $firstRecord = $ipResponse[0]
            $timestampFields = @('lastSeen', 'detection_ts', 'timestamp', 'updated', 'created')
            
            foreach ($field in $timestampFields) {
                if ($firstRecord.PSObject.Properties.Name -contains $field) {
                    $value = $firstRecord.$field
                    Write-Host "`n  ⏰ $field : $value" -ForegroundColor Cyan
                    
                    # Try to parse and show age
                    try {
                        $dt = [DateTime]::Parse($value)
                        $age = (Get-Date) - $dt
                        Write-Host "     Age: $($age.Days) days, $($age.Hours) hours ago" -ForegroundColor Yellow
                    } catch {
                        # Not a parseable date
                    }
                }
            }
        }
    } else {
        Write-Host "  Response (not array):" -ForegroundColor White
        $ipResponse | ConvertTo-Json -Depth 3 | Write-Host
    }
    
    # Save to file
    $ipResponse | ConvertTo-Json -Depth 10 | Out-File "cyren-ip-sample.json" -Encoding UTF8
    Write-Host "`n  💾 Full response saved to: cyren-ip-sample.json" -ForegroundColor Green
    
} catch {
    Write-Host "❌ IP Reputation API Error:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "  Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}

# Test Malware URLs Feed
Write-Host "`n--- Testing Malware URLs Feed ---" -ForegroundColor Cyan

$malwareHeaders = @{
    "Authorization" = "Bearer $CyrenMalwareJwtToken"
    "Accept" = "application/json"
    "User-Agent" = "Microsoft-Sentinel-Cyren-Test/1.0"
}

$malwareParams = @{
    "feedId" = "malware_urls"
    "count" = "10"
    "offset" = "0"
    "format" = "json"
}

try {
    Write-Host "Calling Cyren Malware URLs API..." -ForegroundColor Gray
    $malwareResponse = Invoke-RestMethod -Uri "https://api-feeds.cyren.com/v1/feed/data" `
        -Method Get `
        -Headers $malwareHeaders `
        -Body $malwareParams `
        -ErrorAction Stop
    
    Write-Host "✅ Malware URLs API Response:" -ForegroundColor Green
    
    if ($malwareResponse -is [array]) {
        $count = $malwareResponse.Count
        Write-Host "  Records returned: $count" -ForegroundColor White
        
        if ($count -gt 0) {
            Write-Host "`n  First record:" -ForegroundColor Yellow
            $malwareResponse[0] | ConvertTo-Json -Depth 3 | Write-Host
            
            # Check for timestamps
            $firstRecord = $malwareResponse[0]
            $timestampFields = @('lastSeen', 'detection_ts', 'timestamp', 'updated', 'created')
            
            foreach ($field in $timestampFields) {
                if ($firstRecord.PSObject.Properties.Name -contains $field) {
                    $value = $firstRecord.$field
                    Write-Host "`n  ⏰ $field : $value" -ForegroundColor Cyan
                    
                    # Try to parse and show age
                    try {
                        $dt = [DateTime]::Parse($value)
                        $age = (Get-Date) - $dt
                        Write-Host "     Age: $($age.Days) days, $($age.Hours) hours ago" -ForegroundColor Yellow
                    } catch {
                        # Not a parseable date
                    }
                }
            }
        }
    } else {
        Write-Host "  Response (not array):" -ForegroundColor White
        $malwareResponse | ConvertTo-Json -Depth 3 | Write-Host
    }
    
    # Save to file
    $malwareResponse | ConvertTo-Json -Depth 10 | Out-File "cyren-malware-sample.json" -Encoding UTF8
    Write-Host "`n  💾 Full response saved to: cyren-malware-sample.json" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Malware URLs API Error:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "  Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Check the timestamps above to determine if Cyren has current data." -ForegroundColor Yellow
Write-Host "If timestamps are recent (last few days/weeks) → Cyren is healthy" -ForegroundColor White
Write-Host "If timestamps are old (like TacitRed Oct 26) → Same issue exists`n" -ForegroundColor White

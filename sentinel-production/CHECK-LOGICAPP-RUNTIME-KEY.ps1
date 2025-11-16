# CHECK-LOGICAPP-RUNTIME-KEY.ps1
# Check what API key the Logic App ACTUALLY used in its last successful run

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   LOGIC APP RUNTIME API KEY CHECK" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName

az account set --subscription $sub | Out-Null

$laName = "logic-tacitred-ingestion"

# Get latest successful run
Write-Host "Getting latest successful run..." -ForegroundColor Yellow
$runsUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/runs?api-version=2019-05-01&`$top=1&`$filter=status eq 'Succeeded'"

$runs = az rest --method GET --uri $runsUri 2>$null | ConvertFrom-Json

if(-not $runs.value -or $runs.value.Count -eq 0){
    Write-Host "✗ No successful runs found" -ForegroundColor Red
    exit 1
}

$latestRun = $runs.value[0]
$runName = $latestRun.name
$runTime = [DateTime]::Parse($latestRun.properties.startTime).ToString('yyyy-MM-dd HH:mm:ss')

Write-Host "✓ Latest successful run: $runName" -ForegroundColor Green
Write-Host "  Time: $runTime`n" -ForegroundColor Gray

# Get the Call_TacitRed_API action details
Write-Host "Getting 'Call_TacitRed_API' action details..." -ForegroundColor Yellow
$actionUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/runs/$runName/actions/Call_TacitRed_API?api-version=2019-05-01"

$action = az rest --method GET --uri $actionUri 2>$null | ConvertFrom-Json

if(-not $action){
    Write-Host "✗ Could not get action details" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Action details retrieved`n" -ForegroundColor Green

# Check inputs (what was sent)
Write-Host "═══ ACTION INPUTS (What was sent) ═══" -ForegroundColor Cyan

if($action.properties.inputs){
    Write-Host "Method: $($action.properties.inputs.method)" -ForegroundColor Gray
    Write-Host "URI: $($action.properties.inputs.uri)" -ForegroundColor Gray
    
    if($action.properties.inputs.headers){
        Write-Host "`nHeaders sent:" -ForegroundColor Yellow
        $action.properties.inputs.headers.PSObject.Properties | ForEach-Object {
            $headerName = $_.Name
            $headerValue = $_.Value
            
            if($headerName -eq "Authorization"){
                # Extract the API key from Bearer token
                if($headerValue -match "Bearer (.+)"){
                    $apiKey = $matches[1]
                    Write-Host "  Authorization: Bearer $($apiKey.Substring(0,8))...$($apiKey.Substring($apiKey.Length-8))" -ForegroundColor Cyan
                    
                    # This is the ACTUAL key the Logic App used!
                    Write-Host "`n🔑 ACTUAL API KEY USED BY LOGIC APP:" -ForegroundColor Green
                    Write-Host "   $apiKey" -ForegroundColor Yellow
                    
                    # Test this key
                    Write-Host "`n═══ TESTING THIS KEY ═══" -ForegroundColor Cyan
                    $testUrl = "https://app.tacitred.com/api/v1/findings?from=2025-11-14T00:00:00Z&until=2025-11-14T23:59:59Z&page_size=1"
                    $headers = @{
                        'Authorization' = "Bearer $apiKey"
                        'Accept' = 'application/json'
                    }
                    
                    try {
                        $response = Invoke-RestMethod -Uri $testUrl -Method Get -Headers $headers -TimeoutSec 10
                        Write-Host "✅ SUCCESS! HTTP 200" -ForegroundColor Green
                        Write-Host "   Results: $($response.results.Count)" -ForegroundColor Gray
                        
                        # Compare with config file
                        $configKey = $config.parameters.tacitRed.value.apiKey
                        Write-Host "`n═══ KEY COMPARISON ═══" -ForegroundColor Cyan
                        Write-Host "Config File: $($configKey.Substring(0,8))...$($configKey.Substring($configKey.Length-8))" -ForegroundColor Gray
                        Write-Host "Logic App:   $($apiKey.Substring(0,8))...$($apiKey.Substring($apiKey.Length-8))" -ForegroundColor Gray
                        
                        if($apiKey -eq $configKey){
                            Write-Host "✓ SAME KEY" -ForegroundColor Green
                        }else{
                            Write-Host "✗ DIFFERENT KEYS!" -ForegroundColor Red
                            Write-Host "`n💡 FINDING: Logic App is using a DIFFERENT API key than config file!" -ForegroundColor Yellow
                            Write-Host "   This explains why Logic App works but direct tests fail." -ForegroundColor Yellow
                        }
                        
                    } catch {
                        $code = $_.Exception.Response.StatusCode.value__
                        Write-Host "✗ FAILED! HTTP $code" -ForegroundColor Red
                    }
                }else{
                    Write-Host "  Authorization: $headerValue" -ForegroundColor Gray
                }
            }else{
                Write-Host "  $headerName : $headerValue" -ForegroundColor Gray
            }
        }
    }
}

# Check outputs (what was received)
Write-Host "`n═══ ACTION OUTPUTS (What was received) ═══" -ForegroundColor Cyan

if($action.properties.outputs){
    Write-Host "Status Code: $($action.properties.outputs.statusCode)" -ForegroundColor $(if($action.properties.outputs.statusCode -eq 200){'Green'}else{'Red'})
    
    if($action.properties.outputs.body){
        $body = $action.properties.outputs.body
        if($body.results){
            Write-Host "Results Count: $($body.results.Count)" -ForegroundColor Gray
            
            if($body.results.Count -gt 0){
                Write-Host "`nSample result:" -ForegroundColor Cyan
                $sample = $body.results[0]
                Write-Host "  Email: $($sample.email)" -ForegroundColor Gray
                Write-Host "  Type: $($sample.findingType)" -ForegroundColor Gray
                Write-Host "  Confidence: $($sample.confidence)" -ForegroundColor Gray
            }
        }
    }
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

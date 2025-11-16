# RECREATE-CCF-CONNECTOR.ps1
# Delete and recreate TacitRed CCF connector for clean state

$ErrorActionPreference = 'Stop'

$sub = "774bee0e-b281-4f70-8e40-199e35b65117"
$rg  = "TacitRedCCFTest"
$ws  = "TacitRedCCFWorkspace"

Write-Host "`n════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  DELETE & RECREATE CCF CONNECTOR (CLEAN STATE)" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan

az account set --subscription $sub | Out-Null

# Load API key
$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$apiKey = $config.parameters.tacitRed.value.apiKey

# Get workspace ID
$wsId = az monitor log-analytics workspace show `
    --resource-group $rg `
    --workspace-name $ws `
    --query id -o tsv

$connectorUri = "https://management.azure.com$wsId/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"

# ═══════════════════════════════════════════════════════
# STEP 1: DELETE EXISTING CONNECTOR
# ═══════════════════════════════════════════════════════

Write-Host "`n[1/4] Checking if connector exists..." -ForegroundColor Yellow

$existing = az rest --method GET --uri $connectorUri 2>$null | ConvertFrom-Json

if($existing){
    Write-Host "✓ Found connector: $($existing.name)" -ForegroundColor Gray
    Write-Host "  Current polling: $($existing.properties.request.queryWindowInMin) minutes" -ForegroundColor Gray
    
    Write-Host "`n[2/4] Deleting connector..." -ForegroundColor Yellow
    
    az rest --method DELETE --uri $connectorUri --output none 2>$null
    
    if($LASTEXITCODE -eq 0){
        Write-Host "✓ Connector deleted" -ForegroundColor Green
    } else {
        Write-Host "⚠ Deletion may have failed (continuing anyway)" -ForegroundColor Yellow
    }
    
    Write-Host "`n[3/4] Waiting for deletion to propagate (15 seconds)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    
} else {
    Write-Host "⚠ Connector not found (may already be deleted)" -ForegroundColor Yellow
    Write-Host "`n[2/4] Skipping deletion..." -ForegroundColor Gray
    Write-Host "`n[3/4] Skipping wait..." -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════
# STEP 4: RECREATE CONNECTOR WITH CORRECT CONFIG
# ═══════════════════════════════════════════════════════

Write-Host "`n[4/4] Recreating connector with clean config..." -ForegroundColor Yellow

# Get DCE and DCR details
$dce = az monitor data-collection endpoint list --resource-group $rg | ConvertFrom-Json | Where-Object { $_.name -like "*tacitred*" } | Select-Object -First 1
$dcr = az monitor data-collection rule list --resource-group $rg | ConvertFrom-Json | Where-Object { $_.name -like "*tacitred*" } | Select-Object -First 1

$dceEndpoint = $dce.properties.logsIngestion.endpoint
$dcrImmutableId = $dcr.properties.immutableId

Write-Host "  DCE Endpoint: $dceEndpoint" -ForegroundColor Gray
Write-Host "  DCR Immutable ID: $dcrImmutableId" -ForegroundColor Gray

# Build connector body
$connectorBody = @{
    kind = "RestApiPoller"
    properties = @{
        connectorDefinitionName = "TacitRedThreatIntel"
        dataType = "TacitRed_Findings_CL"
        isActive = $true
        dcrConfig = @{
            streamName = "Custom-TacitRed_Findings_CL"
            dataCollectionEndpoint = $dceEndpoint
            dataCollectionRuleImmutableId = $dcrImmutableId
        }
        auth = @{
            type = "APIKey"
            ApiKeyName = "Authorization"
            ApiKeyIdentifier = ""  # No Bearer prefix
            ApiKey = $apiKey
        }
        request = @{
            apiEndpoint = "https://app.tacitred.com/api/v1/findings"
            httpMethod = "GET"
            queryParameters = @{
                page_size = 100
            }
            queryWindowInMin = 5  # 5 minutes for testing
            queryTimeFormat = "yyyy-MM-ddTHH:mm:ssZ"
            startTimeAttributeName = "from"
            endTimeAttributeName = "until"
            rateLimitQps = 10
            retryCount = 3
            timeoutInSeconds = 60
            headers = @{
                Accept = "application/json"
                "User-Agent" = "Microsoft-Sentinel-TacitRed/1.0"
            }
        }
        paging = @{
            pagingType = "LinkHeader"
            linkHeaderRelLinkName = "next"
            pageSize = 100
        }
        response = @{
            eventsJsonPaths = @("$.results")
            format = "json"
            shouldJoinNestedData = $false
        }
    }
}

$tempFile = "$env:TEMP\ccf-recreate-$(Get-Date -Format 'HHmmss').json"
$connectorBody | ConvertTo-Json -Depth 30 | Out-File -FilePath $tempFile -Encoding UTF8 -Force

Write-Host "`nSending PUT to create connector..." -ForegroundColor Yellow

try {
    $result = az rest --method PUT `
        --uri $connectorUri `
        --headers "Content-Type=application/json" `
        --body "@$tempFile" 2>&1
    
    if($LASTEXITCODE -eq 0){
        Write-Host "✓ Connector created successfully" -ForegroundColor Green
        
        Start-Sleep -Seconds 5
        
        # Verify
        Write-Host "`nVerifying new connector..." -ForegroundColor Yellow
        $newConn = az rest --method GET --uri $connectorUri 2>$null | ConvertFrom-Json
        
        if($newConn){
            Write-Host "`n📊 NEW CONNECTOR STATUS:" -ForegroundColor Cyan
            Write-Host "  Name: $($newConn.name)" -ForegroundColor Gray
            Write-Host "  Active: $($newConn.properties.isActive)" -ForegroundColor $(if($newConn.properties.isActive){'Green'}else{'Red'})
            Write-Host "  Polling: $($newConn.properties.request.queryWindowInMin) minutes" -ForegroundColor $(if($newConn.properties.request.queryWindowInMin -eq 5){'Green'}else{'Yellow'})
            Write-Host "  Auth Header: $($newConn.properties.auth.ApiKeyName)" -ForegroundColor Gray
            Write-Host "  Auth Prefix: '$($newConn.properties.auth.ApiKeyIdentifier)'" -ForegroundColor Gray
            
            $nextPoll = (Get-Date).AddMinutes(5).ToString("HH:mm")
            Write-Host "`n🎉 SUCCESS! Connector recreated with clean state" -ForegroundColor Green
            Write-Host "⏱️  First poll expected by: $nextPoll" -ForegroundColor Cyan
            Write-Host "`nCheck for data around $nextPoll with:" -ForegroundColor White
            Write-Host "  TacitRed_Findings_CL | order by TimeGenerated desc | take 10`n" -ForegroundColor Cyan
        } else {
            Write-Host "⚠ Could not verify connector (but creation succeeded)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✗ Creation failed:" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
    }
    
} catch {
    Write-Host "✗ Error during creation:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
} finally {
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
}

Write-Host "`n════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

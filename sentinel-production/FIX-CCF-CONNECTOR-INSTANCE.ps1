# FIX-CCF-CONNECTOR-INSTANCE.ps1
# Create CCF connector instance after definition has propagated

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   CREATE CCF CONNECTOR INSTANCE" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$ResourceGroup = "TacitRedCCFTest"
$WorkspaceName = "TacitRedCCFWorkspace"
$ApiKey = "a2be534e-6231-4fb0-b8b8-15dbc96e83b7"
$PollingIntervalMin = 5

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId

az account set --subscription $sub | Out-Null

# Load deployment info
$deployInfo = Get-Content ".\Project\Docs\fresh-ccf-deployment.json" -Raw | ConvertFrom-Json

$dceEndpoint = $deployInfo.dceEndpoint
$dcrImmutableId = $deployInfo.dcrImmutableId

Write-Host "Using deployment info:" -ForegroundColor Yellow
Write-Host "  DCE Endpoint: $dceEndpoint" -ForegroundColor Gray
Write-Host "  DCR Immutable ID: $dcrImmutableId" -ForegroundColor Gray
Write-Host "  API Key: $($ApiKey.Substring(0,8))... (KNOWN WORKING)`n" -ForegroundColor Green

# Get workspace ID
$wsId = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query id -o tsv

# Check if connector definition exists
Write-Host "Checking connector definition..." -ForegroundColor Yellow
$connDefUri = "https://management.azure.com$wsId/providers/Microsoft.SecurityInsights/dataConnectorDefinitions/TacitRedThreatIntel?api-version=2024-09-01"

try {
    $connDef = az rest --method GET --uri $connDefUri 2>$null | ConvertFrom-Json
    
    if($connDef){
        Write-Host "✓ Connector definition exists" -ForegroundColor Green
    }else{
        Write-Host "✗ Connector definition NOT FOUND!" -ForegroundColor Red
        Write-Host "  Wait a few more minutes for propagation" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "✗ Error checking definition: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create connector instance
Write-Host "`nCreating CCF connector instance..." -ForegroundColor Yellow

$connInstUri = "https://management.azure.com$wsId/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview"

$connInstBody = @{
    kind = "RestApiPoller"
    properties = @{
        connectorDefinitionName = "TacitRedThreatIntel"
        dataType = "TacitRed_Findings_CL"
        dcrConfig = @{
            streamName = "Custom-TacitRed_Findings_Raw"
            dataCollectionEndpoint = $dceEndpoint
            dataCollectionRuleImmutableId = $dcrImmutableId
        }
        auth = @{
            type = "APIKey"
            ApiKeyName = "Authorization"
            ApiKey = $ApiKey
        }
        request = @{
            apiEndpoint = "https://app.tacitred.com/api/v1/findings"
            httpMethod = "GET"
            queryParameters = @{
                page_size = 100
            }
            queryWindowInMin = $PollingIntervalMin
            queryTimeFormat = "yyyy-MM-ddTHH:mm:ssZ"
            startTimeAttributeName = "from"
            endTimeAttributeName = "until"
            rateLimitQps = 10
            retryCount = 3
            timeoutInSeconds = 60
            headers = @{
                Accept = "application/json"
                "User-Agent" = "Microsoft-Sentinel-TacitRed-CCF-Test/1.0"
            }
        }
        paging = @{
            pagingType = "LinkHeader"
            linkHeaderRelLinkName = "rel=next"
            pageSize = 0
        }
        response = @{
            eventsJsonPaths = @("$.results")
            format = "json"
        }
        shouldJoinNestedData = $false
    }
}

$connInstFile = "$env:TEMP\conn-inst-fix.json"
$connInstBody | ConvertTo-Json -Depth 10 | Out-File -FilePath $connInstFile -Encoding UTF8 -Force

try {
    $result = az rest --method PUT --uri $connInstUri --headers "Content-Type=application/json" --body "@$connInstFile" 2>&1
    Remove-Item $connInstFile -Force -ErrorAction SilentlyContinue
    
    if($LASTEXITCODE -eq 0){
        Write-Host "✅ CCF connector instance created!" -ForegroundColor Green
        
        # Verify
        Write-Host "`nWaiting 5 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        
        $connector = az rest --method GET --uri $connInstUri 2>$null | ConvertFrom-Json
        
        if($connector){
            Write-Host "`n✅ VERIFICATION SUCCESSFUL!" -ForegroundColor Green
            Write-Host "`n📊 CONNECTOR STATUS:" -ForegroundColor Cyan
            Write-Host "  Name: $($connector.name)" -ForegroundColor Gray
            Write-Host "  Kind: $($connector.kind)" -ForegroundColor Gray
            Write-Host "  Is Active: $($connector.properties.isActive)" -ForegroundColor $(if($connector.properties.isActive){'Green'}else{'Red'})
            Write-Host "  Polling Interval: $($connector.properties.request.queryWindowInMin) minutes" -ForegroundColor Gray
            Write-Host "  API Endpoint: $($connector.properties.request.apiEndpoint)" -ForegroundColor Gray
            
            if($connector.properties.auth.ApiKey){
                Write-Host "  API Key: ✅ SET" -ForegroundColor Green
            }else{
                Write-Host "  API Key: ⚠ Shows as null (Azure masking)" -ForegroundColor Yellow
            }
            
            Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Yellow
            Write-Host "  1. CCF will poll within 5 minutes" -ForegroundColor White
            Write-Host "  2. Wait 10 minutes total" -ForegroundColor White
            Write-Host "  3. Run: .\VERIFY-FRESH-CCF.ps1" -ForegroundColor White
            
            $nextPoll = (Get-Date).AddMinutes(5).ToString("HH:mm")
            Write-Host "`n⏱️  First poll expected by: $nextPoll" -ForegroundColor Cyan
            
        }else{
            Write-Host "⚠ Could not verify connector" -ForegroundColor Yellow
        }
        
    }else{
        Write-Host "✗ Failed to create connector instance" -ForegroundColor Red
        Write-Host "  Error: $result" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $connInstFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

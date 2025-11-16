# UPDATE-CCF-TO-5MIN.ps1
# Force update TacitRed CCF connector to 5-minute polling

$ErrorActionPreference = 'Stop'

$sub = "774bee0e-b281-4f70-8e40-199e35b65117"
$rg  = "TacitRedCCFTest"
$ws  = "TacitRedCCFWorkspace"

Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  UPDATE CCF TO 5-MINUTE POLLING" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan

az account set --subscription $sub | Out-Null

# Load API key from config
$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$apiKey = $config.parameters.tacitRed.value.apiKey

# Get workspace ID
$wsId = az monitor log-analytics workspace show `
    --resource-group $rg `
    --workspace-name $ws `
    --query id -o tsv

$connectorId = "$wsId/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings"
$apiVersion = "2023-02-01-preview"  # Try older API version that might support PATCH
$connUri = "https://management.azure.com$connectorId?api-version=$apiVersion"

Write-Host "`nGetting current connector..." -ForegroundColor Yellow
$conn = az rest --method GET --uri $connUri 2>$null | ConvertFrom-Json

if(-not $conn){
    Write-Host "✗ Connector not found" -ForegroundColor Red
    exit 1
}

Write-Host "Current polling: $($conn.properties.request.queryWindowInMin) minutes" -ForegroundColor Gray

# Build complete connector body with all required fields
$updateBody = @{
    kind = "RestApiPoller"
    properties = @{
        connectorDefinitionName = $conn.properties.connectorDefinitionName
        dataType = $conn.properties.dataType
        dcrConfig = $conn.properties.dcrConfig
        isActive = $true
        auth = @{
            type = "APIKey"
            ApiKeyName = "Authorization"
            ApiKeyIdentifier = ""
            ApiKey = $apiKey
        }
        request = @{
            apiEndpoint = $conn.properties.request.apiEndpoint
            httpMethod = $conn.properties.request.httpMethod
            queryParameters = $conn.properties.request.queryParameters
            queryWindowInMin = 5  # ← THE KEY CHANGE
            queryTimeFormat = $conn.properties.request.queryTimeFormat
            startTimeAttributeName = $conn.properties.request.startTimeAttributeName
            endTimeAttributeName = $conn.properties.request.endTimeAttributeName
            rateLimitQps = $conn.properties.request.rateLimitQps
            retryCount = $conn.properties.request.retryCount
            timeoutInSeconds = $conn.properties.request.timeoutInSeconds
            headers = $conn.properties.request.headers
        }
        paging = $conn.properties.paging
        response = $conn.properties.response
    }
}

$tempFile = "$env:TEMP\ccf-update-$(Get-Date -Format 'HHmmss').json"
$updateBody | ConvertTo-Json -Depth 30 | Out-File -FilePath $tempFile -Encoding UTF8 -Force

Write-Host "Sending PUT with 5-minute polling + API key..." -ForegroundColor Yellow

try {
    az rest --method PUT `
        --uri $connUri `
        --headers "Content-Type=application/json" `
        --body "@$tempFile" `
        --output none
    
    Write-Host "✓ Update sent" -ForegroundColor Green
    
    Start-Sleep -Seconds 5
    
    # Verify
    Write-Host "`nVerifying update..." -ForegroundColor Yellow
    $updated = az rest --method GET --uri $connUri 2>$null | ConvertFrom-Json
    
    $polling = $updated.properties.request.queryWindowInMin
    
    Write-Host "`n📊 RESULT:" -ForegroundColor Cyan
    Write-Host "  Polling Interval: $polling minutes" -ForegroundColor $(if($polling -eq 5){'Green'}else{'Yellow'})
    Write-Host "  Active: $($updated.properties.isActive)" -ForegroundColor Gray
    
    if($polling -eq 5){
        $nextPoll = (Get-Date).AddMinutes(5).ToString("HH:mm")
        Write-Host "`n🎉 SUCCESS! Next poll by: $nextPoll" -ForegroundColor Green
        Write-Host "Run this KQL in 5-10 minutes:" -ForegroundColor White
        Write-Host "  TacitRed_Findings_CL | order by TimeGenerated desc | take 10`n" -ForegroundColor Cyan
    } else {
        Write-Host "`n⚠️ Polling still at $polling minutes" -ForegroundColor Yellow
        Write-Host "The update may take effect on next poll cycle." -ForegroundColor Gray
    }
    
} catch {
    Write-Host "✗ Update failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
} finally {
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
}

Write-Host "`n════════════════════════════════════════`n" -ForegroundColor Cyan

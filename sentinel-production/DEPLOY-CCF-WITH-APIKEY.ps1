# DEPLOY-CCF-WITH-APIKEY.ps1
# Redeploy CCF connector with API key properly set via ARM template

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   REDEPLOY CCF CONNECTOR WITH API KEY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$ws = $config.parameters.azure.value.workspaceName
$apiKey = $config.parameters.tacitRed.value.apiKey

az account set --subscription $sub | Out-Null

Write-Host "Deployment Details:" -ForegroundColor Yellow
Write-Host "  Resource Group: $rg" -ForegroundColor Gray
Write-Host "  Workspace: $ws" -ForegroundColor Gray
Write-Host "  API Key: $($apiKey.Substring(0,8))..." -ForegroundColor Gray
Write-Host "  Polling Interval: 5 minutes (for testing)`n" -ForegroundColor Gray

# Get DCE and DCR info
Write-Host "Getting DCE and DCR information..." -ForegroundColor Yellow

$dceList = az monitor data-collection endpoint list --resource-group $rg 2>$null | ConvertFrom-Json
$dce = $dceList | Where-Object {$_.name -like "*sentinel*" -or $_.name -like "*threat*"} | Select-Object -First 1

if(-not $dce){
    Write-Host "✗ Could not find DCE" -ForegroundColor Red
    exit 1
}

$dceEndpoint = $dce.properties.logsIngestion.endpoint
Write-Host "✓ DCE: $dceEndpoint" -ForegroundColor Green

$dcrList = az monitor data-collection rule list --resource-group $rg 2>$null | ConvertFrom-Json
$dcr = $dcrList | Where-Object {$_.name -like "*tacitred*"} | Select-Object -First 1

if(-not $dcr){
    Write-Host "✗ Could not find TacitRed DCR" -ForegroundColor Red
    exit 1
}

$dcrImmutableId = $dcr.immutableId
Write-Host "✓ DCR: $dcrImmutableId`n" -ForegroundColor Green

# Deploy ARM template
Write-Host "Deploying CCF connector via ARM template..." -ForegroundColor Yellow
Write-Host "This will REPLACE the existing connector with API key properly set`n" -ForegroundColor Gray

$templateFile = ".\REDEPLOY-CCF-CONNECTOR-ONLY.json"
$deploymentName = "ccf-connector-redeploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

try {
    az deployment group create `
        --resource-group $rg `
        --name $deploymentName `
        --template-file $templateFile `
        --parameters workspace=$ws `
        --parameters tacitRedApiKey=$apiKey `
        --parameters dceEndpoint=$dceEndpoint `
        --parameters dcrImmutableId=$dcrImmutableId `
        --parameters queryWindowInMin=5 `
        --output table
    
    if($LASTEXITCODE -eq 0){
        Write-Host "`n✅ DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
        
        # Wait and verify
        Write-Host "`nVerifying deployment (waiting 10 seconds)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        
        $uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"
        $connector = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json
        
        Write-Host "`nVerification:" -ForegroundColor Cyan
        Write-Host "  Polling Interval: $($connector.properties.request.queryWindowInMin) minutes" -ForegroundColor Green
        Write-Host "  Is Active: $($connector.properties.isActive)" -ForegroundColor $(if($connector.properties.isActive){'Green'}else{'Red'})
        
        if($connector.properties.auth.ApiKey){
            Write-Host "  API Key: ✅ SET (ARM deployment succeeded)" -ForegroundColor Green
            
            Write-Host "`n🎉 SUCCESS!" -ForegroundColor Green
            Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Cyan
            Write-Host "  1. CCF will poll within next 5 minutes" -ForegroundColor White
            Write-Host "  2. Wait 5-10 minutes total" -ForegroundColor White
            Write-Host "  3. Check for data:" -ForegroundColor White
            Write-Host "     .\VERIFY-TACITRED-DATA.ps1" -ForegroundColor Gray
            Write-Host "`n  4. Look for data with TimeGenerated around: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor White
            
        }else{
            Write-Host "  API Key: ⚠ Still appears null (may be Azure masking)" -ForegroundColor Yellow
            Write-Host "`n  Monitor for CCF polling anyway - API key was set during deployment" -ForegroundColor Yellow
        }
        
    }else{
        Write-Host "`n✗ Deployment failed" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "`n✗ Deployment error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

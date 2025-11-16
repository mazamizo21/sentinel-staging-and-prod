# ============================================================================
# Simple Cyren Deployment
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "`n=== Cyren Deployment ===" -ForegroundColor Cyan

# Configuration
$subscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117"
$resourceGroupName = "SentinelTestStixImport"
$workspaceName = "SentinelThreatIntelWorkspace"
$location = "eastus"

# Set subscription
az account set --subscription $subscriptionId

# Create parameters file
$params = @{
    '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
    contentVersion = "1.0.0.0"
    parameters = @{
        workspace = @{ value = $workspaceName }
        "workspace-location" = @{ value = $location }
        cyrenIPJwtToken = @{ value = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJleHAiOjE5MzAzNDg3OTksImF1ZCI6ImlwX3JlcHV0YXRpb24iLCJzdWIiOiJOSjUxQlU4MDYwNTNZVjBJMEgxQSIsImp0aSI6IjY5MTA3Njg4LWQ4NTQtMTFlZi05NGY5LWJjMjQxMTNkZTQ4ZSIsImlzcyI6ImNsbSJ9.Aw0gyb5l3OQbizawiOCXaJVE8VKOIo5Mm5aRogTr_RgqZ8yklyjzS52NAz3KEh4OTcl1i6qIO3GtaeRhq4x6LUaqwMTiSMUIIm3xU-2b5Y4GeRhsE5tl8Y7fYblaNcPhEOnLfHi8UtX4Aa_VfmPTslZbFoqpTUcaCkOOTBbz7HYEI7YdgziTIbGk-0Jwt47iI_AsaSy-SA13Syuv82rvRM08tOuyNn9hQgyjo0YAmAUbeC5eMCpbkhmujuDwGOhnurVtjvM8fPPsVJJBLJSYNonurwZi-txYVypd3-tQA0nlRJOZuFXKzDjVZEpkG-ivzqyJIbvcCcTXyeADYQOpnQ" }
        cyrenMalwareJwtToken = @{ value = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJleHAiOjE3NzE3MTgzOTksImF1ZCI6Im1hbHdhcmVfdXJscyIsInN1YiI6IjUxWjBGRDQwWTFJN0FBMU9KUDBRIiwianRpIjoiZjFiNGNhMjYtZDg1My0xMWVmLTk0ZjktYmMyNDExM2RlNDhlIiwiaXNzIjoiY2xtIn0.dEh1vGCVAQSChRQsroM5AkC6YyjaG9yzr9lxmj-xWDslgbrTdzeoZPP83nJh05TS6IXHd_CDGlqcdgxQxip9y8kikVKrF12vnTwCMBu_cFG46OHwE8ilCCejBz_L9mr53ksO-bkhqZGrcxsJVxpoSBuaNua3mwUBcH1CoPHyO7XUjgHW4MZShxe0Lb5JHrEil03QElqP_O_GXvcl8CS8l_DUd5y-2J9A4RXrSlSOIe7PQden8w0y8q0wgfYOL0GaAwZvEXl91Rz41Yavm5aC5GKIBUNJzn_OZ5yk5G99FdAkhdT4N87R_j7054l_K-2XBsAAWKsQ89UWgQK7aj-72A" }
        deployConnectors = @{ value = $false }
        deployWorkbooks = @{ value = $true }
        enableKeyVault = @{ value = $false }
        cyrenIPDcrImmutableId = @{ value = "" }
        cyrenMalwareDcrImmutableId = @{ value = "" }
    }
}

$paramsJson = $params | ConvertTo-Json -Depth 10
$paramsJson | Out-File "cyren-params-temp.json" -Encoding UTF8

Write-Host "Deploying Cyren infrastructure..." -ForegroundColor Cyan
az deployment group create `
    --resource-group $resourceGroupName `
    --template-file ".\Cyren-CCF\mainTemplate.json" `
    --parameters "@cyren-params-temp.json" `
    --name "cyren-deploy-$(Get-Date -Format 'yyyyMMddHHmmss')"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Deployment successful!" -ForegroundColor Green
    
    Write-Host "`nReading DCR ImmutableIds..." -ForegroundColor Cyan
    
    $ipDcrId = az monitor data-collection rule show `
        --resource-group $resourceGroupName `
        --name "dcr-cyren-ip-reputation" `
        --query immutableId `
        --output tsv
    
    $malwareDcrId = az monitor data-collection rule show `
        --resource-group $resourceGroupName `
        --name "dcr-cyren-malware-urls" `
        --query immutableId `
        --output tsv
    
    Write-Host "  IP DCR: $ipDcrId" -ForegroundColor White
    Write-Host "  Malware DCR: $malwareDcrId" -ForegroundColor White
    
    Write-Host "`nVerifying table creation..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10
    
    Write-Host "`nNext: Run FIX-Cyren-DcrImmutableId.ps1 to wire up connectors" -ForegroundColor Yellow
} else {
    Write-Host "`n❌ Deployment failed" -ForegroundColor Red
}

Remove-Item "cyren-params-temp.json" -ErrorAction SilentlyContinue

Read-Host "`nPress Enter to exit"

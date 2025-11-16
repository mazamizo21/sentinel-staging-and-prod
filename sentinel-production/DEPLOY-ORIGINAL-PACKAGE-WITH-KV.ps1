# DEPLOY-ORIGINAL-PACKAGE-WITH-KV.ps1
# Deploy the complete original TacitRed CCF package with Key Vault enabled

param(
    [string]$ResourceGroup = "TacitRedCCFTest",
    [string]$WorkspaceName = "TacitRedCCFWorkspace"
)

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   DEPLOY ORIGINAL TACITRED PACKAGE (WITH KEY VAULT)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$apiKey = $config.parameters.tacitRed.value.apiKey

az account set --subscription $sub | Out-Null

Write-Host "`n📋 DEPLOYMENT PLAN:" -ForegroundColor Yellow
Write-Host "  Using: ORIGINAL TacitRed-CCF package" -ForegroundColor White
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host "  Workspace: $WorkspaceName" -ForegroundColor Gray
Write-Host "  API Key: $($apiKey.Substring(0,8))... (KNOWN WORKING)" -ForegroundColor Green
Write-Host "  Key Vault: ENABLED" -ForegroundColor Cyan
Write-Host "  Analytics Rules: YES" -ForegroundColor Gray
Write-Host "  Workbooks: YES" -ForegroundColor Gray
Write-Host "  Connectors: YES`n" -ForegroundColor Gray

# Get workspace location
$wsLocation = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query location -o tsv

Write-Host "Deploying complete package..." -ForegroundColor Yellow
Write-Host "This will deploy:" -ForegroundColor White
Write-Host "  - DCE + DCR + Custom Table" -ForegroundColor DarkGray
Write-Host "  - Key Vault (stores API key)" -ForegroundColor DarkCyan
Write-Host "  - UAMI + RBAC" -ForegroundColor DarkGray
Write-Host "  - CCF Connector Definition + Instance" -ForegroundColor DarkCyan
Write-Host "  - Analytics Rules" -ForegroundColor DarkGray
Write-Host "  - Workbooks`n" -ForegroundColor DarkGray

$templateFile = ".\Tacitred-CCF\mainTemplate.json"
$deploymentName = "tacitred-complete-$(Get-Date -Format 'HHmmss')"

try {
    az deployment group create `
        --resource-group $ResourceGroup `
        --name $deploymentName `
        --template-file $templateFile `
        --parameters workspace=$WorkspaceName `
        --parameters workspace-location=$wsLocation `
        --parameters tacitRedApiKey=$apiKey `
        --parameters deployAnalytics=true `
        --parameters deployWorkbooks=true `
        --parameters deployConnectors=true `
        --parameters enableKeyVault=true `
        --parameters keyVaultOption=new `
        --output json
    
    if($LASTEXITCODE -eq 0){
        Write-Host "`n✅ DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
        
        # Wait for propagation
        Write-Host "`nWaiting 15 seconds for resource propagation..." -ForegroundColor Yellow
        Start-Sleep -Seconds 15
        
        # Check connector
        $wsId = az monitor log-analytics workspace show `
            --resource-group $ResourceGroup `
            --workspace-name $WorkspaceName `
            --query id -o tsv
        
        $connUri = "https://management.azure.com$wsId/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"
        $connector = az rest --method GET --uri $connUri 2>$null | ConvertFrom-Json
        
        Write-Host "`n📊 CCF CONNECTOR STATUS:" -ForegroundColor Cyan
        if($connector){
            Write-Host "  Name: $($connector.name)" -ForegroundColor Gray
            Write-Host "  Kind: $($connector.kind)" -ForegroundColor Gray
            Write-Host "  Is Active: $($connector.properties.isActive)" -ForegroundColor $(if($connector.properties.isActive){'Green'}else{'Red'})
            Write-Host "  Polling Interval: $($connector.properties.request.queryWindowInMin) minutes" -ForegroundColor Gray
            
            if($connector.properties.auth.ApiKey){
                Write-Host "  API Key: ✅ SET!" -ForegroundColor Green
                Write-Host "    Length: $($connector.properties.auth.ApiKey.Length) characters" -ForegroundColor Gray
            }else{
                Write-Host "  API Key: ❌ NULL (SAME ISSUE!)" -ForegroundColor Red
            }
        }else{
            Write-Host "  ⚠ Connector not found (may still be deploying)" -ForegroundColor Yellow
        }
        
        # Check Key Vault
        Write-Host "`n🔐 KEY VAULT STATUS:" -ForegroundColor Cyan
        $kvList = az keyvault list --resource-group $ResourceGroup | ConvertFrom-Json
        $kv = $kvList | Where-Object {$_.name -like "*tacitred*"} | Select-Object -First 1
        
        if($kv){
            Write-Host "  Key Vault: $($kv.name)" -ForegroundColor Gray
            Write-Host "  Location: $($kv.location)" -ForegroundColor Gray
            
            # Check if secret exists
            $secrets = az keyvault secret list --vault-name $kv.name --query "[].name" -o json | ConvertFrom-Json
            
            if($secrets -contains "tacitred-api-key"){
                Write-Host "  Secret 'tacitred-api-key': ✅ EXISTS" -ForegroundColor Green
            }else{
                Write-Host "  Secret 'tacitred-api-key': ⚠ NOT FOUND" -ForegroundColor Yellow
            }
        }else{
            Write-Host "  ⚠ Key Vault not found" -ForegroundColor Yellow
        }
        
        Write-Host "`n💡 ANALYSIS:" -ForegroundColor Yellow
        if($connector -and $connector.properties.auth.ApiKey){
            Write-Host "  ✅ SUCCESS! Original package with Key Vault WORKS!" -ForegroundColor Green
            Write-Host "  The missing piece was deploying the complete package" -ForegroundColor White
        }elseif($connector -and -not $connector.properties.auth.ApiKey){
            Write-Host "  ❌ SAME ISSUE! Even with Key Vault enabled" -ForegroundColor Red
            Write-Host "  This proves the original package has the same problem" -ForegroundColor Yellow
            Write-Host "  CCF RestApiPoller API keys do NOT persist" -ForegroundColor Yellow
        }else{
            Write-Host "  ⚠ Connector not deployed (check logs)" -ForegroundColor Yellow
        }
        
        Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Cyan
        Write-Host "  1. Wait 60-90 minutes for first poll" -ForegroundColor White
        Write-Host "  2. Run: .\VERIFY-FRESH-CCF.ps1" -ForegroundColor White
        Write-Host "  3. Run: .\COLLECT-ALL-LOGS.ps1" -ForegroundColor White
        
    }else{
        Write-Host "`n✗ Deployment failed" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

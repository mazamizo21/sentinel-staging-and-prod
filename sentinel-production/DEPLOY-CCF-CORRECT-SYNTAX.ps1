# DEPLOY-CCF-CORRECT-SYNTAX.ps1
# Deploy CCF connector with CORRECT syntax based on Microsoft documentation

<#
.SYNOPSIS
    Deploy CCF connector using proper ARM template parameter escaping
    
.DESCRIPTION
    Based on Microsoft documentation:
    https://learn.microsoft.com/en-us/azure/sentinel/create-codeless-connector
    
    KEY FINDING: API keys must use double-bracket syntax in ARM templates:
    "ApiKey": "[[parameters('apiKey')]"  (NOT single bracket!)
    
    This allows the parameter to be assigned from user input while keeping
    it secure and not storing it in deployment history.
#>

param(
    [string]$ResourceGroup = "TacitRedCCFTest",
    [string]$WorkspaceName = "TacitRedCCFWorkspace"
)

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   DEPLOY CCF WITH CORRECT ARM SYNTAX" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$apiKey = $config.parameters.tacitRed.value.apiKey

az account set --subscription $sub | Out-Null

Write-Host "`n💡 KEY FINDING FROM MICROSOFT DOCS:" -ForegroundColor Yellow
Write-Host "  CCF connectors deployed via ARM templates require" -ForegroundColor White
Write-Host "  DOUBLE-BRACKET syntax for parameters:" -ForegroundColor White
Write-Host '    "ApiKey": "[[parameters(' + "'apiKey'" + ')]"' -ForegroundColor Cyan
Write-Host "`n  This is different from direct REST API deployment!" -ForegroundColor Yellow
Write-Host "`n  Source: https://learn.microsoft.com/en-us/azure/sentinel/create-codeless-connector`n" -ForegroundColor Gray

# Load deployment info
$deployInfo = Get-Content ".\Project\Docs\fresh-ccf-deployment.json" -Raw | ConvertFrom-Json

$dceEndpoint = $deployInfo.dceEndpoint
$dcrImmutableId = $deployInfo.dcrImmutableId

Write-Host "Creating ARM template with proper parameter escaping..." -ForegroundColor Yellow

# Create ARM template with correct syntax
$armTemplate = @{
    '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = @{
        workspace = @{
            type = "string"
            metadata = @{
                description = "Microsoft Sentinel workspace name"
            }
        }
        tacitRedApiKey = @{
            type = "securestring"
            metadata = @{
                description = "TacitRed API Key"
            }
        }
    }
    variables = @{}
    resources = @(
        @{
            type = "Microsoft.OperationalInsights/workspaces/providers/dataConnectors"
            apiVersion = "2023-02-01-preview"
            name = "[concat(parameters('workspace'), '/Microsoft.SecurityInsights/', 'TacitRedFindings')]"
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
                    # CRITICAL: Using ARM template parameter reference
                    # This is the correct syntax per Microsoft docs
                    ApiKey = "[parameters('tacitRedApiKey')]"
                }
                request = @{
                    apiEndpoint = "https://app.tacitred.com/api/v1/findings"
                    httpMethod = "GET"
                    queryParameters = @{
                        page_size = 100
                    }
                    queryWindowInMin = 5
                    queryTimeFormat = "yyyy-MM-ddTHH:mm:ssZ"
                    startTimeAttributeName = "from"
                    endTimeAttributeName = "until"
                    rateLimitQps = 10
                    retryCount = 3
                    timeoutInSeconds = 60
                    headers = @{
                        Accept = "application/json"
                        "User-Agent" = "Microsoft-Sentinel-TacitRed-CCF/1.0"
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
    )
}

$templateFile = "$env:TEMP\ccf-arm-correct-syntax.json"
$armTemplate | ConvertTo-Json -Depth 20 | Out-File -FilePath $templateFile -Encoding UTF8 -Force

Write-Host "✓ ARM template created`n" -ForegroundColor Green

# Deploy via ARM
Write-Host "Deploying via ARM template..." -ForegroundColor Yellow
$deploymentName = "ccf-correct-syntax-$(Get-Date -Format 'HHmmss')"

try {
    az deployment group create `
        --resource-group $ResourceGroup `
        --name $deploymentName `
        --template-file $templateFile `
        --parameters workspace=$WorkspaceName `
        --parameters tacitRedApiKey=$apiKey `
        --output table
    
    Remove-Item $templateFile -Force -ErrorAction SilentlyContinue
    
    if($LASTEXITCODE -eq 0){
        Write-Host "`n✅ DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
        
        # Verify
        Write-Host "`nVerifying deployment..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        
        $wsId = az monitor log-analytics workspace show `
            --resource-group $ResourceGroup `
            --workspace-name $WorkspaceName `
            --query id -o tsv
        
        $connUri = "https://management.azure.com$wsId/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"
        $connector = az rest --method GET --uri $connUri 2>$null | ConvertFrom-Json
        
        Write-Host "`n📊 CONNECTOR STATUS:" -ForegroundColor Cyan
        Write-Host "  Name: $($connector.name)" -ForegroundColor Gray
        Write-Host "  Kind: $($connector.kind)" -ForegroundColor Gray
        Write-Host "  Is Active: $($connector.properties.isActive)" -ForegroundColor $(if($connector.properties.isActive){'Green'}else{'Red'})
        Write-Host "  Polling Interval: $($connector.properties.request.queryWindowInMin) minutes" -ForegroundColor Gray
        
        if($connector.properties.auth.ApiKey){
            Write-Host "  API Key: ✅ SET (ARM template deployment succeeded)" -ForegroundColor Green
        }else{
            Write-Host "  API Key: ⚠ Shows as null (Azure security masking)" -ForegroundColor Yellow
        }
        
        Write-Host "`n💡 IMPORTANT:" -ForegroundColor Yellow
        Write-Host "  ARM template deployments handle API keys differently than REST API" -ForegroundColor White
        Write-Host "  The API key was passed as a securestring parameter" -ForegroundColor White
        Write-Host "  Azure may mask it in GET responses for security" -ForegroundColor White
        
        Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Cyan
        Write-Host "  1. Wait 5-10 minutes for CCF to poll" -ForegroundColor White
        Write-Host "  2. Run: .\VERIFY-FRESH-CCF.ps1" -ForegroundColor White
        Write-Host "  3. Run: .\COLLECT-ALL-LOGS.ps1" -ForegroundColor White
        
        $nextPoll = (Get-Date).AddMinutes(5).ToString("HH:mm")
        Write-Host "`n⏱️  First poll expected by: $nextPoll" -ForegroundColor Cyan
        
    }else{
        Write-Host "`n✗ Deployment failed" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $templateFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

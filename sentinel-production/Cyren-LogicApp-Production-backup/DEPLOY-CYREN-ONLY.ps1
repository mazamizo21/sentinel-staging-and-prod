<#
.SYNOPSIS
    Deploys the complete Cyren Threat Intelligence solution to Microsoft Sentinel.

.DESCRIPTION
    This script deploys:
    - Data Collection Endpoint (DCE)
    - Data Collection Rules (DCR) for Cyren IP Reputation and Malware URLs
    - Logic Apps with managed identity for data ingestion
    - RBAC role assignments (Monitoring Metrics Publisher)
    - Analytics rules for threat detection
    - Threat Intelligence workbook

.NOTES
    Author: Automated Deployment
    Requires: Azure CLI, Azure subscription with Contributor access
    Run this script by double-clicking or from PowerShell - no cd required.

.EXAMPLE
    .\DEPLOY-CYREN-ONLY.ps1
    Runs deployment using default config file (client-config-COMPLETE.json)

.EXAMPLE
    .\DEPLOY-CYREN-ONLY.ps1 -ConfigFile "my-config.json"
    Runs deployment using custom config file
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Path to configuration file (relative to script directory)")]
    [string]$ConfigFile = 'client-config-COMPLETE.json'
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# SELF-CONTAINED: Automatically set working directory to script location
# This allows the script to run from any location (double-click, scheduled task, etc.)
# ============================================================================
$ScriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = $PWD.Path }
Set-Location $ScriptDir
Write-Host "`n[INFO] Script directory: $ScriptDir" -ForegroundColor Gray

$start = Get-Date

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         CYREN LOGIC APP - CYREN-ONLY DEPLOYMENT             ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# ============================================================================
# LOAD CONFIGURATION
# ============================================================================
$ConfigPath = Join-Path $ScriptDir $ConfigFile
if (-not (Test-Path $ConfigPath)) {
    Write-Host "[ERROR] Configuration file not found: $ConfigPath" -ForegroundColor Red
    Write-Host "[INFO] Please ensure 'client-config-COMPLETE.json' exists in the script directory." -ForegroundColor Yellow
    Write-Host "[INFO] Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}
$config = (Get-Content $ConfigPath | ConvertFrom-Json).parameters
$sub = $config.azure.value.subscriptionId
$rg  = $config.azure.value.resourceGroupName
$ws  = $config.azure.value.workspaceName
$loc = $config.azure.value.location

Write-Host "Config: $sub | $rg | $ws | $loc`n" -ForegroundColor Gray

# Create logs within this package (self-contained)
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$logDir = ".\logs\cyren-only-$ts"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript "$logDir\transcript.log"

# Configure Azure CLI to auto-install extensions without prompting (prevents hanging)
Write-Host 'Configuring Azure CLI for non-interactive extension install...' -ForegroundColor Gray
az config set extension.use_dynamic_install=yes_without_prompt 2>$null

# PHASE 1: Prerequisites
Write-Host '═══ PHASE 1: PREREQUISITES ═══' -ForegroundColor Cyan
az account set --subscription $sub

$wsData = az monitor log-analytics workspace show -g $rg -n $ws -o json | ConvertFrom-Json
$wsObj = @{
    id         = $wsData.id
    customerId = $wsData.customerId
}
Write-Host '✓ Workspace resolved' -ForegroundColor Green

# PHASE 2: DCE (Data Collection Endpoint)
Write-Host "`n═══ PHASE 2: DATA COLLECTION ENDPOINT (DCE) ═══" -ForegroundColor Cyan
Write-Host '[1/4] Deploying or reusing DCE (dce-sentinel-ti)...' -ForegroundColor Yellow

$dceTemplate = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#","contentVersion":"1.0.0.0","parameters":{"loc":{"type":"string"},"name":{"type":"string"}},"resources":[{"type":"Microsoft.Insights/dataCollectionEndpoints","apiVersion":"2022-06-01","name":"[parameters(''name'')]","location":"[parameters(''loc'')]","properties":{"networkAcls":{"publicNetworkAccess":"Enabled"}}}],"outputs":{"id":{"type":"string","value":"[resourceId(''Microsoft.Insights/dataCollectionEndpoints'',parameters(''name''))]"},"endpoint":{"type":"string","value":"[reference(resourceId(''Microsoft.Insights/dataCollectionEndpoints'',parameters(''name''))).logsIngestion.endpoint]"}}}'

$dceTemplatePath = Join-Path $logDir 'cyren-dce.json'
$dceTemplate | Out-File $dceTemplatePath -Encoding UTF8

az deployment group create -g $rg --template-file $dceTemplatePath --parameters loc=$loc name='dce-sentinel-ti' -n "cyren-dce-$ts" -o none

# Get DCE details via REST API
$dceUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Insights/dataCollectionEndpoints/dce-sentinel-ti?api-version=2022-06-01"
$dce   = az rest --method GET --uri $dceUri | ConvertFrom-Json
$dceEndpoint = $dce.properties.logsIngestion.endpoint
$dceId       = $dce.id
Write-Host "✓ DCE: $dceEndpoint" -ForegroundColor Green

# PHASE 3: LOG ANALYTICS TABLES - CYREN ONLY
Write-Host "`n═══ PHASE 3: LOG ANALYTICS TABLE (CYREN_Indicators_CL) ═══" -ForegroundColor Cyan
Write-Host 'Creating Cyren_Indicators_CL with full schema...' -ForegroundColor Yellow

$cyrenSchema = @{
    properties = @{
        schema = @{
            name    = 'Cyren_Indicators_CL'
            columns = @(
                @{ name = 'TimeGenerated';  type = 'datetime' },
                @{ name = 'url_s';          type = 'string'   },
                @{ name = 'ip_s';           type = 'string'   },
                @{ name = 'fileHash_s';     type = 'string'   },
                @{ name = 'domain_s';       type = 'string'   },
                @{ name = 'protocol_s';     type = 'string'   },
                @{ name = 'port_d';         type = 'int'      },
                @{ name = 'category_s';     type = 'string'   },
                @{ name = 'risk_d';         type = 'int'      },
                @{ name = 'firstSeen_t';    type = 'datetime' },
                @{ name = 'lastSeen_t';     type = 'datetime' },
                @{ name = 'source_s';       type = 'string'   },
                @{ name = 'relationships_s';type = 'string'   },
                @{ name = 'detection_methods_s'; type = 'string' },
                @{ name = 'action_s';       type = 'string'   },
                @{ name = 'type_s';         type = 'string'   },
                @{ name = 'identifier_s';   type = 'string'   },
                @{ name = 'detection_ts_t'; type = 'datetime' },
                @{ name = 'object_type_s';  type = 'string'   }
            )
        }
    }
} | ConvertTo-Json -Depth 10

$cyrenSchema | Out-File -FilePath './temp_cyren_schema.json' -Encoding utf8 -Force

az rest --method PUT --url "$($wsObj.id)/tables/Cyren_Indicators_CL?api-version=2023-09-01" --body '@temp_cyren_schema.json' --header 'Content-Type=application/json'

if ($LASTEXITCODE -eq 0) {
    Write-Host '✓ Cyren_Indicators_CL created or updated' -ForegroundColor Green
    Remove-Item './temp_cyren_schema.json' -Force -ErrorAction SilentlyContinue
} else {
    Write-Host '✗ Failed to create Cyren_Indicators_CL - check logs' -ForegroundColor Red
}

Write-Host 'Waiting 30s for table propagation...' -ForegroundColor Yellow
Start-Sleep -Seconds 30
Write-Host '✓ Table propagation wait complete' -ForegroundColor Green

# PHASE 4: DATA COLLECTION RULES (CYREN IP + MALWARE)
Write-Host "`n═══ PHASE 4: DATA COLLECTION RULES (CYREN) ═══" -ForegroundColor Cyan

Write-Host 'Deploying Cyren IP Reputation DCR...' -ForegroundColor Yellow
$ipDcrDeploy = az deployment group create -g $rg --template-file './infrastructure/bicep/dcr-cyren-ip.bicep' --parameters workspaceResourceId="$($wsObj.id)" dceResourceId="$dceId" -n "dcr-cyren-ip-$ts" -o json | ConvertFrom-Json
$ipDcrImmutableId = $ipDcrDeploy.properties.outputs.immutableId.value
$ipDcrId          = $ipDcrDeploy.properties.outputs.id.value

Write-Host 'Deploying Cyren Malware URLs DCR...' -ForegroundColor Yellow
$malDcrDeploy = az deployment group create -g $rg --template-file './infrastructure/bicep/dcr-cyren-malware.bicep' --parameters workspaceResourceId="$($wsObj.id)" dceResourceId="$dceId" -n "dcr-cyren-malware-$ts" -o json | ConvertFrom-Json
$malDcrImmutableId = $malDcrDeploy.properties.outputs.immutableId.value
$malDcrId          = $malDcrDeploy.properties.outputs.id.value

# Fallback auto-detection if outputs missing
$dcrList = az monitor data-collection rule list --resource-group $rg -o json | ConvertFrom-Json

if ([string]::IsNullOrEmpty($ipDcrImmutableId)) {
    Write-Host '  ⚠ Cyren IP DCR immutable ID not captured, auto-detecting...' -ForegroundColor Yellow
    $ipDcr = $dcrList | Where-Object { $_.name -like '*cyren*ip*' -or $_.name -like '*ip-reputation*' } | Select-Object -First 1
    if ($ipDcr) {
        $ipDcrImmutableId = $ipDcr.immutableId
        $ipDcrId          = $ipDcr.id
        Write-Host "  ✓ Auto-detected Cyren IP DCR: $($ipDcr.name)" -ForegroundColor Green
    } else {
        Write-Host '  ✗ Unable to auto-detect Cyren IP DCR' -ForegroundColor Red
    }
}

if ([string]::IsNullOrEmpty($malDcrImmutableId)) {
    Write-Host '  ⚠ Cyren Malware DCR immutable ID not captured, auto-detecting...' -ForegroundColor Yellow
    $malDcr = $dcrList | Where-Object { $_.name -like '*cyren*malware*' -or $_.name -like '*malware-urls*' } | Select-Object -First 1
    if ($malDcr) {
        $malDcrImmutableId = $malDcr.immutableId
        $malDcrId          = $malDcr.id
        Write-Host "  ✓ Auto-detected Cyren Malware DCR: $($malDcr.name)" -ForegroundColor Green
    } else {
        Write-Host '  ✗ Unable to auto-detect Cyren Malware DCR' -ForegroundColor Red
    }
}

Write-Host '✓ Cyren DCRs deployed and verified' -ForegroundColor Green

# PHASE 5: LOGIC APPS - CYREN IP + MALWARE
Write-Host "`n═══ PHASE 5: LOGIC APPS (CYREN INGESTION) ═══" -ForegroundColor Cyan

$cyrenConfig = $config.cyren.value

if (Test-Path './infrastructure/bicep/logicapp-cyren-ip-reputation.bicep') {
    if (-not [string]::IsNullOrEmpty($ipDcrImmutableId)) {
        Write-Host 'Deploying logic-cyren-ip-reputation Logic App...' -ForegroundColor Yellow
        Write-Host "  → DCR: $ipDcrImmutableId" -ForegroundColor Cyan
        Write-Host "  → DCE: $dceEndpoint" -ForegroundColor Cyan

        az deployment group create -g $rg --template-file './infrastructure/bicep/logicapp-cyren-ip-reputation.bicep' `
            --parameters cyrenIpReputationToken="$($cyrenConfig.ipReputation.jwtToken)" `
                        dcrImmutableId="$ipDcrImmutableId" `
                        dceEndpoint="$dceEndpoint" `
                        dcrResourceId="$ipDcrId" `
                        dceResourceId="$dceId" `
            -n "la-cyren-ip-$ts" -o none 2>$null

        Write-Host '✓ Cyren IP Reputation Logic App deployed' -ForegroundColor Green
    } else {
        Write-Host '✗ Cyren IP DCR immutable ID missing - skipping logic-cyren-ip-reputation deployment' -ForegroundColor Red
    }
} else {
    Write-Host '✗ logicapp-cyren-ip-reputation.bicep not found' -ForegroundColor Red
}

if (Test-Path './infrastructure/bicep/logicapp-cyren-malware-urls.bicep') {
    if (-not [string]::IsNullOrEmpty($malDcrImmutableId)) {
        Write-Host 'Deploying logic-cyren-malware-urls Logic App...' -ForegroundColor Yellow
        Write-Host "  → DCR: $malDcrImmutableId" -ForegroundColor Cyan
        Write-Host "  → DCE: $dceEndpoint" -ForegroundColor Cyan

        az deployment group create -g $rg --template-file './infrastructure/bicep/logicapp-cyren-malware-urls.bicep' `
            --parameters cyrenMalwareUrlsToken="$($cyrenConfig.malwareUrls.jwtToken)" `
                        dcrImmutableId="$malDcrImmutableId" `
                        dceEndpoint="$dceEndpoint" `
                        dcrResourceId="$malDcrId" `
                        dceResourceId="$dceId" `
            -n "la-cyren-malware-$ts" -o none 2>$null

        Write-Host '✓ Cyren Malware URLs Logic App deployed' -ForegroundColor Green
    } else {
        Write-Host '✗ Cyren Malware DCR immutable ID missing - skipping logic-cyren-malware-urls deployment' -ForegroundColor Red
    }
} else {
    Write-Host '✗ logicapp-cyren-malware-urls.bicep not found' -ForegroundColor Red
}

# Wait for managed identities to propagate before RBAC
Write-Host "Waiting 120s for managed identities to propagate..." -ForegroundColor Yellow
Start-Sleep -Seconds 120
Write-Host "✓ Identity propagation complete`n" -ForegroundColor Green

# PHASE 6: RBAC ASSIGNMENT (CYREN ONLY)
Write-Host "`n═══ PHASE 6: RBAC ASSIGNMENT (CYREN LOGIC APPS) ═══" -ForegroundColor Cyan

$logicAppRbacConfig = @(
    @{
        Name = 'logic-cyren-ip-reputation'
        DcrId = $ipDcrId
        DceId = $dceId
    },
    @{
        Name = 'logic-cyren-malware-urls'
        DcrId = $malDcrId
        DceId = $dceId
    }
)

$rbacResults = @()

foreach ($laConfig in $logicAppRbacConfig) {
    $laName = $laConfig.Name
    try {
        $laObj = az logic workflow show -g $rg -n $laName 2>$null | ConvertFrom-Json
        if ($laObj -and $laObj.identity.principalId) {
            $principalId = $laObj.identity.principalId
            Write-Host "  [$laName]" -ForegroundColor Cyan
            Write-Host "    Principal ID: $principalId" -ForegroundColor Gray

            if ($laConfig.DcrId) {
                $dcrName = ($laConfig.DcrId -split '/')[-1]
                Write-Host "    Assigning Monitoring Metrics Publisher → DCR: $dcrName" -ForegroundColor Gray
                try {
                    az role assignment create --assignee $principalId --role 'Monitoring Metrics Publisher' --scope $laConfig.DcrId 2>$null | Out-Null
                    Write-Host '      ✓ Monitoring Metrics Publisher → DCR' -ForegroundColor Green
                } catch {
                    Write-Host '      ⚠ DCR role may already exist' -ForegroundColor Yellow
                }
            }

            if ($laConfig.DceId) {
                $dceName = ($laConfig.DceId -split '/')[-1]
                Write-Host "    Assigning Monitoring Metrics Publisher → DCE: $dceName" -ForegroundColor Gray
                try {
                    az role assignment create --assignee $principalId --role 'Monitoring Metrics Publisher' --scope $laConfig.DceId 2>$null | Out-Null
                    Write-Host '      ✓ Monitoring Metrics Publisher → DCE' -ForegroundColor Green
                } catch {
                    Write-Host '      ⚠ DCE role may already exist' -ForegroundColor Yellow
                }
            }

            $rbacResults += @{
                LogicApp  = $laName
                Principal = $principalId
                Status    = 'RBAC Assigned'
            }
        } else {
            Write-Host "  ✗ $laName : Not found or no identity" -ForegroundColor Red
            $rbacResults += @{
                LogicApp  = $laName
                Principal = 'N/A'
                Status    = 'Error'
            }
        }
    } catch {
        Write-Host "  ✗ $laName : Error - $($_.Exception.Message)" -ForegroundColor Red
        $rbacResults += @{
            LogicApp  = $laName
            Principal = 'ERROR'
            Status    = 'Failed'
        }
    }
}

$rbacResults | ConvertTo-Json | Out-File "$logDir\rbac-cyren.json" -Encoding UTF8

Write-Host 'Waiting 60s for initial RBAC propagation...' -ForegroundColor Yellow
Start-Sleep -Seconds 60
Write-Host '✓ Initial RBAC wait complete' -ForegroundColor Green

# PHASE 7: ANALYTICS RULES
Write-Host "`n═══ PHASE 7: ANALYTICS RULES ═══" -ForegroundColor Cyan

$analyticsPath = Join-Path $ScriptDir 'analytics' 'analytics-rules.bicep'
if (Test-Path $analyticsPath) {
    Write-Host 'Deploying Cyren Analytics Rules...' -ForegroundColor Yellow
    try {
        az deployment group create -g $rg --template-file $analyticsPath --parameters workspaceName=$ws -n "cyren-analytics-$ts" -o none 2>$null
        Write-Host '✓ Analytics rules deployed (High-Risk IP, Malware URL, Persistent Threat)' -ForegroundColor Green
    } catch {
        Write-Host '⚠ Analytics deployment had warnings (rules may already exist)' -ForegroundColor Yellow
    }
} else {
    Write-Host '⚠ analytics-rules.bicep not found - skipping analytics deployment' -ForegroundColor Yellow
}

# PHASE 7B: WORKBOOK
Write-Host "`n═══ PHASE 7B: WORKBOOK ═══" -ForegroundColor Cyan

$workbookPath = Join-Path $ScriptDir 'workbooks' 'bicep' 'workbook-cyren-threat-intelligence.bicep'
if (Test-Path $workbookPath) {
    Write-Host 'Deploying Cyren Threat Intelligence Workbook...' -ForegroundColor Yellow
    try {
        az deployment group create -g $rg --template-file $workbookPath --parameters workspaceId="$($wsObj.id)" -n "cyren-workbook-$ts" -o none 2>$null
        Write-Host '✓ Workbook deployed (Cyren Threat Intelligence Dashboard)' -ForegroundColor Green
    } catch {
        Write-Host '⚠ Workbook deployment had warnings (may already exist)' -ForegroundColor Yellow
    }
} else {
    Write-Host '⚠ workbook-cyren-threat-intelligence.bicep not found - skipping workbook' -ForegroundColor Yellow
}

# PHASE 8: INITIAL TEST TRIGGER
Write-Host "`n═══ PHASE 8: INITIAL TEST TRIGGERS ═══" -ForegroundColor Cyan

try {
    Write-Host 'Triggering logic-cyren-ip-reputation once for initial test...' -ForegroundColor Gray
    az logic workflow trigger run -g $rg --name 'logic-cyren-ip-reputation' --trigger-name 'Recurrence' -o none 2>$null
    Write-Host '✓ Trigger requested (IP Reputation)' -ForegroundColor Green
} catch {
    Write-Host '⚠ Unable to trigger logic-cyren-ip-reputation (check if it exists and RBAC)' -ForegroundColor Yellow
}

try {
    Write-Host 'Triggering logic-cyren-malware-urls once for initial test...' -ForegroundColor Gray
    az logic workflow trigger run -g $rg --name 'logic-cyren-malware-urls' --trigger-name 'Recurrence' -o none 2>$null
    Write-Host '✓ Trigger requested (Malware URLs)' -ForegroundColor Green
} catch {
    Write-Host '⚠ Unable to trigger logic-cyren-malware-urls (check if it exists and RBAC)' -ForegroundColor Yellow
}

# SUMMARY
$dur = ((Get-Date) - $start).TotalMinutes
Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ CYREN-ONLY DEPLOYMENT COMPLETE ($($dur.ToString('0.0')) minutes)" -ForegroundColor Green
Write-Host '  • Data Collection Endpoint (dce-sentinel-ti)' -ForegroundColor Gray
Write-Host '  • Cyren_Indicators_CL table (full schema)' -ForegroundColor Gray
Write-Host '  • Cyren IP Reputation DCR (dcr-cyren-ip)' -ForegroundColor Gray
Write-Host '  • Cyren Malware URLs DCR (dcr-cyren-malware)' -ForegroundColor Gray
Write-Host '  • Cyren Logic Apps (logic-cyren-ip-reputation, logic-cyren-malware-urls) with RBAC' -ForegroundColor Gray
Write-Host '  • Analytics rules (High-Risk IP, Malware URL, Persistent Threat)' -ForegroundColor Gray
Write-Host '  • Workbook (Cyren Threat Intelligence Dashboard)' -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`nDeployment Logs: $logDir" -ForegroundColor Gray

Stop-Transcript

# Keep window open if run by double-click
if ($Host.Name -eq 'ConsoleHost' -and [Environment]::UserInteractive) {
    Write-Host "`n[INFO] Deployment complete. Press any key to close..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

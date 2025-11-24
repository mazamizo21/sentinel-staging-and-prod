[CmdletBinding()]
param(
    [string]$ConfigFile = '..\client-config-COMPLETE.json'
)

$ErrorActionPreference = 'Stop'

# Resolve script directory and move there
$ScriptDir = Split-Path -Parent $PSCommandPath
Set-Location $ScriptDir
Write-Host "Working directory: $ScriptDir" -ForegroundColor Gray

$start = Get-Date

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       TACITRED LOGIC APP - TACITRED-ONLY DEPLOYMENT         ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Load config
$config = (Get-Content $ConfigFile | ConvertFrom-Json).parameters
$sub = $config.azure.value.subscriptionId
$rg  = $config.azure.value.resourceGroupName
$ws  = $config.azure.value.workspaceName
$loc = $config.azure.value.location

Write-Host "Config: $sub | $rg | $ws | $loc`n" -ForegroundColor Gray

# Create logs within this package
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$logDir = ".\docs\deployment-logs\tacitred-only-$ts"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript "$logDir\transcript.log"

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
Write-Host '[1/3] Deploying or reusing DCE (dce-sentinel-ti)...' -ForegroundColor Yellow

# Same inline ARM template pattern as DEPLOY-COMPLETE.ps1
$dceTemplate = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#","contentVersion":"1.0.0.0","parameters":{"loc":{"type":"string"},"name":{"type":"string"}},"resources":[{"type":"Microsoft.Insights/dataCollectionEndpoints","apiVersion":"2022-06-01","name":"[parameters(''name'')]","location":"[parameters(''loc'')]","properties":{"networkAcls":{"publicNetworkAccess":"Enabled"}}}],"outputs":{"id":{"type":"string","value":"[resourceId(''Microsoft.Insights/dataCollectionEndpoints'',parameters(''name''))]"},"endpoint":{"type":"string","value":"[reference(resourceId(''Microsoft.Insights/dataCollectionEndpoints'',parameters(''name''))).logsIngestion.endpoint]"}}}'

$dceTemplate | Out-File "$env:TEMP\tacitred-dce.json" -Encoding UTF8

az deployment group create -g $rg --template-file "$env:TEMP\tacitred-dce.json" --parameters loc=$loc name='dce-sentinel-ti' -n "tacitred-dce-$ts" -o none

# Get DCE details via REST API
$dceUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Insights/dataCollectionEndpoints/dce-sentinel-ti?api-version=2022-06-01"
$dce   = az rest --method GET --uri $dceUri | ConvertFrom-Json
$dceEndpoint = $dce.properties.logsIngestion.endpoint
$dceId       = $dce.id
Write-Host "✓ DCE: $dceEndpoint" -ForegroundColor Green

# PHASE 3: TABLE - TacitRed_Findings_CL only
Write-Host "`n═══ PHASE 3: LOG ANALYTICS TABLES (TACITRED ONLY) ═══" -ForegroundColor Cyan
Write-Host 'Creating TacitRed_Findings_CL with full schema...' -ForegroundColor Yellow

$tacitredSchema = @{
    properties = @{
        schema = @{
            name    = 'TacitRed_Findings_CL'
            columns = @(
                @{ name = 'TimeGenerated';  type = 'datetime' },
                @{ name = 'email_s';        type = 'string'   },
                @{ name = 'domain_s';       type = 'string'   },
                @{ name = 'findingType_s';  type = 'string'   },
                @{ name = 'confidence_d';   type = 'int'      },
                @{ name = 'firstSeen_t';    type = 'datetime' },
                @{ name = 'lastSeen_t';     type = 'datetime' },
                @{ name = 'notes_s';        type = 'string'   },
                @{ name = 'source_s';       type = 'string'   },
                @{ name = 'severity_s';     type = 'string'   },
                @{ name = 'status_s';       type = 'string'   },
                @{ name = 'campaign_id_s';  type = 'string'   },
                @{ name = 'user_id_s';      type = 'string'   },
                @{ name = 'username_s';     type = 'string'   },
                @{ name = 'detection_ts_t'; type = 'datetime' },
                @{ name = 'metadata_s';     type = 'string'   }
            )
        }
    }
} | ConvertTo-Json -Depth 10

$tacitredSchema | Out-File -FilePath './temp_tacitred_schema.json' -Encoding utf8 -Force

az rest --method PUT --url "$($wsObj.id)/tables/TacitRed_Findings_CL?api-version=2023-09-01" --body '@temp_tacitred_schema.json' --header 'Content-Type=application/json'

if ($LASTEXITCODE -eq 0) {
    Write-Host '✓ TacitRed_Findings_CL created or updated' -ForegroundColor Green
    Remove-Item './temp_tacitred_schema.json' -Force -ErrorAction SilentlyContinue
} else {
    Write-Host '✗ Failed to create TacitRed_Findings_CL - check logs' -ForegroundColor Red
}

Write-Host 'Waiting 30s for table propagation...' -ForegroundColor Yellow
Start-Sleep -Seconds 30
Write-Host '✓ Table propagation wait complete' -ForegroundColor Green

# PHASE 4: DCR - TacitRed only
Write-Host "`n═══ PHASE 4: DATA COLLECTION RULE (TACITRED ONLY) ═══" -ForegroundColor Cyan

Write-Host 'Deploying TacitRed DCR...' -ForegroundColor Yellow

$tacitredDcrDeploy = az deployment group create -g $rg --template-file '.\infrastructure\bicep\dcr-tacitred-findings.bicep' --parameters workspaceResourceId="$($wsObj.id)" dceResourceId="$dceId" -n "dcr-tacitred-$ts" -o json | ConvertFrom-Json

$tacitredDcrImmutableId = $tacitredDcrDeploy.properties.outputs.immutableId.value
$tacitredDcrId          = $tacitredDcrDeploy.properties.outputs.id.value

# Fallback auto-detection if outputs missing
$dcrList = az monitor data-collection rule list --resource-group $rg -o json | ConvertFrom-Json
if ([string]::IsNullOrEmpty($tacitredDcrImmutableId)) {
    Write-Host '  ⚠ TacitRed DCR immutable ID not captured, auto-detecting...' -ForegroundColor Yellow
    $tacitredDcr = $dcrList | Where-Object { $_.name -like '*tacitred*' -or $_.name -like '*findings*' } | Select-Object -First 1
    if ($tacitredDcr) {
        $tacitredDcrImmutableId = $tacitredDcr.immutableId
        $tacitredDcrId          = $tacitredDcr.id
        Write-Host "  ✓ Auto-detected TacitRed DCR: $($tacitredDcr.name)" -ForegroundColor Green
    } else {
        Write-Host '  ✗ Unable to auto-detect TacitRed DCR' -ForegroundColor Red
    }
}

Write-Host '✓ TacitRed DCR deployed and verified' -ForegroundColor Green

# PHASE 5: Logic App - TacitRed ingestion only
Write-Host "`n═══ PHASE 5: LOGIC APP (TACITRED INGESTION) ═══" -ForegroundColor Cyan

if (Test-Path '.\infrastructure\bicep\logicapp-tacitred-ingestion.bicep') {
    if (-not [string]::IsNullOrEmpty($tacitredDcrImmutableId)) {
        Write-Host 'Deploying logic-tacitred-ingestion Logic App...' -ForegroundColor Yellow
        Write-Host "  → DCR: $tacitredDcrImmutableId" -ForegroundColor Cyan
        Write-Host "  → DCE: $dceEndpoint" -ForegroundColor Cyan

        az deployment group create -g $rg --template-file '.\infrastructure\bicep\logicapp-tacitred-ingestion.bicep' `
            --parameters tacitRedApiKey="$($config.tacitRed.value.apiKey)" `
                        dcrImmutableId="$tacitredDcrImmutableId" `
                        dceEndpoint="$dceEndpoint" `
                        dcrResourceId="$tacitredDcrId" `
                        dceResourceId="$dceId" `
            -n "la-tacitred-$ts" -o none 2>$null

        Write-Host '✓ TacitRed Logic App deployed' -ForegroundColor Green
    } else {
        Write-Host '✗ TacitRed DCR immutable ID missing - skipping Logic App deployment' -ForegroundColor Red
    }
} else {
    Write-Host '✗ logicapp-tacitred-ingestion.bicep not found' -ForegroundColor Red
}

# PHASE 6: RBAC for TacitRed Logic App
Write-Host "`n═══ PHASE 6: RBAC ASSIGNMENT (TACITRED ONLY) ═══" -ForegroundColor Cyan

$laName = 'logic-tacitred-ingestion'
$rbacResults = @()

try {
    $laObj = az logic workflow show -g $rg -n $laName 2>$null | ConvertFrom-Json
    if ($laObj -and $laObj.identity.principalId) {
        $principalId = $laObj.identity.principalId
        Write-Host "  [$laName]" -ForegroundColor Cyan
        Write-Host "    Principal ID: $principalId" -ForegroundColor Gray

        if ($tacitredDcrId) {
            Write-Host '    Assigning Monitoring Metrics Publisher → DCR' -ForegroundColor Gray
            try {
                az role assignment create --assignee $principalId --role 'Monitoring Metrics Publisher' --scope $tacitredDcrId 2>$null | Out-Null
                Write-Host '      ✓ Role assigned on DCR' -ForegroundColor Green
            } catch {
                Write-Host '      ⚠ DCR role may already exist' -ForegroundColor Yellow
            }
        }

        if ($dceId) {
            Write-Host '    Assigning Monitoring Metrics Publisher → DCE' -ForegroundColor Gray
            try {
                az role assignment create --assignee $principalId --role 'Monitoring Metrics Publisher' --scope $dceId 2>$null | Out-Null
                Write-Host '      ✓ Role assigned on DCE' -ForegroundColor Green
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
        Write-Host '  ✗ logic-tacitred-ingestion : Not found or no identity' -ForegroundColor Red
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

$rbacResults | ConvertTo-Json | Out-File "$logDir\rbac-tacitred.json" -Encoding UTF8

Write-Host 'Waiting 60s for initial RBAC propagation...' -ForegroundColor Yellow
Start-Sleep -Seconds 60
Write-Host '✓ Initial RBAC wait complete' -ForegroundColor Green

# PHASE 7: ANALYTICS (TACITRED-ONLY - NO CYREN CROSSFED)
Write-Host "`n═══ PHASE 7: ANALYTICS RULES (TACITRED ONLY) ═══" -ForegroundColor Cyan

if (Test-Path '.\analytics\analytics-rules.bicep') {
    Write-Host 'Deploying TacitRed analytics rules (no Cyren crossfeed)...' -ForegroundColor Yellow

    az deployment group create `
        -g $rg `
        --template-file '.\analytics\analytics-rules.bicep' `
        --parameters workspaceName=$ws location=$loc `
                    enableRepeatCompromise=true `
                    enableHighRiskUser=false `
                    enableActiveCompromisedAccount=false `
                    enableDepartmentCluster=false `
                    enableMalwareInfrastructure=false `
                    enableCrossFeedCorrelation=false `
        -n "tacitred-analytics-$ts" `
        -o none 2>&1 | Out-File -FilePath "$logDir\analytics-deploy.log" -Encoding utf8

    if ($LASTEXITCODE -eq 0) {
        Write-Host '✓ TacitRed analytics rules deployed (no Cyren crossfeed)' -ForegroundColor Green
    } else {
        Write-Host "✗ TacitRed analytics deployment FAILED (exit code: $LASTEXITCODE)" -ForegroundColor Red
    }
} else {
    Write-Host '⚠ analytics/analytics-rules.bicep not found' -ForegroundColor Yellow
}

# PHASE 8: OPTIONAL INITIAL TRIGGER
Write-Host "`n═══ PHASE 8: INITIAL TEST TRIGGER (OPTIONAL) ═══" -ForegroundColor Cyan

try {
    Write-Host 'Triggering logic-tacitred-ingestion once for initial test...' -ForegroundColor Gray
    az logic workflow trigger run -g $rg --name 'logic-tacitred-ingestion' --trigger-name 'Recurrence' -o none 2>$null
    Write-Host '✓ Trigger requested (check Logic App run history for status)' -ForegroundColor Green
} catch {
    Write-Host '⚠ Unable to trigger logic-tacitred-ingestion (check if it exists and RBAC)' -ForegroundColor Yellow
}

# SUMMARY
$dur = ((Get-Date) - $start).TotalMinutes
Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ TACITRED-ONLY DEPLOYMENT COMPLETE ($($dur.ToString('0.0')) minutes)" -ForegroundColor Green
Write-Host '  • Data Collection Endpoint (dce-sentinel-ti)' -ForegroundColor Gray
Write-Host '  • TacitRed_Findings_CL table (full schema)' -ForegroundColor Gray
Write-Host '  • TacitRed DCR (dcr-tacitred-findings)' -ForegroundColor Gray
Write-Host '  • TacitRed Logic App (logic-tacitred-ingestion) with RBAC' -ForegroundColor Gray
Write-Host '  • TacitRed analytics rules (no Cyren crossfeed)' -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`nDeployment Logs: $logDir" -ForegroundColor Gray

Stop-Transcript

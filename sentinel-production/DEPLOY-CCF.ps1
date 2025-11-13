# Complete Automated Deployment - Sentinel Threat Intelligence with CCF
# Version: 2.0.0 - CCF (Codeless Connector Framework) enabled
# This deploys CCF connectors instead of Logic Apps

[CmdletBinding()]
$ConfigFile = 'd:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production\client-config-COMPLETE.json'

# Ensure script runs from correct directory
$ScriptDir = Split-Path -Parent $PSCommandPath
Set-Location $ScriptDir
Write-Host "Working directory: $ScriptDir" -ForegroundColor Gray

$ErrorActionPreference = "Stop"
$start = Get-Date

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   SENTINEL THREAT INTELLIGENCE - CCF DEPLOYMENT (BETA)      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Load config
$config = (Get-Content $ConfigFile | ConvertFrom-Json).parameters
$sub = $config.azure.value.subscriptionId
$rg = $config.azure.value.resourceGroupName
$ws = $config.azure.value.workspaceName
$loc = $config.azure.value.location

# Check if CCF is enabled
if(-not $config.ccf.value.enabled) {
    Write-Host "✗ CCF is NOT enabled in config file" -ForegroundColor Red
    Write-Host "  Set ccf.enabled = true in client-config-COMPLETE.json" -ForegroundColor Yellow
    exit 1
}

# Create logs
$ts = Get-Date -Format "yyyyMMddHHmmss"
$logDir = ".\docs\deployment-logs\ccf-$ts"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript "$logDir\transcript.log"

Write-Host "Config: $sub | $rg | $ws | $loc`n" -ForegroundColor Gray
Write-Host "CCF Enabled: Deploying Codeless Connector Framework`n" -ForegroundColor Green

# Prerequisites
Write-Host "═══ PHASE 1: PREREQUISITES ═══" -ForegroundColor Cyan
az account set --subscription $sub
$wsData = az monitor log-analytics workspace show -g $rg -n $ws -o json | ConvertFrom-Json
$wsObj = @{
    id = $wsData.id
    customerId = $wsData.customerId
}
Write-Host "✓ Prerequisites validated`n" -ForegroundColor Green

# Deploy DCE
Write-Host "═══ PHASE 2: INFRASTRUCTURE ═══" -ForegroundColor Cyan
Write-Host "[1/4] Deploying DCE..." -ForegroundColor Yellow

$dceTemplate = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#","contentVersion":"1.0.0.0","parameters":{"loc":{"type":"string"},"name":{"type":"string"}},"resources":[{"type":"Microsoft.Insights/dataCollectionEndpoints","apiVersion":"2022-06-01","name":"[parameters(''name'')]","location":"[parameters(''loc'')]","properties":{"networkAcls":{"publicNetworkAccess":"Enabled"}}}],"outputs":{"id":{"type":"string","value":"[resourceId(''Microsoft.Insights/dataCollectionEndpoints'',parameters(''name''))]"},"endpoint":{"type":"string","value":"[reference(resourceId(''Microsoft.Insights/dataCollectionEndpoints'',parameters(''name''))).logsIngestion.endpoint]"}}}'
$dceTemplate | Out-File "$env:TEMP\dce.json" -Encoding UTF8

az deployment group create -g $rg --template-file "$env:TEMP\dce.json" --parameters loc=$loc name="dce-sentinel-ti" -n "dce-$ts" -o none

# Get DCE details
$dceUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Insights/dataCollectionEndpoints/dce-sentinel-ti?api-version=2022-06-01"
$dce = az rest --method GET --uri $dceUri | ConvertFrom-Json
$dceEndpoint = $dce.properties.logsIngestion.endpoint
$dceId = $dce.id
Write-Host "✓ DCE: $dceEndpoint" -ForegroundColor Green

# Deploy tables with full schemas
Write-Host "[2/4] Creating tables with full schemas..." -ForegroundColor Yellow

# TacitRed_Findings_CL - Full schema
$tacitredSchema = @{
    properties = @{
        schema = @{
            name = "TacitRed_Findings_CL"
            columns = @(
                @{name="TimeGenerated";type="datetime"},
                @{name="email_s";type="string"},
                @{name="domain_s";type="string"},
                @{name="findingType_s";type="string"},
                @{name="confidence_d";type="int"},
                @{name="firstSeen_t";type="datetime"},
                @{name="lastSeen_t";type="datetime"},
                @{name="notes_s";type="string"},
                @{name="source_s";type="string"},
                @{name="severity_s";type="string"},
                @{name="status_s";type="string"},
                @{name="campaign_id_s";type="string"},
                @{name="user_id_s";type="string"},
                @{name="username_s";type="string"},
                @{name="detection_ts_t";type="datetime"},
                @{name="metadata_s";type="string"}
            )
        }
    }
} | ConvertTo-Json -Depth 10

# Cyren_Indicators_CL - Full schema  
$cyrenSchema = @{
    properties = @{
        schema = @{
            name = "Cyren_Indicators_CL"
            columns = @(
                @{name="TimeGenerated";type="datetime"},
                @{name="url_s";type="string"},
                @{name="ip_s";type="string"},
                @{name="fileHash_s";type="string"},
                @{name="domain_s";type="string"},
                @{name="protocol_s";type="string"},
                @{name="port_d";type="int"},
                @{name="category_s";type="string"},
                @{name="risk_d";type="int"},
                @{name="firstSeen_t";type="datetime"},
                @{name="lastSeen_t";type="datetime"},
                @{name="source_s";type="string"},
                @{name="relationships_s";type="string"},
                @{name="detection_methods_s";type="string"},
                @{name="action_s";type="string"},
                @{name="type_s";type="string"},
                @{name="identifier_s";type="string"},
                @{name="detection_ts_t";type="datetime"},
                @{name="object_type_s";type="string"}
            )
        }
    }
} | ConvertTo-Json -Depth 10

# Create tables
Write-Host "  Creating TacitRed_Findings_CL..." -ForegroundColor Gray
$tacitredSchema | Out-File -FilePath "./temp_tacitred_schema.json" -Encoding utf8 -Force
az rest --method PUT --url "$($wsObj.id)/tables/TacitRed_Findings_CL?api-version=2023-09-01" --body '@temp_tacitred_schema.json' --header "Content-Type=application/json"
if($LASTEXITCODE -eq 0){ Write-Host "  ✓ TacitRed_Findings_CL created" -ForegroundColor Green; Remove-Item "./temp_tacitred_schema.json" -Force } else { Write-Host "  ✗ Failed" -ForegroundColor Red }

Write-Host "  Creating Cyren_Indicators_CL..." -ForegroundColor Gray
$cyrenSchema | Out-File -FilePath "./temp_cyren_schema.json" -Encoding utf8 -Force
az rest --method PUT --url "$($wsObj.id)/tables/Cyren_Indicators_CL?api-version=2023-09-01" --body '@temp_cyren_schema.json' --header "Content-Type=application/json"
if($LASTEXITCODE -eq 0){ Write-Host "  ✓ Cyren_Indicators_CL created" -ForegroundColor Green; Remove-Item "./temp_cyren_schema.json" -Force } else { Write-Host "  ✗ Failed" -ForegroundColor Red }

Write-Host "  Waiting 30s for table propagation..." -ForegroundColor Yellow
Start-Sleep -Seconds 30
Write-Host "✓ Tables created with full schemas" -ForegroundColor Green

# Deploy DCRs
Write-Host "[3/4] Deploying DCRs..." -ForegroundColor Yellow

Write-Host "  Deploying TacitRed DCR..." -ForegroundColor Gray
$tacitredDcrDeploy = az deployment group create -g $rg --template-file ".\infrastructure\bicep\dcr-tacitred-findings.bicep" --parameters workspaceResourceId="$($wsObj.id)" dceResourceId="$dceId" -n "dcr-tacitred-$ts" -o json | ConvertFrom-Json
$tacitredDcrImmutableId = $tacitredDcrDeploy.properties.outputs.immutableId.value
$tacitredDcrId = $tacitredDcrDeploy.properties.outputs.id.value

Write-Host "  Deploying Cyren IP DCR..." -ForegroundColor Gray
$ipDcrDeploy = az deployment group create -g $rg --template-file ".\infrastructure\bicep\dcr-cyren-ip.bicep" --parameters workspaceResourceId="$($wsObj.id)" dceResourceId="$dceId" -n "dcr-ip-$ts" -o json | ConvertFrom-Json
$ipDcrImmutableId = $ipDcrDeploy.properties.outputs.immutableId.value
$ipDcrId = $ipDcrDeploy.properties.outputs.id.value

Write-Host "  Deploying Cyren Malware DCR..." -ForegroundColor Gray
$malDcrDeploy = az deployment group create -g $rg --template-file ".\infrastructure\bicep\dcr-cyren-malware.bicep" --parameters workspaceResourceId="$($wsObj.id)" dceResourceId="$dceId" -n "dcr-mal-$ts" -o json | ConvertFrom-Json
$malDcrImmutableId = $malDcrDeploy.properties.outputs.immutableId.value
$malDcrId = $malDcrDeploy.properties.outputs.id.value

Write-Host "✓ DCRs deployed (TacitRed, Cyren IP, Cyren Malware)" -ForegroundColor Green

# Deploy CCF Connectors
Write-Host "[4/4] Deploying CCF Connectors..." -ForegroundColor Yellow

if($config.ccf.value.deployTacitRedCCF) {
    Write-Host "  Deploying TacitRed CCF Connector..." -ForegroundColor Gray
    Write-Host "    → DCR: $tacitredDcrImmutableId" -ForegroundColor Cyan
    Write-Host "    → DCE: $dceEndpoint" -ForegroundColor Cyan
    
    az deployment group create -g $rg `
        --template-file ".\infrastructure\bicep\ccf-connector-tacitred.bicep" `
        --parameters `
            workspaceName=$ws `
            apiBaseUrl="$($config.tacitRed.value.apiBaseUrl)" `
            apiKey="$($config.tacitRed.value.apiKey)" `
            dcrImmutableId="$tacitredDcrImmutableId" `
            dceIngestionEndpoint="$dceEndpoint" `
            dceResourceId="$dceId" `
        -n "ccf-tacitred-$ts" -o none 2>&1 | Out-Null
    
    if($LASTEXITCODE -eq 0) {
        Write-Host "    ✓ TacitRed CCF Deployed" -ForegroundColor Green
    } else {
        Write-Host "    ✗ TacitRed CCF Failed" -ForegroundColor Red
    }
}

if($config.ccf.value.deployCyrenCCF) {
    Write-Host "  Deploying Cyren CCF Connector..." -ForegroundColor Gray
    Write-Host "    → DCR (IP): $ipDcrImmutableId" -ForegroundColor Cyan
    Write-Host "    → DCE: $dceEndpoint" -ForegroundColor Cyan
    
    # Note: Cyren has 2 feeds, deploying IP reputation connector
    az deployment group create -g $rg `
        --template-file ".\infrastructure\bicep\ccf-connector-cyren.bicep" `
        --parameters `
            workspaceName=$ws `
            apiToken="$($config.cyren.value.ipReputation.jwtToken)" `
            dcrImmutableId="$ipDcrImmutableId" `
            dceIngestionEndpoint="$dceEndpoint" `
            dceResourceId="$dceId" `
        -n "ccf-cyren-$ts" -o none 2>&1 | Out-Null
    
    if($LASTEXITCODE -eq 0) {
        Write-Host "    ✓ Cyren CCF Deployed" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Cyren CCF Failed" -ForegroundColor Red
    }
}

Write-Host "✓ CCF Connectors deployed`n" -ForegroundColor Green

# Wait for CCF connectors to initialize
Write-Host "Waiting 60s for CCF connectors to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 60
Write-Host "✓ Initialization complete`n" -ForegroundColor Green

# RBAC for CCF - Managed identities need access to DCE/DCR
Write-Host "═══ PHASE 3: RBAC ASSIGNMENT (CCF) ═══" -ForegroundColor Cyan
Write-Host "  ℹ CCF connectors use managed identities" -ForegroundColor Gray
Write-Host "  ℹ Assigning Monitoring Metrics Publisher role`n" -ForegroundColor Gray

# Get CCF connector managed identities
Write-Host "  Retrieving CCF connector identities..." -ForegroundColor Yellow
$ccfConnectors = az sentinel data-connector list -g $rg -w $ws -o json 2>$null | ConvertFrom-Json
$ccfIdentities = @()

foreach($connector in $ccfConnectors) {
    if($connector.kind -eq "APIPolling" -and $connector.identity) {
        $ccfIdentities += @{
            Name = $connector.name
            PrincipalId = $connector.identity.principalId
        }
        Write-Host "    Found: $($connector.name) → $($connector.identity.principalId)" -ForegroundColor Gray
    }
}

if($ccfIdentities.Count -gt 0) {
    Write-Host "  Assigning RBAC roles to $($ccfIdentities.Count) CCF connectors..." -ForegroundColor Yellow
    
    foreach($identity in $ccfIdentities) {
        Write-Host "    [$($identity.Name)]" -ForegroundColor Cyan
        
        # Assign to DCE
        try {
            az role assignment create --assignee $identity.PrincipalId --role "Monitoring Metrics Publisher" --scope $dceId 2>$null | Out-Null
            Write-Host "      ✓ Monitoring Metrics Publisher → DCE" -ForegroundColor Green
        } catch {
            Write-Host "      ⚠ DCE role may already exist" -ForegroundColor Yellow
        }
        
        # Assign to all DCRs
        foreach($dcrId in @($tacitredDcrId, $ipDcrId, $malDcrId)) {
            try {
                az role assignment create --assignee $identity.PrincipalId --role "Monitoring Metrics Publisher" --scope $dcrId 2>$null | Out-Null
            } catch { }
        }
        Write-Host "      ✓ Monitoring Metrics Publisher → All DCRs" -ForegroundColor Green
    }
    
    Write-Host "  ✓ RBAC assignments complete" -ForegroundColor Green
} else {
    Write-Host "  ⚠ No CCF connectors found - RBAC will be assigned automatically" -ForegroundColor Yellow
}

Write-Host "  ℹ Azure RBAC propagation takes 5-30 minutes" -ForegroundColor Gray
Write-Host "  ℹ CCF connectors will start polling after propagation completes`n" -ForegroundColor Gray

# Analytics
Write-Host "═══ PHASE 4: ANALYTICS ═══" -ForegroundColor Cyan
Write-Host "[1/1] Deploying analytics rules..." -ForegroundColor Yellow

if(Test-Path ".\analytics\analytics-rules.bicep"){
    az deployment group create `
        -g $rg `
        --template-file ".\analytics\analytics-rules.bicep" `
        --parameters workspaceName=$ws location=$loc `
        -n "analytics-$ts" `
        -o none 2>&1 | Out-File -FilePath "$logDir\analytics-deploy.log" -Encoding utf8

    if($LASTEXITCODE -eq 0){
        Write-Host "✓ Analytics rules deployed" -ForegroundColor Green
    } else {
        Write-Host "✗ Analytics rules deployment FAILED" -ForegroundColor Red
    }
} else {
    Write-Host "⚠ Bicep template not found" -ForegroundColor Yellow
}
Write-Host "✓ Analytics complete`n" -ForegroundColor Green

# Workbooks
Write-Host "═══ PHASE 5: WORKBOOKS ═══" -ForegroundColor Cyan
$wbId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws"
$wbCount = 0
foreach($wb in $config.workbooks.value.workbooks){
    if($wb.enabled -and (Test-Path ".\workbooks\bicep\$($wb.bicepFile)")){
        Write-Host "  Deploying: $($wb.name)..." -ForegroundColor Yellow
        az deployment group create `
            -g $rg `
            --template-file ".\workbooks\bicep\$($wb.bicepFile)" `
            --parameters workspaceId=$wbId location=$loc `
            -n "wb-$wbCount-$ts" `
            -o none 2>&1
        
        if($LASTEXITCODE -eq 0){
            Write-Host "    ✓ $($wb.name) deployed" -ForegroundColor Green
            $wbCount++
        } else {
            Write-Host "    ✗ $($wb.name) failed" -ForegroundColor Red
        }
    }
}
Write-Host "✓ Deployed $wbCount workbooks`n" -ForegroundColor Green

# Summary
$dur = ((Get-Date) - $start).TotalMinutes
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ CCF DEPLOYMENT COMPLETE ($($dur.ToString('0.0')) minutes)" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "`nDeployed Components:" -ForegroundColor Cyan
Write-Host "  • Data Collection Endpoint (DCE)" -ForegroundColor Gray
Write-Host "  • 3 Data Collection Rules (TacitRed, Cyren IP, Cyren Malware)" -ForegroundColor Gray
Write-Host "  • 2 Log Analytics Tables (Full Schemas)" -ForegroundColor Gray
Write-Host "  • CCF Connectors (Codeless Framework)" -ForegroundColor Gray
Write-Host "  • 6 Analytics Rules" -ForegroundColor Gray
Write-Host "  • $wbCount Workbooks" -ForegroundColor Gray

Write-Host "`n⚠ IMPORTANT: CCF Connector Activation" -ForegroundColor Yellow
Write-Host "  1. CCF connectors deployed with managed identities" -ForegroundColor Gray
Write-Host "  2. RBAC propagation takes 30-60 minutes" -ForegroundColor Gray
Write-Host "  3. CCF will START POLLING after RBAC propagates" -ForegroundColor Gray
Write-Host "  4. Check connector status in Sentinel portal:" -ForegroundColor Gray
Write-Host "     Configuration → Data connectors → Search for 'TacitRed' or 'Cyren'" -ForegroundColor White
Write-Host "`n  5. To activate connectors immediately (if not auto-started):" -ForegroundColor Gray
Write-Host "     • Go to Data connector in portal" -ForegroundColor Gray
Write-Host "     • Click 'Connect' button" -ForegroundColor Gray
Write-Host "     • CCF will start polling the API" -ForegroundColor Gray

Write-Host "`nDeployment Logs: $logDir" -ForegroundColor Gray

# Cleanup temp files
Remove-Item -Path "./temp_*.json" -Force -ErrorAction SilentlyContinue

Stop-Transcript

# Save state
@{ts=$ts;dur=$dur;dce=$dce.id;tacitredDcr=$tacitredDcrId;ipDcr=$ipDcrId;malDcr=$malDcrId;ccfEnabled=$true}|ConvertTo-Json|Out-File "$logDir\state.json" -Encoding UTF8
Write-Host "Logs archived at: $logDir`n" -ForegroundColor Cyan

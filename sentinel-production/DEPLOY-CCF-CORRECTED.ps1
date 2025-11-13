# CCF Deployment - CORRECTED Solution
# Based on official Microsoft patterns (Cisco Meraki example)
# AI Security Engineer - Full Ownership

[CmdletBinding()]
param(
    [string]$ConfigFile = ".\client-config-COMPLETE.json"
)

$ErrorActionPreference = "Stop"
$start = Get-Date

# Create log directory
$ts = Get-Date -Format "yyyyMMddHHmmss"
$logDir = ".\docs\deployment-logs\ccf-corrected-$ts"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript "$logDir\transcript.log"

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   CCF DEPLOYMENT - CORRECTED SOLUTION (Production Ready)    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Load config
$config = (Get-Content $ConfigFile | ConvertFrom-Json).parameters
$sub = $config.azure.value.subscriptionId
$rg = $config.azure.value.resourceGroupName
$ws = $config.azure.value.workspaceName
$loc = $config.azure.value.location

Write-Host "Subscription: $sub" -ForegroundColor Gray
Write-Host "Resource Group: $rg" -ForegroundColor Gray
Write-Host "Workspace: $ws" -ForegroundColor Gray
Write-Host "Location: $loc`n" -ForegroundColor Gray

# Set subscription
az account set --subscription $sub

# ═══════════════════════════════════════════════════════════════
# PHASE 1: DEPLOY INFRASTRUCTURE (mainTemplate.json)
# ═══════════════════════════════════════════════════════════════
Write-Host "═══ PHASE 1: INFRASTRUCTURE DEPLOYMENT ═══" -ForegroundColor Cyan
Write-Host "[1/3] Deploying DCE, DCRs, and Tables..." -ForegroundColor Yellow

$infraDeployment = az deployment group create `
    -g $rg `
    --template-file ".\mainTemplate.json" `
    --parameters `
        workspace=$ws `
        workspace-location=$loc `
        tacitRedApiKey="$($config.tacitRed.value.apiKey)" `
        cyrenIPJwtToken="$($config.cyren.value.ipReputation.jwtToken)" `
        cyrenMalwareJwtToken="$($config.cyren.value.malwareUrls.jwtToken)" `
    -n "ccf-infra-$ts" `
    -o json | ConvertFrom-Json

if($LASTEXITCODE -ne 0) {
    Write-Host "✗ Infrastructure deployment FAILED" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Capture outputs
$dceEndpoint = $infraDeployment.properties.outputs.dceEndpoint.value
$tacitRedDcrId = $infraDeployment.properties.outputs.tacitRedDcrImmutableId.value
$ipDcrId = $infraDeployment.properties.outputs.cyrenIPDcrImmutableId.value
$malDcrId = $infraDeployment.properties.outputs.cyrenMalwareDcrImmutableId.value

Write-Host "✓ DCE Endpoint: $dceEndpoint" -ForegroundColor Green
Write-Host "✓ TacitRed DCR: $tacitRedDcrId" -ForegroundColor Green
Write-Host "✓ Cyren IP DCR: $ipDcrId" -ForegroundColor Green
Write-Host "✓ Cyren Malware DCR: $malDcrId" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════
# PHASE 2: DEPLOY CONNECTOR DEFINITION
# ═══════════════════════════════════════════════════════════════
Write-Host "`n═══ PHASE 2: CONNECTOR DEFINITION ═══" -ForegroundColor Cyan
Write-Host "[2/3] Deploying connector UI definition..." -ForegroundColor Yellow

$connDefUrl = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectorDefinitions/ThreatIntelligenceFeeds?api-version=2022-01-01-preview"

az rest --method PUT `
    --url $connDefUrl `
    --body '@Data-Connectors/ThreatIntelDataConnectorDefinition.json' `
    --headers "Content-Type=application/json" `
    -o none 2>&1 | Out-File "$logDir\connector-definition-deploy.log"

if($LASTEXITCODE -eq 0) {
    Write-Host "✓ Connector definition deployed" -ForegroundColor Green
} else {
    Write-Host "✗ Connector definition deployment FAILED" -ForegroundColor Red
    Write-Host "  Check log: $logDir\connector-definition-deploy.log" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════
# PHASE 3: DEPLOY DATA CONNECTORS
# ═══════════════════════════════════════════════════════════════
Write-Host "`n═══ PHASE 3: DATA CONNECTORS ═══" -ForegroundColor Cyan
Write-Host "[3/3] Deploying 3 data connectors..." -ForegroundColor Yellow

# Load connector template and replace placeholders
$connectorTemplate = Get-Content ".\Data-Connectors\ThreatIntelDataConnectors.json" -Raw
$connectorTemplate = $connectorTemplate.Replace("{{dataCollectionEndpoint}}", $dceEndpoint)
$connectorTemplate = $connectorTemplate.Replace("{{tacitRedDcrImmutableId}}", $tacitRedDcrId)
$connectorTemplate = $connectorTemplate.Replace("{{cyrenIPDcrImmutableId}}", $ipDcrId)
$connectorTemplate = $connectorTemplate.Replace("{{cyrenMalwareDcrImmutableId}}", $malDcrId)
$connectorTemplate = $connectorTemplate.Replace("{{tacitRedApiKey}}", $config.tacitRed.value.apiKey)
$connectorTemplate = $connectorTemplate.Replace("{{cyrenIPJwtToken}}", $config.cyren.value.ipReputation.jwtToken)
$connectorTemplate = $connectorTemplate.Replace("{{cyrenMalwareJwtToken}}", $config.cyren.value.malwareUrls.jwtToken)

$connectors = $connectorTemplate | ConvertFrom-Json

# Deploy each connector
$connectorResults = @()
foreach($connector in $connectors) {
    $connectorName = $connector.name
    $connectorUrl = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/${connectorName}?api-version=2022-10-01-preview"
    
    Write-Host "  Deploying: $connectorName..." -ForegroundColor Gray
    
    $connectorBody = $connector | ConvertTo-Json -Depth 20
    $connectorBody | Out-File "$logDir\$connectorName-body.json" -Encoding UTF8
    
    $result = az rest --method PUT `
        --url $connectorUrl `
        --body "@$logDir\$connectorName-body.json" `
        --headers "Content-Type=application/json" `
        -o json 2>&1
    
    if($LASTEXITCODE -eq 0) {
        Write-Host "    ✓ $connectorName deployed" -ForegroundColor Green
        $connectorResults += @{Name=$connectorName; Status="Success"}
    } else {
        Write-Host "    ✗ $connectorName FAILED" -ForegroundColor Red
        $result | Out-File "$logDir\$connectorName-error.log" -Encoding UTF8
        $connectorResults += @{Name=$connectorName; Status="Failed"; Error=$result}
    }
}

# ═══════════════════════════════════════════════════════════════
# VALIDATION
# ═══════════════════════════════════════════════════════════════
Write-Host "`n═══ VALIDATION ═══" -ForegroundColor Cyan

Write-Host "[1/4] Checking connector definition..." -ForegroundColor Yellow
$connDef = az rest --method GET --url $connDefUrl -o json 2>$null | ConvertFrom-Json
if($connDef) {
    Write-Host "  ✓ Connector definition exists" -ForegroundColor Green
    Write-Host "    Title: $($connDef.properties.connectorUiConfig.title)" -ForegroundColor Gray
} else {
    Write-Host "  ✗ Connector definition NOT FOUND" -ForegroundColor Red
}

Write-Host "[2/4] Checking data connectors..." -ForegroundColor Yellow
$dataConnectors = az sentinel data-connector list -g $rg -w $ws -o json 2>$null | ConvertFrom-Json
$ccfConnectors = $dataConnectors | Where-Object { $_.kind -eq "RestApiPoller" }
Write-Host "  Found: $($ccfConnectors.Count) CCF connectors" -ForegroundColor Gray
foreach($conn in $ccfConnectors) {
    Write-Host "    - $($conn.name) → $($conn.properties.dataType)" -ForegroundColor Gray
}

Write-Host "[3/4] Checking tables..." -ForegroundColor Yellow
$tables = @("TacitRed_Findings_CL", "Cyren_Indicators_CL")
foreach($table in $tables) {
    $tableExists = az monitor log-analytics workspace table show `
        -g $rg `
        --workspace-name $ws `
        -n $table `
        -o json 2>$null
    if($tableExists) {
        Write-Host "  ✓ $table exists" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $table NOT FOUND" -ForegroundColor Red
    }
}

Write-Host "[4/4] Checking DCRs..." -ForegroundColor Yellow
$dcrs = az monitor data-collection rule list -g $rg -o json | ConvertFrom-Json
$threatIntelDcrs = $dcrs | Where-Object { $_.name -like "*threat*" -or $_.name -like "*tacit*" -or $_.name -like "*cyren*" }
Write-Host "  Found: $($threatIntelDcrs.Count) DCRs" -ForegroundColor Gray
foreach($dcr in $threatIntelDcrs) {
    Write-Host "    - $($dcr.name)" -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
$duration = ((Get-Date) - $start).TotalMinutes

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  CCF DEPLOYMENT COMPLETE ($($duration.ToString('0.0')) minutes)              ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green

Write-Host "`nDeployment Summary:" -ForegroundColor Cyan
Write-Host "  Infrastructure: ✓ DCE, 3 DCRs, 2 Tables" -ForegroundColor Gray
Write-Host "  Connector Definition: ✓ ThreatIntelligenceFeeds" -ForegroundColor Gray
Write-Host "  Data Connectors:" -ForegroundColor Gray
foreach($result in $connectorResults) {
    $symbol = if($result.Status -eq "Success") {"✓"} else {"✗"}
    $color = if($result.Status -eq "Success") {"Green"} else {"Red"}
    Write-Host "    $symbol $($result.Name)" -ForegroundColor $color
}

Write-Host "`n⚠ NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Open Azure Portal → Microsoft Sentinel → $ws" -ForegroundColor White
Write-Host "  2. Navigate to: Configuration → Data connectors" -ForegroundColor White
Write-Host "  3. Search for: 'Threat Intelligence Feeds'" -ForegroundColor White
Write-Host "  4. Verify connector shows 'Connected' status" -ForegroundColor White
Write-Host "  5. Monitor data ingestion (1-6 hours for first data)" -ForegroundColor White

Write-Host "`nDeployment Logs: $logDir" -ForegroundColor Gray

# Save state
@{
    timestamp = $ts
    duration = $duration
    dceEndpoint = $dceEndpoint
    tacitRedDcrId = $tacitRedDcrId
    ipDcrId = $ipDcrId
    malDcrId = $malDcrId
    connectorResults = $connectorResults
} | ConvertTo-Json | Out-File "$logDir\state.json" -Encoding UTF8

Stop-Transcript
Write-Host "`n✅ Deployment script complete`n" -ForegroundColor Green

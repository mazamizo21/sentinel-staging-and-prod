# Deep Dive Diagnostics - TacitRed CCF vs Logic App Comparison
# Generated: 2025-11-19

$ErrorActionPreference = "Continue"

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     TACITRED CCF DEEP DIVE DIAGNOSTICS                      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Configuration
$ccfRg = "TacitRed-Production-Test-RG"
$ccfWs = "TacitRed-Production-Test-Workspace"
$ccfWorkspaceId = "72e125d2-4f75-4497-a6b5-90241feb387a"

$logicAppRg = "SentinelTestStixImport"
$logicAppWs = "SentinelThreatIntelWorkspace"
$logicAppWorkspaceId = "524ca34b-b412-4189-a236-7fc453c9a88b"

$sub = "774bee0e-b281-4f70-8e40-199e35b65117"

$results = @{}

# ==== SECTION 1: DATA INGESTION STATUS ====
Write-Host "═══ 1. DATA INGESTION STATUS ═══" -ForegroundColor Yellow

Write-Host "`n[CCF Environment]" -ForegroundColor Cyan
$ccfCount = az monitor log-analytics query --workspace $ccfWorkspaceId --analytics-query "TacitRed_Findings_CL | count" -o json | ConvertFrom-Json
$ccfRecords = if ($ccfCount.tables[0].rows) { [int]$ccfCount.tables[0].rows[0][0] } else { 0 }
Write-Host "  Records: $ccfRecords" -ForegroundColor $(if($ccfRecords -gt 0){'Green'}else{'Red'})
$results.ccf_records = $ccfRecords

Write-Host "`n[Logic App Environment]" -ForegroundColor Cyan
$logicAppCount = az monitor log-analytics query --workspace $logicAppWorkspaceId --analytics-query "TacitRed_Findings_CL | count" -o json | ConvertFrom-Json
$logicAppRecords = [int]$logicAppCount.tables[0].rows[0][0]
Write-Host "  Records: $logicAppRecords" -ForegroundColor Green
$results.logicapp_records = $logicAppRecords

# ==== SECTION 2: TABLE SCHEMA COMPARISON ====
Write-Host "`n═══ 2. TABLE SCHEMA VALIDATION ═══" -ForegroundColor Yellow

Write-Host "`n[CCF Table]" -ForegroundColor Cyan
$ccfTable = az monitor log-analytics workspace table show -g $ccfRg --workspace-name $ccfWs --name TacitRed_Findings_CL -o json | ConvertFrom-Json
Write-Host "  Provisioning State: $($ccfTable.properties.provisioningState)" -ForegroundColor Green
Write-Host "  Columns: $($ccfTable.properties.schema.columns.Count)" -ForegroundColor Gray
$results.ccf_table_state = $ccfTable.properties.provisioningState
$results.ccf_table_columns = $ccfTable.properties.schema.columns.Count

Write-Host "`n[Logic App Table]" -ForegroundColor Cyan
$logicAppTable = az monitor log-analytics workspace table show -g $logicAppRg --workspace-name $logicAppWs --name TacitRed_Findings_CL -o json | ConvertFrom-Json
Write-Host "  Provisioning State: $($logicAppTable.properties.provisioningState)" -ForegroundColor Green
Write-Host "  Columns: $($logicAppTable.properties.schema.columns.Count)" -ForegroundColor Gray

# ==== SECTION 3: DCR CONFIGURATION COMPARISON ====
Write-Host "`n═══ 3. DCR CONFIGURATION ═══" -ForegroundColor Yellow

Write-Host "`n[CCF DCR]" -ForegroundColor Cyan
$ccfDcr = az monitor data-collection rule show -g $ccfRg -n dcr-tacitred-findings -o json | ConvertFrom-Json
Write-Host "  Name: $($ccfDcr.name)" -ForegroundColor Gray
Write-Host "  Immutable ID: $($ccfDcr.immutableId)" -ForegroundColor Gray
Write-Host "  State: $($ccfDcr.provisioningState)" -ForegroundColor Green
Write-Host "  Stream Declaration: $($ccfDcr.streamDeclarations.Keys -join ', ')" -ForegroundColor Gray
Write-Host "  Transform KQL:" -ForegroundColor Gray
Write-Host "    $($ccfDcr.dataFlows[0].transformKql)" -ForegroundColor DarkGray
$results.ccf_dcr_id = $ccfDcr.immutableId
$results.ccf_dcr_state = $ccfDcr.provisioningState

Write-Host "`n[Logic App DCR]" -ForegroundColor Cyan
$logicAppDcr = az monitor data-collection rule show -g $logicAppRg -n dcr-tacitred-findings -o json | ConvertFrom-Json
Write-Host "  Name: $($logicAppDcr.name)" -ForegroundColor Gray
Write-Host "  Immutable ID: $($logicAppDcr.immutableId)" -ForegroundColor Gray
Write-Host "  State: $($logicAppDcr.provisioningState)" -ForegroundColor Green
Write-Host "  Stream Declaration: $($logicAppDcr.streamDeclarations.Keys -join ', ')" -ForegroundColor Gray
Write-Host "  Transform KQL:" -ForegroundColor Gray
Write-Host "    $($logicAppDcr.dataFlows[0].transformKql)" -ForegroundColor DarkGray

# ==== SECTION 4: DCE ENDPOINT COMPARISON ====
Write-Host "`n═══ 4. DCE ENDPOINTS ═══" -ForegroundColor Yellow

Write-Host "`n[CCF DCE]" -ForegroundColor Cyan
$ccfDce = az rest --method get --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$ccfRg/providers/Microsoft.Insights/dataCollectionEndpoints/dce-threatintel-feeds?api-version=2022-06-01" | ConvertFrom-Json
Write-Host "  Endpoint: $($ccfDce.properties.logsIngestion.endpoint)" -ForegroundColor Gray
Write-Host "  State: $($ccfDce.properties.provisioningState)" -ForegroundColor Green
$results.ccf_dce_endpoint = $ccfDce.properties.logsIngestion.endpoint

Write-Host "`n[Logic App DCE]" -ForegroundColor Cyan
$logicAppDce = az rest --method get --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$logicAppRg/providers/Microsoft.Insights/dataCollectionEndpoints/dce-sentinel-ti?api-version=2022-06-01" | ConvertFrom-Json
Write-Host "  Endpoint: $($logicAppDce.properties.logsIngestion.endpoint)" -ForegroundColor Gray
Write-Host "  State: $($logicAppDce.properties.provisioningState)" -ForegroundColor Green

# ==== SECTION 5: CCF CONNECTOR CONFIGURATION ====
Write-Host "`n═══ 5. CCF CONNECTOR CONFIGURATION ═══" -ForegroundColor Yellow

$connectorUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$ccfRg/providers/Microsoft.OperationalInsights/workspaces/$ccfWs/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview"
$connector = az rest --method get --uri $connectorUri | ConvertFrom-Json

Write-Host "  Name: $($connector.name)" -ForegroundColor Gray
Write-Host "  Kind: $($connector.kind)" -ForegroundColor Gray
Write-Host "  Is Active: $($connector.properties.isActive)" -ForegroundColor $(if($connector.properties.isActive){'Green'}else{'Red'})
Write-Host "  API Endpoint: $($connector.properties.request.apiEndpoint)" -ForegroundColor Gray
Write-Host "  Query Window: $($connector.properties.request.queryWindowInMin) minutes" -ForegroundColor Gray
Write-Host "  Auth Type: $($connector.properties.auth.type)" -ForegroundColor Gray
Write-Host "  Auth Header: $($connector.properties.auth.apiKeyName)" -ForegroundColor Gray
Write-Host "  DCR Immutable ID: $($connector.properties.dcrConfig.dataCollectionRuleImmutableId)" -ForegroundColor Gray
Write-Host "  DCE Endpoint: $($connector.properties.dcrConfig.dataCollectionEndpoint)" -ForegroundColor Gray
Write-Host "  Stream Name: $($connector.properties.dcrConfig.streamName)" -ForegroundColor Gray
Write-Host "  Query Parameters:" -ForegroundColor Gray
$connector.properties.request.queryParameters.PSObject.Properties | ForEach-Object {
    Write-Host "    $($_.Name): $($_.Value)" -ForegroundColor DarkGray
}

$results.ccf_connector_active = $connector.properties.isActive
$results.ccf_connector_endpoint = $connector.properties.request.apiEndpoint
$results.ccf_connector_window = $connector.properties.request.queryWindowInMin

# ==== SECTION 6: LOGIC APP CONFIGURATION ====
Write-Host "`n═══ 6. LOGIC APP CONFIGURATION ═══" -ForegroundColor Yellow

$logicAppUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$logicAppRg/providers/Microsoft.Logic/workflows/logic-tacitred-ingestion?api-version=2019-05-01"
$logicApp = az rest --method get --uri $logicAppUri | ConvertFrom-Json

Write-Host "  Name: $($logicApp.name)" -ForegroundColor Gray
Write-Host "  State: $($logicApp.properties.state)" -ForegroundColor Green
Write-Host "  Identity: $($logicApp.identity.type)" -ForegroundColor Gray
Write-Host "  Principal ID: $($logicApp.identity.principalId)" -ForegroundColor Gray

# Extract API call details from Logic App definition
$apiCall = $logicApp.properties.definition.actions.Call_TacitRed_API
Write-Host "`n  API Call Configuration:" -ForegroundColor Cyan
Write-Host "    URI Template: $($apiCall.inputs.uri)" -ForegroundColor DarkGray
Write-Host "    Method: $($apiCall.inputs.method)" -ForegroundColor DarkGray
Write-Host "    Auth Header: $($apiCall.inputs.headers.Authorization)" -ForegroundColor DarkGray

# ==== SECTION 7: STREAM DECLARATION COMPARISON ====
Write-Host "`n═══ 7. STREAM DECLARATION COMPARISON ═══" -ForegroundColor Yellow

Write-Host "`n[CCF DCR Stream]" -ForegroundColor Cyan
$ccfStream = $ccfDcr.streamDeclarations.'Custom-TacitRed_Findings_CL'
Write-Host "  Columns: $($ccfStream.columns.Count)" -ForegroundColor Gray
Write-Host "  Column Names:" -ForegroundColor Gray
$ccfStream.columns.name | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }

Write-Host "`n[Logic App DCR Stream]" -ForegroundColor Cyan  
$logicAppStream = $logicAppDcr.streamDeclarations.'Custom-TacitRed_Findings_Raw'
Write-Host "  Stream Name: Custom-TacitRed_Findings_Raw" -ForegroundColor Gray
Write-Host "  Columns: $($logicAppStream.columns.Count)" -ForegroundColor Gray
Write-Host "  Column Names:" -ForegroundColor Gray
$logicAppStream.columns.name | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }

# ==== SECTION 8: CRITICAL DIFFERENCES ====
Write-Host "`n═══ 8. CRITICAL DIFFERENCES IDENTIFIED ═══" -ForegroundColor Red

$differences = @()

# Stream name difference
if ($ccfDcr.streamDeclarations.Keys -ne $logicAppDcr.streamDeclarations.Keys) {
    $diff = "⚠️  STREAM NAME MISMATCH:`n" +
            "   CCF DCR uses: $($ccfDcr.streamDeclarations.Keys -join ', ')`n" +
            "   Logic App DCR uses: $($logicAppDcr.streamDeclarations.Keys -join ', ')`n" +
            "   CCF Connector references: $($connector.properties.dcrConfig.streamName)"
    $differences += $diff
    Write-Host $diff -ForegroundColor Yellow
}

# Check if stream columns match
$ccfStreamCols = $ccfStream.columns.name | Sort-Object
$logicAppStreamCols = $logicAppStream.columns.name | Sort-Object
$colDiff = Compare-Object $ccfStreamCols $logicAppStreamCols
if ($colDiff) {
    $diff = "⚠️  STREAM COLUMN MISMATCH:`n" +
            "   Columns differ between CCF and Logic App DCR streams"
    $differences += $diff
    Write-Host $diff -ForegroundColor Yellow
    $colDiff | ForEach-Object {
        Write-Host "    $($_.InputObject) - $($_.SideIndicator)" -ForegroundColor Gray
    }
}

# Transform KQL differences
if ($ccfDcr.dataFlows[0].transformKql -ne $logicAppDcr.dataFlows[0].transformKql) {
    $diff = "⚠️  TRANSFORM KQL DIFFERS between CCF and Logic App DCR"
    $differences += $diff
    Write-Host $diff -ForegroundColor Yellow
}

# ==== SECTION 9: DIAGNOSTIC QUERIES ====
Write-Host "`n═══ 9. DIAGNOSTIC QUERIES ═══" -ForegroundColor Yellow

Write-Host "`n[Checking for DCR Errors in CCF Environment]" -ForegroundColor Cyan
$dcrErrors = az monitor log-analytics query --workspace $ccfWorkspaceId --analytics-query "AzureDiagnostics | where TimeGenerated > ago(2h) | where ResourceType == 'DATACOLLECTIONRULES' or Category contains 'DataCollection' | project TimeGenerated, Category, OperationName, ResultDescription" -o json | ConvertFrom-Json

if ($dcrErrors.tables[0].rows.Count -gt 0) {
    Write-Host "  Found $($dcrErrors.tables[0].rows.Count) DCR diagnostic entries" -ForegroundColor Yellow
    $dcrErrors.tables[0].rows | ForEach-Object {
        $msg = "    $($_[0]) - $($_[1]) - $($_[2]) - $($_[3])"
        Write-Host $msg -ForegroundColor DarkGray
    }
} else {
    Write-Host "  No DCR diagnostic entries found" -ForegroundColor Gray
}

# ==== SUMMARY ====
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     DIAGNOSIS SUMMARY                                        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "CCF Records: $($results.ccf_records)" -ForegroundColor $(if($results.ccf_records -gt 0){'Green'}else{'Red'})
Write-Host "Logic App Records: $($results.logicapp_records)" -ForegroundColor Green
Write-Host "CCF Connector Active: $($results.ccf_connector_active)" -ForegroundColor $(if($results.ccf_connector_active){'Green'}else{'Red'})
Write-Host "Critical Differences Found: $($differences.Count)" -ForegroundColor $(if($differences.Count -gt 0){'Yellow'}else{'Green'})

if ($differences.Count -gt 0) {
    Write-Host "`nCRITICAL ISSUES TO INVESTIGATE:" -ForegroundColor Red
    $differences | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
}

# Save results
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$outputFile = "..\Project\Docs\Validation\TacitRed\deep-dive-diagnostics-$timestamp.json"
$results | ConvertTo-Json -Depth 10 | Out-File $outputFile -Encoding UTF8
Write-Host "`nDiagnostics saved to: $outputFile" -ForegroundColor Cyan

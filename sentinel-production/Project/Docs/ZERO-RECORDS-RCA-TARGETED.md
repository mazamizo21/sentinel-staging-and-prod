# Zero Records RCA - Targeted Analysis

**Date:** 2025-11-14  
**Incident:** 0 records in Log Analytics tables after 2+ hours  
**Status:** Investigation in progress

---

## CRITICAL FINDING FROM TACITRED DEEP DIVE

### ⚠️ TacitRed Architecture Confusion

**From my complete code analysis:**

**TacitRed uses CCF RestApiPoller (ARM-native), NOT Logic Apps**

Evidence from mainTemplate.json:
- **Lines 589-644:** TacitRed connector is type `RestApiPoller` (CCF)
- **Line 619:** `queryWindowInMin: 60` (polls every 60 minutes)
- **Line 614:** API endpoint `https://app.tacitred.com/api/v1/findings`
- **Line 609-611:** Auth type `APIKey` with `Authorization` header
- **Line 453:** Deployment script is **DISABLED** (`condition: false`)

**Key Implications:**
1. There should be NO "logic-tacitred-findings" Logic App for TacitRed
2. TacitRed ingestion is handled entirely by CCF (ARM resource type: `Microsoft.OperationalInsights/workspaces/providers/dataConnectors`)
3. First data expected 60-120 minutes after deployment (not immediate)

**From Retrieved Memory:**
> "Created a TacitRed test DCR and test table path (TacitRed_Findings_Test_CL) and temporarily rewired the TacitRedFindings connector to that DCR/stream with queryWindowInMin=1 for rapid testing."

> "IMPORTANT FOR PRODUCTION/PACKAGING: Before compiling the Content Hub package or going to production, revert TacitRedFindings back to the original table and DCR stream (TacitRed_Findings_CL / Custom-TacitRed_Findings_CL and production DCR immutableId) and restore a production-safe queryWindowInMin (e.g. 60 minutes)."

### 🔴 CRITICAL QUESTION #1: Which Table Configuration is Active?

**Need to verify:**
```kql
// Check if test table exists and has data
TacitRed_Findings_Test_CL
| where TimeGenerated > ago(3h)
| summarize Count = count()

// Check if production table exists and has data
TacitRed_Findings_CL
| where TimeGenerated > ago(3h)
| summarize Count = count()
```

**Possible scenarios:**
1. **Connector still pointed at test table** (TacitRed_Findings_Test_CL)
2. **Connector reverted to production table** (TacitRed_Findings_CL)
3. **Connector misconfigured** (wrong DCR/DCE/stream)

---

## TACITRED ROOT CAUSE ANALYSIS

### Scenario A: Test Configuration Still Active
**If connector is using TacitRed_Findings_Test_CL:**
- queryWindowInMin = 1 (polls every minute)
- Should see data quickly if API has data
- **But:** Your direct API test showed ResultCount=0

**Diagnosis:** Legitimate upstream data absence, not ingestion failure

### Scenario B: Production Configuration Active
**If connector is using TacitRed_Findings_CL:**
- queryWindowInMin = 60 (polls every hour)
- First poll: 0-60 minutes after deployment
- Data appears: 60-120 minutes after deployment
- **After 2 hours:** Should see at least 1-2 polling cycles

**Your API Test Results:**
- HTTP 200 (auth valid ✓)
- ResultCount = 0 (no data in 5-minute window)

**Diagnosis:** API has no data for the queried time ranges

### Scenario C: Connector Misconfigured
**Symptoms:**
- CCF connector exists but dcrConfig is null/missing
- DCR/DCE endpoints incorrect
- Stream name mismatch
- Table name mismatch

**Need to check:**
```powershell
# Get TacitRedFindings connector configuration
$sub = "<subscription-id>"
$rg = "<resource-group>"
$ws = "<workspace-name>"

$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"

az rest --method GET --uri $uri | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

**Look for:**
- `properties.dcrConfig.dataCollectionRuleImmutableId` (must match dcr-tacitred-findings immutableId)
- `properties.dcrConfig.streamName` (should be `Custom-TacitRed_Findings_CL`)
- `properties.dataType` (should be `TacitRed_Findings_CL`)
- `properties.request.queryWindowInMin` (1 for test, 60 for prod)

---

## CYREN ROOT CAUSE ANALYSIS

### Architecture Clarification Needed

**From diagnostic script (lines 315-319):**
```powershell
$logicApps = @(
    @{Name='logic-tacitred-findings'; Type='TacitRed'},  # ← SHOULD NOT EXIST for CCF TacitRed
    @{Name='logicapp-cyren-ip-reputation'; Type='Cyren'},
    @{Name='logicapp-cyren-malware-urls'; Type='Cyren'}
)
```

**Questions:**
1. Are Cyren connectors using CCF or Logic Apps?
2. If CCF: Are CyrenIPReputation and CyrenMalwareURLs connectors configured?
3. If Logic Apps: Are they successfully POSTing to DCE?

### Cyren CCF Connectors (if CCF approach)
**From diagnostic script (lines 500-504):**
```powershell
$ccfConnectors = @(
    @{Name='TacitRedFindings'; Type='TacitRed'},
    @{Name='CyrenIPReputation'; Type='Cyren'},
    @{Name='CyrenMalwareURLs'; Type='Cyren'}
)
```

**Known Issues from Status Report:**
- Previous CCF deployment failed with `ResourceNotFound workspace placeholder`
- CCF connectors had `dcrConfig` missing
- This indicates **incomplete deployment**

### Cyren API Validation Gap

**From Status Report:**
> "Manual Cyren API test previously failed with Invalid URI: The hostname could not be parsed – that was a bug in the test script, so we still do not yet have a clean, confirmed Cyren API call with the JWT."

**Critical:** No confirmed successful Cyren API call with actual data

**Need:**
1. Clean Cyren IP Reputation API test with JWT
2. Clean Cyren Malware URLs API test with JWT
3. Verify both return HTTP 200 and ResultCount > 0

---

## EXPECTED vs. ACTUAL TABLE STATUS

### Expected Tables (Based on Architecture)

| Table Name | Feed Type | Connector Type | Expected Data Latency |
|------------|-----------|----------------|----------------------|
| TacitRed_Findings_CL | Production | CCF RestApiPoller | 60-120 min (queryWindowInMin=60) |
| TacitRed_Findings_Test_CL | Test | CCF RestApiPoller (if configured) | 1-5 min (queryWindowInMin=1) |
| Cyren_IpReputation_CL | Production | CCF or Logic App | Depends on method |
| Cyren_MalwareUrls_CL | Production | CCF or Logic App | Depends on method |
| Cyren_Indicators_CL | Legacy? | Unknown | May be old table name |

**Need to determine:**
1. Which tables actually exist?
2. Which are being actively written to?
3. Which connectors/Logic Apps are targeting which tables?

---

## DIAGNOSTIC ACTION PLAN

### Step 1: Identify Active Tables
```kql
search *
| where TimeGenerated > ago(3h)
| where $table matches regex "(?i)(tacitred|cyren)"
| summarize Count = count(), 
    Latest = max(TimeGenerated),
    Earliest = min(TimeGenerated)
  by $table
| order by Latest desc
```

### Step 2: Check TacitRed CCF Connector Configuration
```powershell
# Get full connector config
$sub = "<sub-id>"
$rg = "<rg-name>"
$ws = "<ws-name>"

$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"

$connector = az rest --method GET --uri $uri | ConvertFrom-Json

Write-Host "Connector Name: $($connector.name)"
Write-Host "Kind: $($connector.kind)"
Write-Host "Data Type: $($connector.properties.dataType)"

# Critical: Check DCR config
if($connector.properties.dcrConfig){
    Write-Host "DCR Config EXISTS:"
    Write-Host "  DCR ID: $($connector.properties.dcrConfig.dataCollectionRuleImmutableId)"
    Write-Host "  DCE: $($connector.properties.dcrConfig.dataCollectionEndpoint)"
    Write-Host "  Stream: $($connector.properties.dcrConfig.streamName)"
} else {
    Write-Host "WARNING: No dcrConfig found!" -ForegroundColor Red
}

# Check polling configuration
Write-Host "Query Window: $($connector.properties.request.queryWindowInMin) minutes"
Write-Host "API Endpoint: $($connector.properties.request.apiEndpoint)"
```

### Step 3: Verify DCR Configuration Matches Connector
```powershell
# Get DCR details
$dcrName = "dcr-tacitred-findings"
$dcrInfo = az monitor data-collection rule show -g $rg -n $dcrName | ConvertFrom-Json

Write-Host "DCR Name: $dcrName"
Write-Host "DCR Immutable ID: $($dcrInfo.properties.immutableId)"
Write-Host "Stream Declarations:"
$dcrInfo.properties.streamDeclarations.PSObject.Properties | ForEach-Object {
    Write-Host "  - $($_.Name)"
}

Write-Host "`nData Flows:"
$dcrInfo.properties.dataFlows | ForEach-Object {
    Write-Host "  Input Stream: $($_.streams -join ', ')"
    Write-Host "  Output Stream: $($_.outputStream)"
    Write-Host "  Transform: $($_.transformKql)"
}
```

### Step 4: Check Cyren Architecture
```powershell
# Determine if Cyren is using CCF or Logic Apps

# Check for CCF connectors
$cyrenCCF = @('CyrenIPReputation', 'CyrenMalwareURLs')
foreach($name in $cyrenCCF){
    $uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/$name?api-version=2024-09-01"
    try {
        $conn = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json
        if($conn){
            Write-Host "✓ CCF Connector $name exists"
        }
    } catch {
        Write-Host "✗ CCF Connector $name not found"
    }
}

# Check for Logic Apps
$cyrenLogicApps = @('logicapp-cyren-ip-reputation', 'logicapp-cyren-malware-urls')
foreach($name in $cyrenLogicApps){
    try {
        $la = az logic workflow show -g $rg -n $name 2>$null | ConvertFrom-Json
        if($la){
            Write-Host "✓ Logic App $name exists (State: $($la.properties.state))"
        }
    } catch {
        Write-Host "✗ Logic App $name not found"
    }
}
```

### Step 5: Test APIs with Actual Data Retrieval
```powershell
# TacitRed API - Extended time range
$tacitRedKey = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "tacitred-api-key" --query "value" -o tsv
$headers = @{
    'Authorization' = "Bearer $tacitRedKey"
    'Accept' = 'application/json'
}

# Test last 24 hours
$endTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$startTime = (Get-Date).AddHours(-24).ToString("yyyy-MM-ddTHH:mm:ssZ")
$uri = "https://app.tacitred.com/api/v1/findings?from=$startTime&until=$endTime&page_size=100"

$response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
Write-Host "TacitRed API (24h window):"
Write-Host "  Results: $($response.results.Count)"
Write-Host "  Total Count: $($response | Select-Object -ExpandProperty totalCount -ErrorAction SilentlyContinue)"

# Cyren IP Reputation API
$cyrenIPJWT = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "cyren-ip-jwt-token" --query "value" -o tsv
$headers = @{
    'Authorization' = "Bearer $cyrenIPJWT"
    'Accept' = 'application/json'
}

$uri = "https://api-feeds.cyren.com/v1/feed/data?feedId=ip_reputation&offset=0&count=100&format=jsonl"
$response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
Write-Host "Cyren IP API:"
Write-Host "  Records: $($response.Count)"

# Cyren Malware URLs API
$cyrenMalwareJWT = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "cyren-malware-jwt-token" --query "value" -o tsv
$headers = @{
    'Authorization' = "Bearer $cyrenMalwareJWT"
    'Accept' = 'application/json'
}

$uri = "https://api-feeds.cyren.com/v1/feed/data?feedId=malware_urls&offset=0&count=100&format=jsonl"
$response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
Write-Host "Cyren Malware API:"
Write-Host "  Records: $($response.Count)"
```

---

## IMMEDIATE NEXT STEPS

### Priority 1: Clarify TacitRed Configuration
1. Run diagnostic script: `.\DIAGNOSE-ZERO-RECORDS.ps1 -Detailed -TestAPIs`
2. Check which table (test vs production) the connector is targeting
3. Verify queryWindowInMin setting (1 vs 60)
4. If test config: Revert to production before packaging
5. If production config + no API data: This is expected behavior (upstream has no data)

### Priority 2: Clarify Cyren Architecture
1. Determine if Cyren is CCF or Logic App-based
2. If CCF: Check dcrConfig presence
3. If Logic Apps: Check latest run status and Send_to_DCE action
4. Verify Cyren API actually returns data (not tested cleanly yet)

### Priority 3: API Data Validation
1. Extend TacitRed API test time range to 24 hours or 7 days
2. Perform clean Cyren API tests with valid JWTs
3. Confirm if feeds have actual data or are legitimately empty

---

## DECISION TREE

```
Is TacitRed CCF connector configured?
├─ YES → Check dcrConfig
│   ├─ dcrConfig present and correct?
│   │   ├─ YES → Check queryWindowInMin
│   │   │   ├─ queryWindowInMin = 1 (test mode)?
│   │   │   │   ├─ YES → Data should appear in 1-5 min IF API has data
│   │   │   │   │         → Your API test showed 0 results
│   │   │   │   │         → DIAGNOSIS: Legitimate upstream data absence
│   │   │   │   └─ NO → queryWindowInMin = 60 (production)?
│   │   │   │             → Data appears in 60-120 min IF API has data
│   │   │   │             → After 2 hours: Should see data
│   │   │   │             → DIAGNOSIS: Check API for longer time range
│   │   │   └─ Polling interval incorrect?
│   │   │                 → DIAGNOSIS: Configuration error
│   │   └─ NO → dcrConfig missing?
│   │             → DIAGNOSIS: Broken CCF deployment (previous known issue)
│   │             → ACTION: Redeploy CCF connector with correct dcrConfig
│   └─ Connector not found?
│                 → DIAGNOSIS: CCF not deployed
│                 → ACTION: Deploy CCF connector via ARM template
└─ NO → Check for Logic Apps
          └─ "logic-tacitred-findings" exists?
                ├─ YES → This is incorrect! TacitRed should use CCF, not Logic App
                │         → ACTION: Delete Logic App, deploy CCF connector
                └─ NO → No ingestion method deployed
                          → ACTION: Deploy TacitRed CCF connector
```

---

## SUMMARY OF UNKNOWNS

### TacitRed
- [ ] Which table is the CCF connector targeting? (Test vs Production)
- [ ] What is the current queryWindowInMin setting?
- [ ] Is dcrConfig properly configured with correct DCR immutableId?
- [ ] Does TacitRed API have data in longer time ranges (e.g., last 7 days)?

### Cyren
- [ ] Are Cyren connectors using CCF or Logic Apps?
- [ ] If CCF: Is dcrConfig present and correct?
- [ ] If Logic Apps: Are they successfully POST ing to DCE?
- [ ] Do Cyren APIs return actual data with the JWT tokens?
- [ ] Which Cyren table names are correct? (Cyren_IpReputation_CL, Cyren_MalwareUrls_CL, or Cyren_Indicators_CL?)

---

**Next Action:** Run `.\DIAGNOSE-ZERO-RECORDS.ps1 -Detailed -TestAPIs` to get concrete answers to these questions.

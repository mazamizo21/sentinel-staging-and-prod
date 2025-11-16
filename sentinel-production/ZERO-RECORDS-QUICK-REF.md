# Zero Records - Quick Reference Card

**Time Since Deployment:** 2+ hours  
**Issue:** 0 records in Log Analytics tables

---

## 🔴 CRITICAL DISCOVERY

### TacitRed Uses CCF (NOT Logic Apps)

From my complete code analysis of `mainTemplate.json`:

**TacitRed Connector:**
- **Type:** CCF RestApiPoller (lines 589-644)
- **Polling:** Every 60 minutes (line 619: `queryWindowInMin: 60`)
- **Expected First Data:** 60-120 minutes after deployment
- **Auth:** API Key in Authorization header (lines 609-611)
- **Endpoint:** https://app.tacitred.com/api/v1/findings (line 614)

**There should be NO "logic-tacitred-findings" Logic App for TacitRed.**

---

## ⚠️ TEST vs. PRODUCTION CONFIGURATION

**From Retrieved Memory:**
> TacitRed was temporarily rewired to test table `TacitRed_Findings_Test_CL` with `queryWindowInMin=1` for rapid testing.
> 
> **MUST REVERT to production before packaging:**
> - Table: `TacitRed_Findings_CL`
> - Stream: `Custom-TacitRed_Findings_CL`
> - Polling: `queryWindowInMin=60`

---

## 🎯 IMMEDIATE ACTIONS

### 1. Run Diagnostic Script
```powershell
cd d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production
.\DIAGNOSE-ZERO-RECORDS.ps1 -Detailed -TestAPIs
```

**This will check:**
- Which tables exist and have data
- TacitRed CCF connector configuration
- Cyren connector configuration (CCF or Logic Apps)
- API connectivity and data availability
- DCR/DCE configuration

### 2. Check TacitRed CCF Connector Config
```powershell
# Replace with your values
$sub = "your-subscription-id"
$rg = "your-resource-group"
$ws = "your-workspace-name"

$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"

$connector = az rest --method GET --uri $uri | ConvertFrom-Json

# Check critical fields
Write-Host "Data Type: $($connector.properties.dataType)"
Write-Host "Query Window: $($connector.properties.request.queryWindowInMin) minutes"
Write-Host "Has DCR Config: $($null -ne $connector.properties.dcrConfig)"

if($connector.properties.dcrConfig){
    Write-Host "Stream Name: $($connector.properties.dcrConfig.streamName)"
    Write-Host "DCR ID: $($connector.properties.dcrConfig.dataCollectionRuleImmutableId)"
}
```

**Expected Values:**
- dataType: `TacitRed_Findings_CL` (production) or `TacitRed_Findings_Test_CL` (test)
- queryWindowInMin: `60` (production) or `1` (test)
- streamName: `Custom-TacitRed_Findings_CL`
- dcrConfig: **Must exist and have valid DCR immutableId**

### 3. Test TacitRed API with Extended Time Range
```powershell
$tacitRedKey = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "tacitred-api-key" --query "value" -o tsv

$headers = @{
    'Authorization' = "Bearer $tacitRedKey"
    'Accept' = 'application/json'
}

# Test last 7 days (more likely to have data)
$endTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$startTime = (Get-Date).AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ")
$uri = "https://app.tacitred.com/api/v1/findings?from=$startTime&until=$endTime&page_size=100"

$response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers

Write-Host "TacitRed API (7-day window):"
Write-Host "Status: $($response.status)"
Write-Host "Result Count: $($response.results.Count)"

if($response.results.Count -gt 0){
    Write-Host "`nSample Finding:"
    $response.results[0] | ConvertTo-Json -Depth 3
}
```

---

## 📊 DIAGNOSIS SCENARIOS

### Scenario A: Test Configuration Active
**Symptoms:**
- dataType = `TacitRed_Findings_Test_CL`
- queryWindowInMin = 1

**Expected Behavior:**
- Polls every 1 minute
- Data should appear within 1-5 minutes IF API has data

**Your Observation:**
- 2+ hours, 0 records
- Direct API test (5-min window) returned 0 results

**Diagnosis:** ✅ **Legitimate upstream data absence** (not a technical failure)

### Scenario B: Production Configuration Active
**Symptoms:**
- dataType = `TacitRed_Findings_CL`
- queryWindowInMin = 60

**Expected Behavior:**
- Polls every 60 minutes
- First poll: 0-60 min after deployment
- Data appears: 60-120 min after deployment

**Your Observation:**
- 2+ hours elapsed
- Should have seen 1-2 polling cycles

**Diagnosis:**
- If API test (7-day window) returns 0: ✅ **Upstream has no data**
- If API test (7-day window) returns >0: 🔴 **Connector misconfiguration or ingestion failure**

### Scenario C: Connector Misconfigured
**Symptoms:**
- dcrConfig is null or missing
- DCR immutableId doesn't match actual DCR
- Stream name is wrong
- DCE endpoint is wrong

**Expected Behavior:**
- Connector will fail silently or error during ingestion
- No data will appear in any table

**Diagnosis:** 🔴 **Broken CCF deployment** (matches previous Cyren CCF issue: "ResourceNotFound workspace placeholder")

**Action:** Redeploy CCF connector with correct ARM template

---

## 🔍 KEY QUESTIONS TO ANSWER

1. **Is TacitRed CCF connector using test or production table?**
   - Check `properties.dataType` field

2. **Is dcrConfig present and correct?**
   - Must have: dataCollectionRuleImmutableId, dataCollectionEndpoint, streamName

3. **Does TacitRed API have data in longer time ranges?**
   - Test with 7-day or 30-day window

4. **Is Cyren using CCF or Logic Apps?**
   - Check for CCF connectors: CyrenIPReputation, CyrenMalwareURLs
   - Check for Logic Apps: logicapp-cyren-ip-reputation, logicapp-cyren-malware-urls

5. **Do Cyren APIs return actual data?**
   - Need clean API test with JWT (previous test had script bug)

---

## 🚨 RED FLAGS

### TacitRed
- ❌ Logic App "logic-tacitred-findings" should NOT exist
- ❌ dcrConfig missing from CCF connector
- ❌ queryWindowInMin still set to 1 (test mode)
- ❌ dataType pointing to test table instead of production

### Cyren
- ❌ CCF connectors exist but dcrConfig is missing (previous known issue)
- ❌ No confirmed successful API call with actual data returned
- ❌ ARM deployment failed with "ResourceNotFound workspace placeholder"

---

## ✅ GREEN FLAGS

### What's Working
- ✅ Key Vault integration (secrets accessible)
- ✅ TacitRed API authentication (HTTP 200)
- ✅ DCE and DCRs deployed correctly
- ✅ Logic Apps (if used for Cyren) can POST to DCE without NotFound

---

## 📌 EXPECTED TIMELINE

**TacitRed Production Mode (queryWindowInMin=60):**
```
T+0:   Deployment complete
T+15:  First poll window opens (may poll anytime between T+0 and T+60)
T+60:  First poll should have occurred
T+90:  Data should be visible in Log Analytics (30-min ingestion lag)
T+120: Second poll should have occurred
T+150: Second batch of data visible

After 2 hours: Should see 1-2 batches of data (if API has data)
```

**TacitRed Test Mode (queryWindowInMin=1):**
```
T+0:   Deployment complete
T+1:   First poll
T+2:   Data should be visible
T+5:   5 batches of data should be present

After 2 hours: Should see 120 batches of data (if API has data)
```

---

## 🎯 NEXT STEPS

1. **Run diagnostic script** to get concrete data
2. **Check CCF connector configuration** (especially dcrConfig)
3. **Test API with extended time range** (7 days instead of 5 minutes)
4. **Verify test vs. production configuration**
5. **If test mode:** Revert to production before packaging
6. **If no upstream data:** Document as expected behavior
7. **If connector misconfigured:** Redeploy with correct DCR/DCE/stream settings

---

**Status:** Investigation in progress  
**Next Action:** Run diagnostic script with `-Detailed -TestAPIs` flags

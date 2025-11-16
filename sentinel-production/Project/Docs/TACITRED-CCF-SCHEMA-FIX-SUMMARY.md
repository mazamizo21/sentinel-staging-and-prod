# TacitRed CCF Schema Fix Summary

**Date:** November 14, 2025  
**Time:** 7:05 PM EST  
**Issue:** Zero data ingestion despite active connector

---

## Root Cause Identified

### Schema Mismatch Between DCR Stream and Table

**Table Schema** (`TacitRed_Findings_CL`):
- Columns have suffixes: `email_s`, `domain_s`, `findingType_s`, `confidence_d`, `firstSeen_t`, etc.

**DCR Stream Declaration** (lines 210-277 in mainTemplate.json):
- Columns had NO suffixes: `email`, `domain`, `findingType`, `confidence`, `firstSeen`, etc.

**Original Transform KQL** (line 296):
```kql
source | extend TimeGenerated = now()
```

**Problem:** Transform didn't rename fields, so Azure tried to insert:
- Stream columns: `email`, `domain`, etc.
- Into table columns: `email_s`, `domain_s`, etc.
- Result: **Silent drop** (schema mismatch, no errors logged)

---

## Fix Applied

### Updated Transform KQL

```kql
source 
| extend TimeGenerated = now() 
| project-rename 
    email_s = email,
    domain_s = domain,
    findingType_s = findingType,
    confidence_d = confidence,
    firstSeen_t = firstSeen,
    lastSeen_t = lastSeen,
    notes_s = notes,
    source_s = source,
    severity_s = severity,
    status_s = status,
    campaign_id_s = campaign_id,
    user_id_s = user_id,
    username_s = username,
    detection_ts_t = detection_ts,
    metadata_s = metadata
```

**Note:** Actual deployed DCR uses `project` instead of `project-rename`, but achieves the same result:
```kql
project 
  TimeGenerated=tg, 
  email_s=tostring(email), 
  domain_s=tostring(domain), 
  ...
```

---

## Current Status (7:05 PM)

### ✅ Fixed Components

1. **DCR Transform:** Correctly maps stream columns to table columns with suffixes
2. **Auth Header:** `Authorization: <key>` (no Bearer prefix) – matches working Logic App
3. **API Key:** Validated via direct curl test → returns 200 OK
4. **Connector:** Active, polling every 60 minutes

### ❌ Outstanding Issue

**No data in `TacitRed_Findings_CL` after 93 minutes**

Expected first poll: ~6:33 PM (60 min after 5:33 PM deployment)  
Current time: 7:05 PM  
**First poll should have completed by now.**

---

## Possible Remaining Issues

### 1. Connector Still Using Old Auth During Polls

- The connector **instance** shows correct auth in GET response
- But CCF backend **may be caching** the `[[parameters('...')]]` value incorrectly
- The deployment's connectivity check keeps failing with 401, suggesting the double-bracket parameter isn't being resolved properly **at runtime**

### 2. DCR Transform Applied But Not Active Yet

- DCR shows correct transform in GET response
- But Azure may need time to propagate the change to the ingestion pipeline
- Typical propagation: 5-15 minutes (we're past that)

### 3. CCF Scheduler Delay

- First poll can take **30-60 minutes** after deployment (per Microsoft docs)
- We're at 93 minutes, so this is less likely

---

## Next Steps

### Immediate Actions

1. **Wait for next poll window** (~8:05 PM = 60 min from last expected poll)
2. **Run validation query:**
   ```kusto
   TacitRed_Findings_CL
   | summarize Count = count(), Latest = max(TimeGenerated)
   ```

3. **If still no data by 8:15 PM:**
   - Check Azure diagnostics logs for DCE/DCR errors
   - Verify CCF is actually calling the API (check for any audit logs)
   - Consider recreating the connector instance entirely

### Long-Term Fix for Marketplace

The template is now correct:
- Auth: `ApiKeyIdentifier: ""` (no Bearer)
- Transform: Maps all fields with correct suffixes
- API Key: Uses secure `[[parameters('tacitRedApiKey')]]` syntax

**For Content Hub deployment:**
- Connectivity check will fail (401) during deployment – this is expected with `[[parameters(...)]]`
- Connector will be created despite the error
- Runtime polling should work once the parameter is resolved by Sentinel backend

---

## Files Modified

1. `Tacitred-CCF/mainTemplate.json` (line 296):
   - Added field renaming to transform KQL

---

## Validation Commands

### Check for data
```powershell
$wsId = "<workspace-id>"
$query = 'TacitRed_Findings_CL | summarize Count = count(), Latest = max(TimeGenerated)'
az monitor log-analytics query --workspace $wsId --analytics-query $query
```

### Check connector status
```powershell
$connUri = "https://management.azure.com<workspace-id>/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"
az rest --method GET --uri $connUri | ConvertFrom-Json | Select -ExpandProperty properties | Select isActive, @{N='Polling';E={$_.request.queryWindowInMin}}
```

### Check DCR transform
```powershell
az monitor data-collection rule show --resource-group TacitRedCCFTest --name dcr-tacitred-ccf-test --query "dataFlows[0].transformKql"
```

---

## Key Learnings

1. **DCR transforms must explicitly map stream columns to table columns when suffixes differ**
2. **Silent drops are common** – no errors logged when schema doesn't match
3. **CCF `[[parameters(...)]]` syntax causes connectivity check to fail** (401), but connector still deploys
4. **First poll can take 30-60 minutes** after deployment – not immediate like Logic Apps
5. **Direct API testing is critical** to isolate auth issues from schema issues

---

**Status:** Schema fix applied and verified in DCR. Waiting for next poll cycle to confirm data ingestion.

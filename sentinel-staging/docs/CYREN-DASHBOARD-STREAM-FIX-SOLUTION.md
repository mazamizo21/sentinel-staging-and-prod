# Cyren Threat InDepth Dashboard - Stream Name Fix Solution

**Date:** 2025-11-12  
**Issue:** Cyren Threat InDepth (CCF) workbook doesn't show any information  
**Status:** ✅ **FIXED** - Ready for Deployment

---

## Problem Summary

The Cyren Threat Intelligence Dashboard was not displaying data because of a **stream name mismatch** between the Logic Apps (data producers) and the Data Collection Rule (data processor).

### Root Cause

```
Logic Apps → Wrong Stream Names → DCR → No Data → Empty Dashboard
```

**Specific Issues:**
1. **IP Reputation Logic App** was sending to: `Custom-Cyren_IpReputation_Raw`
2. **Malware URLs Logic App** was sending to: `Custom-Cyren_MalwareUrls_Raw`
3. **DCR was expecting:** `Custom-Cyren_Indicators_CL`
4. **Workbook queries were looking for:** `Cyren_Indicators_CL` table

---

## Solution Implemented

### 1. Fixed Stream Names in Logic Apps

Updated both Logic Apps to use the correct stream name:

**Files Modified:**
- `infrastructure/bicep/logicapp-cyren-ip-reputation.bicep`
  - Line 29: Changed `Custom-Cyren_IpReputation_Raw` → `Custom-Cyren_Indicators_CL`
  
- `infrastructure/bicep/logicapp-cyren-malware-urls.bicep`
  - Line 29: Changed `Custom-Cyren_MalwareUrls_Raw` → `Custom-Cyren_Indicators_CL`

### 2. Corrected Data Flow

```
Logic Apps → Custom-Cyren_Indicators_CL → DCR → Cyren_Indicators_CL → Dashboard ✅
```

Now both Logic Apps send data to the correct stream that the DCR is configured to process.

---

## Deployment Instructions

### Option 1: Automated Deployment (Recommended)

```powershell
cd "Sentinel-Full-deployment-production\sentinel-staging"

# Run the fix script
.\docs\fix-cyren-dashboard-streams.ps1 `
    -ResourceGroupName "YOUR-RESOURCE-GROUP" `
    -SubscriptionId "YOUR-SUBSCRIPTION-ID"
```

**Before running:**
1. Replace `"YOUR-CYREN-IP-TOKEN"` with actual Cyren IP Reputation API token
2. Replace `"YOUR-CYREN-MALWARE-TOKEN"` with actual Cyren Malware URLs API token
3. Update resource group and subscription ID parameters

### Option 2: Manual Deployment

```powershell
# Deploy IP Reputation Logic App
az deployment group create `
    --resource-group "YOUR-RESOURCE-GROUP" `
    --name "cyren-ip-fixed-$(Get-Date -Format 'yyyyMMddHHmmss')" `
    --template-file "infrastructure/bicep/logicapp-cyren-ip-reputation.bicep" `
    --parameters cyrenIpReputationToken="YOUR-TOKEN" dcrImmutableId="YOUR-DCR-ID" dceEndpoint="YOUR-DCE-ENDPOINT"

# Deploy Malware URLs Logic App
az deployment group create `
    --resource-group "YOUR-RESOURCE-GROUP" `
    --name "cyren-malware-fixed-$(Get-Date -Format 'yyyyMMddHHmmss')" `
    --template-file "infrastructure/bicep/logicapp-cyren-malware-urls.bicep" `
    --parameters cyrenMalwareUrlsToken="YOUR-TOKEN" dcrImmutableId="YOUR-DCR-ID" dceEndpoint="YOUR-DCE-ENDPOINT"
```

---

## Expected Results

After deployment:

### 1. Data Flow Corrected
- Both Logic Apps will send data to `Custom-Cyren_Indicators_CL` stream
- DCR will process data and store it in `Cyren_Indicators_CL` table
- Workbook queries will find and display the data

### 2. Dashboard Sections Will Show:
- ✅ **Threat Intelligence Overview** (total indicators, risk distribution)
- ✅ **Risk Distribution Over Time** (timechart)
- ✅ **Top 20 Malicious Domains** (table with risk scores)
- ✅ **Threat Categories Distribution** (pie chart)
- ✅ **Threat Types Distribution** (pie chart)
- ✅ **Recent High-Risk Indicators** (table with risk ≥ 70)
- ✅ **Ingestion Volume** (7-day timechart)

### 3. TacitRed Correlation
- Will show overlapping domains between Cyren and TacitRed (if any exist)

---

## Verification Steps

### 1. Immediate Verification (after deployment)
```powershell
# Trigger Logic Apps manually for immediate testing
# Or wait for next scheduled run (every 6 hours)
```

### 2. Check Dashboard
1. Navigate to Azure Sentinel → Threat Intelligence
2. Open "Cyren Threat Intelligence Dashboard"
3. Verify all sections show data

### 3. Verify Table Data
Run this query in Log Analytics:
```kql
Cyren_Indicators_CL
| take 10
```
Should return records from both IP Reputation and Malware URLs feeds.

---

## Technical Details

### Stream Name Mapping

| Component | Before Fix | After Fix | Status |
|-----------|------------|-----------|--------|
| IP Reputation Logic App | `Custom-Cyren_IpReputation_Raw` | `Custom-Cyren_Indicators_CL` | ✅ Fixed |
| Malware URLs Logic App | `Custom-Cyren_MalwareUrls_Raw` | `Custom-Cyren_Indicators_CL` | ✅ Fixed |
| DCR Configuration | `Custom-Cyren_Indicators_CL` | `Custom-Cyren_Indicators_CL` | ✅ Correct |
| Workbook Queries | N/A | `Cyren_Indicators_CL` table | ✅ Correct |

### Data Transformation

The DCR transformation KQL correctly maps:
- IP addresses from `identifier` or `meta.ip_address`
- Domains from `identifier` or extracted from URLs
- Risk scores from `detection.risk`
- Categories from `detection.category`
- Timestamps from `first_seen` and `last_seen`

---

## Files Modified

1. `infrastructure/bicep/logicapp-cyren-ip-reputation.bicep`
   - Fixed stream name parameter

2. `infrastructure/bicep/logicapp-cyren-malware-urls.bicep`
   - Fixed stream name parameter

3. `docs/fix-cyren-dashboard-streams.ps1` (new)
   - Automated deployment script
   - Handles parameter resolution
   - Provides deployment validation

---

## Troubleshooting

### If Dashboard Still Shows No Data:

1. **Check Logic App Runs:**
   - Go to Logic Apps in Azure Portal
   - Check run history for successful executions
   - Verify no authentication errors

2. **Check DCR Logs:**
   ```powershell
   az monitor data-collection rule show --resource-group <RG> --name "dcr-cyren-indicators"
   ```

3. **Verify Data in Table:**
   ```kql
   Cyren_Indicators_CL
   | where TimeGenerated >= ago(1h)
   | count
   ```

4. **Check Stream Name:**
   - Ensure Logic Apps are using `Custom-Cyren_Indicators_CL`
   - Verify DCR is configured for this stream

---

## Summary

The Cyren Threat InDepth Dashboard issue was caused by a simple stream name mismatch between Logic Apps and the DCR. By aligning all components to use the same stream name (`Custom-Cyren_Indicators_CL`), data will now flow correctly from the Logic Apps through the DCR to the `Cyren_Indicators_CL` table, where the workbook queries can access it.

**Status:** ✅ **FIXED** - Deploy the updated Logic Apps to resolve the issue.

---

**Next Steps:**
1. Deploy the fixed Logic Apps using the provided script
2. Wait for data ingestion (or trigger manually)
3. Verify dashboard displays data correctly
4. Monitor ongoing data ingestion

**Prevention:**
- Standardize stream names across all components
- Document data flow architecture
- Include stream name validation in deployment scripts
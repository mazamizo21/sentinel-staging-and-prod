# Cyren Threat Intelligence Dashboard Fix Summary

**Date:** 2025-11-11  
**Issue:** Cyren Threat Intelligence Dashboard showing "The query returned no results" for most sections

---

## Problem Analysis

### Root Cause: Stream Name Mismatch

The Cyren Threat Intelligence Dashboard was not displaying data because of a stream name mismatch between:

1. **Logic Apps** (data producers):
   - IP Reputation Logic App: `Custom-Cyren_IpReputation_CL`
   - Malware URLs Logic App: `Custom-Cyren_MalwareUrls_CL`

2. **Workbook Queries** (data consumers):
   - All queries looking for: `Cyren_Indicators_CL`

3. **DCR Configuration**:
   - Stream declaration: `Custom-Cyren_Indicators_CL`
   - Transformation KQL: Maps to `Cyren_Indicators_CL` table

### Data Flow Issue

```
Logic Apps → Wrong Stream Names → DCR → No Data → Empty Dashboard
```

The Logic Apps were sending data to different streams than what the DCR was configured to process, resulting in data not being stored in the expected table.

---

## Solution Implemented

### 1. Fixed Stream Names in Logic Apps

Updated both Logic Apps to use the correct stream name:

**Before:**
- IP Reputation: `Custom-Cyren_IpReputation_CL`
- Malware URLs: `Custom-Cyren_MalwareUrls_CL`

**After:**
- IP Reputation: `Custom-Cyren_Indicators_CL`
- Malware URLs: `Custom-Cyren_Indicators_CL`

### 2. Fixed DCR Transformation Path

Corrected the DCR transformation file path in `dcr-cyren.bicep`:

**Before:**
```bicep
transformKql: loadTextContent('../dcr/cyren-dcr-transformation.kql')
```

**After:**
```bicep
transformKql: loadTextContent('../infrastructure/cyren-dcr-transformation.kql')
```

### 3. Files Modified

1. `infrastructure/bicep/logicapp-cyren-ip-reputation.bicep`
   - Line 29: Changed streamName parameter to `'Custom-Cyren_Indicators_CL'`

2. `infrastructure/bicep/logicapp-cyren-malware-urls.bicep`
   - Line 29: Changed streamName parameter to `'Custom-Cyren_Indicators_CL'`

3. `bicep/dcr-cyren.bicep`
   - Line 77: Corrected transformation file path

---

## Deployment Instructions

### Option 1: Redeploy Logic Apps (Recommended)

```bash
# Navigate to the infrastructure directory
cd Sentinel-Full-deployment-production/sentinel-staging/infrastructure/bicep

# Redeploy both Logic Apps with corrected stream names
az deployment group create \
  --resource-group <ResourceGroupName> \
  --template-file logicapp-cyren-ip-reputation.bicep \
  --parameters logicapp-cyren-ip-reputation.parameters.json

az deployment group create \
  --resource-group <ResourceGroupName> \
  --template-file logicapp-cyren-malware-urls.bicep \
  --parameters logicapp-cyren-malware-urls.parameters.json
```

### Option 2: Update Existing Logic Apps

Use the provided PowerShell script:

```powershell
.\docs\fix-cyren-dashboard-streams.ps1 -ResourceGroupName <ResourceGroupName> -SubscriptionId <SubscriptionId>
```

---

## Expected Results

After applying these fixes:

1. **Data Flow Corrected:**
   ```
   Logic Apps → Custom-Cyren_Indicators_CL → DCR → Cyren_Indicators_CL → Dashboard
   ```

2. **Dashboard Sections Will Show:**
   - ✅ Threat Intelligence Overview (total indicators, risk distribution)
   - ✅ Risk Distribution Over Time (timechart)
   - ✅ Top 20 Malicious Domains (table with risk scores)
   - ✅ Threat Categories Distribution (pie chart)
   - ✅ Threat Types Distribution (pie chart)
   - ✅ Recent High-Risk Indicators (table with risk ≥ 70)
   - ✅ Ingestion Volume (7-day timechart)

3. **TacitRed Correlation:**
   - Will show overlapping domains between Cyren and TacitRed (if any exist)

---

## Verification Steps

1. **Wait for Data Ingestion:**
   - Logic Apps run every 6 hours
   - Or trigger manually for immediate testing

2. **Check Dashboard:**
   - Navigate to Azure Sentinel → Threat Intelligence
   - Open "Cyren Threat Intelligence Dashboard"
   - Verify all sections show data

3. **Verify Table Data:**
   ```kql
   Cyren_Indicators_CL
   | take 10
   ```
   Should return records from both IP Reputation and Malware URLs feeds

---

## Technical Details

### Stream Name Mapping

| Component | Stream Name | Table Name | Status |
|-----------|-------------|------------|--------|
| IP Reputation Logic App | Custom-Cyren_Indicators_CL | Cyren_Indicators_CL | ✅ Fixed |
| Malware URLs Logic App | Custom-Cyren_Indicators_CL | Cyren_Indicators_CL | ✅ Fixed |
| DCR | Custom-Cyren_Indicators_CL | Cyren_Indicators_CL | ✅ Correct |
| Workbook Queries | N/A | Cyren_Indicators_CL | ✅ Correct |

### Data Transformation

The DCR transformation KQL correctly maps:
- IP addresses from `identifier` or `meta.ip_address`
- Domains from `identifier` or extracted from URLs
- Risk scores from `detection.risk`
- Categories from `detection.category`
- Timestamps from `first_seen` and `last_seen`

---

## Summary

The Cyren Threat Intelligence Dashboard issue was caused by a simple stream name mismatch. By aligning all components to use the same stream name (`Custom-Cyren_Indicators_CL`), data will now flow correctly from the Logic Apps through the DCR to the `Cyren_Indicators_CL` table, where the workbook queries can access it.

**Status:** ✅ **FIXED** - Deploy the updated Logic Apps to resolve the issue.
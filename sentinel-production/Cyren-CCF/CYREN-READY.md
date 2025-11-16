# Cyren CCF Solution - Ready for Deployment

**Date:** 2025-11-16  
**Status:** ✅ **READY** - Waiting for fresh API data from Cyren engineer

---

## Summary

The Cyren CCF solution has been fully prepared with the same immutableId fix pattern as TacitRed. All scripts and templates are ready for deployment once Cyren provides fresh data (within last 60 minutes).

---

## Current Situation

### ✅ What's Fixed

- ✅ **ARM Template Updated** (`mainTemplate.json`)
  - Added `cyrenIPDcrImmutableId` parameter
  - Added `cyrenMalwareDcrImmutableId` parameter
  - Both connectors now use parameters instead of `reference()`
  - Same pattern as TacitRed fix

- ✅ **Deployment Script Created** (`BUILD-Cyren-OneClick.ps1`)
  - 3-step process: Deploy infra → Read ImmutableIds → Deploy connectors
  - Automatic verification of ImmutableId match
  - Interactive prompts for JWT tokens

- ✅ **Fix Script Created** (`FIX-Cyren-DcrImmutableId.ps1`)
  - Post-deployment immutableId correction for both connectors
  - Handles IP Reputation and Malware URLs separately
  - Verification after fix

### ⏳ What's Pending

- ⏳ **Fresh API Data** - Cyren engineer needs to provide data within last 60 minutes
- ⏳ **Deployment** - Deploy once fresh data is available
- ⏳ **Data Ingestion Verification** - Confirm connectors poll and ingest data

---

## API Data Status

### Current Data Freshness (as of 2025-11-16)

**IP Reputation Feed:**
- Last seen: `2025-11-10T19:57:03.907Z` (Nov 10, 2025)
- Age: ~6 days old
- Status: ❌ Too old for 60-minute polling window

**Malware URLs Feed:**
- Last seen: `2025-11-07T01:32:40.023Z` (Nov 7, 2025)
- Age: ~9 days old
- Status: ❌ Too old for 60-minute polling window

### Why This Matters

The Cyren connectors use `queryWindowInMin: 60`, meaning they only poll data from the **last 60 minutes**. Since the most recent Cyren data is 6-9 days old, the connectors will poll but find zero records, resulting in zero ingestion.

**Solution:** Wait for Cyren engineer to provide fresh data (within last hour), then deploy.

---

## Files Ready

### ARM Template
- **File:** `Cyren-CCF/mainTemplate.json`
- **Changes:**
  - Lines 105-118: Added two immutableId parameters
  - Line 767: IP Reputation connector uses `cyrenIPDcrImmutableId` parameter
  - Line 805: Malware URLs connector uses `cyrenMalwareDcrImmutableId` parameter

### Deployment Scripts

1. **BUILD-Cyren-OneClick.ps1**
   - One-click deployment with correct immutableId wiring
   - 3-step process ensures no caching issues
   - Automatic verification

2. **FIX-Cyren-DcrImmutableId.ps1**
   - Post-deployment fix if needed
   - Updates both connectors
   - Verifies fix success

3. **TEST-Cyren-API-Auto.ps1**
   - Tests both Cyren APIs directly
   - Checks data freshness
   - Saves sample responses

---

## Deployment Process (When Ready)

### Prerequisites

1. ✅ Cyren engineer provides fresh data (within last 60 minutes)
2. ✅ Verify fresh data with `TEST-Cyren-API-Auto.ps1`
3. ✅ Have JWT tokens ready (from `client-config-COMPLETE.json`)

### Deployment Steps

```powershell
# Step 1: Verify fresh data
.\Cyren-CCF\TEST-Cyren-API-Auto.ps1

# Check timestamps in output - should be within last hour

# Step 2: Deploy with one-click script
.\Cyren-CCF\BUILD-Cyren-OneClick.ps1

# Script will:
# - Deploy infrastructure (DCE, DCRs, Table, UAMI, RBAC)
# - Read actual DCR immutableIds
# - Deploy connectors with correct immutableIds
# - Verify immutableId match

# Step 3: Wait for first poll (60-90 minutes)

# Step 4: Verify data ingestion
```

### Verification KQL

```kql
// Check for any Cyren data
Cyren_Indicators_CL
| summarize Count = count(),
          FirstSeen = min(TimeGenerated),
          LastSeen = max(TimeGenerated)

// Split by feed
Cyren_Indicators_CL
| extend Feed = case(
    isnotempty(ip_s) and isempty(url_s), "IP Reputation",
    isnotempty(url_s), "Malware URLs",
    "Unknown"
)
| summarize count() by Feed, bin(TimeGenerated, 1h)
| order by TimeGenerated desc
```

---

## Architecture

### Resources Deployed

1. **Data Collection Endpoint (DCE)**
   - Name: `dce-threatintel-feeds`
   - Shared by both feeds

2. **Data Collection Rules (DCRs)**
   - `dcr-cyren-ip-reputation`
   - `dcr-cyren-malware-urls`

3. **Custom Table**
   - Name: `Cyren_Indicators_CL`
   - Shared by both feeds
   - 19 columns (url_s, ip_s, fileHash_s, domain_s, etc.)

4. **User-Assigned Managed Identity (UAMI)**
   - Name: `uami-ccf-deployment`
   - RBAC: Sentinel Contributor (workspace + RG)

5. **CCF Connectors**
   - `CyrenIPReputation` (RestApiPoller)
   - `CyrenMalwareURLs` (RestApiPoller)

6. **Optional: Key Vault**
   - For secure JWT token storage
   - Default: disabled (tokens passed as securestring)

7. **Workbooks** (2)
   - Cyren Threat Intelligence
   - Cyren Threat Intelligence (Enhanced)

### Data Flow

```
Cyren API (IP Reputation)
  ↓
CyrenIPReputation Connector (polls every 60 min)
  ↓
DCE (dce-threatintel-feeds)
  ↓
DCR (dcr-cyren-ip-reputation)
  ↓
Cyren_Indicators_CL table

Cyren API (Malware URLs)
  ↓
CyrenMalwareURLs Connector (polls every 60 min)
  ↓
DCE (dce-threatintel-feeds)
  ↓
DCR (dcr-cyren-malware-urls)
  ↓
Cyren_Indicators_CL table
```

---

## Connector Configuration

### IP Reputation Connector

```json
{
  "kind": "RestApiPoller",
  "properties": {
    "connectorDefinitionName": "CyrenThreatIntel",
    "dataType": "Cyren_Indicators_CL",
    "dcrConfig": {
      "streamName": "Custom-Cyren_Indicators_CL",
      "dataCollectionEndpoint": "[DCE endpoint]",
      "dataCollectionRuleImmutableId": "[parameters('cyrenIPDcrImmutableId')]"
    },
    "auth": {
      "type": "APIKey",
      "ApiKeyName": "Authorization",
      "ApiKey": "Bearer [JWT]"
    },
    "request": {
      "apiEndpoint": "https://api-feeds.cyren.com/v1/feed/data",
      "httpMethod": "GET",
      "queryParameters": {
        "feedId": "ip_reputation",
        "count": 100,
        "offset": 0,
        "format": "jsonl"
      },
      "queryWindowInMin": 60,
      "rateLimitQps": 10,
      "retryCount": 3,
      "timeoutInSeconds": 60
    },
    "paging": {
      "pagingType": "Offset",
      "offsetParameterName": "offset",
      "pageSize": 100
    },
    "response": {
      "eventsJsonPaths": ["$"],
      "format": "jsonl"
    }
  }
}
```

### Malware URLs Connector

Same structure, different `feedId`: `malware_urls`

---

## Troubleshooting

### If No Data After Fresh API Data Available

1. **Check connector status:**
   ```powershell
   az rest --method GET --url "/subscriptions/.../dataConnectors/CyrenIPReputation?api-version=2023-02-01-preview"
   ```

2. **Verify immutableId match:**
   ```powershell
   .\Cyren-CCF\FIX-Cyren-DcrImmutableId.ps1
   ```

3. **Check DCR diagnostics:**
   ```kql
   AzureDiagnostics
   | where ResourceType == "DATAOLLECTIONRULES"
   | where Resource has "cyren"
   | order by TimeGenerated desc
   ```

4. **Manually trigger poll (if needed):**
   - Not directly supported by CCF
   - Wait for next scheduled poll (every 60 minutes)

---

## Next Steps

1. ✅ **Wait for Cyren engineer** to provide fresh data
2. ✅ **Test API** with `TEST-Cyren-API-Auto.ps1` to confirm fresh data
3. ✅ **Deploy** with `BUILD-Cyren-OneClick.ps1`
4. ✅ **Verify** data ingestion after 60-90 minutes
5. ✅ **Create Content Hub package** (Cyren-CCF-Clean folder) after successful deployment

---

## Related Files

- `mainTemplate.json` - ARM template with immutableId fix
- `BUILD-Cyren-OneClick.ps1` - One-click deployment script
- `FIX-Cyren-DcrImmutableId.ps1` - Post-deployment fix script
- `TEST-Cyren-API-Auto.ps1` - API data freshness test
- `createUiDefinition.json` - Portal UI wizard
- `Package/packageMetadata.json` - Content Hub metadata

---

**Status:** ✅ Ready for deployment when fresh API data is available  
**Action Required:** Wait for Cyren engineer to provide fresh data

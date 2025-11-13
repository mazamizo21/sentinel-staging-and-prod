# CCF Connector Data Parsing Issue - Root Cause Analysis

**Date:** November 13, 2025 09:58 AM  
**Issue:** 5.7M records in Cyren_Indicators_CL but ALL columns are empty  
**Status:** 🔍 INVESTIGATING - Root cause identified

---

## Problem Summary

### What We Found
- ✅ 5,704,932 records ingested into Cyren_Indicators_CL
- ✅ Table schema has all correct columns (ip_s, url_s, category_s, risk_d, etc.)
- ✅ CCF connectors are active and polling
- ❌ **ALL data columns are completely empty (NULL)**

### Impact
- Workbooks show "no results" for queries that filter by ip_s, url_s, category_s, etc.
- Only queries that don't filter by these columns work (e.g., count, TimeGenerated)
- 5.7M records are essentially useless without parsed data

---

## Root Cause

### Architecture
```
Cyren API (JSONL format)
    ↓
CCF Connector (RestApiPoller)
    ↓
Data Collection Endpoint (DCE)
    ↓
Data Collection Rule (DCR) ← **TRANSFORMATION HAPPENS HERE**
    ↓
Log Analytics Table (Cyren_Indicators_CL)
```

### The Issue

**CCF connectors ARE configured to use DCRs:**
```json
{
  "dcrConfig": {
    "streamName": "Custom-Cyren_Indicators_CL",
    "dataCollectionEndpoint": "{{dataCollectionEndpoint}}",
    "dataCollectionRuleImmutableId": "{{cyrenIPDcrImmutableId}}"
  }
}
```

**DCR transformation exists:**
```kql
source 
| extend tg1=todatetime(detection_ts) 
| extend tg2=iif(isnull(tg1), todatetime(lastSeen), tg1) 
| extend tg=iif(isnull(tg2), now(), tg2) 
| project 
    TimeGenerated=tg, 
    url_s=tostring(url), 
    ip_s=tostring(ip), 
    domain_s=tostring(domain),
    category_s=tostring(category),
    risk_d=toint(risk),
    ...
```

**BUT:** The DCR transformation expects fields named `url`, `ip`, `domain`, `category`, `risk`, etc. (without suffixes).

**The Cyren API might be returning:**
- Different field names (e.g., `IP` instead of `ip`)
- Nested JSON structure
- Different format than expected

---

## Investigation Steps

### Step 1: Check Actual API Response Format

We need to see what the Cyren API actually returns. Options:

**Option A: Check CCF connector logs**
```bash
# Get recent connector runs
az rest --method GET \
  --url "/subscriptions/.../providers/Microsoft.SecurityInsights/dataConnectors/CyrenIPReputation?api-version=2024-09-01"
```

**Option B: Test Cyren API directly**
```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  "https://api-feeds.cyren.com/v1/feed/data?feedId=ip_reputation&count=5&offset=0&format=jsonl"
```

**Option C: Check DCR ingestion logs**
```kql
// Check if DCR is receiving data
DCRLogEvents
| where TimeGenerated > ago(1h)
| where RuleName contains "cyren"
```

### Step 2: Common Cyren API Response Formats

**Format 1: Flat JSON (Expected)**
```json
{
  "ip": "1.2.3.4",
  "url": "http://malicious.com",
  "category": "malware",
  "risk": 80,
  "detection_ts": "2025-11-13T10:00:00Z"
}
```

**Format 2: Nested JSON**
```json
{
  "indicator": {
    "value": "1.2.3.4",
    "type": "ip"
  },
  "threat": {
    "category": "malware",
    "score": 80
  }
}
```

**Format 3: Different Field Names**
```json
{
  "IP": "1.2.3.4",
  "URL": "http://malicious.com",
  "Category": "malware",
  "RiskScore": 80
}
```

---

## Solution Approaches

### Approach 1: Fix DCR Transformation (Recommended)

**If API returns different field names:**
```kql
source 
| extend 
    // Try multiple possible field names
    ip_value = coalesce(tostring(ip), tostring(IP), tostring(['IP']), ""),
    url_value = coalesce(tostring(url), tostring(URL), tostring(['URL']), ""),
    category_value = coalesce(tostring(category), tostring(Category), ""),
    risk_value = coalesce(toint(risk), toint(RiskScore), toint(score), 50)
| project 
    TimeGenerated = now(),
    ip_s = ip_value,
    url_s = url_value,
    category_s = category_value,
    risk_d = risk_value,
    ...
```

**If API returns nested JSON:**
```kql
source 
| extend indicator = parse_json(indicator)
| extend threat = parse_json(threat)
| project 
    TimeGenerated = now(),
    ip_s = tostring(indicator.value),
    category_s = tostring(threat.category),
    risk_d = toint(threat.score),
    ...
```

### Approach 2: Update CCF Connector Response Mapping

Some CCF connectors support response field mapping:
```json
{
  "response": {
    "eventsJsonPaths": ["$"],
    "format": "jsonl",
    "fieldMappings": [
      {"sourceField": "IP", "targetField": "ip"},
      {"sourceField": "URL", "targetField": "url"}
    ]
  }
}
```

### Approach 3: Use Custom Parser Function

Create a parser function that handles the transformation:
```kql
Cyren_Indicators_CL
| extend parsed = parse_json(RawData)  // If data is in RawData column
| extend 
    ip_s = tostring(parsed.IP),
    url_s = tostring(parsed.URL),
    ...
```

---

## Next Steps

### Immediate Actions

1. **Test Cyren API Response Format**
   - Make direct API call to see actual response
   - Document exact field names and structure

2. **Update DCR Transformation**
   - Modify transformation KQL to match actual API format
   - Add fallbacks for missing fields
   - Test with sample data

3. **Redeploy DCR**
   - Deploy updated DCR configuration
   - Wait for next CCF connector poll (up to 6 hours)
   - Verify new data is parsed correctly

4. **Clean Up Empty Records (Optional)**
   - Delete the 5.7M empty records
   - Or leave them (they don't affect queries with WHERE clauses)

### Verification

After fixing DCR:
```kql
// Check if new data has populated columns
Cyren_Indicators_CL
| where TimeGenerated > ago(1h)
| where isnotempty(ip_s) or isnotempty(url_s)
| take 10
```

---

## Files to Update

1. **DCR Bicep Files:**
   - `sentinel-production/infrastructure/bicep/dcr-cyren-ip.bicep`
   - `sentinel-production/infrastructure/bicep/dcr-cyren-malware.bicep`

2. **Deployment Script:**
   - Update and redeploy DCRs
   - No need to redeploy CCF connectors (they're already correct)

3. **Workbooks:**
   - May need to update queries if field names change
   - Or add fallbacks for empty columns

---

## Status

**Current:** Waiting to identify actual Cyren API response format

**Next:** Once we know the format, update DCR transformation and redeploy

**Timeline:** 
- Fix DCR: 15 minutes
- Redeploy: 5 minutes
- Wait for next poll: Up to 6 hours
- Verify: 5 minutes

---

**Investigation Date:** November 13, 2025 09:58 AM  
**Next Action:** Test Cyren API to see actual response format

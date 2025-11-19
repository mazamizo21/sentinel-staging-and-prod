# TacitRed CCF Root Cause Analysis
**Date:** 2025-11-19  
**Status:** ROOT CAUSE IDENTIFIED

---

## Executive Summary

The TacitRed CCF connector is **failing silently** due to a **schema type mismatch** in the Data Collection Rule (DCR). The working Logic App uses correct type conversions, while the CCF DCR attempts to ingest JSON string data directly into typed columns (datetime, int) without conversion, causing ingestion failures.

---

## Evidence

### Working Environment (Logic App)
- **Resource Group:** `SentinelTestStixImport`
- **Workspace:** `SentinelThreatIntelWorkspace`
- **Records Ingested:** **51,700+** (Last update: 2025-11-19 14:14 UTC)
- **Status:** ✅ **WORKING PERFECTLY**

### Non-Working Environment (CCF)
- **Resource Group:** `TacitRed-Production-Test-RG`
- **Workspace:** `TacitRed-Production-Test-Workspace`
- **Records Ingested:** **0**
- **Connector Status:** `isActive: true`
- **Status:** 🔴 **ZERO INGESTION**

---

## Critical Differences

### 1. DCR Stream Architecture

#### ✅ Logic App DCR (WORKING)
```json
{
  "streamDeclarations": {
    "Custom-TacitRed_Findings_Raw": {
      "columns": [
        {"name": "email", "type": "string"},
        {"name": "confidence", "type": "string"},    // STRING
        {"name": "firstSeen", "type": "string"},     // STRING  
        {"name": "detection_ts", "type": "string"}   // STRING
      ]
    },
    "Custom-TacitRed_Findings_CL": {
      "columns": [
        {"name": "email_s", "type": "string"},
        {"name": "confidence_d", "type": "int"},     // INT (converted)
        {"name": "firstSeen_t", "type": "datetime"}, // DATETIME (converted)
        {"name": "detection_ts_t", "type": "datetime"} // DATETIME (converted)
      ]
    }
  },
  "dataFlows": [{
    "streams": ["Custom-TacitRed_Findings_Raw"],  // INPUT: Raw strings
    "outputStream": "Custom-TacitRed_Findings_CL", // OUTPUT: Typed columns
    "transformKql": "source | extend tg1=todatetime(detection_ts) | ... | project TimeGenerated=tg, email_s=tostring(email), confidence_d=toint(confidence), firstSeen_t=todatetime(firstSeen), ..."
  }]
}
```

#### 🔴 CCF DCR (NOT WORKING)
```json
{
  "streamDeclarations": {
    "Custom-TacitRed_Findings_CL": {
      "columns": [
        {"name": "email", "type": "string"},
        {"name": "confidence", "type": "int"},      // INT (expects conversion but none provided)
        {"name": "firstSeen", "type": "datetime"},  // DATETIME (expects conversion but none provided)
        {"name": "detection_ts", "type": "datetime"} // DATETIME (expects conversion but none provided)
      ]
    }
  },
  "dataFlows": [{
    "streams": ["Custom-TacitRed_Findings_CL"],     // INPUT/OUTPUT: Same stream
    "outputStream": "Custom-TacitRed_Findings_CL",
    "transformKql": "source | extend TimeGenerated = now() | project-rename email_s = email, confidence_d = confidence, firstSeen_t = firstSeen, ..."
    // ❌ NO TYPE CONVERSIONS - Just renames fields
  }]
}
```

---

## The Problem

### TacitRed API Response (JSON)
```json
{
  "results": [
    {
      "email": "user@example.com",
      "confidence": "85",                    // STRING
      "firstSeen": "2025-11-19T10:00:00Z",  // STRING
      "detection_ts": "2025-11-19T12:00:00Z" // STRING
    }
  ]
}
```

### What Happens

1. **CCF Connector** sends JSON data to DCE/DCR
2. **DCR expects**:
   - `confidence` as `int`
   - `firstSeen` as `datetime`
   - `detection_ts` as `datetime`
3. **DCR receives** strings: `"85"`, `"2025-11-19T10:00:00Z"`, etc.
4. **Transform KQL** only renames fields (`project-rename`) - **NO TYPE CONVERSION**
5. **Ingestion fails** silently due to type mismatch
6. **Result:** 0 records ingested

### Why Logic App Works

The Logic App DCR:
1. Accepts **all STRING columns** in the input stream (`Custom-TacitRed_Findings_Raw`)
2. Performs **explicit type conversions** in transformKql:
   - `toint(confidence)` → int
   - `todatetime(firstSeen)` → datetime
   - `todatetime(detection_ts)` → datetime
3. Outputs to final stream with correctly typed columns

---

## Solution

Update the CCF DCR to match the Logic App architecture:

### Required Changes to `mainTemplate.json`

1. **Add a separate RAW input stream** with all STRING columns
2. **Use proper type conversions** in transformKql
3. **Keep the output stream** with typed columns for the table

### Updated DCR Configuration

```json
{
  "streamDeclarations": {
    "Custom-TacitRed_Findings_Raw": {
      "columns": [
        {"name": "email", "type": "string"},
        {"name": "domain", "type": "string"},
        {"name": "findingType", "type": "string"},
        {"name": "confidence", "type": "string"},      // STRING (from API)
        {"name": "firstSeen", "type": "string"},       // STRING (from API)
        {"name": "lastSeen", "type": "string"},        // STRING (from API)
        {"name": "notes", "type": "string"},
        {"name": "source", "type": "string"},
        {"name": "severity", "type": "string"},
        {"name": "status", "type": "string"},
        {"name": "campaign_id", "type": "string"},
        {"name": "user_id", "type": "string"},
        {"name": "username", "type": "string"},
        {"name": "detection_ts", "type": "string"},    // STRING (from API)
        {"name": "metadata", "type": "string"}
      ]
    },
    "Custom-TacitRed_Findings_CL": {
      "columns": [
        {"name": "TimeGenerated", "type": "datetime"},
        {"name": "email_s", "type": "string"},
        {"name": "domain_s", "type": "string"},
        {"name": "findingType_s", "type": "string"},
        {"name": "confidence_d", "type": "int"},
        {"name": "firstSeen_t", "type": "datetime"},
        {"name": "lastSeen_t", "type": "datetime"},
        {"name": "notes_s", "type": "string"},
        {"name": "source_s", "type": "string"},
        {"name": "severity_s", "type": "string"},
        {"name": "status_s", "type": "string"},
        {"name": "campaign_id_s", "type": "string"},
        {"name": "user_id_s", "type": "string"},
        {"name": "username_s", "type": "string"},
        {"name": "detection_ts_t", "type": "datetime"},
        {"name": "metadata_s", "type": "string"}
      ]
    }
  },
  "dataFlows": [{
    "streams": ["Custom-TacitRed_Findings_Raw"],
    "destinations": ["clv2ws1"],
    "transformKql": "source | extend tg1=todatetime(detection_ts) | extend tg2=iif(isnull(tg1), todatetime(lastSeen), tg1) | extend tg=iif(isnull(tg2), now(), tg2) | project TimeGenerated=tg, email_s=tostring(email), domain_s=tostring(domain), findingType_s=tostring(findingType), confidence_d=toint(confidence), firstSeen_t=todatetime(firstSeen), lastSeen_t=todatetime(lastSeen), notes_s=tostring(notes), source_s=tostring(source), severity_s=tostring(severity), status_s=tostring(status), campaign_id_s=tostring(campaign_id), user_id_s=tostring(user_id), username_s=tostring(username), detection_ts_t=todatetime(detection_ts), metadata_s=tostring(metadata)",
    "outputStream": "Custom-TacitRed_Findings_CL"
  }]
}
```

### CCF Connector Configuration Change

Update the connector's `dcrConfig.streamName`:
```json
"dcrConfig": {
  "streamName": "Custom-TacitRed_Findings_Raw",  // Changed from Custom-TacitRed_Findings_CL
  "dataCollectionEndpoint": "...",
  "dataCollectionRuleImmutableId": "..."
}
```

---

## Validation Steps (Post-Fix)

1. **Deploy updated template**
2. **Wait 2-3 minutes** for first CCF poll
3. **Check data ingestion:**
   ```kql
   TacitRed_Findings_CL
   | where TimeGenerated > ago(10m)
   | count
   ```
4. **Verify field types:**
   ```kql
   TacitRed_Findings_CL
   | take 1
   | project confidence_d, firstSeen_t, detection_ts_t
   ```

---

## Why This Wasn't Caught Earlier

1. **No diagnostic logs**: CCF doesn't emit detailed error logs for schema mismatches
2. **Silent failure**: Azure accepts the deployment but fails ingestion silently
3. **Connector shows active**: `isActive: true` doesn't mean data is flowing
4. **No validation at deploy time**: ARM doesn't validate stream/API response compatibility

---

## Lessons Learned

1. Always use **STRING types** for input streams from REST APIs
2. Perform **explicit type conversions** in transformKql
3. Use **two-stream architecture** (Raw → Typed) for external data sources
4. Test with **real API data** before assuming ARM deployment success means working ingestion

---

## Next Action

Fix the `mainTemplate.json` DCR configuration and connector streamName, then redeploy.

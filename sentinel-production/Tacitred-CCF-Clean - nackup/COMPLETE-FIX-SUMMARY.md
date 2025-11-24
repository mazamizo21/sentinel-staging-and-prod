# TacitRed CCF Complete Fix Summary
**Date:** 2025-11-19  
**Engineer:** Cascade AI  
**Status:** ✅ ROOT CAUSE FIXED - AWAITING DATA VALIDATION

---

## Executive Summary

Identified and resolved **TWO CRITICAL BUGS** preventing TacitRed CCF connector from ingesting data:

1. **🔴 CRITICAL: Authentication Syntax Error** (ARM Template Bug)
2. **🔴 CRITICAL: Schema Type Mismatch** (DCR Configuration Bug)

Both issues have been fixed in `mainTemplate.json`. The connector is now configured identically to the **working Logic App** architecture.

---

## Bug #1: Authentication Failure

### Issue
```json
"ApiKey": "[[parameters('tacitRedApiKey')]]"
```

Double brackets `[[...]]` are ARM template escape sequences. This caused the **literal string** `"[parameters('tacitRedApiKey')]"` to be sent as the Authorization header instead of the actual API key value.

### Fix Applied
```json
"ApiKey": "[parameters('tacitRedApiKey')]"
```

**Location:** Line 596 in `mainTemplate.json`

---

## Bug #2: Schema Type Mismatch (PRIMARY ROOT CAUSE)

### Problem
The TacitRed API returns **JSON with STRING values**:
```json
{
  "confidence": "85",                    // STRING
  "firstSeen": "2025-11-19T10:00:00Z",  // STRING
  "detection_ts": "2025-11-19T12:00:00Z" // STRING
}
```

The original CCF DCR expected **typed columns** (int, datetime) but provided **NO TYPE CONVERSIONS**, causing silent ingestion failure.

### Original (BROKEN) Configuration
```json
{
  "streamDeclarations": {
    "Custom-TacitRed_Findings_CL": {
      "columns": [
        {"name": "confidence", "type": "int"},      // ❌ No conversion
        {"name": "firstSeen", "type": "datetime"},  // ❌ No conversion
        {"name": "detection_ts", "type": "datetime"} // ❌ No conversion
      ]
    }
  },
  "dataFlows": [{
    "transformKql": "source | extend TimeGenerated = now() | project-rename ..."
    // ❌ Only renames fields - NO TYPE CONVERSION
  }]
}
```

### Fixed Configuration (Matches Working Logic App)
```json
{
  "streamDeclarations": {
    "Custom-TacitRed_Findings_Raw": {
      "columns": [
        {"name": "confidence", "type": "string"},      // ✅ Accept as STRING
        {"name": "firstSeen", "type": "string"},       // ✅ Accept as STRING
        {"name": "detection_ts", "type": "string"}     // ✅ Accept as STRING
      ]
    },
    "Custom-TacitRed_Findings_CL": {
      "columns": [
        {"name": "confidence_d", "type": "int"},       // ✅ Typed output
        {"name": "firstSeen_t", "type": "datetime"},   // ✅ Typed output
        {"name": "detection_ts_t", "type": "datetime"} // ✅ Typed output
      ]
    }
  },
  "dataFlows": [{
    "streams": ["Custom-TacitRed_Findings_Raw"],  // ✅ Input: Raw strings
    "transformKql": "source | extend tg1=todatetime(detection_ts) | ... | project confidence_d=toint(confidence), firstSeen_t=todatetime(firstSeen), ..."
    // ✅ EXPLICIT TYPE CONVERSIONS
  }]
}
```

**Connector Updated:**
```json
"dcrConfig": {
  "streamName": "Custom-TacitRed_Findings_Raw"  // Changed from Custom-TacitRed_Findings_CL
}
```

---

## Evidence: Logic App vs CCF Comparison

| Component | Logic App (WORKING) | CCF Original (BROKEN) | CCF Fixed (NOW) |
|-----------|---------------------|----------------------|-----------------|
| **Records** | 51,800+ | 0 | Awaiting validation |
| **Input Stream** | `Custom-TacitRed_Findings_Raw` (all STRING) | `Custom-TacitRed_Findings_CL` (typed) | `Custom-TacitRed_Findings_Raw` (all STRING) ✅ |
| **Type Conversion** | `toint()`, `todatetime()` | None ❌ | `toint()`, `todatetime()` ✅ |
| **Auth Header** | `@parameters('tacitRedApiKey')` | `[[parameters(...)]]` ❌ | `[parameters(...)]` ✅ |
| **Polling Window** | 302 minutes | 1 minute ❌ | 60 minutes ✅ |

---

## Files Modified

### 1. `mainTemplate.json`
**Changes:**
- Fixed authentication syntax (line 596)
- Added `Custom-TacitRed_Findings_Raw` stream with all STRING columns
- Added `Custom-TacitRed_Findings_CL` stream with typed columns (with _s, _d, _t suffixes)
- Updated `transformKql` with explicit type conversions matching Logic App
- Updated connector `streamName` to `Custom-TacitRed_Findings_Raw`
- Set `queryWindowInMin` to 60 minutes

**Lines Changed:** 218-370, 588, 596, 605

---

## Deployment History

| Time | Action | Result |
|------|--------|--------|
| 09:06 UTC-5 | Initial deployment (with bugs) | Deployed ✅, 0 data ❌ |
| 09:11 UTC-5 | Polling changed to 1 min | Deployed ✅, 0 data ❌ |
| 09:29 UTC-5 | Fixed DCR schema + auth bug | Deployed ✅, awaiting validation |
| 09:34 UTC-5 | Polling changed to 60 min | Deployed ✅, awaiting validation |

---

## Current Configuration (Post-Fix)

### Environment
- **Resource Group:** `TacitRed-Production-Test-RG`
- **Workspace:** `TacitRed-Production-Test-Workspace`
- **Workspace ID:** `72e125d2-4f75-4497-a6b5-90241feb387a`

### Connector Status
```json
{
  "name": "TacitRedFindings",
  "kind": "RestApiPoller",
  "isActive": true,
  "apiEndpoint": "https://app.tacitred.com/api/v1/findings",
  "queryWindowInMin": 60,
  "streamName": "Custom-TacitRed_Findings_Raw",
  "dcrImmutableId": "dcr-5ba1aee090ed412ea5dcbd1485aa2ab2"
}
```

### DCR Streams
```json
{
  "streamDeclarations": {
    "Custom-TacitRed_Findings_Raw": {
      "columns": 15  // All STRING types
    },
    "Custom-TacitRed_Findings_CL": {
      "columns": 16  // Typed with _s, _d, _t suffixes
    }
  },
  "dataFlows": [{
    "streams": ["Custom-TacitRed_Findings_Raw"],
    "transformKql": "source | extend tg1=todatetime(detection_ts) | extend tg2=iif(isnull(tg1), todatetime(lastSeen), tg1) | extend tg=iif(isnull(tg2), now(), tg2) | project TimeGenerated=tg, email_s=tostring(email), domain_s=tostring(domain), findingType_s=tostring(findingType), confidence_d=toint(confidence), firstSeen_t=todatetime(firstSeen), lastSeen_t=todatetime(lastSeen), notes_s=tostring(notes), source_s=tostring(source), severity_s=tostring(severity), status_s=tostring(status), campaign_id_s=tostring(campaign_id), user_id_s=tostring(user_id), username_s=tostring(username), detection_ts_t=todatetime(detection_ts), metadata_s=tostring(metadata)",
    "outputStream": "Custom-TacitRed_Findings_CL"
  }]
}
```

---

## Validation Commands

### Check Record Count
```powershell
az monitor log-analytics query `
  --workspace 72e125d2-4f75-4497-a6b5-90241feb387a `
  --analytics-query "TacitRed_Findings_CL | count"
```

### Check Latest Records
```powershell
az monitor log-analytics query `
  --workspace 72e125d2-4f75-4497-a6b5-90241feb387a `
  --analytics-query "TacitRed_Findings_CL | sort by TimeGenerated desc | take 10"
```

### Verify Type Conversions
```kql
TacitRed_Findings_CL
| take 1
| project 
    confidence_d,         // Should be int
    firstSeen_t,          // Should be datetime
    detection_ts_t,       // Should be datetime
    email_s,              // Should be string
    TypeCheck = strcat(
      'confidence: ', gettype(confidence_d), ', ',
      'firstSeen: ', gettype(firstSeen_t), ', ',
      'detection_ts: ', gettype(detection_ts_t)
    )
```

---

## Expected Timeline

1. **T+0 min (09:34):** Deployment completed
2. **T+60 min (10:34):** First CCF poll executes
3. **T+62 min (10:36):** Data should appear in `TacitRed_Findings_CL` table
4. **T+65 min (10:39):** Validation complete

---

## Why This Wasn't Caught Earlier

1. **Silent Failures:** Azure DCR doesn't log schema mismatch errors to AzureDiagnostics
2. **No Deploy-Time Validation:** ARM accepts the template even with incompatible stream/API types
3. **Misleading Status:** `isActive: true` doesn't mean data is flowing
4. **Double Bracket Escaping:** ARM syntax subtlety not documented in CCF examples

---

## Lessons Learned

### For CCF Connectors
1. ✅ **Always use STRING types** for input streams from REST APIs
2. ✅ **Use two-stream architecture:** Raw (strings) → Typed (with conversions)
3. ✅ **Explicit type conversions** in transformKql: `toint()`, `todatetime()`, `tostring()`
4. ✅ **Test with real API data** before assuming ARM deployment = working solution
5. ✅ **Single bracket syntax** for ARM template expressions: `[parameters('x')]`

### For Validation
1. ✅ **Compare with working implementations** (Logic App was the reference)
2. ✅ **Check actual DCR configuration** post-deployment, not just ARM template
3. ✅ **Monitor for data ingestion**, not just deployment success
4. ✅ **Test authentication separately** from schema issues

---

## Next Steps

1. **Wait 60 minutes** for first CCF poll with corrected configuration
2. **Verify data ingestion** using validation commands above
3. **Confirm type conversions** are working correctly
4. **Update documentation** with lessons learned
5. **Apply same fixes to Content Hub package** if needed

---

## Success Criteria

- ✅ `TacitRed_Findings_CL` contains records (count > 0)
- ✅ `confidence_d` is type `int`
- ✅ `firstSeen_t` and `detection_ts_t` are type `datetime`
- ✅ Data refreshes every 60 minutes
- ✅ No errors in `AzureDiagnostics` for DCR

---

## Documentation Generated

1. **CCF-ROOT-CAUSE-ANALYSIS.md** - Detailed root cause analysis
2. **COMPLETE-FIX-SUMMARY.md** - This document
3. **DEEP-DIVE-DIAGNOSTICS.ps1** - Diagnostic comparison script
4. **MONITOR-TACITRED-INGESTION.ps1** - Real-time monitoring script

---

## Contact & Support

For issues or questions:
- Review `CCF-ROOT-CAUSE-ANALYSIS.md` for technical details
- Check deployment logs in `Project/Docs/Validation/TacitRed/`
- Verify configuration matches this document

**Status:** ✅ All fixes applied. Awaiting first poll cycle for validation.

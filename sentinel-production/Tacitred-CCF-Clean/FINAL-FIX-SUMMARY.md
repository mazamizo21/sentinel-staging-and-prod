# TacitRed CCF - Final Complete Fix
**Date:** 2025-11-19  
**Status:** DEPLOYED - Awaiting Validation

---

## Critical Discovery

**Both Logic App AND CCF were broken** - Logic App has 51,800 records but they're EMPTY (all fields except severity_s are blank).

**Root Cause:** TacitRed API returns **deeply nested JSON**, but both implementations expected flat fields.

---

## API Response Structure (Actual)

```json
{
  "results": [
    {
      "activity_id": 1,
      "finding": {
        "supporting_data": {
          "credential": "mustafabky63@gmail.com",  // ← email is HERE (nested!)
          "domain": "sony.com",                    // ← domain is HERE (nested!)
          "date_compromised": "2025-10-04T09:42:00.000Z",
          "stealer": "Generic Stealer"
        },
        "title": "mustafabky63@gmail.com login...",
        "types": ["compromised_credential"]
      },
      "severity": "0.18",  // ← Only top-level field
      "time": "2025-10-26T17:40:08.59941321Z"
    }
  ]
}
```

---

## All Fixes Applied (THREE CRITICAL BUGS)

### Bug #1: Authentication Syntax Error
```json
// BEFORE (BROKEN):
"ApiKey": "[[parameters('tacitRedApiKey')]]"  // Double brackets = escape sequence

// AFTER (FIXED):
"ApiKey": "[parameters('tacitRedApiKey')]"     // Single brackets = parameter reference
```

### Bug #2: Invalid Query Parameter
```json
// BEFORE (BROKEN):
"queryParameters": {
  "types[]": "compromised_credentials",  // Doesn't exist in working Logic App!
  "page_size": 100
}

// AFTER (FIXED):
"queryParameters": {
  "page_size": 100  // Removed types[] parameter
}
```

### Bug #3: Nested JSON Structure Mismatch (**PRIMARY ROOT CAUSE**)

**BEFORE (BROKEN) - Expected flat fields:**
```json
"streamDeclarations": {
  "Custom-TacitRed_Findings_Raw": {
    "columns": [
      {"name": "email", "type": "string"},      // Doesn't exist at top level!
      {"name": "domain", "type": "string"},     // Doesn't exist at top level!
      {"name": "confidence", "type": "int"}     // Wrong type!
    ]
  }
}
```

**AFTER (FIXED) - RawData + parse_json():**
```json
"streamDeclarations": {
  "Custom-TacitRed_Findings_Raw": {
    "columns": [
      {"name": "RawData", "type": "string"}  // Entire JSON object as string
    ]
  }
},
"dataFlows": [{
  "transformKql": "source 
    | extend parsed = parse_json(RawData) 
    | extend supporting_data = parsed['finding']['supporting_data'] 
    | extend tg = todatetime(parsed['time']) 
    | extend TimeGenerated = iif(isnull(tg), now(), tg) 
    | project 
        TimeGenerated, 
        email_s=tostring(supporting_data['credential']),          // Extract nested!
        domain_s=tostring(supporting_data['domain']),             // Extract nested!
        findingType_s=tostring(parsed['finding']['types'][0]),
        confidence_d=toint(toreal(parsed['severity']) * 100),
        firstSeen_t=todatetime(supporting_data['date_compromised']),
        lastSeen_t=todatetime(supporting_data['date_compromised']),
        notes_s=tostring(parsed['finding']['title']),
        source_s=tostring(supporting_data['stealer']),
        severity_s=tostring(parsed['severity']),
        status_s='active',
        detection_ts_t=todatetime(supporting_data['date_compromised']),
        metadata_s=tostring(RawData)"
}]
```

### Bug #4: shouldJoinNestedData Configuration
```json
// BEFORE:
"shouldJoinNestedData": false  // Ignores nested structure

// AFTER:
"shouldJoinNestedData": true   // Enables nested data joining
```

---

## Field Mapping (API → Table)

| API Field | Path | Table Column | Transform |
|-----------|------|--------------|-----------|
| `finding.supporting_data.credential` | Nested | `email_s` | `tostring()` |
| `finding.supporting_data.domain` | Nested | `domain_s` | `tostring()` |
| `finding.types[0]` | Nested array | `findingType_s` | `tostring()` |
| `severity` | Top-level | `severity_s` | `tostring()` |
| `severity` | Top-level | `confidence_d` | `toint(toreal() * 100)` |
| `finding.supporting_data.date_compromised` | Nested | `firstSeen_t`, `lastSeen_t`, `detection_ts_t` | `todatetime()` |
| `finding.title` | Nested | `notes_s` | `tostring()` |
| `finding.supporting_data.stealer` | Nested | `source_s` | `tostring()` |
| `time` | Top-level | `TimeGenerated` | `todatetime()` |

---

## Current Deployment Status

### Environment
- **Resource Group:** `TacitRed-Production-Test-RG`
- **Workspace:** `TacitRed-Production-Test-Workspace`
- **Workspace ID:** `72e125d2-4f75-4497-a6b5-90241feb387a`
- **DCR Immutable ID:** `dcr-5ba1aee090ed412ea5dcbd1485aa2ab2`

### Configuration
```json
{
  "connector": {
    "name": "TacitRedFindings",
    "kind": "RestApiPoller",
    "isActive": true,
    "streamName": "Custom-TacitRed_Findings_Raw",
    "pollingMinutes": 1,
    "apiEndpoint": "https://app.tacitred.com/api/v1/findings",
    "queryParameters": {
      "page_size": 100
    },
    "shouldJoinNestedData": true
  },
  "dcr": {
    "inputStream": "Custom-TacitRed_Findings_Raw",
    "outputStream": "Custom-TacitRed_Findings_CL",
    "inputColumns": ["RawData (string)"],
    "transform": "parse_json → extract nested fields"
  }
}
```

---

## Validation (Pending)

### Expected Results (after ~2 min):
```kql
TacitRed_Findings_CL
| where TimeGenerated > ago(10m)
| take 10
```

**Should show:**
- ✅ `email_s`: "mustafabky63@gmail.com" (NOT empty!)
- ✅ `domain_s`: "sony.com" (NOT empty!)
- ✅ `findingType_s`: "compromised_credential" (NOT empty!)
- ✅ `confidence_d`: 18 (integer, NOT null!)
- ✅ `severity_s`: "0.18"
- ✅ `source_s`: "Generic Stealer" (NOT empty!)
- ✅ `notes_s`: Full finding title (NOT empty!)

---

## Why Previous Attempts Failed

1. **First attempt:** Fixed auth, but still had nested JSON mismatch
2. **Second attempt:** Added two-stream architecture with STRING types, but CCF doesn't serialize nested objects to those flat fields
3. **Third attempt:** Removed `types[]` parameter, enabled `shouldJoinNestedData`, but stream still expected flat fields
4. **FINAL (this):** RawData approach - single string column, parse entire JSON in transformKql, extract all nested fields explicitly

---

## KQL Syntax Lessons Learned

1. ❌ `parsed.time` - Dot notation doesn't work after `parse_json()`
2. ✅ `parsed['time']` - Bracket notation required for JSON property access
3. ❌ `coalesce()` - Not supported in DCR transformKql
4. ✅ `iif(isnull(), ..., ...)` - Use instead of coalesce

---

## Files Modified

1. **mainTemplate.json**
   - Lines 218-226: Changed Raw stream to single RawData column
   - Line 312: Complete transformKql rewrite with parse_json() and nested field extraction
   - Line 596: Fixed auth syntax (removed double brackets)
   - Line 602: Removed invalid `types[]` parameter
   - Line 626: Enabled `shouldJoinNestedData`
   - Line 604: Set polling to 1 minute (for testing)

---

## Next Actions

1. ⏳ **Wait 90-120 seconds** for first poll cycle
2. ✅ **Run validation query** to check for data with populated fields
3. 📊 **Verify field types** (confidence_d should be int, dates should be datetime)
4. 🔄 **Change polling back to 60 minutes** after validation success
5. 📝 **Document successful architecture** for Content Hub package

---

## Success Criteria

- [x] Deployment completes without errors
- [ ] Records appear in TacitRed_Findings_CL
- [ ] email_s field is populated (not empty)
- [ ] domain_s field is populated (not empty)
- [ ] confidence_d is integer type
- [ ] firstSeen_t is datetime type
- [ ] All nested fields successfully extracted

**Status:** Awaiting first poll results (~2 minutes from deployment)

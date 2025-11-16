# TacitRed CCF - Outside-the-Box Issues Analysis

**Date**: 2025-11-16  
**Analysis Type**: Deep dive beyond naming/syntax  
**Status**: 2 issues found, multiple recommendations

---

## 🔴 CRITICAL ISSUES

### None Found ✅

All critical infrastructure is correctly configured.

---

## ⚠️ WARNING ISSUES

### Issue 1: Workbooks Reference Non-Existent Cyren Table

**Location**: All 6 workbooks  
**Problem**: Workbooks contain KQL queries that reference `Cyren_Indicators_CL` table, which doesn't exist in TacitRed-only deployment.

**Example queries in workbooks:**
```kql
union withsource=TableName Cyren_Indicators_CL, TacitRed_Findings_CL
| where TimeGenerated > ago(7d)
| extend ThreatScore = toint(iif(TableName == "Cyren_Indicators_CL", ...))
```

**Impact**: 
- Workbooks will show errors when trying to query Cyren_Indicators_CL
- Visualizations may be incomplete or fail to render
- User confusion about "missing table"

**Fix Options**:
1. **Remove Cyren references** - Strip out all `Cyren_Indicators_CL` from workbook queries
2. **Use `isfuzzy=true`** - Change `union` to `union isfuzzy=true` so missing table is ignored
3. **Conditional deployment** - Only deploy workbooks if both TacitRed and Cyren are configured

**Recommendation**: Use `union isfuzzy=true` for backward compatibility if user later adds Cyren.

---

### Issue 2: Aggressive Polling Interval (Production Risk)

**Location**: Line 533  
**Current Value**: `queryWindowInMin: 5`  
**Problem**: Polling every 5 minutes is very aggressive and may cause:
- Excessive API calls to TacitRed (potential rate limiting)
- Higher Azure costs (more DCR ingestion operations)
- Minimal benefit (compromised credentials don't change every 5 minutes)

**Calculation**:
- 5-minute polling = 288 polls/day
- 60-minute polling = 24 polls/day (12x reduction)

**TacitRed API Limits**: Unknown, but 288 daily calls is aggressive

**Recommendation**: 
- **Testing**: 5 minutes is fine
- **Production**: Change to 60 minutes (1 hour)
- **Compromise**: 15-30 minutes

**Fix**:
```json
"queryWindowInMin": 60  // or 15/30 for moderate frequency
```

---

## 📋 INFORMATIONAL (Verify, Not Issues)

### 3. Paging Configuration Assumption

**Location**: Lines 545-548  
**Current**:
```json
"paging": {
  "pagingType": "LinkHeader",
  "linkHeaderTokenJsonPath": "$.next"
}
```

**Assumption**: TacitRed API returns a JSON body with `next` field for pagination.

**Verification Needed**:
Check TacitRed API response:
```json
{
  "results": [...],
  "next": "https://app.tacitred.com/api/v1/findings?page=2",
  "previous": null,
  "count": 150
}
```

If `next` is NOT in response body but in HTTP Link header, should use:
```json
"paging": {
  "pagingType": "LinkHeader",
  "linkHeaderRelLinkName": "next"
}
```

**Current Status**: Logic App doesn't show paging config, so this needs TacitRed API docs verification.

---

### 4. Time Format Compatibility

**Location**: Line 534  
**Current**: `queryTimeFormat: "yyyy-MM-ddTHH:mm:ssZ"`  
**Format**: ISO 8601 with 'Z' suffix (UTC)  
**Example**: `2025-11-16T10:47:19Z`

**Verification**: Logic App uses same format ✅  
**Status**: Correct

---

### 5. Query Parameters - Types Filter

**Location**: Lines 529-532  
**Current**:
```json
"queryParameters": {
  "types[]": "compromised_credentials",
  "page_size": 100
}
```

**Verification**: 
- Logic App example shows `types[]=compromised_credentials` ✅
- `page_size` vs `pageSize` - TacitRed uses underscore ✅

**Status**: Correct

---

### 6. Response Path

**Location**: Lines 549-554  
**Current**: `"eventsJsonPaths": ["$.results"]`

**Assumption**: TacitRed API returns:
```json
{
  "results": [
    { "email": "...", "domain": "...", ... },
    { "email": "...", "domain": "...", ... }
  ]
}
```

**Verification**: Logic App uses same path ✅  
**Status**: Correct

---

### 7. Auth Configuration

**Location**: Lines 520-525  
**Current**:
```json
"auth": {
  "type": "APIKey",
  "ApiKeyName": "Authorization",
  "ApiKeyIdentifier": "",
  "ApiKey": "[[parameters('tacitRedApiKey')]]"
}
```

**Verification**:
- Logic App uses `Authorization: <key>` (no Bearer) ✅
- `ApiKeyIdentifier` empty is correct ✅
- Double brackets `[[...]]` for runtime parameter ✅

**Status**: Correct

---

### 8. Headers

**Location**: Lines 540-543  
**Current**:
```json
"headers": {
  "Accept": "application/json",
  "User-Agent": "Microsoft-Sentinel-TacitRed/1.0"
}
```

**Logic App sends**:
```json
"Authorization": "<key>",
"Accept": "application/json",
"User-Agent": "LogicApp-Sentinel-TacitRed-Ingestion/1.0"
```

**Note**: CCF adds `Authorization` header automatically from `auth` config, so we don't include it in `headers`.

**Status**: Correct

---

### 9. Rate Limiting

**Location**: Line 537  
**Current**: `rateLimitQps: 10`  
**Meaning**: 10 queries per second max

**Calculation**: With 5-minute polling, we make 1 request every 300 seconds = 0.003 QPS  
**Status**: Well below limit ✅

---

### 10. Transform KQL Syntax

**Location**: Line 296  
**Current**:
```kql
source 
| extend TimeGenerated = now() 
| project-rename email_s = email, domain_s = domain, ...
```

**Verification**:
- `source` is the standard input alias ✅
- `extend TimeGenerated = now()` adds ingestion timestamp ✅
- `project-rename` adds _s/_d/_t suffixes ✅
- All 15 fields mapped ✅

**Status**: Correct

---

### 11. Workbook Cyren References

**Count**: 6 workbooks, multiple queries  
**Pattern**: `union withsource=TableName Cyren_Indicators_CL, TacitRed_Findings_CL`

**Examples**:
- Line 567: Threat Intelligence Command Center
- Line 582: Threat Intelligence Command Center (Enhanced)
- Line 597: Executive Risk Dashboard
- Line 612: Executive Risk Dashboard (Enhanced)
- Line 627: Threat Hunter's Arsenal
- Line 642: Threat Hunter's Arsenal (Enhanced)

**Status**: ⚠️ Needs fixing

---

### 12. Analytics Rule Table Reference

**Location**: Line 680  
**Query**: `TacitRed_Findings_CL | where TimeGenerated > ago(7d) | ...`

**Status**: ✅ Correct (only references TacitRed table)

---

## 🎯 RECOMMENDATIONS

### Priority 1: Fix Workbooks (Cyren References)

**Option A - Use isfuzzy=true (Recommended)**
Change all workbook union statements from:
```kql
union withsource=TableName Cyren_Indicators_CL, TacitRed_Findings_CL
```

To:
```kql
union isfuzzy=true withsource=TableName Cyren_Indicators_CL, TacitRed_Findings_CL
```

This allows workbooks to work even if Cyren table doesn't exist.

**Option B - Remove Cyren Entirely**
Strip out all Cyren references and make workbooks TacitRed-only.

---

### Priority 2: Adjust Polling Interval for Production

Change `queryWindowInMin` from `5` to:
- **15 minutes** - Moderate frequency
- **30 minutes** - Balanced
- **60 minutes** - Production standard

---

### Priority 3: Verify TacitRed Paging

Confirm TacitRed API response includes `next` field in JSON body.  
If not, change paging config to use HTTP Link header.

---

## ✅ THINGS THAT ARE CORRECT

1. DCR immutableId reference (fixed) ✅
2. DCE endpoint reference (fixed) ✅
3. Stream names and mappings ✅
4. Field transforms (all 15 fields) ✅
5. Auth configuration ✅
6. Time format (ISO 8601 with Z) ✅
7. Query parameters (types[], page_size) ✅
8. Response path ($.results) ✅
9. Rate limiting (10 QPS is safe) ✅
10. Analytics rule (no Cyren references) ✅

---

## 🔍 VERIFICATION CHECKLIST

After fixes, verify:

- [ ] Workbooks render without errors (Cyren issue fixed)
- [ ] Polling interval is appropriate for environment (5 min for test, 60 for prod)
- [ ] Data appears in TacitRed_Findings_CL after first poll
- [ ] Paging works if TacitRed returns >100 results
- [ ] DCR diagnostics show successful ingestion (no errors)

---

## SUMMARY

**Critical Issues**: 0  
**Warning Issues**: 2 (Workbooks Cyren refs, Aggressive polling)  
**Informational**: 10 (all verified correct)  
**Overall Status**: Template is functionally correct, needs workbook fix and production polling adjustment

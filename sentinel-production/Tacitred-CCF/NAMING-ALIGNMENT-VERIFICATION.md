# TacitRed CCF Naming Alignment Verification

**Date**: 2025-11-16  
**Template**: mainTemplate.TacitRedFullSolution.json  
**Status**: ✅ ALL NAMES ALIGNED

---

## Summary

Verified all naming and references across the entire data flow pipeline:
- TacitRed API response fields
- DCR stream declaration (input)
- DCR transform KQL
- Custom table schema (output)
- CCF connector configuration
- Analytics rules
- Workbooks

**Result**: All names are correctly aligned. No mismatches found.

---

## 1. Variables (Lines 100-109)

```json
"workspaceResourceId": "[resourceId('Microsoft.OperationalInsights/Workspaces', parameters('workspace'))]"
"dceName": "dce-threatintel-feeds"  ✅
"tacitRedDcrName": "dcr-tacitred-findings"  ✅
"uamiName": "uami-ccf-deployment"  ✅
```

---

## 2. Data Collection Endpoint (Lines 112-121)

```json
"type": "Microsoft.Insights/dataCollectionEndpoints"
"name": "[variables('dceName')]"  → "dce-threatintel-feeds"  ✅
```

**Referenced by:**
- DCR (line 209): ✅ Correct
- Connector (line 541): ✅ Correct via reference()

---

## 3. Custom Table (Lines 123-198)

```json
"type": "Microsoft.OperationalInsights/workspaces/tables"
"name": "[concat(parameters('workspace'), '/TacitRed_Findings_CL')]"  ✅
```

**Schema columns (with suffixes):**
- TimeGenerated (datetime) ✅
- email_s (string) ✅
- domain_s (string) ✅
- findingType_s (string) ✅
- confidence_d (int) ✅
- firstSeen_t (datetime) ✅
- lastSeen_t (datetime) ✅
- notes_s (string) ✅
- source_s (string) ✅
- severity_s (string) ✅
- status_s (string) ✅
- campaign_id_s (string) ✅
- user_id_s (string) ✅
- username_s (string) ✅
- detection_ts_t (datetime) ✅
- metadata_s (string) ✅

**Referenced by:**
- DCR dependsOn (line 206): ✅ Correct
- Connector dataType (line 538): ✅ Correct
- Analytics rule (line 680): ✅ Correct
- Workbooks: ✅ All use TacitRed_Findings_CL

---

## 4. Data Collection Rule (Lines 200-300)

```json
"type": "Microsoft.Insights/dataCollectionRules"
"name": "[variables('tacitRedDcrName')]"  → "dcr-tacitred-findings"  ✅
```

### 4a. Stream Declaration (Lines 210-278)

**Stream name**: `Custom-TacitRed_Findings_CL`  ✅

**Input columns (NO suffixes - matches TacitRed API):**
- TimeGenerated (datetime) ✅
- email (string) ✅
- domain (string) ✅
- findingType (string) ✅
- confidence (int) ✅
- firstSeen (datetime) ✅
- lastSeen (datetime) ✅
- notes (string) ✅
- source (string) ✅
- severity (string) ✅
- status (string) ✅
- campaign_id (string) ✅
- user_id (string) ✅
- username (string) ✅
- detection_ts (datetime) ✅
- metadata (string) ✅

### 4b. Transform KQL (Line 296)

```kql
source 
| extend TimeGenerated = now() 
| project-rename 
    email_s = email,           ✅
    domain_s = domain,         ✅
    findingType_s = findingType,  ✅
    confidence_d = confidence,     ✅
    firstSeen_t = firstSeen,       ✅
    lastSeen_t = lastSeen,         ✅
    notes_s = notes,               ✅
    source_s = source,             ✅
    severity_s = severity,         ✅
    status_s = status,             ✅
    campaign_id_s = campaign_id,   ✅
    user_id_s = user_id,           ✅
    username_s = username,         ✅
    detection_ts_t = detection_ts, ✅
    metadata_s = metadata          ✅
```

**Verification:**
- Input names (right side): Match stream declaration ✅
- Output names (left side): Match table schema ✅
- All 15 fields mapped correctly ✅

### 4c. Data Flow (Lines 288-299)

```json
"streams": ["Custom-TacitRed_Findings_CL"]  ✅ Matches stream declaration
"outputStream": "Custom-TacitRed_Findings_CL"  ✅ Matches stream name
"destinations": ["clv2ws1"]  ✅ Matches destination name (line 284)
```

### 4d. Destination (Lines 280-286)

```json
"logAnalytics": [{
  "workspaceResourceId": "[variables('workspaceResourceId')]"  ✅
  "name": "clv2ws1"  ✅
}]
```

**Referenced by:**
- dataFlows.destinations (line 293): ✅ Correct

---

## 5. CCF Connector Definition (Lines 449-523)

```json
"name": "[concat(parameters('workspace'), '/Microsoft.SecurityInsights/', 'TacitRedThreatIntel')]"  ✅
"graphQueriesTableName": "TacitRed_Findings_CL"  ✅
"baseQuery": "TacitRed_Findings_CL"  ✅
"dataTypes": [{"name": "TacitRed_Findings_CL"}]  ✅
```

---

## 6. CCF Connector Instance (Lines 525-598)

```json
"name": "[concat(parameters('workspace'), '/Microsoft.SecurityInsights/', 'TacitRedFindings')]"  ✅
"connectorDefinitionName": "TacitRedThreatIntel"  ✅ Matches definition
"dataType": "TacitRed_Findings_CL"  ✅ Matches table
```

### 6a. DCR Config (Lines 539-543)

```json
"streamName": "Custom-TacitRed_Findings_CL"  ✅ Matches DCR stream
"dataCollectionEndpoint": "[reference(...dceName...)]"  ✅ References correct DCE
"dataCollectionRuleImmutableId": "[reference(...tacitRedDcrName...)]"  ✅ References correct DCR
```

**FIXED**: Removed 'full' parameter to prevent caching ✅

### 6b. Request Config (Lines 550-567)

```json
"apiEndpoint": "https://app.tacitred.com/api/v1/findings"  ✅
"queryParameters": {
  "types[]": "compromised_credentials",  ✅
  "page_size": 100  ✅
}
```

### 6c. Response Config (Lines 573-577)

```json
"eventsJsonPaths": ["$.results"]  ✅ Matches TacitRed API response structure
```

---

## 7. Analytics Rule (Lines 674-761)

```json
"dependsOn": [
  "[resourceId('Microsoft.OperationalInsights/workspaces/tables', parameters('workspace'), 'TacitRed_Findings_CL')]"  ✅
]
"query": "TacitRed_Findings_CL | where TimeGenerated > ago(7d) | ..."  ✅
```

Uses correct table name and column references (email_s, username_s, etc.) ✅

---

## 8. Workbooks (Lines 580-673)

All 6 workbooks reference:
- Table: `TacitRed_Findings_CL` ✅
- Columns: `email_s`, `domain_s`, `confidence_d`, `source_s`, etc. ✅
- Workspace: `[variables('workspaceResourceId')]` ✅

---

## Data Flow Verification

### Complete Pipeline

```
TacitRed API Response ($.results)
    ↓
    fields: email, domain, findingType, confidence, etc. (no suffixes)
    ↓
CCF Connector (TacitRedFindings)
    ↓
    eventsJsonPaths: ["$.results"]
    ↓
DCE (dce-threatintel-feeds)
    ↓
DCR (dcr-tacitred-findings)
    ↓
    Stream: Custom-TacitRed_Findings_CL
    Input columns: email, domain, findingType, etc. (no suffixes)
    ↓
    Transform KQL: project-rename to add suffixes
    ↓
    Output: email_s, domain_s, findingType_s, etc. (with suffixes)
    ↓
Custom Table (TacitRed_Findings_CL)
    ↓
    Columns: email_s, domain_s, findingType_s, etc. (with suffixes)
    ↓
Analytics Rules & Workbooks
    ↓
    Query: TacitRed_Findings_CL | where ... email_s, domain_s, etc.
```

**Status**: ✅ ALL ALIGNED - No breaks in the pipeline

---

## Known Issues (RESOLVED)

### 1. DCR ImmutableId Mismatch ✅ FIXED
- **Issue**: ARM reference() was returning cached immutableId
- **Fix**: Removed 'full' parameter from reference() calls (line 541-542)
- **Status**: Fixed in template, manually corrected in current deployment

---

## Validation Checklist

After deployment, verify:

- [ ] DCE exists: `dce-threatintel-feeds`
- [ ] DCR exists: `dcr-tacitred-findings`
- [ ] Table exists: `TacitRed_Findings_CL` with 16 columns
- [ ] Connector exists: `TacitRedFindings` with `isActive: true`
- [ ] DCR immutableId matches between DCR and connector
- [ ] Stream name in connector matches DCR: `Custom-TacitRed_Findings_CL`
- [ ] Data flows after 10-15 minutes: `TacitRed_Findings_CL | count > 0`

---

## Conclusion

✅ **ALL NAMING IS CORRECTLY ALIGNED**

No mismatches found in:
- Resource names
- Variable references
- Stream declarations
- Transform mappings
- Table schema
- Connector configuration
- Analytics rules
- Workbooks

The only issue was the DCR immutableId caching, which has been fixed.

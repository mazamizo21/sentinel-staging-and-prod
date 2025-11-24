# Official Microsoft Documentation-Based Fix
**Source:** https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-transformations-structure

## Problem
TacitRed API returns nested JSON, but we were treating it as strings.

## Official Solution

### Step 1: Define Stream with `dynamic` Type

According to [Microsoft Docs on DCR Structure](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-structure), stream declarations support the `dynamic` data type.

**Current (Wrong):**
```json
"Custom-TacitRed_Findings_Raw": {
  "columns": [
    {"name": "RawData", "type": "string"}  // ❌ Wrong!
  ]
}
```

**Correct (Per Official Docs):**
```json
"Custom-TacitRed_Findings_Raw": {
  "columns": [
    {"name": "finding", "type": "dynamic"},      // ✅ Nested object
    {"name": "severity", "type": "string"},      // ✅ Top-level field
    {"name": "time", "type": "string"},          // ✅ Top-level field
    {"name": "activity_id", "type": "int"},      // ✅ Top-level field
    {"name": "category_uid", "type": "int"},
    {"name": "class_id", "type": "int"},
    {"name": "severity_id", "type": "int"},
    {"name": "state_id", "type": "int"}
  ]
}
```

### Step 2: Transform with parse_json()

According to [Microsoft Docs on Transformations](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-transformations-structure#handling-dynamic-data):

**Example from Docs:**
```kql
source 
| extend parsedAdditionalContext = parse_json(AdditionalContext) 
| extend Level = toint(parsedAdditionalContext.Level) 
| extend DeviceId = tostring(parsedAdditionalContext.DeviceID)
```

**Applied to TacitRed:**
```kql
source 
| extend parsed_finding = parse_json(finding)
| extend supporting_data = parsed_finding.supporting_data
| extend types_array = parsed_finding.types
| extend time_value = todatetime(column_ifexists('time', ''))
| extend TimeGenerated = iif(isnull(time_value), now(), time_value)
| project 
    TimeGenerated,
    email_s = tostring(supporting_data.credential),
    domain_s = tostring(supporting_data.domain),
    findingType_s = tostring(types_array[0]),
    confidence_d = toint(toreal(severity) * 100),
    firstSeen_t = todatetime(supporting_data.date_compromised),
    lastSeen_t = todatetime(supporting_data.date_compromised),
    notes_s = tostring(parsed_finding.title),
    source_s = tostring(supporting_data.stealer),
    severity_s = tostring(severity),
    status_s = 'active',
    campaign_id_s = '',
    user_id_s = '',
    username_s = '',
    detection_ts_t = todatetime(supporting_data.date_compromised),
    metadata_s = tostring(finding)
```

## Implementation Plan

### For Logic App DCR:

1. Update stream declaration to use `dynamic` type for `finding`
2. Update transformKql with proper `parse_json()` and dot notation
3. Test with manual Logic App trigger

### For CCF Connector:

1. Update stream declaration in mainTemplate.json
2. Update transformKql
3. Remove `shouldJoinNestedData` (not needed with dynamic type)
4. Redeploy and test

## Key Differences from Previous Attempts

| Attempt | Approach | Issue |
|---------|----------|-------|
| 1-3 | Flat fields (string) | Nested data ignored |
| 4 | RawData as string | `time` is reserved keyword, complex escaping |
| **5 (This)** | **`dynamic` type** | **Official Microsoft approach** ✅ |

## References

- [DCR Structure - Stream Declarations](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-structure)
- [Transformations - Handling Dynamic Data](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-transformations-structure#handling-dynamic-data)
- [Supported KQL in Transformations](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-transformations-structure)

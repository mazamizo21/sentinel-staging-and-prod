# TacitRed CCF Hub v2 - Deployment Report
**Date:** 2025-11-26  
**Deployment Target:** sentinel-production Resource Group  
**Status:** ✅ SUCCESSFUL

---

## Deployment Summary

### Critical Fix Applied
**Microsoft Support Guidance:** Removed duplicate `Custom-TacitRed_Findings_CL` stream declaration from DCR `streamDeclarations` section per Microsoft ticket feedback.

**Issue:** The CL table schema was incorrectly duplicated in the DCR JSON. The schema should only exist in:
1. `Microsoft.OperationalInsights/workspaces/tables` resource (table definition)
2. The `outputStream` reference in `dataFlows`

**Fix:** Removed lines 233-300 from mainTemplate.json containing the duplicate CL stream declaration. Only the `Custom-TacitRed_Findings_Raw` stream remains in `streamDeclarations`.

### Infrastructure Deployed

| Resource Type | Resource Name | Status | Notes |
|--------------|---------------|---------|-------|
| Resource Group | sentinel-production | ✅ Created | Location: East US |
| Log Analytics Workspace | sentinel-production-ws | ✅ Created | SKU: PerGB2018, Retention: 30 days |
| Sentinel Solution | SecurityInsights | ✅ Enabled | Onboarded via ARM API |
| Data Collection Endpoint | dce-threatintel-feeds | ✅ Deployed | Public network enabled |
| Custom Table | TacitRed_Findings_CL | ✅ Deployed | 16 columns defined |
| Data Collection Rule | dcr-tacitred-findings | ✅ Deployed | ImmutableId: dcr-0128d1482fd64bb5a8b7ca486582f9a5 |
| Managed Identity | uami-ccf-deployment | ✅ Deployed | For deployment automation |
| CCF Connector Definition | TacitRedThreatIntel | ✅ Deployed | Customizable kind |
| CCF Data Connector | TacitRedFindings | ✅ Deployed | RestApiPoller type |
| Analytics Rule | Repeat Compromise Detection | ✅ Deployed | Scheduled, High severity |
| Workbook | TacitRed SecOps | ✅ Deployed | Compromised Credentials triage |

### Deployment Parameters Used

```json
{
  "workspace": "sentinel-production-ws",
  "workspace-location": "eastus",
  "location": "eastus",
  "tacitRedApiKey": "*** (secured)",
  "deployAnalytics": true,
  "deployWorkbooks": true,
  "deployConnectors": true,
  "enableKeyVault": false
}
```

---

## DCR Configuration (Corrected)

### Stream Declarations
**Before Fix:**
- `Custom-TacitRed_Findings_Raw` ✅ (API input format)
- `Custom-TacitRed_Findings_CL` ❌ (duplicate - removed)

**After Fix:**
- `Custom-TacitRed_Findings_Raw` ✅ (API input format only)

### Data Flow
- **Input Stream:** `Custom-TacitRed_Findings_Raw`
- **Transform KQL:** Parses dynamic `finding` field and maps to CL schema
- **Output Stream:** `Custom-TacitRed_Findings_CL`
- **Destination:** Log Analytics workspace `clv2ws1`

### Transform Logic
```kql
source 
| project TimeGenerated=now(), 
    email_s=tostring(finding.supporting_data.credential), 
    domain_s=tostring(finding.supporting_data.domain), 
    findingType_s=tostring(finding.uid), 
    confidence_d=toint(75), 
    ...
```

---

## CCF Connector Configuration

### API Configuration
- **Endpoint:** `https://app.tacitred.com/api/v1/findings`
- **Method:** GET
- **Authentication:** APIKey (Bearer token)
- **Query Window:** 60 minutes
- **Rate Limit:** 10 QPS
- **Retry Count:** 3
- **Timeout:** 60 seconds

### Polling Configuration
- **Query Parameters:**
  - `page_size`: 100
  - `types[]`: compromised_credentials
  - `from`: (dynamic, last poll time)
  - `until`: (dynamic, current time)

### Response Handling
- **Events Path:** `$.results`
- **Paging Type:** LinkHeader
- **Link Path:** `$.next`
- **Format:** JSON

---

## Validation Steps

### Immediate Checks
1. ✅ DCR deployed with correct immutableId
2. ✅ Custom table `TacitRed_Findings_CL` created in workspace
3. ✅ CCF connector definition registered
4. ✅ CCF data connector instance created
5. ⏳ Waiting for first data ingestion (polling interval: 60 min)

### Post-Deployment Validation Queries

```kql
// Check connector health
SecurityInsightsDataConnectorLogs
| where TimeGenerated > ago(24h)
| where ConnectorName contains "TacitRed"
| project TimeGenerated, ConnectorName, Status, ErrorMessage
| order by TimeGenerated desc

// Check DCR ingestion
ADXTableUsageStatistics
| where TimeGenerated > ago(24h)
| where TableName == "TacitRed_Findings_CL"
| summarize RecordCount=sum(Quantity) by bin(TimeGenerated, 1h)

// Verify table schema
TacitRed_Findings_CL
| getschema

// First data check (after initial poll)
TacitRed_Findings_CL
| where TimeGenerated > ago(2h)
| take 10
```

---

## Comparison with LogicApp Solution

### LogicApp DCR (Working)
- Uses flat column structure in `Custom-TacitRed_Findings_Raw`
- 15 string columns for API fields
- Transform KQL uses `tostring()`, `toint()`, `todatetime()` conversions
- Reference: `/TacitRed-LogicApp-Production/infrastructure/bicep/dcr-tacitred-findings.bicep`

### CCF DCR (Fixed)
- Uses dynamic `finding` field for API response
- Single `dynamic` column + `severity` string
- Transform KQL parses JSON from dynamic field
- Aligns with Microsoft CCF best practices

---

## Key Differences from Original

| Aspect | Original | Fixed |
|--------|----------|-------|
| streamDeclarations | 2 streams (Raw + CL) | 1 stream (Raw only) |
| CL Schema Location | Duplicated in DCR | Only in table definition |
| ARM Validation | Failed | Passed ✅ |
| Microsoft Guidance | Not followed | Implemented ✅ |

---

## Next Steps

1. **Monitor First Poll:** Wait 60 minutes for initial data ingestion
2. **Validate Data Flow:** Run validation queries to confirm records in `TacitRed_Findings_CL`
3. **Check Connector Logs:** Review `SecurityInsightsDataConnectorLogs` for any errors
4. **Test Analytics Rule:** Verify "Repeat Compromise Detection" rule triggers correctly
5. **Review Workbook:** Confirm "TacitRed SecOps" workbook displays data

---

## Troubleshooting Reference

### If No Data After 2 Hours
1. Check connector status in Sentinel portal
2. Review DCR diagnostic logs
3. Verify API key is valid and has correct permissions
4. Check TacitRed API endpoint accessibility
5. Review polling configuration (query window, parameters)

### Common Issues
- **401 Unauthorized:** API key invalid or expired
- **Empty Results:** No new findings in time window
- **Transform Errors:** JSON structure mismatch in `finding` field
- **Rate Limiting:** Adjust `rateLimitQps` if needed

---

## Deployment Artifacts

- **Main Template:** `/Tacitred-CCF-Hub-v2/Package/mainTemplate.json`
- **Parameters File:** `/Tacitred-CCF-Hub-v2/deployment-parameters.json`
- **Deployment Name:** `tacitred-ccf-20251126-200310`
- **Deployment Log:** Stored in Azure Portal deployment history

---

## Conclusion

✅ **Deployment Successful**  
✅ **Microsoft Support Fix Applied**  
✅ **All Resources Deployed**  
⏳ **Awaiting First Data Ingestion**

The TacitRed CCF connector is now deployed with the corrected DCR configuration per Microsoft support guidance. The duplicate CL stream declaration has been removed, allowing the CCF RestApiPoller to function correctly.

**Next Validation Window:** Check data ingestion status in 60-90 minutes.

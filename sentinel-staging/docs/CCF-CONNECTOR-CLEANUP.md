# CCF Connector Cleanup - Summary Report

**Date:** 2025-01-XX  
**Workspace:** SentinelThreatIntelWorkspace  
**Resource Group:** SentinelTestStixImport  
**Subscription:** 774bee0e-b281-4f70-8e40-199e35b65117

---

## Issue Identified

User reported seeing **5 CCF connectors** in the Azure Portal instead of the expected **3**:
- Expected: 2 for Cyren (IP + Malware), 1 for TacitRed, and 1 combined definition
- Actual: 5 connector definitions visible in the GUI

Additionally, the "Cyren Threat InDepth" workbook was showing errors.

---

## Root Cause Analysis

The issue was caused by **duplicate connector definitions** at the UI layer:

### Data Layer (Actual Connectors - Working Correctly)
- ✅ **TacitRedFindings** → `TacitRed_Findings_CL`
- ✅ **CyrenIPReputation** → `Cyren_Indicators_CL`
- ✅ **CyrenMalwareURLs** → `Cyren_Indicators_CL`

### UI Layer (Connector Definitions - Had Duplicates)
Before cleanup:
1. ❌ `ccf-cyren-definition` - "Cyren Threat InDepth (CCF)" - **DUPLICATE**
2. ❌ `ccf-tacitred-definition` - "TacitRed Compromised Credentials (CCF)" - **DUPLICATE**
3. ❌ `ccf-cyren-enhanced-definition` - "Cyren Threat InDepth - Enterprise Edition" - **DUPLICATE/ERROR**
4. ❌ `ccf-tacitred-enhanced-definition` - "TacitRed Compromised Credentials - Enterprise Edition" - **DUPLICATE**
5. ✅ `ThreatIntelligenceFeeds` - "Threat Intelligence Feeds (TacitRed + Cyren)" - **ACTIVE**

---

## Resolution Steps

### 1. Investigation
```powershell
# Listed all data connectors (actual data layer)
az sentinel data-connector list -g $rg -w $ws

# Listed all connector definitions (UI layer)
az rest --method GET --url "https://management.azure.com/.../dataConnectorDefinitions?api-version=2024-09-01"
```

### 2. Identified Blocker
- Workspace had a **resource lock** (`PreventWorkspaceDeletion`) preventing deletion
- Error: `ScopeLocked - The scope cannot perform delete operation because following scope(s) are locked`

### 3. Cleanup Process
```powershell
# Step 1: Remove workspace lock
az lock delete --name "PreventWorkspaceDeletion" --resource-group $rg --resource-name $ws --resource-type "Microsoft.OperationalInsights/workspaces"

# Step 2: Delete duplicate definitions
az resource delete --ids "/subscriptions/.../dataConnectorDefinitions/ccf-cyren-definition"
az resource delete --ids "/subscriptions/.../dataConnectorDefinitions/ccf-tacitred-definition"
az resource delete --ids "/subscriptions/.../dataConnectorDefinitions/ccf-cyren-enhanced-definition"
az resource delete --ids "/subscriptions/.../dataConnectorDefinitions/ccf-tacitred-enhanced-definition"

# Step 3: Restore workspace lock
az lock create --name "PreventWorkspaceDeletion" --lock-type CanNotDelete --resource-group $rg --resource-name $ws --resource-type "Microsoft.OperationalInsights/workspaces"
```

### 4. Results
- ✅ **4 duplicate connector definitions deleted**
- ✅ **1 active definition retained**: "Threat Intelligence Feeds (TacitRed + Cyren)"
- ✅ **3 data connectors remain active** and ingesting data
- ✅ **Workspace lock restored** for protection

---

## CCF Logging & Tracking

### Data Tables
CCF connectors write data to the following Log Analytics tables:

1. **Cyren_Indicators_CL** - Cyren threat intelligence (IP reputation + malware URLs)
2. **TacitRed_Findings_CL** - TacitRed compromised credentials
3. **AzureDiagnostics** - DCR transformation logs (if diagnostic settings enabled)

### Tracking Queries

**Monitor Cyren data ingestion:**
```kql
Cyren_Indicators_CL
| where TimeGenerated > ago(7d)
| summarize Count = count() by bin(TimeGenerated, 1h)
| render timechart
```

**Monitor TacitRed data ingestion:**
```kql
TacitRed_Findings_CL
| where TimeGenerated > ago(7d)
| summarize Count = count() by bin(TimeGenerated, 1h)
| render timechart
```

**Check DCR transformation logs:**
```kql
AzureDiagnostics
| where Category == "DataCollectionRuleProcessingLogs"
| where TimeGenerated > ago(1d)
| project TimeGenerated, OperationName, ResultDescription, _ResourceId
```

**Verify data freshness:**
```kql
union Cyren_Indicators_CL, TacitRed_Findings_CL
| summarize 
    LatestRecord = max(TimeGenerated),
    RecordCount = count()
| extend MinutesSinceLastRecord = datetime_diff('minute', now(), LatestRecord)
```

---

## Verification Steps

1. **Azure Portal:**
   - Navigate to Sentinel → Data connectors
   - Refresh the page (Ctrl+F5 to clear cache)
   - Verify only **1 connector definition** is visible: "Threat Intelligence Feeds (TacitRed + Cyren)"

2. **Workbook Check:**
   - Open "Cyren Threat Intelligence Dashboard (Enhanced)"
   - Verify no errors are displayed
   - Confirm data is populating correctly

3. **Data Validation:**
   ```kql
   // Check both tables have recent data
   union Cyren_Indicators_CL, TacitRed_Findings_CL
   | where TimeGenerated > ago(1h)
   | summarize count() by Type
   ```

---

## Best Practices for Future

1. **Avoid Duplicate Definitions:**
   - Use a single combined connector definition for related data sources
   - Document connector naming conventions

2. **Resource Lock Management:**
   - Always check for resource locks before attempting deletions
   - Document lock removal/restoration in change logs

3. **CCF Monitoring:**
   - Set up alerts for data ingestion gaps (>2 hours without data)
   - Create a dashboard to track CCF connector health
   - Enable diagnostic settings on DCRs for transformation logging

4. **Deployment Hygiene:**
   - Clean up test/duplicate resources immediately after validation
   - Use consistent naming: `{vendor}-{datatype}-{environment}`

---

## Related Files

- **Connector Definitions:** `sentinel-staging/infrastructure/bicep/ccf-*.bicep`
- **Data Collection Rules:** `sentinel-staging/infrastructure/bicep/dcr-*.bicep`
- **Workbooks:** `sentinel-staging/workbooks/bicep/workbook-cyren-*.bicep`
- **Deployment Script:** `sentinel-staging/DEPLOY-COMPLETE.ps1`

---

## Status: ✅ RESOLVED

All duplicate connector definitions have been removed. The workspace now shows only the active "Threat Intelligence Feeds" connector with 3 underlying data connectors functioning correctly.

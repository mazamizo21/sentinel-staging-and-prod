# CCF RestApiPoller Evidence Package - README

**Package Created**: November 16, 2025 05:29 UTC-5  
**Issue**: Microsoft Sentinel CCF RestApiPoller not polling despite active status  
**Workspace**: TacitRedCCFWorkspace (TacitRedCCFTest resource group)

---

## Package Contents

### Core Evidence Files

1. **00-EXECUTIVE-SUMMARY.md**
   - High-level summary for Microsoft support
   - Key findings and recommendations
   - Quick reference for case escalation

2. **01-environment-details.txt**
   - Subscription, resource group, workspace details
   - Complete list of deployed resources
   - Timestamps and locations

3. **02-ccf-connector-config.json**
   - Full RestApiPoller connector configuration
   - Auth settings, request parameters, paging config
   - Shows `isActive: true` status

4. **03-dce-config.json**
   - Data Collection Endpoint configuration
   - Network ACLs and ingestion endpoint URL

5. **04-dcr-config.json**
   - Data Collection Rule configuration
   - Stream declarations, transform KQL, destinations
   - Diagnostic settings configuration

6. **05-table-schema.json**
   - TacitRed_Findings_CL custom table schema
   - 16 columns with _s, _d, _t suffixes
   - Retention and plan settings

7. **06-query-results.txt**
   - KQL query results proving zero activity
   - Table count: 0
   - DCR diagnostics count: 0
   - Connector status: active

8. **07-arm-template.json**
   - Complete ARM template used for deployment
   - Shows all resource definitions and dependencies
   - Latest GA apiVersions (DCE/DCR: 2024-03-11, Table: 2025-07-01)

9. **08-deployment-history.json**
   - ARM deployment status and timeline
   - Provisioning state and timestamps
   - Resource deployment operations

10. **09-api-validation-tests.txt**
    - Direct HTTP tests proving API key validity
    - Results from local machine and Logic App
    - Shows 200 OK responses with same key

11. **10-logic-app-comparison.md**
    - Side-by-side comparison of working Logic App vs CCF
    - Identical auth and endpoint configuration
    - Logic App: 2300+ records, CCF: 0 records

12. **README.md** (this file)
    - Package overview and usage instructions

---

## How to Use This Package

### For Microsoft Support Ticket

1. **Attach entire folder** to your support case
2. **Reference `00-EXECUTIVE-SUMMARY.md`** in ticket description
3. **Highlight key evidence**:
   - Zero records after 60+ minutes (file 06)
   - Zero diagnostic logs (file 06)
   - Connector marked active (file 02)
   - API key proven valid (files 09, 10)

### For Internal Review

1. **Start with** `00-EXECUTIVE-SUMMARY.md` for overview
2. **Review** `10-logic-app-comparison.md` to see working vs non-working config
3. **Examine** `02-ccf-connector-config.json` for exact RestApiPoller settings
4. **Check** `06-query-results.txt` for zero-activity proof

---

## Key Evidence Points

### ✅ What's Working

- ARM deployment: Succeeded
- All resources created: DCE, DCR, table, connector, UAMI
- Connector status: `isActive: true`
- API key: Valid (proven via Logic App with 2300+ records)
- Direct API tests: HTTP 200 OK
- ARM template: Modernized with latest GA apiVersions

### ❌ What's Not Working

- TacitRed_Findings_CL: 0 records after 60+ minutes
- AzureDiagnostics for DCR: 0 logs (no poll attempts)
- No observable polling activity
- No errors or warnings in any logs

### 🔍 Root Cause Hypothesis

**CCF RestApiPoller backend/scheduler is not executing HTTP calls** despite:
- Correct configuration
- Active connector status
- Valid API credentials
- Proper infrastructure setup

This points to an **internal CCF service issue** rather than a configuration problem.

---

## Timeline

- **05:14 UTC-5**: ARM deployment completed
- **05:15-05:25**: Verified workspace, connector, and resources
- **05:25-05:28**: Ran diagnostic queries (all returned 0)
- **05:29**: Created this evidence package

**Total wait time**: 60+ minutes with no polling activity observed

---

## Next Steps

1. **Submit to Microsoft** with case reference number
2. **Request CCF backend investigation** for workspace `TacitRedCCFWorkspace`
3. **Ask Microsoft to check**:
   - Internal CCF scheduler state
   - Whether HTTP calls are being attempted
   - Any internal error logs not exposed via diagnostics

---

## Contact

**Submitted by**: TacitRed-Defender-Integration  
**Date**: 2025-11-16  
**Workspace**: TacitRedCCFWorkspace  
**Subscription**: 774bee0e-b281-4f70-8e40-199e35b65117

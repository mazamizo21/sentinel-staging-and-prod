# Microsoft Sentinel CCF RestApiPoller Issue - Evidence Package

**Date**: November 16, 2025  
**Subscription**: 774bee0e-b281-4f70-8e40-199e35b65117  
**Resource Group**: TacitRedCCFTest  
**Workspace**: TacitRedCCFWorkspace (East US)  
**Issue**: CCF RestApiPoller connector active but not polling/ingesting data

---

## Executive Summary

We deployed a clean Microsoft Sentinel CCF RestApiPoller connector for TacitRed compromised credentials ingestion. Despite correct ARM template configuration, active connector status, and a proven-working API key (validated via Logic Apps with 2300+ successful ingestions), the CCF connector shows **zero ingestion activity** and **zero diagnostic logs** after 60+ minutes.

### Key Findings

1. **Infrastructure Deployed Successfully**
   - ✅ Data Collection Endpoint (DCE): `dce-threatintel-feeds`
   - ✅ Data Collection Rule (DCR): `dcr-tacitred-findings` with diagnostics enabled
   - ✅ Custom Table: `TacitRed_Findings_CL` (16 columns)
   - ✅ CCF Connector: `TacitRedFindings` (RestApiPoller, isActive=true)
   - ✅ User-Assigned Managed Identity with proper RBAC

2. **Zero Ingestion Activity**
   - `TacitRed_Findings_CL`: 0 records after 60+ minutes
   - `AzureDiagnostics` for DCR: 0 logs (no poll attempts visible)
   - No errors, no warnings, no activity

3. **API Key Validated Externally**
   - Same API key works in Azure Logic Apps (2300+ records ingested)
   - Direct HTTP tests from local machine: 200 OK
   - Endpoint: `https://app.tacitred.com/api/v1/findings`
   - Auth: `Authorization: <api-key>` (no Bearer prefix)

4. **ARM Template Modernized**
   - Updated to latest GA apiVersions:
     - DCE/DCR: `2024-03-11`
     - Custom Table: `2025-07-01`
     - Key Vault: `2025-05-01`
   - Removed deploymentScripts (ARM-only)
   - Added `types[]=compromised_credentials` query parameter
   - Paging aligned with CCF docs: `LinkHeader` with `$.next`

### Conclusion

**This is strong evidence of a Microsoft Sentinel CCF RestApiPoller backend/scheduler issue.** The connector is marked active, all infrastructure is correct, the API key is valid, but there is no observable polling activity or diagnostic output after extensive wait time.

---

## Evidence Files in This Package

1. `00-EXECUTIVE-SUMMARY.md` - This file
2. `01-environment-details.txt` - Subscription, RG, workspace, deployed resources
3. `02-ccf-connector-config.json` - Full RestApiPoller configuration
4. `03-dce-config.json` - Data Collection Endpoint configuration
5. `04-dcr-config.json` - Data Collection Rule configuration with transform
6. `05-table-schema.json` - TacitRed_Findings_CL table schema
7. `06-query-results.txt` - KQL query results showing zero data/diagnostics
8. `07-arm-template.json` - Final ARM template used for deployment
9. `08-deployment-history.txt` - ARM deployment status and timeline
10. `09-api-validation-tests.txt` - Direct API tests proving key validity
11. `10-logic-app-comparison.md` - Working Logic App config for comparison

---

## Recommended Microsoft Actions

1. **Investigate CCF RestApiPoller backend** for workspace `TacitRedCCFWorkspace`:
   - Check internal scheduler state for connector `TacitRedFindings`
   - Verify if HTTP calls are being attempted to TacitRed API
   - Review any internal error logs not exposed via diagnostics

2. **Confirm secure parameter handling** in RestApiPoller:
   - Validate that `[[parameters('tacitRedApiKey')]]` syntax is supported
   - Confirm runtime key injection is working (vs deployment-time only)

3. **Provide guidance** on:
   - Expected time-to-first-poll for new RestApiPoller connectors
   - How to troubleshoot "active but not polling" scenarios
   - Whether additional diagnostics can be enabled for CCF backend

---

## Contact Information

**Submitted by**: TacitRed-Defender-Integration  
**Timestamp**: 2025-11-16 05:29:00 UTC-5  
**Case Reference**: [Your Microsoft case number]

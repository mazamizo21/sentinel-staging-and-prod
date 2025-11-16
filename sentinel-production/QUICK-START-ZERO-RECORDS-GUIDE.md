# Quick Start Guide - Zero Records Issue Resolution

**Purpose:** Immediate action plan to diagnose and resolve zero records issue  
**Time to Resolution:** 15-60 minutes depending on root cause  

---

## 🚀 IMMEDIATE ACTIONS (5 minutes)

### Step 1: Run Enhanced Diagnostic
```powershell
cd sentinel-production
.\ENHANCED-ZERO-RECORDS-DIAGNOSTIC.ps1 -FocusArea "All" -RunAPIs
```

### Step 2: Check Generated Report
```powershell
# View the latest diagnostic report
Get-ChildItem ".\docs\enhanced-zero-records-diagnostic-*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { 
    Get-Content $_.FullName | ConvertFrom-Json | ConvertTo-Json -Depth 5
}
```

---

## 📊 EXPECTED OUTCOMES

### Scenario A: "TacitRedNoUpstreamData"
**What this means:** APIs working, but no threat data available  
**Is this bad?** No - may be normal if no current threats  
**Action:** Monitor over longer periods, contact TacitRed if needed

### Scenario B: "CyrenCCFIssue"  
**What this means:** Connector configuration problems  
**Is this bad?** Yes - fixable technical issue  
**Action:** Run generated fix script to repair CCF connectors

### Scenario C: "Healthy"
**What this means:** All components working, data flowing  
**Is this bad?** No - issue resolved or was temporary  
**Action:** Verify with KQL queries in workbooks

---

## 🔧 TARGETED FIXES

### If Only TacitRed Empty
```powershell
# Test longer time ranges
.\TEST-TACITRED-API.ps1 -TimeRangeHours 168 -Detailed

# Monitor API for 24 hours
while($true) {
    .\TEST-TACITRED-API.ps1 -TimeRangeHours 1
    Start-Sleep 3600  # Wait 1 hour
}
```

### If Only Cyren Empty
```powershell
# Generate and run CCF fix
.\ENHANCED-ZERO-RECORDS-DIAGNOSTIC.ps1 -FocusArea "Cyren" -GenerateFixes
.\generated-fixes\Fix-Cyren-CCF-Connectors.ps1

# Verify fix
az rest --method GET --uri "https://management.azure.com/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/SentinelTestStixImport/providers/Microsoft.OperationalInsights/workspaces/SentinelThreatIntelWorkspace/providers/Microsoft.SecurityInsights/dataConnectors/CyrenIPReputation?api-version=2024-09-01"
```

### If Both Empty
```powershell
# Full comprehensive diagnostic
.\DIAGNOSE-ZERO-RECORDS.ps1 -Detailed -TestAPIs

# Check all possible table names
# Run VERIFY-TABLE-STATUS.kql in Log Analytics
```

---

## 📋 VERIFICATION CHECKLIST

### Post-Fix Verification
- [ ] Run diagnostic script again
- [ ] Check table counts in Log Analytics
- [ ] Verify data freshness (< 6 hours old)
- [ ] Test workbook visualizations
- [ ] Confirm Logic Apps running successfully

### Success Indicators
✅ Diagnostic shows "Healthy" or "NoUpstreamData" (not configuration errors)  
✅ Tables show record counts > 0  
✅ Data freshness < 6 hours  
✅ Workbooks display visualizations  
✅ No connector errors in logs  

---

## 🆘 ESCALATION PATH

### If Issue Persists After Fixes
1. **Collect Diagnostic Data:**
   ```powershell
   .\ENHANCED-ZERO-RECORDS-DIAGNOSTIC.ps1 -FocusArea "All" -RunAPIs > diagnostic-output.json
   ```

2. **Vendor Support:**
   - **TacitRed:** support@tacitred.com
   - **Cyren:** Customer portal support
   - **Microsoft Azure:** Create support ticket with workspace ID

3. **Information to Provide:**
   - Diagnostic report JSON
   - Specific tables showing 0 records
   - Time range of investigation
   - Any error messages from diagnostic

---

## 📚 REFERENCE MATERIALS

### Key Files Created/Used
- [`ENHANCED-ZERO-RECORDS-DIAGNOSTIC.ps1`](./ENHANCED-ZERO-RECORDS-DIAGNOSTIC.ps1) - Primary diagnostic tool
- [`ZERO-RECORDS-RCA-ANALYSIS.md`](./docs/ZERO-RECORDS-RCA-ANALYSIS.md) - Detailed root cause analysis
- [`kql/VERIFY-TABLE-STATUS.kql`](./kql/VERIFY-TABLE-STATUS.kql) - Log Analytics verification queries
- [`TEST-TACITRED-API.ps1`](./TEST-TACITRED-API.ps1) - TacitRed API testing
- [`TEST-CYREN-API.ps1`](./TEST-CYREN-API.ps1) - Cyren API testing

### Configuration Files
- [`client-config-COMPLETE.json`](./client-config-COMPLETE.json) - Current deployment configuration

---

## ⏱️ TYPICAL RESOLUTION TIMES

| Root Cause | Time to Fix | Complexity |
|-------------|---------------|------------|
| TacitRed No Upstream Data | 0-2 hours (monitoring) | Low |
| Cyren CCF Configuration | 15-60 minutes | Medium |
| API Connectivity Issues | 30-120 minutes | Medium |
| Complex Multi-Issue | 2-4 hours | High |

---

## 🎯 SUCCESS METRICS

### Before Fix
- Table Record Count: 0
- Data Freshness: N/A
- Connector Status: Unknown/Errors

### After Fix (Target)
- Table Record Count: > 0
- Data Freshness: < 6 hours
- Connector Status: Healthy
- Diagnostic Status: Healthy

---

## 🔄 ONGOING MONITORING

### Set Up Alerts (Post-Resolution)
```kql
// Alert for no data ingestion
union 
    (TacitRed_Findings_CL | extend TableName="TacitRed_Findings_CL"),
    (Cyren_IpReputation_CL | extend TableName="Cyren_IpReputation_CL"),
    (Cyren_MalwareUrls_CL | extend TableName="Cyren_MalwareUrls_CL")
| where TimeGenerated > ago(12h)
| summarize Count=count() by TableName
| where Count == 0
```

### Daily Health Check
```powershell
# Schedule to run daily
.\ENHANCED-ZERO-RECORDS-DIAGNOSTIC.ps1 -FocusArea "All"
```

---

## 📞 QUICK HELP

### Most Common Issues
1. **"All tables show 0, but APIs return data"**
   - Check CCF connector dcrConfig
   - Verify DCR immutable IDs
   - Run with `-GenerateFixes` flag

2. **"Only TacitRed empty, APIs return 0"**
   - This may be normal
   - Test with longer time ranges (24-168 hours)
   - Contact TacitRed about feed activity

3. **"Only Cyren empty, APIs have data"**
   - CCF configuration issue
   - Table name mismatch
   - Run Cyren-focused diagnostic

### Emergency Commands
```powershell
# Quick table status check
az monitor log-analytics query -w SentinelThreatIntelWorkspace --analytics-query "union TacitRed_Findings_CL, Cyren_IpReputation_CL, Cyren_MalwareUrls_CL | summarize Count=count() by TableName | where Count == 0"

# Force CCF connector check
az rest --method GET --uri "https://management.azure.com/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/SentinelTestStixImport/providers/Microsoft.OperationalInsights/workspaces/SentinelThreatIntelWorkspace/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2024-09-01"
```

---

**Status:** ✅ Ready for immediate use  
**Next Action:** Run enhanced diagnostic script  
**Expected Resolution:** Under 1 hour for configuration issues, 2+ hours for upstream data issues
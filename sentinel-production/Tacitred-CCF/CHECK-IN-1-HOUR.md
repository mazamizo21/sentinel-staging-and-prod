# TacitRed CCF - 1-Hour Check Instructions

**Deployment Time**: 2025-11-16 ~06:08 EST  
**Check Time**: ~07:08 EST (1 hour from deployment)  
**Expected Data**: ~07:38 EST (90 minutes for safety)

---

## ✅ Deployment Completed

**Status**: Deployment shows "Failed" due to 401 connectivity check  
**This is EXPECTED** - The connector works at runtime despite the deployment-time 401 error.

---

## 🔍 What to Check in 1 Hour

### 1. Verify Connector Configuration

Run this command:

```powershell
az rest --method get `
  --uri "/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/TacitRedCCFTest/providers/Microsoft.OperationalInsights/workspaces/TacitRedCCFWorkspace/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview" `
  --query "{Active:properties.isActive, Polling:properties.request.queryWindowInMin, DCR:properties.dcrConfig.dataCollectionRuleImmutableId}" `
  --output table
```

**Expected Output**:
```
Active    Polling    DCR
--------  ---------  ------------------------------------
True      60         dcr-351b65c926314deb9f3ae6e7fd8f0397
```

---

### 2. Check for Data Ingestion

**In Azure Portal:**
1. Go to **Microsoft Sentinel** → **TacitRedCCFWorkspace**
2. Click **Logs**
3. Run this KQL query:

```kql
TacitRed_Findings_CL
| where TimeGenerated > ago(2h)
| summarize Count = count(), 
            Latest = max(TimeGenerated),
            FirstEmail = any(email_s)
| project Count, Latest, FirstEmail
```

**Expected Results**:

**If Count > 0**: ✅ **SUCCESS!** Data is flowing
- You should see records ingested
- `Latest` will show the most recent record timestamp
- `FirstEmail` will show a sample email address

**If Count = 0**: ⏳ Wait another 30 minutes
- First poll happens at 60-minute mark
- Ingestion latency can add 10-30 minutes
- Check again at 90-minute mark

---

### 3. Verify DCR ImmutableId Match

Run this to ensure the fix worked:

```powershell
# Get actual DCR immutableId
$dcrId = az monitor data-collection rule show `
  --name dcr-tacitred-findings `
  --resource-group TacitRedCCFTest `
  --query immutableId -o tsv

# Get connector's DCR reference
$connectorDcr = az rest --method get `
  --uri "/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/TacitRedCCFTest/providers/Microsoft.OperationalInsights/workspaces/TacitRedCCFWorkspace/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview" `
  --query "properties.dcrConfig.dataCollectionRuleImmutableId" -o tsv

Write-Host "DCR Actual:    $dcrId"
Write-Host "Connector Ref: $connectorDcr"
if ($dcrId -eq $connectorDcr) {
    Write-Host "`n✓✓✓ MATCH - DCR immutableId fix worked!"
} else {
    Write-Host "`n✗ MISMATCH - Issue not resolved"
}
```

**Expected**: Both IDs should match exactly

---

### 4. Check Workbooks

**In Azure Portal:**
1. Go to **Microsoft Sentinel** → **Workbooks**
2. Open any of these workbooks:
   - Threat Intelligence Command Center
   - Executive Risk Dashboard
   - Threat Hunter's Arsenal

**Expected**: Workbooks should render **without errors** (even though Cyren table is missing, thanks to `isfuzzy=true`)

---

### 5. Check Analytics Rule

**In Azure Portal:**
1. Go to **Microsoft Sentinel** → **Analytics**
2. Look for rule: **"TacitRed - Repeat Compromise Detection"**

**Expected**: 
- Status: **Enabled**
- Last Run: Within last hour
- Incidents: 0 (unless there are actual repeat compromises)

---

## 📊 Quick Verification Script

Run this all-in-one check:

```powershell
Write-Host "=== TacitRed CCF Status Check ===`n"

# 1. Connector
$conn = az rest --method get --uri "/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/TacitRedCCFTest/providers/Microsoft.OperationalInsights/workspaces/TacitRedCCFWorkspace/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview" | ConvertFrom-Json
Write-Host "Connector Active: $($conn.properties.isActive)"
Write-Host "Polling Interval: $($conn.properties.request.queryWindowInMin) min"

# 2. Data
$ws = "07ccb90a-2962-4028-8ede-61fb87c6d850"
$count = az monitor log-analytics query --workspace $ws --analytics-query "TacitRed_Findings_CL | where TimeGenerated > ago(2h) | count" --output tsv
Write-Host "Records Ingested: $count"

if ($count -gt 0) {
    Write-Host "`n✅ SUCCESS! Data is flowing!"
} else {
    Write-Host "`n⏳ No data yet - check again in 30 minutes"
}
```

---

## 🎯 Success Criteria

**Deployment is successful if**:
- ✅ Connector: `isActive = true`
- ✅ Polling: `60 minutes`
- ✅ DCR IDs match
- ✅ Data appears in table (Count > 0)
- ✅ Workbooks render without errors

---

## ⚠️ If No Data After 90 Minutes

1. **Check DCR Diagnostics**:
   ```kql
   AzureDiagnostics
   | where TimeGenerated > ago(2h)
   | where ResourceId contains "dcr-tacitred-findings"
   | project TimeGenerated, Category, OperationName, ResultDescription
   ```

2. **Check if TacitRed API has findings** (from your local machine):
   ```powershell
   $key = "a2be534e-6231-4fb0-b8b8-15dbc96e83b7"
   curl "https://app.tacitred.com/api/v1/findings?types[]=compromised_credentials&from=2025-11-01&until=2025-11-16&page_size=10" -H "Authorization: $key"
   ```
   
   If this returns 0 results, TacitRed simply has no findings in this time window.

3. **Verify Connector is polling**:
   - Check Azure Portal → Sentinel → Data connectors → TacitRed
   - Status should show "Connected"
   - Last log received time should update

---

## 📞 If Issues Persist

Reference the evidence package and documentation:
- `DCR-IMMUTABLEID-FIX.md` - Root cause of original issue
- `FIXES-APPLIED.md` - All fixes in v1.0.1
- `OUTSIDE-THE-BOX-ISSUES.md` - Known limitations
- `Project/Docs/CCF-Evidence-20251116-052902/` - Complete evidence

---

## ✅ Expected Timeline

| Time | Event |
|------|-------|
| 06:08 EST | Deployment completed |
| 07:08 EST | First poll cycle (60 min) |
| 07:18 EST | Data starts appearing in table |
| 07:38 EST | Safe check time (90 min total) |

**Check back at 07:38 EST for best results!**

# DCR ImmutableId Reference Fix

**Date**: 2025-11-16  
**Issue**: ARM template `reference()` function was returning stale/cached DCR immutableId  
**Impact**: CCF RestApiPoller connector pointed to wrong DCR, causing zero ingestion

---

## Problem

In `mainTemplate.TacitRedFullSolution.json`, the connector's DCR reference was:

```json
"dataCollectionRuleImmutableId": "[reference(resourceId('Microsoft.Insights/dataCollectionRules', variables('tacitRedDcrName')), '2024-03-11', 'full').properties.immutableId]"
```

This caused ARM to return a **cached/stale immutableId** instead of the newly created DCR's actual immutableId.

### Observed Behavior

- **ARM returned**: `dcr-fe23ef67d0d74784a5fc2e5c7e5d7e47` (old/cached)
- **Actual DCR had**: `dcr-351b65c926314deb9f3ae6e7fd8f0397` (correct)
- **Result**: Connector sent data to non-existent DCR → zero ingestion

---

## Root Cause

The `'full'` parameter in `reference()` can cause ARM to use cached resource state, especially when:
- Resources are repeatedly created/deleted in the same resource group
- Multiple deployments happen in quick succession
- ARM's resource cache hasn't been invalidated

---

## Fix Applied

**Removed the `'full'` parameter** from both DCE and DCR reference calls:

```json
"dataCollectionEndpoint": "[reference(resourceId('Microsoft.Insights/dataCollectionEndpoints', variables('dceName')), '2024-03-11').properties.logsIngestion.endpoint]",
"dataCollectionRuleImmutableId": "[reference(resourceId('Microsoft.Insights/dataCollectionRules', variables('tacitRedDcrName')), '2024-03-11').properties.immutableId]"
```

This forces ARM to fetch **fresh resource properties** at deployment time instead of using cached state.

---

## Post-Deployment Validation

After deploying this template, **always verify** the connector has the correct DCR immutableId:

### 1. Get the actual DCR immutableId

```bash
az monitor data-collection rule show \
  --name dcr-tacitred-findings \
  --resource-group <your-rg> \
  --query immutableId -o tsv
```

### 2. Get the connector's DCR reference

```bash
az rest --method get \
  --uri "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace>/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview" \
  --query "properties.dcrConfig.dataCollectionRuleImmutableId" -o tsv
```

### 3. Compare

If they **don't match**, manually update the connector:

```bash
# Get connector config
az rest --method get --uri "<connector-uri>" > connector.json

# Edit connector.json to fix the immutableId

# Update connector
az rest --method put --uri "<connector-uri>" --body @connector.json
```

---

## Prevention for Future Deployments

### Option 1: Clean Resource Group
- Deploy to a **fresh resource group** each time
- Avoids ARM cache issues from previous deployments

### Option 2: Post-Deployment Script
- Add a validation script that:
  1. Checks DCR vs connector immutableId match
  2. Auto-corrects if mismatch detected
  3. Logs the correction for audit

### Option 3: Use Variables (Not Recommended)
- Store immutableId in a variable after DCR creation
- Use variable instead of `reference()`
- Requires deployment scripts or nested templates

---

## Testing

After this fix, test by:

1. **Delete the resource group** (to clear any ARM cache)
2. **Redeploy** using the fixed template
3. **Verify** DCR immutableId match immediately after deployment
4. **Wait 10 minutes** and check `TacitRed_Findings_CL` for data

---

## Related Files

- `mainTemplate.TacitRedFullSolution.json` - Fixed ARM template
- `Project/Docs/CCF-Evidence-20251116-052902/` - Evidence package showing the issue
- `temp-connector.json` - Manual fix applied to current deployment

---

## Status

✅ **ARM template fixed** (removed 'full' parameter)  
✅ **Current deployment manually corrected**  
⏳ **Waiting for data ingestion** (5-10 minutes from fix time)

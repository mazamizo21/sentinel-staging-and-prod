# Workbook Deployment Issue Analysis
**Date:** 2025-11-13  
**Issue:** Marketplace deployment script reports "All 8 workbooks processed successfully" but 0 workbooks exist

## Problem Statement
The configure-workbooks deploymentScripts resource executed without errors and logged:
```
WB1 exists or created
WB2 exists or created
...
All 8 workbooks processed successfully
```

However, verification shows 0 workbooks in the resource group.

## Root Cause Hypothesis
The `az monitor app-insights workbook create` command is either:
1. Not available in the Azure CLI version in deployment scripts (2.51.0)
2. Failing silently due to suppressed stderr (`2>/dev/null`)
3. Creating workbooks in the wrong scope/location
4. Using incorrect parameters for the workbook type

## Investigation Steps
1. Script logs show all 8 commands reached the fallback `|| echo 'WBx exists or created'`
2. This indicates the `az monitor app-insights workbook create` commands all failed
3. Error suppression (`2>/dev/null`) prevented us from seeing the actual errors

## Solution Approach
Option 1: Remove error suppression and capture real errors
Option 2: Use az rest with Microsoft.Insights/workbooks API directly
Option 3: Deploy workbooks as native ARM resources (inline in mainTemplate.json)

## Recommended Fix
Use az rest with Microsoft.Insights/workbooks API and proper JSON body handling via temp files.

## Next Actions
1. Remove `2>/dev/null` from commands to see actual errors
2. Test az monitor app-insights workbook create locally to verify syntax
3. If command unavailable, switch to az rest approach with validated JSON

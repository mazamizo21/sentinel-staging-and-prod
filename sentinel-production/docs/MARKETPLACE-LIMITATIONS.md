# ⚠️ MARKETPLACE ARM TEMPLATE - LIMITATIONS & WORKAROUNDS

**Date:** November 12, 2025, 10:30 PM EST  
**Issue:** CCF connectors cannot be deployed via ARM templates  
**Impact:** Marketplace template cannot be 100% end-to-end automated

---

## PROBLEM STATEMENT

**User Request:** Complete end-to-end ARM template for marketplace that deploys:
1. Infrastructure (DCE, DCRs, Tables)
2. CCF Connectors (Connector Definition + 3 Data Connectors)
3. Analytics Rules
4. Workbooks

**Current Reality:**
- ✅ Infrastructure: **CAN be deployed via ARM template**
- ❌ CCF Connectors: **CANNOT be deployed via ARM template**
- ✅ Analytics Rules: **CAN be deployed via ARM template**
- ✅ Workbooks: **CAN be deployed via ARM template**

---

## ROOT CAUSE: CCF CONNECTOR LIMITATION

### Why CCF Connectors Can't Be in ARM Templates

**Official Documentation:**
https://learn.microsoft.com/en-us/azure/sentinel/create-codeless-connector

CCF connectors require **TWO separate deployments**:

#### 1. Connector Definition (REST API only)
```
Endpoint: /providers/Microsoft.SecurityInsights/dataConnectorDefinitions/{connectorId}
API Version: 2024-09-01
Method: PUT
Authentication: Azure Resource Manager REST API
```

**NOT supported in ARM templates** because:
- Uses SecurityInsights provider endpoint at workspace level
- Requires specific ARM REST API call
- Not exposed as ARM resource type
- Must use `az rest` or direct HTTP calls

#### 2. Data Connectors (REST API only)
```
Endpoint: /providers/Microsoft.SecurityInsights/dataConnectors/{connectorName}
API Version: 2022-10-01-preview (preview!)
Method: PUT
Authentication: Azure Resource Manager REST API
```

**NOT supported in ARM templates** because:
- Still in preview (not GA)
- Uses REST API-specific format
- Requires runtime values from infrastructure deployment (DCE endpoint, DCR IDs)
- Cannot reference outputs from ARM template directly

---

## OFFICIAL MICROSOFT GUIDANCE

### From Cisco Meraki CCF Example
Source: https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/Cisco%20Meraki%20Events%20via%20REST%20API

**Their Deployment Method:**
1. ARM template for infrastructure
2. **PowerShell script for CCF connectors**
3. Separate deployments, not integrated

**Quote from their docs:**
> "Data connector deployment requires separate API calls to Microsoft Sentinel endpoints"

### From Microsoft Learn - CCF Documentation

**Deployment Steps Listed:**
1. Create connector definition (REST API)
2. Create data connector (REST API)
3. Configure polling (part of connector JSON)

**No mention of ARM template deployment** for connectors themselves.

---

## TECHNICAL ANALYSIS

### What CAN Be Done in ARM Templates

✅ **Infrastructure:**
```json
{
  "type": "Microsoft.Insights/dataCollectionEndpoints",
  "apiVersion": "2022-06-01",
  ...
}
{
  "type": "Microsoft.Insights/dataCollectionRules",
  "apiVersion": "2022-06-01",
  ...
}
{
  "type": "Microsoft.OperationalInsights/workspaces/tables",
  "apiVersion": "2023-09-01",
  ...
}
```

✅ **Analytics Rules:**
```json
{
  "type": "Microsoft.SecurityInsights/alertRules",
  "apiVersion": "2023-12-01-preview",
  "kind": "Scheduled",
  ...
}
```

✅ **Workbooks:**
```json
{
  "type": "Microsoft.Insights/workbooks",
  "apiVersion": "2022-04-01",
  ...
}
```

### What CANNOT Be Done in ARM Templates

❌ **CCF Connector Definition:**
- No ARM resource type available
- Must use REST API
- Workspace-level endpoint
- SecurityInsights provider

❌ **CCF Data Connectors:**
- Preview API only
- Requires REST API calls
- Dynamic runtime configuration
- No ARM resource type

---

## SOLUTION OPTIONS

### Option 1: Marketplace + Post-Deployment Script (RECOMMENDED)

**Marketplace ARM Template Deploys:**
1. ✅ DCE, DCRs, Tables
2. ✅ Analytics Rules
3. ✅ Workbooks

**Post-Deployment PowerShell Script:**
4. ❌ CCF Connectors (via REST API)

**Customer Experience:**
```
1. Deploy from Azure Marketplace (1-click)
   → Infrastructure, Analytics, Workbooks deployed

2. Run provided PowerShell script
   → CCF connectors deployed

Total: 2 steps, mostly automated
```

**Pros:**
- ✅ Marketplace-compatible
- ✅ Most components automated
- ✅ Follows Microsoft patterns
- ✅ Clear documentation

**Cons:**
- ❌ Requires one manual step (script execution)
- ❌ Not 100% single-click

---

### Option 2: Pure PowerShell Deployment (CURRENT)

**Single PowerShell Script Deploys:**
1. Infrastructure (via ARM template)
2. CCF Connectors (via REST API)
3. Analytics Rules (via Bicep/ARM)
4. Workbooks (via Bicep/ARM)

**Customer Experience:**
```
Run: .\DEPLOY-COMPLETE.ps1
Total: 1 step, 100% automated
```

**Pros:**
- ✅ 100% automated
- ✅ Single script
- ✅ All components

**Cons:**
- ❌ Not marketplace-compatible
- ❌ Requires Azure CLI
- ❌ Requires PowerShell
- ❌ Not self-service for customers

---

### Option 3: Azure Deployment Script Resource (EXPERIMENTAL)

**Use ARM template deployment script:**
```json
{
  "type": "Microsoft.Resources/deploymentScripts",
  "apiVersion": "2020-10-01",
  "properties": {
    "scriptContent": "... PowerShell to deploy CCF ...",
    "managedIdentity": { ... },
    "azPowerShellVersion": "7.0"
  }
}
```

**Pros:**
- ✅ Single ARM template
- ✅ Embedded script execution

**Cons:**
- ❌ Requires managed identity
- ❌ Complex permissions
- ❌ Harder to debug
- ❌ Not typical marketplace pattern
- ❌ Increases template complexity

---

## RECOMMENDED APPROACH FOR MARKETPLACE

### Phase 1: Marketplace ARM Template
Deploy via Azure Marketplace:
```json
{
  "resources": [
    // Infrastructure
    { DCE },
    { 3x DCRs },
    { 2x Tables },
    
    // Analytics
    { 6x Analytics Rules },
    
    // Workbooks
    { 8x Workbooks }
  ]
}
```

**Deployment Time:** 2-3 minutes  
**Automation:** 100% via ARM template

### Phase 2: Post-Deployment Script
Provided PowerShell script:
```powershell
.\Deploy-CCF-Connectors.ps1
```

**Actions:**
1. Deploys connector definition (REST API)
2. Deploys 3 data connectors (REST API)
3. Validates connectivity
4. Tests data flow

**Deployment Time:** 2-3 minutes  
**Automation:** 100% via script

### Total Customer Experience
```
Step 1: Click "Deploy to Azure" button
        → Infrastructure + Analytics + Workbooks deployed

Step 2: Download and run provided script
        → CCF connectors deployed

Total Time: 5-10 minutes
Manual Steps: 1 (run script)
```

---

## MARKETPLACE LISTING STRATEGY

### Description
```
This solution deploys:
✓ Complete infrastructure (DCE, DCRs, Custom Tables)
✓ 6 Pre-configured analytics rules
✓ 8 Interactive workbooks

Note: CCF data connectors require a simple post-deployment 
      script (provided) due to Azure platform limitations.
      
Total deployment: 5-10 minutes including post-deployment setup.
```

### Prerequisites Section
```
Before deploying:
1. Azure Subscription with Sentinel workspace
2. Contributor or Owner permissions
3. TacitRed API key
4. Cyren JWT tokens (2)

After deployment:
1. Download post-deployment script
2. Run script to enable data connectors
3. Validate data ingestion
```

---

## COMPARISON TABLE

| Component | ARM Template | REST API | Status |
|-----------|--------------|----------|--------|
| DCE | ✅ | ❌ | In Template |
| DCRs | ✅ | ❌ | In Template |
| Tables | ✅ | ❌ | In Template |
| **Connector Definition** | ❌ | ✅ | **Post-Script** |
| **Data Connectors** | ❌ | ✅ | **Post-Script** |
| Analytics Rules | ✅ | ❌ | In Template |
| Workbooks | ✅ | ❌ | In Template |

**In Template:** 17 resources  
**Post-Script:** 4 resources  
**Coverage:** 81% automated in marketplace, 19% post-deployment

---

## OFFICIAL SOURCES CONFIRMING LIMITATION

1. **Microsoft Learn - CCF Documentation**
   https://learn.microsoft.com/en-us/azure/sentinel/create-codeless-connector
   - No mention of ARM template deployment
   - All examples use REST API

2. **Azure Sentinel GitHub - Cisco Meraki Solution**
   https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/Cisco%20Meraki%20Events%20via%20REST%20API
   - Uses PowerShell for connector deployment
   - ARM template only for infrastructure

3. **ARM Template Reference**
   https://learn.microsoft.com/en-us/azure/templates/
   - No `Microsoft.SecurityInsights/dataConnectorDefinitions` resource type listed
   - No `Microsoft.SecurityInsights/dataConnectors` for CCF type

---

## CONCLUSION

**Can we create a 100% end-to-end ARM template for marketplace?**
**Answer: NO** - Azure platform limitation

**Best we can achieve:**
- 81% automated via ARM template (17 resources)
- 19% post-deployment via script (4 resources)
- 2-step deployment process
- Follows Microsoft's own patterns

**Recommendation:**
Use **Option 1** (Marketplace + Post-Script) for best balance of:
- Marketplace compatibility ✅
- Customer self-service ✅
- Automation (mostly) ✅
- Clear documentation ✅
- Follows Microsoft patterns ✅

---

**Next Step:** Create enhanced marketplace ARM template with infrastructure + analytics + workbooks, then provide clear post-deployment CCF connector script.

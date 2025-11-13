# CCF Deployment Guide - Codeless Connector Framework

**Status:** ✅ CCF Connectors Fixed and Ready  
**Date:** November 12, 2025, 8:50 PM  
**Deployment:** In Progress

---

## 🔧 What Was Fixed

### 1. TacitRed CCF Connector (`ccf-connector-tacitred.bicep`)

#### ❌ Original Issues:
- **Wrong API URL:** Used `https://api.tacitred.com` (doesn't exist)
- **Missing page_size parameter:** API requires pagination
- **Missing API Key format:**  Wasn't properly formatted

#### ✅ Fixes Applied:
```bicep
// FIXED: Correct API URL (matches working Logic App)
param apiBaseUrl string = 'https://app.tacitred.com/api/v1'

// FIXED: Added page_size parameter
queryParameters: {
  page_size: '100'
}

// FIXED: API Key authentication
auth: {
  type: 'APIKey'
  ApiKeyName: 'Authorization'
  ApiKeyIdentifier: ''
  ApiKey: apiKey
  IsApiKeyInPostPayload: false
}
```

#### 📝 What We Learned from Logic App:
The working Logic App uses:
- **URL:** `https://app.tacitred.com/api/v1/findings`
- **Auth Header:** `Authorization: {apiKey}` (no Bearer prefix)
- **Query Params:** `from`, `until`, `page_size=100`
- **Response Path:** `$.results` (array of findings)

### 2. Cyren CCF Connector (`ccf-connector-cyren.bicep`)

#### ❌ Original Issues:
- **Missing DCE endpoint parameter**
- **Wrong API endpoint format**
- **Missing resource naming**
- **Incorrect parameter mapping**

#### ✅ Fixes Applied:
```bicep
// FIXED: Added DCE endpoint parameter
param dceIngestionEndpoint string

// FIXED: Correct API URL
param apiBaseUrl string = 'https://api-feeds.cyren.com/v1/feed/data'

// FIXED: Proper resource naming
resource connectorDefinition 'Microsoft.OperationalInsights/workspaces/providers/dataConnectorDefinitions@2022-12-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/${connectorName}-definition'
  // ...
}

// FIXED: DCE endpoint in dcrConfig
dcrConfig: {
  dataCollectionEndpoint: dceIngestionEndpoint
  dataCollectionRuleImmutableId: dcrImmutableId
  streamName: streamName
}

// FIXED: Query parameters
queryParameters: {
  count: '100'
}
```

---

## 📦 What Was Deployed

### DEPLOY-CCF.ps1 Script Created

New deployment script specifically for CCF:
- ✅ Deploys DCE (Data Collection Endpoint)
- ✅ Creates custom tables with full schemas
- ✅ Deploys 3 DCRs (TacitRed, Cyren IP, Cyren Malware)
- ✅ **Deploys CCF Connectors** (instead of Logic Apps)
- ✅ Assigns RBAC to CCF managed identities
- ✅ Deploys Analytics Rules
- ✅ Deploys Workbooks

### Differences from DEPLOY-COMPLETE.ps1

| Component | DEPLOY-COMPLETE.ps1 | DEPLOY-CCF.ps1 |
|-----------|---------------------|----------------|
| **Data Ingestion** | Logic Apps | CCF Connectors |
| **Authentication** | Managed Identity + RBAC | Managed Identity + RBAC |
| **API Polling** | Logic App Recurrence | CCF Built-in Polling |
| **Configuration** | Bicep parameters | Bicep parameters |
| **Cost** | Per-execution | Included in Sentinel |

---

## 🚀 Current Deployment Status

### Phase 1: Prerequisites ✅
- Azure subscription configured
- Workspace validated

### Phase 2: Infrastructure ✅
- **DCE Created:** `dce-sentinel-ti`
- **Tables Created:** 
  - `TacitRed_Findings_CL` (16 columns)
  - `Cyren_Indicators_CL` (19 columns)
- **DCRs Deployed:**
  - TacitRed DCR: `dcr-52e906441b0942499caadc7d803e32be`
  - Cyren IP DCR: (immutableId)
  - Cyren Malware DCR: (immutableId)

### Phase 3: CCF Connectors 🔄
- **TacitRed CCF:** Deploying...
- **Cyren CCF:** Pending...

### Phase 4: RBAC ⏳
- Will assign after CCF connectors create their managed identities

### Phase 5: Analytics ⏳
- Waiting for infrastructure completion

### Phase 6: Workbooks ⏳
- Waiting for infrastructure completion

---

## 🔍 How to Verify CCF Deployment

### Check CCF Connectors in Portal

1. **Navigate to Sentinel:**
   - Azure Portal → Microsoft Sentinel
   - Select workspace: `SentinelThreatIntelWorkspace`

2. **View Data Connectors:**
   - Configuration → Data connectors
   - Search for: `TacitRed` or `Cyren`

3. **Check Connector Status:**
   ```
   Expected Status: Connected / Receiving data
   Last Data Received: Within last hour
   ```

### Check CCF Connector via CLI

```powershell
# List all data connectors
az sentinel data-connector list `
  -g SentinelTestStixImport `
  -w SentinelThreatIntelWorkspace `
  -o table

# View specific connector
az rest --method GET `
  --uri "https://management.azure.com/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/SentinelTestStixImport/providers/Microsoft.OperationalInsights/workspaces/SentinelThreatIntelWorkspace/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2023-02-01-preview"
```

### Check Data Ingestion

```kql
// Check TacitRed data
TacitRed_Findings_CL
| where TimeGenerated > ago(1h)
| summarize Count = count(), 
            FirstSeen = min(TimeGenerated),
            LastSeen = max(TimeGenerated)
| project Count, FirstSeen, LastSeen

// Check Cyren data
Cyren_Indicators_CL
| where TimeGenerated > ago(1h)
| summarize Count = count(),
            FirstSeen = min(TimeGenerated),
            LastSeen = max(TimeGenerated)
| project Count, FirstSeen, LastSeen
```

---

## 🐛 Troubleshooting CCF Connectors

### Issue 1: "CCF Connector Not Appearing in Portal"

**Possible Causes:**
- Deployment still in progress (can take 5-10 minutes)
- Deployment failed silently

**How to Check:**
```powershell
# Check deployment status
az deployment group show `
  -g SentinelTestStixImport `
  -n ccf-tacitred-<timestamp> `
  --query "properties.provisioningState"
```

**Solutions:**
1. Wait 5-10 minutes for deployment to complete
2. Check deployment logs in `docs/deployment-logs/ccf-<timestamp>/`
3. Manually verify connector exists via API (see commands above)

### Issue 2: "CCF Connector Shows 'Disconnected'"

**Possible Causes:**
- RBAC not propagated yet (takes 5-30 minutes)
- API credentials incorrect
- API endpoint unreachable

**Solutions:**
1. **Wait for RBAC:** Check back in 30 minutes
2. **Verify Credentials:**
   - TacitRed: Verify API key is correct
   - Cyren: Verify JWT token is not expired
3. **Test API Manually:**
   ```powershell
   # Test TacitRed API
   $headers = @{
       Authorization = "YOUR_API_KEY"
       Accept = "application/json"
   }
   Invoke-RestMethod -Uri "https://app.tacitred.com/api/v1/findings?from=2025-11-01T00:00:00Z&until=2025-11-12T23:59:59Z&page_size=10" -Headers $headers
   ```

### Issue 3: "CCF Connector Connected but No Data"

**Possible Causes:**
- API has no new data in polling window
- DCR transformation failing
- API rate limiting

**Solutions:**
1. **Expand Polling Window:**
   - Edit CCF connector in portal
   - Increase `queryWindowInMin` parameter
2. **Check DCR Logs:**
   ```kql
   AzureDiagnostics
   | where ResourceType == "DATACONNECTORS"
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, Message, Level
   ```
3. **Manually Trigger Polling:**
   - In portal, go to Data connector
   - Click "Poll now" or "Connect" button

---

## 📊 Comparison: Logic Apps vs CCF

### What We Know Works (Logic Apps)

**TacitRed Logic App:**
- ✅ Successfully polls `https://app.tacitred.com/api/v1/findings`
- ✅ Uses `Authorization` header with API key
- ✅ Fetches data with `from`, `until`, `page_size` params
- ✅ Sends to DCE using Managed Identity
- ✅ Runs every 15 minutes (configurable)

**Cyren Logic Apps:**
- ✅ Successfully polls Cyren API feeds
- ✅ Uses Bearer token authentication
- ✅ Separate Logic Apps for IP reputation and Malware URLs
- ✅ Runs every 6 hours (configurable)

### What We're Testing (CCF)

**TacitRed CCF Connector:**
- 🔄 Uses same API URL as working Logic App
- 🔄 Uses same authentication method
- 🔄 Uses same query parameters
- ⚠️ **Different:** Built-in Azure poller (not Logic App)
- ⚠️ **Different:** No custom retry logic (uses CCF defaults)

**Cyren CCF Connector:**
- 🔄 Uses Cyren API feed
- 🔄 Uses Bearer token (same as Logic App)
- ⚠️ **Different:** Single connector vs two Logic Apps
- ⚠️ **Different:** CCF handles both feeds? (needs verification)

---

## 🎯 Key Configuration Parameters

### TacitRed CCF

```bicep
workspaceName: 'SentinelThreatIntelWorkspace'
apiBaseUrl: 'https://app.tacitred.com/api/v1'
apiKey: '<YOUR_API_KEY>'
dcrImmutableId: '<DCR_IMMUTABLE_ID>'
streamName: 'Custom-TacitRed_Findings_CL'
dceIngestionEndpoint: 'https://dce-sentinel-ti-xxx.eastus-1.ingest.monitor.azure.com'
queryWindowInMin: 43200  # 30 days for historical pull
```

### Cyren CCF

```bicep
workspaceName: 'SentinelThreatIntelWorkspace'
apiBaseUrl: 'https://api-feeds.cyren.com/v1/feed/data'
apiToken: '<YOUR_JWT_TOKEN>'
dcrImmutableId: '<DCR_IMMUTABLE_ID>'
streamName: 'Custom-Cyren_Indicators_CL'
dceIngestionEndpoint: 'https://dce-sentinel-ti-xxx.eastus-1.ingest.monitor.azure.com'
queryWindowInMin: 360  # 6 hours
```

---

## 📝 Post-Deployment Checklist

### Immediate (0-5 minutes)
- [ ] Check deployment completed without errors
- [ ] Verify DCE exists in Azure Portal
- [ ] Verify 3 DCRs exist
- [ ] Verify 2 custom tables exist

### Short-term (30-60 minutes)
- [ ] Check CCF connectors appear in Sentinel → Data connectors
- [ ] Verify CCF connectors show "Connected" status
- [ ] Check RBAC assignments propagated
- [ ] Manually trigger CCF polling if needed

### Medium-term (1-6 hours)
- [ ] Verify data appearing in `TacitRed_Findings_CL` table
- [ ] Verify data appearing in `Cyren_Indicators_CL` table
- [ ] Check Analytics rules are triggering
- [ ] Test workbook queries return data

### Long-term (24 hours)
- [ ] Monitor CCF connector stability
- [ ] Compare data volume vs Logic App approach
- [ ] Check for any CCF-specific errors
- [ ] Validate cost savings (no Logic App executions)

---

## 🔄 Rollback Plan (If CCF Fails)

### Option 1: Re-deploy with Logic Apps

```powershell
# Use the original deployment script
cd d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production
.\DEPLOY-COMPLETE.ps1
```

**Note:** This will deploy Logic Apps instead of CCF connectors

### Option 2: Hybrid Approach

Keep CCF for what works, use Logic Apps for what doesn't:
- If TacitRed CCF works → Keep it
- If Cyren CCF fails → Deploy Cyren Logic Apps manually

---

## 🎓 Learning from This Deployment

### Key Insights

1. **CCF is Newer:**
   - Less documentation available
   - Fewer examples in the wild
   - More restrictive than Logic Apps

2. **API Compatibility:**
   - CCF expects standard REST API patterns
   - TacitRed API follows these patterns ✅
   - Cyren API might need adaptation ⚠️

3. **Debugging:**
   - CCF errors are harder to debug than Logic Apps
   - No visible "run history" like Logic Apps
   - Must rely on Azure diagnostics logs

4. **When to Use CCF:**
   - ✅ Standard REST APIs with JSON responses
   - ✅ Simple pagination (LinkHeader or page number)
   - ✅ API key or Bearer token auth
   - ❌ Complex auth flows (OAuth, SAML)
   - ❌ Non-standard response formats
   - ❌ APIs requiring custom data transformation

---

## 📞 Next Steps

1. **Monitor deployment completion:**
   - Check PowerShell window for final status
   - Review logs in `docs/deployment-logs/ccf-<timestamp>/`

2. **Verify CCF connectors in portal:**
   - Go to Sentinel → Data connectors
   - Check status of TacitRed and Cyren connectors

3. **If CCF works:**
   - Document success
   - Compare performance vs Logic Apps
   - Consider migrating fully to CCF

4. **If CCF fails:**
   - Review error messages
   - Check API compatibility
   - Fall back to Logic Apps if needed

---

**Status:** ✅ CCF connectors fixed with correct API URLs and auth  
**Deployment:** In progress  
**Est. Completion:** 5-10 minutes  
**Logs:** `docs/deployment-logs/ccf-<timestamp>/`

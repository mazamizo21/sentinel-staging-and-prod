# 🧪 MARKETPLACE DEPLOYMENT - TESTING GUIDE

**Complete step-by-step testing before production deployment**

---

## 📋 TESTING PHASES

### Phase 1: Local Validation (5 minutes)
### Phase 2: Azure Portal Sandbox Test (10 minutes)
### Phase 3: Test Subscription Deployment (30 minutes)
### Phase 4: Production Validation (1 hour)

---

## ✅ PHASE 1: LOCAL VALIDATION

### Step 1.1: Validate JSON Syntax

```powershell
# Test mainTemplate.json
$template = Get-Content ".\marketplace-package\mainTemplate.json" -Raw
$template | ConvertFrom-Json
Write-Host "✓ mainTemplate.json is valid JSON" -ForegroundColor Green

# Test createUiDefinition.json
$ui = Get-Content ".\marketplace-package\createUiDefinition.json" -Raw
$ui | ConvertFrom-Json
Write-Host "✓ createUiDefinition.json is valid JSON" -ForegroundColor Green
```

**Expected:** No errors, both files parse successfully

### Step 1.2: ARM Template Validation

```powershell
# Validate ARM template syntax
az deployment group validate `
    --resource-group <YOUR_TEST_RG> `
    --template-file .\marketplace-package\mainTemplate.json `
    --parameters `
        workspaceName=<YOUR_TEST_WORKSPACE> `
        tacitRedApiKey="test-key-placeholder-aaaa-bbbb-cccc" `
        cyrenIPJwtToken="eyJtest.placeholder.token" `
        cyrenMalwareJwtToken="eyJtest.placeholder.token"
```

**Expected Output:**
```json
{
  "properties": {
    "validatedResources": [...]
  }
}
```

✅ If validation passes, template syntax is correct!

### Step 1.3: Check File Sizes

```powershell
Get-ChildItem .\marketplace-package\ | ForEach-Object {
    $sizeMB = [math]::Round($_.Length / 1MB, 2)
    Write-Host "$($_.Name): $sizeMB MB" -ForegroundColor Gray
}
```

**Limits:**
- mainTemplate.json: < 4 MB ✅
- createUiDefinition.json: < 1 MB ✅

---

## ✅ PHASE 2: AZURE PORTAL SANDBOX TEST

### Step 2.1: Test UI Definition in Sandbox

1. Open: https://portal.azure.com/#blade/Microsoft_Azure_CreateUIDef/SandboxBlade

2. **Paste your createUiDefinition.json content**

3. **Click "Preview"**

4. **Test the wizard:**
   - ✅ Basics step loads
   - ✅ Workspace selector populates workspaces
   - ✅ API credential fields accept input
   - ✅ Validation messages appear for invalid input
   - ✅ All steps navigate correctly

**Expected View:**
```
Step 1: Basics
  - Subscription: [Dropdown works]
  - Resource Group: [Dropdown works]
  
Step 2: Workspace
  - Workspace Selector: [Shows your workspaces]
  
Step 3: Credentials
  - TacitRed API Key: [Password box works]
  - Cyren IP JWT: [Password box works]
  - Cyren Malware JWT: [Password box works]
  
Step 4: Configuration
  - Polling Frequency: [Dropdown works]
  - Deploy Analytics: [Checkbox works]
  - Deploy Workbooks: [Checkbox works]
```

### Step 2.2: Test Parameter Validation

**Try these invalid inputs to verify validation:**

| Field | Invalid Input | Expected Error |
|-------|--------------|----------------|
| TacitRed API Key | "abc" | "Must be at least 8 characters" |
| Cyren JWT Token | "invalid" | "Must be a valid JWT token" |

✅ Validation should block invalid inputs

---

## ✅ PHASE 3: TEST SUBSCRIPTION DEPLOYMENT

### Step 3.1: Create Test Environment

```powershell
# Create isolated test resource group
$testRG = "rg-sentinel-marketplace-test"
$location = "eastus"
$testWorkspace = "test-sentinel-ws"

az group create --name $testRG --location $location

# Create test Sentinel workspace
az monitor log-analytics workspace create `
    --resource-group $testRG `
    --workspace-name $testWorkspace `
    --location $location

# Enable Sentinel
az sentinel workspace create `
    --resource-group $testRG `
    --workspace-name $testWorkspace
```

### Step 3.2: Test Deployment via Azure CLI

```powershell
# Deploy using mainTemplate.json
$deploymentName = "marketplace-test-$(Get-Date -Format 'yyyyMMddHHmmss')"

az deployment group create `
    --resource-group $testRG `
    --name $deploymentName `
    --template-file .\marketplace-package\mainTemplate.json `
    --parameters `
        workspaceName=$testWorkspace `
        location=$location `
        tacitRedApiKey="YOUR_REAL_API_KEY_HERE" `
        cyrenIPJwtToken="YOUR_REAL_CYREN_IP_JWT" `
        cyrenMalwareJwtToken="YOUR_REAL_CYREN_MALWARE_JWT" `
        pollingFrequencyMinutes=360 `
        deployAnalytics=true `
        deployWorkbooks=true `
    --mode Incremental `
    --verbose
```

**Monitor deployment:**
```powershell
# Watch deployment status
az deployment group show `
    --resource-group $testRG `
    --name $deploymentName `
    --query 'properties.provisioningState'
```

**Expected Output:** `"Succeeded"`

### Step 3.3: Verify Deployed Resources

```powershell
Write-Host "`n═══ DEPLOYMENT VERIFICATION ═══" -ForegroundColor Cyan

# 1. Check DCE
Write-Host "`n[1/6] Data Collection Endpoint..." -ForegroundColor Yellow
az monitor data-collection endpoint list `
    --resource-group $testRG `
    --query "[?contains(name, 'threatintel')].name"

# 2. Check DCRs
Write-Host "`n[2/6] Data Collection Rules..." -ForegroundColor Yellow
az monitor data-collection rule list `
    --resource-group $testRG `
    --query "[].name"

# 3. Check Tables
Write-Host "`n[3/6] Custom Tables..." -ForegroundColor Yellow
az monitor log-analytics workspace table list `
    --resource-group $testRG `
    --workspace-name $testWorkspace `
    --query "[?contains(name, '_CL')].name"

# 4. Check Connector Definition
Write-Host "`n[4/6] Connector Definition..." -ForegroundColor Yellow
az sentinel data-connector list `
    --resource-group $testRG `
    --workspace-name $testWorkspace `
    --query "[?kind=='RestApiPoller'].name"

# 5. Check Data Connectors
Write-Host "`n[5/6] Data Connectors..." -ForegroundColor Yellow
az rest --method GET `
    --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$testRG/providers/Microsoft.OperationalInsights/workspaces/$testWorkspace/providers/Microsoft.SecurityInsights/dataConnectorDefinitions?api-version=2024-09-01" `
    --query "value[].name"

# 6. Portal Check
Write-Host "`n[6/6] Open in Portal..." -ForegroundColor Yellow
Write-Host "https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$testRG/providers/Microsoft.OperationalInsights/workspaces/$testWorkspace/overview" -ForegroundColor Cyan
```

**Expected Resources:**
- ✅ 1 DCE: `dce-threatintel-feeds`
- ✅ 3 DCRs: `dcr-tacitred-findings`, `dcr-cyren-ip`, `dcr-cyren-malware`
- ✅ 2 Tables: `TacitRed_Findings_CL`, `Cyren_Indicators_CL`
- ✅ 1 Connector Definition: `ThreatIntelligenceFeeds`
- ✅ 3 Data Connectors: `TacitRedFindings`, `CyrenIPReputation`, `CyrenMalwareURLs`

### Step 3.4: Test "Deploy to Azure" Button

Create test button HTML:

```html
<!DOCTYPE html>
<html>
<body>
<h1>Marketplace Test - Deploy to Azure</h1>

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2F<YOUR_REPO>%2Fmain%2Fsentinel-production%2Fmarketplace-package%2FmainTemplate.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2F<YOUR_REPO>%2Fmain%2Fsentinel-production%2Fmarketplace-package%2FcreateUiDefinition.json">
    <img src="https://aka.ms/deploytoazurebutton"/>
</a>

</body>
</html>
```

**Test Steps:**
1. Upload `mainTemplate.json` and `createUiDefinition.json` to GitHub
2. Update URLs in button link
3. Click button
4. Portal should open with your wizard
5. Complete deployment

---

## ✅ PHASE 4: PRODUCTION VALIDATION

### Step 4.1: Validate Data Ingestion (Wait 30 min)

```kql
// Check TacitRed data arrived
TacitRed_Findings_CL
| where TimeGenerated > ago(1h)
| summarize Count = count(), Latest = max(TimeGenerated)

// Check Cyren data arrived
Cyren_Indicators_CL
| where TimeGenerated > ago(1h)
| summarize Count = count(), Latest = max(TimeGenerated)
```

**Expected:** 
- Count > 0
- Latest timestamp within last hour

### Step 4.2: Verify Connector Status

1. Navigate to: **Sentinel** → **Data connectors**
2. Search: **"Threat Intelligence Feeds"**
3. **Expected Status:** 
   - ✅ Connected
   - ✅ Last log received: < 1 hour ago
   - ✅ 3 connections active

### Step 4.3: Test Analytics Rules (If deployed)

```kql
// Check analytics rules exist
SecurityAlert
| where AlertName contains "TacitRed" or AlertName contains "Cyren"
| summarize count() by AlertName
```

### Step 4.4: Test Workbooks (If deployed)

1. Navigate to: **Sentinel** → **Workbooks**
2. **Expected Workbooks:**
   - ✅ Threat Intelligence Command Center
   - ✅ Executive Risk Dashboard
   - ✅ Threat Hunter's Arsenal
   - ✅ Cyren Threat Intelligence

3. Open each workbook and verify:
   - ✅ Loads without errors
   - ✅ Shows data (if ingestion completed)
   - ✅ All visualizations render

### Step 4.5: Performance Test

```powershell
# Monitor resource utilization
az monitor metrics list `
    --resource /subscriptions/<sub>/resourceGroups/$testRG/providers/Microsoft.Insights/dataCollectionEndpoints/dce-threatintel-feeds `
    --metric "IncomingBytes" `
    --interval PT1H
```

**Expected:** Normal ingestion rates, no throttling

---

## 🧹 CLEANUP TEST ENVIRONMENT

```powershell
# Delete test resource group
az group delete --name $testRG --yes --no-wait

Write-Host "✓ Test environment cleanup initiated" -ForegroundColor Green
```

---

## 📊 TEST CHECKLIST

### Pre-Deployment
- [ ] mainTemplate.json validates successfully
- [ ] createUiDefinition.json works in sandbox
- [ ] All parameters have correct types
- [ ] SecureString used for secrets
- [ ] File sizes < limits

### Deployment
- [ ] Template deploys without errors
- [ ] All resources created successfully
- [ ] No permission errors
- [ ] Deployment completes in < 15 minutes

### Post-Deployment
- [ ] DCE deployed and accessible
- [ ] 3 DCRs deployed with correct streams
- [ ] 2 custom tables created
- [ ] 1 connector definition deployed
- [ ] 3 data connectors deployed and connected
- [ ] Data starts flowing within 30 minutes

### Functional Testing
- [ ] TacitRed connector polling API successfully
- [ ] Cyren IP connector polling API successfully
- [ ] Cyren Malware connector polling API successfully
- [ ] Data visible in Log Analytics
- [ ] Analytics rules triggering (if deployed)
- [ ] Workbooks displaying data (if deployed)

### Portal Experience
- [ ] Connector shows "Connected" status
- [ ] "Last log received" timestamp recent
- [ ] No error messages in portal
- [ ] Workbooks load without errors

---

## 🚨 COMMON ISSUES & FIXES

### Issue 1: Deployment Fails - "InvalidTemplate"

**Cause:** JSON syntax error

**Fix:**
```powershell
# Validate JSON
Get-Content .\marketplace-package\mainTemplate.json | ConvertFrom-Json
```

### Issue 2: Connector Shows "Disconnected"

**Cause:** Invalid API credentials

**Fix:**
1. Verify API keys are correct
2. Check API endpoint accessibility
3. Review DCE logs for errors

### Issue 3: No Data Ingesting

**Cause:** DCR transformation or API issue

**Fix:**
```kql
// Check DCE ingestion logs
AzureDiagnostics
| where Category == "DataCollectionRuleIngestion"
| where TimeGenerated > ago(1h)
| order by TimeGenerated desc
```

### Issue 4: Workbooks Show No Data

**Cause:** Tables empty or query issues

**Fix:**
```kql
// Verify tables have data
union TacitRed_Findings_CL, Cyren_Indicators_CL
| count
```

---

## 🎯 PRODUCTION READINESS CRITERIA

### ✅ All must pass before production:

1. **Template Validation**
   - ✅ Passes `az deployment group validate`
   - ✅ No syntax errors
   - ✅ All parameters documented

2. **UI Testing**
   - ✅ Sandbox test passes
   - ✅ All selectors populate correctly
   - ✅ Validation works

3. **Deployment Testing**
   - ✅ Successful deployment in test subscription
   - ✅ All resources created
   - ✅ No errors in logs

4. **Functional Testing**
   - ✅ Data flows within 30 minutes
   - ✅ Connectors show "Connected"
   - ✅ Analytics and workbooks work

5. **Performance Testing**
   - ✅ No throttling
   - ✅ Reasonable resource usage
   - ✅ Expected data volumes

6. **Security Review**
   - ✅ Secrets use securestring
   - ✅ No credentials in logs
   - ✅ Proper RBAC

---

## 📞 NEXT STEPS AFTER TESTING

### If All Tests Pass ✅

1. **Commit to Git:**
   ```powershell
   git add marketplace-package/
   git commit -m "✅ Marketplace package tested and validated"
   git push origin main
   ```

2. **Create GitHub Release**
   - Tag: `v1.0.0`
   - Include mainTemplate.json and createUiDefinition.json

3. **Update Deploy Button URLs**
   - Use your GitHub raw file URLs
   - Test button one more time

4. **Prepare for Marketplace Submission**
   - Create Partner Center account
   - Prepare assets (logo, screenshots)
   - Submit for review

### If Tests Fail ❌

1. Review error logs in `docs/deployment-logs/`
2. Fix issues in templates
3. Retest from Phase 1
4. Document fixes in change log

---

## 📚 TESTING COMMANDS REFERENCE

```powershell
# Quick validation script
.\test-marketplace-deployment.ps1

# Manual validation
az deployment group validate --resource-group <rg> --template-file .\marketplace-package\mainTemplate.json

# Deploy for testing
az deployment group create --resource-group <rg> --template-file .\marketplace-package\mainTemplate.json --parameters @parameters.json

# Check deployment status
az deployment group show --resource-group <rg> --name <deployment-name>

# List all resources
az resource list --resource-group <rg> --output table

# Cleanup
az group delete --name <rg> --yes --no-wait
```

---

**Testing Duration:** ~1 hour total  
**Production Readiness:** After all phases pass  
**Support:** Check MARKETPLACE-STRUCTURE.md for architecture details

---

**Good luck with testing! 🚀**

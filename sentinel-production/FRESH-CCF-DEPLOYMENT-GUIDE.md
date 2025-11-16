# Fresh CCF Deployment - Quick Start Guide

**Purpose:** Deploy a completely fresh, isolated CCF environment to test if the issue is environment-specific.

---

## 🎯 **What This Does**

Creates a **brand new** resource group with:
- ✅ New Log Analytics workspace
- ✅ Microsoft Sentinel enabled
- ✅ Full CCF infrastructure (DCE, DCR, table, UAMI, RBAC)
- ✅ CCF connector with **KNOWN WORKING** API key
- ❌ **NO Logic Apps** (pure CCF test)

---

## 📋 **Prerequisites**

✅ **API Key Confirmed Working:** `a2be534e-6231-4fb0-b8b8-15dbc96e83b7`  
   (Logic Apps proved it with 2,300+ records)

✅ **Azure CLI authenticated**

✅ **Subscription:** `774bee0e-b281-4f70-8e40-199e35b65117`

---

## 🚀 **Step 1: Deploy Fresh Environment**

```powershell
.\DEPLOY-FRESH-CCF-ONLY.ps1
```

**What it creates:**
- Resource Group: `TacitRedCCFTest`
- Workspace: `TacitRedCCFWorkspace`
- Polling Interval: **5 minutes** (for fast testing)

**Duration:** ~5-10 minutes

**Output:** 
- All resources created
- CCF connector deployed with API key
- Next poll time displayed

---

## ⏱️ **Step 2: Wait for First Poll**

CCF will poll every **5 minutes**.

**Timeline:**
```
T+0:  Deployment complete
T+5:  First CCF poll attempt
T+10: Second poll (if first failed)
T+15: Data should definitely appear if working
```

---

## ✅ **Step 3: Verify Data**

After waiting **10-15 minutes**, run:

```powershell
.\VERIFY-FRESH-CCF.ps1
```

**What it checks:**
1. ✅ CCF connector status (active? configured?)
2. ✅ Table data (any records?)
3. ✅ DCE/DCR configuration (correct?)
4. ✅ Timing (has poll happened yet?)

---

## 🔍 **Interpreting Results**

### **Scenario A: Data Appears** ✅
```
✅ DATA FOUND!
  Records: 100
  Latest: 2025-11-14 21:30:00
```

**Conclusion:** CCF works! The issue was environment-specific in the old deployment.

**Action:** Use fresh environment for marketplace package testing.

---

### **Scenario B: No Data After 15 Minutes** ❌
```
⚠ Table exists but has 0 records
⚠ First poll should have happened by now
```

**Conclusion:** CCF has a persistent issue (not environment-specific).

**Possible causes:**
1. Azure backend CCF bug
2. API key still not persisting (even in fresh deployment)
3. CCF RestApiPoller limitation with this specific API

**Action:** Consider alternatives (Logic Apps, or contact Microsoft Support).

---

## 📊 **What We're Testing**

| Component | Old Environment | Fresh Environment |
|-----------|----------------|-------------------|
| Workspace | SentinelThreatIntelWorkspace | TacitRedCCFWorkspace |
| Resource Group | SentinelTestStixImport | TacitRedCCFTest |
| Logic Apps | ✅ Running (2300 records) | ❌ Not deployed |
| CCF Connector | ❌ Not polling | ❓ Testing now |
| Deployments | Multiple (test + prod) | Single fresh deployment |
| State | "Dirty" (many updates) | Clean (first deployment) |

**Key difference:** Fresh environment has **zero prior state** or conflicts.

---

## 🎯 **Success Criteria**

### **If CCF works in fresh environment:**
- ✅ Proves CCF is functional
- ✅ Old environment had state conflicts
- ✅ Marketplace package will work for customers
- ✅ Can proceed with submission

### **If CCF fails in fresh environment:**
- ❌ CCF has inherent issue
- ❌ Need alternative solution
- ⚠️ Consider deploying both CCF + Logic Apps in package
- ⚠️ Or deploy Logic Apps only

---

## 📁 **Files Created**

| File | Purpose |
|------|---------|
| `DEPLOY-FRESH-CCF-ONLY.ps1` | Creates fresh CCF environment |
| `VERIFY-FRESH-CCF.ps1` | Checks deployment and data |
| `Project/Docs/fresh-ccf-deployment.json` | Deployment info (timestamps, IDs) |

---

## 🔧 **Manual Verification (Azure Portal)**

If you prefer to check manually:

1. **Navigate to:**
   ```
   Azure Portal → Resource Groups → TacitRedCCFTest
   → TacitRedCCFWorkspace → Logs
   ```

2. **Run query:**
   ```kql
   TacitRed_Findings_CL
   | summarize count()
   ```

3. **Expected result:**
   - After 10-15 minutes: **100+** records
   - If 0 records: Wait longer or CCF has issue

---

## 🧹 **Cleanup (After Testing)**

If you want to delete the test environment:

```powershell
az group delete --name TacitRedCCFTest --yes --no-wait
```

**Note:** Only do this after confirming results!

---

## 📞 **Next Steps Based on Results**

### **If CCF Works:**
1. ✅ Document that fresh deployments work
2. ✅ Update marketplace package documentation
3. ✅ Proceed with submission
4. ✅ Note that test environment may have issues but customer deployments will be fine

### **If CCF Fails:**
1. ❌ Open Microsoft Support ticket for CCF RestApiPoller
2. ⚠️ Consider hybrid approach (CCF + Logic Apps backup)
3. ⚠️ Or pivot to Logic Apps-only solution
4. 📋 Provide this deployment as evidence to Microsoft

---

## 📊 **Known Facts (To Remember)**

✅ **API Key is VALID** - Logic Apps prove it (2,300 records)  
✅ **Infrastructure is CORRECT** - DCE, DCR, tables all working  
✅ **CCF Config is CORRECT** - All settings verified  
❌ **CCF API Key Won't Persist** - Shows NULL in old environment  
❓ **Fresh Environment** - Will it work here?

---

**This is your definitive test to determine if CCF can work at all.**

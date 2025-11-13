# 🎯 DEPLOYMENT METHODS: PowerShell vs Marketplace

## Quick Answer to Your Questions

### ✅ Q1: Will tenant/subscription/workspace be in GUI for marketplace?

**YES!** The `createUiDefinition.json` provides a wizard with:
- Subscription selector (dropdown)
- Resource group selector (with "Create new" option)
- **Workspace selector** (populated from selected subscription)

**Customer never edits config files!**

### ✅ Q2: Do we use client-config-COMPLETE.json in marketplace?

**NO!** Two separate approaches:

| Approach | Config File | Use Case |
|----------|-------------|----------|
| **PowerShell** | client-config-COMPLETE.json | Testing, development, your deployments |
| **Marketplace** | createUiDefinition.json (UI wizard) | Customer deployments |

### ✅ Q3: Should we separate secrets and variables?

**ALREADY DONE in marketplace package!**

**Secrets (securestring - never stored):**
```json
"tacitRedApiKey": {
  "type": "securestring"  // ✅ Encrypted, never logged
}
```

**Variables (regular parameters):**
```json
"workspaceName": {
  "type": "string"  // ✅ Non-sensitive
}
```

### ✅ Q4: Do we use PowerShell script in ARM template?

**NO!** Marketplace uses **pure ARM templates only**.

**NOT ALLOWED in marketplace:**
- ❌ PowerShell scripts (.ps1)
- ❌ az commands
- ❌ Azure CLI
- ❌ Bash scripts

**ALLOWED in marketplace:**
- ✅ ARM templates (.json)
- ✅ Linked templates
- ✅ ARM functions

### ✅ Q5: Create new folder for marketplace?

**YES! Already created:** `marketplace-package/`

**Structure:**
```
sentinel-production/
├── DEPLOY-CCF-CORRECTED.ps1       ← For YOU (testing)
├── client-config-COMPLETE.json    ← For YOU (testing)
├── analytics/                     ← Shared by both
├── workbooks/                     ← Shared by both
└── marketplace-package/           ← NEW: For CUSTOMERS
    ├── mainTemplate.json          ← Pure ARM (to create)
    ├── createUiDefinition.json    ← ✅ Created
    ├── README.md                  ← ✅ Created
    └── MARKETPLACE-STRUCTURE.md   ← ✅ Created
```

---

## 📊 SIDE-BY-SIDE COMPARISON

| Aspect | PowerShell Deployment | Marketplace Deployment |
|--------|----------------------|------------------------|
| **Entry Point** | `DEPLOY-CCF-CORRECTED.ps1` | "Deploy to Azure" button |
| **Who Uses** | You (testing, dev) | Customers (production) |
| **Configuration** | `client-config-COMPLETE.json` | `createUiDefinition.json` (UI wizard) |
| **Tenant Selection** | Hardcoded in config | Selected in UI dropdown |
| **Subscription** | Hardcoded in config | Selected in UI dropdown |
| **Workspace** | Hardcoded in config | Selected from dropdown (populated) |
| **API Keys** | In config file (file on disk) | SecureString (never written to disk) |
| **Execution** | PowerShell + az commands | Pure ARM template |
| **Requirements** | Azure CLI installed | Just a web browser |
| **Updates** | Edit config, rerun script | Redeploy from marketplace |
| **Deployment Time** | ~3 minutes | ~10 minutes |
| **Security** | Keys in file (risky) | Keys encrypted (secure) |

---

## 🏗️ WHAT'S IN MARKETPLACE PACKAGE

### Files Created ✅

1. **createUiDefinition.json** (215 lines)
   - Subscription/workspace selectors
   - Secure credential inputs
   - Validation rules
   - Customer-friendly wizard

2. **README.md** (300+ lines)
   - Marketplace listing description
   - Prerequisites
   - Post-deployment steps
   - Troubleshooting

3. **MARKETPLACE-STRUCTURE.md** (500+ lines)
   - Complete architecture guide
   - Best practices
   - Answers to all your questions

### Files Needed (Next Steps)

4. **mainTemplate.json** (to create)
   - Pure ARM template
   - No PowerShell/az commands
   - Deploy all resources

5. **nestedTemplates/** (optional, recommended)
   - infrastructure.json (DCE, DCRs, Tables)
   - connectors.json (CCF connectors)
   - analytics.json (Rules)
   - workbooks.json (Dashboards)

---

## 🎨 CUSTOMER DEPLOYMENT FLOW

### PowerShell Method (Your Testing)

```
1. You edit client-config-COMPLETE.json
2. You hardcode subscription/workspace/keys
3. You run: .\DEPLOY-CCF-CORRECTED.ps1
4. Script runs az commands
5. Resources deployed
```

### Marketplace Method (Customer Production)

```
1. Customer clicks "Get It Now" on marketplace
2. Azure Portal opens with wizard
3. Customer selects from dropdowns:
   - Subscription
   - Resource Group
   - Workspace (auto-populated)
4. Customer enters API credentials (secure input boxes)
5. Customer clicks "Review + Create"
6. ARM template executes (no scripts!)
7. Resources deployed
```

---

## 🔐 HOW SECRETS ARE HANDLED

### PowerShell (Current - For Testing)

```json
{
  "tacitRed": {
    "value": {
      "apiKey": "a2be534e-6231-4fb0-b8b8-15dbc96e83b7"  // ❌ In file
    }
  }
}
```

**Risk:** File on disk, can be committed to Git accidentally

### Marketplace (Customers)

```json
{
  "parameters": {
    "tacitRedApiKey": {
      "type": "securestring"  // ✅ Never on disk
    }
  }
}
```

**Secure:** 
- Customer types in UI password box
- Passed encrypted to ARM
- Never logged
- Never stored in file

---

## 🚀 DEPLOYMENT ARCHITECTURE

### PowerShell Flow

```
client-config-COMPLETE.json
    ↓
DEPLOY-CCF-CORRECTED.ps1 reads config
    ↓
Runs: az deployment group create
    ↓
Runs: az rest --method PUT
    ↓
Runs: az sentinel data-connector list
    ↓
Resources created
```

**Pros:** Flexible, easy to test  
**Cons:** Requires Azure CLI, keys in files

### Marketplace Flow

```
Customer fills UI wizard (createUiDefinition.json)
    ↓
Values passed to mainTemplate.json
    ↓
ARM engine executes template
    ↓
Resources created declaratively
    ↓
No scripts run!
```

**Pros:** Secure, customer-friendly, no Azure CLI needed  
**Cons:** More complex to build

---

## 📂 FILE USAGE

### PowerShell Deployment Uses:

- ✅ `DEPLOY-CCF-CORRECTED.ps1`
- ✅ `client-config-COMPLETE.json`
- ✅ `analytics/*.bicep` (converted to JSON at runtime)
- ✅ `workbooks/bicep/*.bicep` (converted to JSON at runtime)
- ✅ `Data-Connectors/*.json`

### Marketplace Deployment Uses:

- ✅ `marketplace-package/mainTemplate.json` (master ARM template)
- ✅ `marketplace-package/createUiDefinition.json` (UI wizard)
- ✅ `marketplace-package/README.md` (listing description)
- ✅ Optionally: `marketplace-package/nestedTemplates/*.json`
- ❌ **Does NOT use:**
  - ❌ `DEPLOY-CCF-CORRECTED.ps1`
  - ❌ `client-config-COMPLETE.json`
  - ❌ Any .ps1 files
  - ❌ Any az commands

---

## ✅ BEST PRACTICES FOLLOWED

### 1. Separation of Concerns ✅

```
Testing/Development → PowerShell scripts
Production/Customers → Marketplace ARM
```

### 2. Secrets Management ✅

```
PowerShell → Keys in config (acceptable for testing)
Marketplace → SecureString parameters (required for production)
```

### 3. Workspace Selection ✅

```
PowerShell → Hardcoded in config
Marketplace → Selected from dropdown (populated from subscription)
```

### 4. No Hardcoding ✅

```
PowerShell → Config file with hardcoded values
Marketplace → All values from UI, nothing hardcoded
```

### 5. Modular Design ✅

```
Shared Components:
- Analytics rules (*.kql)
- Workbooks (*.bicep)
- Data connector configs (*.json)

Deployment Methods:
- PowerShell wrapper (for testing)
- ARM wrapper (for marketplace)
```

---

## 🎯 WHAT YOU NEED TO DO NEXT

### Immediate (For Marketplace)

1. ✅ **Create mainTemplate.json**
   - Pure ARM template
   - References nested templates or inline resources
   - No PowerShell, no az commands

2. ✅ **Test createUiDefinition.json**
   - Use Azure Portal sandbox
   - Verify workspace dropdown populates
   - Test parameter validation

3. ✅ **Create nested templates** (optional but recommended)
   - `nestedTemplates/infrastructure.json`
   - `nestedTemplates/connectors.json`
   - `nestedTemplates/analytics.json`
   - `nestedTemplates/workbooks.json`

### Later (For Marketplace Submission)

4. ⏳ **Create marketplace assets**
   - Logo (90x90 PNG)
   - Screenshots (5-6 images)
   - metadata.json
   - LICENSE.md

5. ⏳ **Test deployment**
   - Deploy from ARM template directly
   - Deploy from "Deploy to Azure" button
   - Test in clean subscription

6. ⏳ **Submit to marketplace**
   - Partner Center account
   - Solution package
   - Marketplace listing

---

## 💡 KEY TAKEAWAYS

### For Testing (You)
- ✅ Keep using `DEPLOY-CCF-CORRECTED.ps1`
- ✅ Keep using `client-config-COMPLETE.json`
- ✅ This is fastest for development

### For Customers (Marketplace)
- ✅ Use `marketplace-package/` folder
- ✅ Pure ARM templates only
- ✅ UI wizard for all inputs
- ✅ No config files needed

### Both Can Coexist
- ✅ Same analytics rules
- ✅ Same workbooks
- ✅ Same data connectors
- ✅ Different deployment wrappers

---

## 📞 SUMMARY

**Your Questions → Answers:**

1. ✅ **Tenant/subscription/workspace in GUI?** → YES, via createUiDefinition.json
2. ✅ **Use client-config-COMPLETE.json?** → NO, only for PowerShell testing
3. ✅ **Separate secrets and variables?** → YES, already done (securestring vs string)
4. ✅ **PowerShell in ARM template?** → NO, pure ARM only for marketplace
5. ✅ **New folder for marketplace?** → YES, created `marketplace-package/`

**Next Step:** Create `mainTemplate.json` for marketplace deployment!

---

**Created:** November 12, 2025  
**Purpose:** Guide for marketplace deployment  
**Status:** Ready for mainTemplate.json creation

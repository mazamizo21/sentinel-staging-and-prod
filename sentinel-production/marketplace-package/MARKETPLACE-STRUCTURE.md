# Azure Marketplace Package Structure

## 📦 WHAT'S DIFFERENT: PowerShell vs Marketplace

### Current PowerShell Deployment
```
DEPLOY-CCF-CORRECTED.ps1
├── Uses: client-config-COMPLETE.json (hardcoded values)
├── Runs: az commands (requires Azure CLI)
├── Input: Manual config file editing
└── Use Case: Direct deployment, testing, development
```

### Marketplace Deployment (Required)
```
mainTemplate.json
├── Pure ARM template (no PowerShell, no az commands)
├── Parameters: From UI (tenant, subscription, workspace selected by customer)
├── Secrets: Secure parameters (never stored in files)
└── Use Case: Azure Marketplace, customer self-service
```

---

## 🏗️ MARKETPLACE PACKAGE FILES

### Required Files

| File | Purpose | Created By |
|------|---------|------------|
| **mainTemplate.json** | Main ARM deployment template | ✅ To create |
| **createUiDefinition.json** | Marketplace UI wizard | ✅ To create |
| **README.md** | Marketplace listing description | ✅ To create |
| **LICENSE.md** | License terms | ✅ To create |

### Optional But Recommended

| File | Purpose |
|------|---------|
| **nestedTemplates/** | Modular sub-templates (DCRs, connectors, etc) |
| **icons/logo.png** | 90x90 marketplace icon |
| **screenshots/** | Product screenshots for listing |
| **metadata.json** | Solution metadata |

---

## 🎨 UI DEFINITION STRUCTURE

### Customer Sees This Flow:

```
Step 1: Basics
├── Select Subscription
├── Select Resource Group (or create new)
└── Select Region

Step 2: Workspace Selection  
└── Select existing Microsoft Sentinel workspace

Step 3: API Credentials (Secure)
├── TacitRed API Key (securestring)
├── Cyren IP JWT Token (securestring)
└── Cyren Malware JWT Token (securestring)

Step 4: Review + Create
├── Validate inputs
├── Show estimated cost
└── Deploy button
```

**NO client-config-COMPLETE.json used!**  
All values come from UI selections.

---

## 🔐 SECRETS MANAGEMENT

### ❌ WRONG (Current - for PowerShell only)
```json
{
  "tacitRed": {
    "value": {
      "apiKey": "hardcoded-key-here"  // ❌ Stored in file
    }
  }
}
```

### ✅ CORRECT (Marketplace)
```json
{
  "$schema": "...",
  "parameters": {
    "tacitRedApiKey": {
      "type": "securestring",  // ✅ Never stored
      "metadata": {
        "description": "TacitRed API Key"
      }
    }
  }
}
```

Customer enters in UI → Passed securely to ARM → Never written to disk

---

## 📋 PARAMETER CATEGORIES

### Separated into:

**1. System Parameters (Auto-selected by customer)**
- `location` - From "Basics" step
- `workspace-location` - Auto-detected
- `workspaceName` - Selected from dropdown

**2. Secret Parameters (Secure input)**
- `tacitRedApiKey` - securestring
- `cyrenIPJwtToken` - securestring  
- `cyrenMalwareJwtToken` - securestring

**3. Configuration Parameters (Optional)**
- `pollingFrequency` - Default: 360 minutes
- `enableAnalytics` - Default: true
- `enableWorkbooks` - Default: true

---

## 🚀 DEPLOYMENT FLOW

### Marketplace Deployment Process:

```
Customer clicks "Get It Now" on Marketplace
    ↓
Azure Portal opens with createUiDefinition.json
    ↓
Customer fills out wizard:
  1. Select subscription/resource group/region
  2. Select existing Sentinel workspace  
  3. Enter API credentials (secure)
  4. Click "Review + Create"
    ↓
Azure validates inputs
    ↓
Customer clicks "Create"
    ↓
mainTemplate.json executes (pure ARM)
    ↓
Resources deployed:
  - DCE
  - DCRs
  - Tables
  - CCF Connectors
  - Analytics Rules
  - Workbooks
    ↓
Deployment complete notification
    ↓
Customer sees resources in Sentinel
```

**NO PowerShell scripts run!**  
**NO az commands executed!**  
**Pure ARM template deployment!**

---

## 🔧 WHAT NEEDS TO BE CONVERTED

### From PowerShell → ARM Template

| PowerShell Command | ARM Equivalent |
|-------------------|----------------|
| `az deployment group create` | ARM deployment resource |
| `az rest --method PUT` | Nested ARM resource |
| `az monitor log-analytics workspace show` | Reference existing workspace |
| `az sentinel data-connector list` | Not needed (declarative) |

### Example Conversion:

**PowerShell (Current):**
```powershell
az deployment group create \
  --template-file mainTemplate.json \
  --parameters tacitRedApiKey=$apiKey
```

**ARM Template (Marketplace):**
```json
{
  "type": "Microsoft.Resources/deployments",
  "apiVersion": "2021-04-01",
  "name": "mainDeployment",
  "properties": {
    "mode": "Incremental",
    "templateLink": {
      "uri": "https://raw.githubusercontent.com/.../mainTemplate.json"
    },
    "parameters": {
      "tacitRedApiKey": {
        "value": "[parameters('tacitRedApiKey')]"
      }
    }
  }
}
```

---

## 📂 RECOMMENDED FOLDER STRUCTURE

```
marketplace-package/
├── mainTemplate.json              # Main deployment template
├── createUiDefinition.json        # UI wizard definition
├── README.md                      # Marketplace description
├── LICENSE.md                     # License
├── metadata.json                  # Solution metadata
├── nestedTemplates/               # Modular templates
│   ├── infrastructure.json        # DCE, DCRs, Tables
│   ├── connectors.json            # CCF connectors
│   ├── analytics.json             # Analytics rules
│   └── workbooks.json             # Workbooks
├── icons/
│   └── logo.png                   # 90x90 icon
└── screenshots/
    ├── screenshot1.png            # Connector view
    ├── screenshot2.png            # Workbook view
    └── screenshot3.png            # Analytics view
```

---

## ✅ BEST PRACTICES

### 1. **Use Linked Templates for Modularity**

**Why?** ARM templates have 4MB limit. Break into:
- Infrastructure (DCE, DCRs, Tables)
- Data Connectors (CCF)
- Analytics (Rules)
- Workbooks

### 2. **Reference Existing Workspace (Don't Create)**

```json
{
  "type": "Microsoft.OperationalInsights/workspaces",
  "apiVersion": "2022-10-01",
  "name": "[parameters('workspaceName')]",
  "existing": true  // ✅ Don't create, reference existing
}
```

### 3. **All Secrets as SecureString**

```json
"tacitRedApiKey": {
  "type": "securestring",  // ✅ Never logged, never stored
  "metadata": {
    "description": "..."
  }
}
```

### 4. **Validate Inputs in UI**

```json
"tacitRedApiKey": {
  "type": "Microsoft.Common.PasswordBox",
  "constraints": {
    "required": true,
    "regex": "^[a-zA-Z0-9-]{30,}$",  // ✅ Validate format
    "validationMessage": "Must be at least 30 characters"
  }
}
```

### 5. **Use Standard Output Names**

```json
"outputs": {
  "workspaceName": {
    "type": "string",
    "value": "[parameters('workspaceName')]"
  },
  "connectorName": {
    "type": "string",
    "value": "ThreatIntelligenceFeeds"
  }
}
```

---

## 🎯 ANSWERS TO YOUR QUESTIONS

### Q1: "Will tenant/subscription/workspace be in GUI?"

**YES!** The `createUiDefinition.json` provides:
- **Subscription selector** (built-in Azure control)
- **Resource Group selector** (with "Create new" option)
- **Workspace dropdown** (populated from selected subscription)

Customer NEVER edits config files!

### Q2: "Will we use client-config-COMPLETE.json in marketplace?"

**NO!** That file is for PowerShell deployment only.

**Marketplace uses:**
- `mainTemplate.json` (ARM template)
- `createUiDefinition.json` (UI wizard)
- All values come from customer selections

### Q3: "Should we separate secrets and variables?"

**YES! Already done in ARM approach:**

**Secrets (securestring):**
- TacitRed API Key
- Cyren JWT Tokens

**Variables (regular parameters):**
- Workspace name
- Location
- Polling frequency

### Q4: "PowerShell script in ARM template?"

**NO! Pure ARM only!**

**Marketplace doesn't support:**
- ❌ PowerShell scripts
- ❌ az commands
- ❌ Azure CLI

**Marketplace supports:**
- ✅ ARM templates (declarative)
- ✅ Linked templates
- ✅ ARM functions

### Q5: "Create new folder for marketplace?"

**YES! Recommended structure:**

```
sentinel-production/
├── DEPLOY-CCF-CORRECTED.ps1       # For testing/dev
├── client-config-COMPLETE.json    # For testing/dev
├── analytics/                     # Shared
├── workbooks/                     # Shared
├── Data-Connectors/               # Shared
└── marketplace-package/           # ✅ NEW - For marketplace
    ├── mainTemplate.json
    ├── createUiDefinition.json
    ├── README.md
    └── nestedTemplates/
```

**Two deployment methods:**
1. **PowerShell** (for you, testing) → Uses scripts
2. **Marketplace** (for customers) → Uses ARM package

---

## 📊 COMPARISON TABLE

| Aspect | PowerShell Deployment | Marketplace Deployment |
|--------|----------------------|------------------------|
| **Who uses** | You (testing) | Customers (production) |
| **Entry point** | DEPLOY-CCF-CORRECTED.ps1 | "Deploy to Azure" button |
| **Configuration** | client-config-COMPLETE.json | createUiDefinition.json |
| **Secrets** | In config file (risky) | SecureString (secure) |
| **Execution** | az commands | ARM template |
| **Requirements** | Azure CLI installed | Just a browser |
| **Tenant/Sub/WS** | Hardcoded in config | Selected in UI |
| **Updates** | Edit config, rerun script | Redeploy from marketplace |

---

## 🚀 NEXT STEPS

1. ✅ Create `mainTemplate.json` (complete ARM template)
2. ✅ Create `createUiDefinition.json` (proper UI with pickers)
3. ✅ Test locally with Azure Portal sandbox
4. ✅ Create nested templates for modularity
5. ✅ Add validation and error handling
6. ✅ Create README for marketplace listing
7. ✅ Package and submit to marketplace

---

**Summary:** Marketplace = Pure ARM templates, no PowerShell, no config files, customer-friendly UI!

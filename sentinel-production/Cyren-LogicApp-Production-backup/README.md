# Cyren Threat Intelligence - Microsoft Sentinel Deployment

## Overview

This package deploys the **Cyren Threat Intelligence** solution to Microsoft Sentinel, providing real-time threat detection from Cyren's IP Reputation and Malware URLs feeds.

## What Gets Deployed

| Component | Description |
|-----------|-------------|
| **Data Collection Endpoint** | `dce-sentinel-ti` - Ingestion endpoint for threat data |
| **Data Collection Rules** | `dcr-cyren-ip` and `dcr-cyren-malware` - Transform and route data |
| **Log Analytics Table** | `Cyren_Indicators_CL` - Stores all threat indicators |
| **Logic Apps** | `logic-cyren-ip-reputation` and `logic-cyren-malware-urls` - Poll Cyren APIs |
| **RBAC** | Monitoring Metrics Publisher role on DCE/DCR for Logic Apps |
| **Analytics Rules** | 3 detection rules (High-Risk IP, Malware URL, Persistent Threat) |
| **Workbook** | Cyren Threat Intelligence Dashboard |

---

## Prerequisites

### 1. Azure CLI
Install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

Verify installation:
```powershell
az --version
```

### 2. Azure Login
Login to Azure before running the script:
```powershell
az login
```

### 3. Azure Permissions
You need **Contributor** access to the target resource group.

### 4. Cyren JWT Tokens
Obtain JWT tokens from Cyren for:
- IP Reputation feed
- Malware URLs feed

---

## Configuration

### Edit `client-config-COMPLETE.json`

Open the configuration file and update these values:

```json
{
  "parameters": {
    "azure": {
      "value": {
        "subscriptionId": "YOUR-SUBSCRIPTION-ID",
        "resourceGroupName": "YOUR-RESOURCE-GROUP",
        "workspaceName": "YOUR-LOG-ANALYTICS-WORKSPACE",
        "location": "eastus",
        "tenantId": "YOUR-TENANT-ID"
      }
    },
    "cyren": {
      "value": {
        "ipReputation": {
          "jwtToken": "YOUR-CYREN-IP-REPUTATION-JWT-TOKEN"
        },
        "malwareUrls": {
          "jwtToken": "YOUR-CYREN-MALWARE-URLS-JWT-TOKEN"
        }
      }
    }
  }
}
```

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `subscriptionId` | Azure Subscription ID | `774bee0e-b281-4f70-8e40-199e35b65117` |
| `resourceGroupName` | Target Resource Group | `Cyren-LogicApp-Production` |
| `workspaceName` | Log Analytics Workspace name | `Cyren-LogicApp-Production` |
| `location` | Azure region | `eastus` |
| `jwtToken` (IP) | Cyren IP Reputation JWT token | `eyJ0eXAi...` |
| `jwtToken` (Malware) | Cyren Malware URLs JWT token | `eyJ0eXAi...` |

---

## How to Run

### Option 1: Double-Click (Recommended)
1. Open File Explorer
2. Navigate to this folder
3. **Double-click** `DEPLOY-CYREN-ONLY.ps1`
4. If prompted, select "Run with PowerShell"
5. Wait for deployment to complete (~10-15 minutes)

### Option 2: PowerShell
```powershell
# Navigate to the script folder (optional - script auto-detects location)
cd "C:\Path\To\Cyren-LogicApp-Production"

# Run the script
.\DEPLOY-CYREN-ONLY.ps1
```

### Option 3: Custom Config File
```powershell
.\DEPLOY-CYREN-ONLY.ps1 -ConfigFile "my-custom-config.json"
```

---

## Deployment Phases

The script executes these phases:

1. **Prerequisites** - Verify Azure subscription and workspace
2. **DCE** - Deploy Data Collection Endpoint
3. **Table** - Create `Cyren_Indicators_CL` table with full schema
4. **DCRs** - Deploy Data Collection Rules for IP and Malware feeds
5. **Logic Apps** - Deploy ingestion Logic Apps with managed identity
6. **RBAC** - Assign Monitoring Metrics Publisher role
7. **Analytics** - Deploy detection rules
8. **Workbook** - Deploy threat intelligence dashboard
9. **Test** - Trigger initial data ingestion

---

## Post-Deployment Verification

### 1. Check Logic Apps
In Azure Portal:
- Go to **Resource Group** → **Logic Apps**
- Verify `logic-cyren-ip-reputation` and `logic-cyren-malware-urls` exist
- Check **Run history** for successful executions

### 2. Check Data Ingestion
In Log Analytics:
```kql
Cyren_Indicators_CL
| summarize count() by source_s
| order by count_ desc
```

### 3. Check Analytics Rules
In Sentinel:
- Go to **Analytics** → **Active rules**
- Verify 3 Cyren rules are enabled

### 4. Check Workbook
In Sentinel:
- Go to **Workbooks** → **My workbooks**
- Open "Cyren Threat Intelligence Dashboard"

---

## Troubleshooting

### "Configuration file not found"
- Ensure `client-config-COMPLETE.json` is in the same folder as the script
- Check file name spelling

### "Subscription not found"
- Run `az login` to authenticate
- Verify `subscriptionId` in config file

### "Logic App trigger failed"
- Wait 2-3 minutes for RBAC propagation
- Manually trigger from Azure Portal

### "No data in table"
- Data ingestion takes 2-5 minutes after trigger
- Check Logic App run history for errors
- Verify Cyren JWT tokens are valid

---

## Logs

Deployment logs are saved to:
```
.\logs\cyren-only-YYYYMMDDHHMMSS\
  ├── transcript.log       # Full deployment transcript
  └── rbac-cyren.json      # RBAC assignment results
```

---

## Support

For issues:
1. Check `logs\` folder for error details
2. Verify Azure CLI is up to date: `az upgrade`
3. Ensure Cyren JWT tokens haven't expired

---

## File Structure

```
Cyren-LogicApp-Production/
├── DEPLOY-CYREN-ONLY.ps1           # Main deployment script
├── client-config-COMPLETE.json     # Configuration file (EDIT THIS)
├── README.md                       # This file
├── analytics/
│   ├── analytics-rules.bicep       # Sentinel analytics rules
│   └── rules/                      # KQL rule definitions
├── infrastructure/
│   └── bicep/
│       ├── dcr-cyren-ip.bicep
│       ├── dcr-cyren-malware.bicep
│       ├── logicapp-cyren-ip-reputation.bicep
│       └── logicapp-cyren-malware-urls.bicep
├── workbooks/
│   └── bicep/
│       └── workbook-cyren-threat-intelligence.bicep
└── logs/                           # Deployment logs (auto-created)
```

---

## Version

- **Package Version**: 1.0.0
- **Last Updated**: November 2025
- **Cyren API**: v1

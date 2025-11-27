# TacitRed Logic App - Sentinel Integration

This package deploys a Logic App that integrates TacitRed threat intelligence data with Microsoft Sentinel.

## Prerequisites

Before running the deployment, ensure you have:

1. **Azure CLI installed** - [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
2. **PowerShell 7+** (PowerShell Core) - [Install PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell)
3. **Azure subscription** with Owner or Contributor access
4. **Existing Resource Group** with a Log Analytics Workspace and Microsoft Sentinel enabled
5. **TacitRed API Key** from your TacitRed account

---

## Quick Start

### Step 1: Configure Your Settings

Edit the `client-config-COMPLETE.json` file with your Azure and TacitRed details:

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
    "tacitRed": {
      "value": {
        "apiKey": "YOUR-TACITRED-API-KEY"
      }
    }
  }
}
```

### Step 2: Login to Azure

Open PowerShell and login to Azure:

```powershell
az login
```

### Step 3: Run the Deployment

Navigate to this folder and run:

```powershell
.\DEPLOY-TACITRED-ONLY.ps1
```

Or run from any directory:

```powershell
& "C:\path\to\TacitRed-LogicApp-Production\DEPLOY-TACITRED-ONLY.ps1"
```

---

## Configuration Reference

### Required Variables

| Variable | Location in Config | Description |
|----------|-------------------|-------------|
| `subscriptionId` | `azure.value.subscriptionId` | Your Azure subscription ID (GUID) |
| `resourceGroupName` | `azure.value.resourceGroupName` | Name of your existing Resource Group |
| `workspaceName` | `azure.value.workspaceName` | Name of your Log Analytics Workspace |
| `location` | `azure.value.location` | Azure region (e.g., `eastus`, `westus2`) |
| `tenantId` | `azure.value.tenantId` | Your Azure AD tenant ID (GUID) |
| `apiKey` | `tacitRed.value.apiKey` | Your TacitRed API key |

### How to Find Your Azure IDs

**Subscription ID:**
```powershell
az account show --query id -o tsv
```

**Tenant ID:**
```powershell
az account show --query tenantId -o tsv
```

**Resource Group (list all):**
```powershell
az group list --query "[].name" -o tsv
```

**Log Analytics Workspace (list all in a resource group):**
```powershell
az monitor log-analytics workspace list -g YOUR-RESOURCE-GROUP --query "[].name" -o tsv
```

---

## What Gets Deployed

The script deploys the following Azure resources:

| Resource | Name | Purpose |
|----------|------|---------|
| Data Collection Endpoint | `dce-sentinel-ti` | Receives data from Logic App |
| Custom Log Table | `TacitRed_Findings_CL` | Stores TacitRed findings in Log Analytics |
| Data Collection Rule | `dcr-tacitred-findings` | Routes data to the custom table |
| Logic App | `logic-tacitred-ingestion` | Polls TacitRed API and sends to Sentinel |
| RBAC Assignments | Monitoring Metrics Publisher | Allows Logic App to ingest data |
| Analytics Rules | Sentinel Detection Rules | Detects repeat compromises and threats |
| Workbook | TacitRed SecOps Dashboard | Visual dashboard for credential monitoring |

---

## Post-Deployment Verification

### Check Logic App Status

1. Go to Azure Portal → Resource Group → `logic-tacitred-ingestion`
2. Click **Run History** to see execution status
3. Status should show **Succeeded**

### Query Data in Sentinel

In your Log Analytics Workspace, run:

```kusto
TacitRed_Findings_CL
| summarize count(), min(TimeGenerated), max(TimeGenerated)
```

---

## Troubleshooting

### "Forbidden" Error on Logic App Run

RBAC permissions take 5-10 minutes to propagate after deployment. Wait and retry:

```powershell
# Manually trigger the Logic App
az rest --method POST --uri "https://management.azure.com/subscriptions/YOUR-SUB-ID/resourceGroups/YOUR-RG/providers/Microsoft.Logic/workflows/logic-tacitred-ingestion/triggers/Recurrence/run?api-version=2019-05-01"
```

### Logic App Not Found

Ensure the Resource Group and Workspace exist before running the deployment.

### Azure CLI Extension Prompt

The script automatically configures Azure CLI to install extensions without prompting. If you see prompts, run:

```powershell
az config set extension.use_dynamic_install=yes_without_prompt
```

---

## Logs

Deployment logs are saved in the `logs/` folder within this package:
- `logs/deployment-TIMESTAMP/transcript.log` - Full deployment transcript

---

## Support

For issues with:
- **TacitRed API** - Contact TacitRed support
- **Azure/Sentinel** - Contact your Azure administrator
- **This deployment package** - Review logs in the `logs/` folder

---

## Version

- Package Version: 1.0.0
- Last Updated: November 2025

# Cyren & TacitRed CCF Hub Deployment Guide

This guide documents how to deploy the **Cyren-CCF-Hub** and **Tacitred-CCF-Hub** solutions to an existing Microsoft Sentinel workspace using **Azure CLI**.

> Run all commands from the folder:
>
> `d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production`

---

## 1. Prerequisites

- Existing **Log Analytics workspace** with **Microsoft Sentinel** enabled:
  - Subscription ID: `<SUBSCRIPTION_ID>`
  - Resource group: `<RESOURCE_GROUP_NAME>`
  - Workspace name: `<WORKSPACE_NAME>`
  - Workspace region: `<WORKSPACE_LOCATION>` (e.g. `eastus`)
- Azure CLI logged into the correct tenant:
  - `az login`
  - `az account set --subscription <SUBSCRIPTION_ID>`
- Secrets:
  - **Cyren**:
    - `<CYREN_IP_JWT_TOKEN>`
    - `<CYREN_MALWARE_JWT_TOKEN>`
  - **TacitRed**:
    - `<TACITRED_API_KEY>`

> For safer handling of secrets, prefer environment variables or Key Vault over pasting secrets directly in the command line.

---

## 2. Deploy Cyren-CCF-Hub

Template: `./Cyren-CCF-Hub/Package/mainTemplate.json`

### 2.1 Minimal deployment (all features enabled)

```powershell
az deployment group create `
  --subscription <SUBSCRIPTION_ID> `
  --resource-group <RESOURCE_GROUP_NAME> `
  --name Cyren-CCF-Hub-Deploy `
  --template-file "./Cyren-CCF-Hub/Package/mainTemplate.json" `
  --parameters `
    workspace="<WORKSPACE_NAME>" `
    workspace-location="<WORKSPACE_LOCATION>" `
    cyrenIPJwtToken="<CYREN_IP_JWT_TOKEN>" `
    cyrenMalwareJwtToken="<CYREN_MALWARE_JWT_TOKEN>"
```

Defaults:

- `deployAnalytics` = `true`
- `deployWorkbooks` = `true`
- `deployConnectors` = `true`
- `enableKeyVault` = `false`

### 2.2 Optional parameters

You can override any of these if needed:

```powershell
--parameters `
  workspace="<WORKSPACE_NAME>" `
  workspace-location="<WORKSPACE_LOCATION>" `
  cyrenIPJwtToken="<CYREN_IP_JWT_TOKEN>" `
  cyrenMalwareJwtToken="<CYREN_MALWARE_JWT_TOKEN>" `
  deployAnalytics=true `
  deployWorkbooks=true `
  deployConnectors=true `
  enableKeyVault=false `
  keyVaultOption="new" `
  keyVaultName="<KEYVAULT_NAME>" `
  keyVaultResourceGroup="<KEYVAULT_RG>" `
  enablePrivateEndpoint=false `
  subnetId="<SUBNET_RESOURCE_ID>"
```

> For direct Content Hub packaging scenarios, `cyrenIPDcrImmutableId` and `cyrenMalwareDcrImmutableId` are wired for pipeline use, but are not required for local CLI deployments.

---

## 3. Deploy Tacitred-CCF-Hub

Template: `./Tacitred-CCF-Hub/Package/mainTemplate.json`

### 3.1 Minimal deployment (all features enabled)

```powershell
az deployment group create `
  --subscription <SUBSCRIPTION_ID> `
  --resource-group <RESOURCE_GROUP_NAME> `
  --name TacitRed-CCF-Hub-Deploy `
  --template-file "./Tacitred-CCF-Hub/Package/mainTemplate.json" `
  --parameters `
    workspace="<WORKSPACE_NAME>" `
    workspace-location="<WORKSPACE_LOCATION>" `
    tacitRedApiKey="<TACITRED_API_KEY>"
```

Defaults:

- `tacitRedDcrImmutableId` = `""` (for local CLI deploys, template creates the DCR and resolves the immutableId internally)
- `deployAnalytics` = `true`
- `deployWorkbooks` = `true`
- `deployConnectors` = `true`
- `enableKeyVault` = `false`

### 3.2 Optional parameters

```powershell
--parameters `
  workspace="<WORKSPACE_NAME>" `
  workspace-location="<WORKSPACE_LOCATION>" `
  tacitRedApiKey="<TACITRED_API_KEY>" `
  tacitRedDcrImmutableId="" `
  deployAnalytics=true `
  deployWorkbooks=true `
  deployConnectors=true `
  enableKeyVault=false `
  keyVaultOption="new" `
  keyVaultName="<KEYVAULT_NAME>" `
  keyVaultResourceGroup="<KEYVAULT_RG>" `
  enablePrivateEndpoint=false `
  subnetId="<SUBNET_RESOURCE_ID>"
```

> For **Content Hub** packaging, the pipeline is expected to deploy the TacitRed DCR first, read its `immutableId`, and pass it as `tacitRedDcrImmutableId`. For local CLI, keeping it empty is correct.

---

## 4. Secret handling with environment variables (recommended)

Example of using environment variables in PowerShell to avoid inline secrets:

```powershell
$env:CYREN_IP_JWT = "<CYREN_IP_JWT_TOKEN>"
$env:CYREN_MALWARE_JWT = "<CYREN_MALWARE_JWT_TOKEN>"
$env:TACITRED_API_KEY = "<TACITRED_API_KEY>"
```

Then:

```powershell
az deployment group create `
  --subscription <SUBSCRIPTION_ID> `
  --resource-group <RESOURCE_GROUP_NAME> `
  --name Cyren-CCF-Hub-Deploy `
  --template-file "./Cyren-CCF-Hub/Package/mainTemplate.json" `
  --parameters `
    workspace="<WORKSPACE_NAME>" `
    workspace-location="<WORKSPACE_LOCATION>" `
    cyrenIPJwtToken=$env:CYREN_IP_JWT `
    cyrenMalwareJwtToken=$env:CYREN_MALWARE_JWT
```

```powershell
az deployment group create `
  --subscription <SUBSCRIPTION_ID> `
  --resource-group <RESOURCE_GROUP_NAME> `
  --name TacitRed-CCF-Hub-Deploy `
  --template-file "./Tacitred-CCF-Hub/Package/mainTemplate.json" `
  --parameters `
    workspace="<WORKSPACE_NAME>" `
    workspace-location="<WORKSPACE_LOCATION>" `
    tacitRedApiKey=$env:TACITRED_API_KEY
```

---

## 5. Post-deployment verification (high level)

- Confirm resources created in the resource group:
  - Data Collection Endpoint (DCE)
  - Cyren and TacitRed DCRs
  - Custom tables: `Cyren_Indicators_CL`, `TacitRed_Findings_CL`
  - CCF data connectors for Cyren and TacitRed
  - Optional: Key Vault and role assignments if enabled
- Check Sentinel **Data connectors** blade for:
  - **Cyren Threat Intelligence** connector
  - **TacitRed Compromised Credentials** connector
- Validate ingestion via KQL:

```kusto
Cyren_Indicators_CL
| take 10
```

```kusto
TacitRed_Findings_CL
| take 10
```

This file serves as the authoritative quick-start for deploying both Cyren and TacitRed CCF Hub solutions to your Sentinel workspace.

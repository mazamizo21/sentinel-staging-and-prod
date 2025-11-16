# TacitRed CCF - Detailed Code Map

**Generated:** 2025-11-14  
**Purpose:** Line-by-line mapping of TacitRed implementation

---

## FILE: mainTemplate.json (824 lines)

### Header & Metadata (Lines 1-10)
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0",
  "metadata": {
    "author": "TacitRed",
    "comments": "TacitRed Compromised Credentials Solution for Microsoft Sentinel"
  }
}
```

### Parameters Section (Lines 8-99)
| Lines | Parameter | Type | Purpose |
|-------|-----------|------|---------|
| 9-13 | workspace | string | Sentinel workspace name |
| 15-21 | workspace-location | string | Azure region |
| 22-27 | tacitRedApiKey | securestring | TacitRed API key |
| 28-34 | deployAnalytics | bool | Deploy analytics rule toggle |
| 35-41 | deployWorkbooks | bool | Deploy workbooks toggle |
| 42-48 | deployConnectors | bool | Deploy CCF connector toggle |
| 49-55 | enableKeyVault | bool | Enable Key Vault toggle |
| 56-63 | keyVaultOption | string | new/existing Key Vault |
| 64-70 | keyVaultName | string | Key Vault name |
| 71-77 | keyVaultResourceGroup | string | Key Vault RG |
| 78-84 | enablePrivateEndpoint | bool | Private endpoint toggle |
| 85-91 | subnetId | string | Subnet for private endpoint |
| 92-98 | forceUpdateTag | string | Force script re-execution |

### Variables Section (Lines 100-110)
```json
{
  "workspaceResourceId": "[resourceId('Microsoft.OperationalInsights/Workspaces', parameters('workspace'))]",
  "dceName": "dce-threatintel-feeds",
  "tacitRedDcrName": "dcr-tacitred-findings",
  "_solutionName": "ThreatIntelligenceFeeds",
  "_solutionVersion": "1.0.0",
  "solutionId": "threatintel.sentinel-solution-threatintel-feeds",
  "uamiName": "uami-ccf-deployment",
  "keyVaultResourceId": "[if(parameters('enableKeyVault'), ...)]",
  "useKeyVault": "[parameters('enableKeyVault')]"
}
```

### Resources Section (Lines 111-807)

#### Resource 1: Data Collection Endpoint (Lines 112-122)
```json
{
  "type": "Microsoft.Insights/dataCollectionEndpoints",
  "apiVersion": "2022-06-01",
  "name": "dce-threatintel-feeds",
  "location": "[parameters('workspace-location')]",
  "properties": {
    "networkAcls": {
      "publicNetworkAccess": "Enabled"
    }
  }
}
```

#### Resource 2: Custom Table (Lines 123-198)
**Table:** `TacitRed_Findings_CL`  
**Schema Definition:** Lines 128-196 (16 columns)

| Lines | Column | Type |
|-------|--------|------|
| 131-134 | TimeGenerated | datetime |
| 135-138 | email_s | string |
| 139-142 | domain_s | string |
| 143-146 | findingType_s | string |
| 147-150 | confidence_d | int |
| 151-154 | firstSeen_t | datetime |
| 155-158 | lastSeen_t | datetime |
| 159-162 | notes_s | string |
| 163-166 | source_s | string |
| 167-170 | severity_s | string |
| 171-174 | status_s | string |
| 175-178 | campaign_id_s | string |
| 179-182 | user_id_s | string |
| 183-186 | username_s | string |
| 187-190 | detection_ts_t | datetime |
| 191-194 | metadata_s | string |

#### Resource 3: Data Collection Rule (Lines 199-301)
**Name:** `dcr-tacitred-findings`  
**Dependencies:** DCE + Custom Table

**Stream Declaration (Lines 210-279):** `Custom-TacitRed_Findings_CL`
- 16 columns without suffixes (email, domain, confidence, etc.)

**Data Flow (Lines 288-299):**
```json
{
  "streams": ["Custom-TacitRed_Findings_CL"],
  "destinations": ["clv2ws1"],
  "transformKql": "source | extend TimeGenerated = now()",
  "outputStream": "Custom-TacitRed_Findings_CL"
}
```

#### Resource 4: User-Assigned Managed Identity (Lines 302-307)
```json
{
  "type": "Microsoft.ManagedIdentity/userAssignedIdentities",
  "name": "uami-ccf-deployment",
  "location": "[parameters('workspace-location')]"
}
```

#### Resource 5-6: Role Assignments (Lines 308-334)
**Assignment 1 (Lines 308-321):** Workspace-level Sentinel Contributor
```json
{
  "type": "Microsoft.Authorization/roleAssignments",
  "scope": "[workspaceResourceId]",
  "roleDefinitionId": "b24988ac-6180-42a0-ab88-20f7382dd24c"
}
```

**Assignment 2 (Lines 322-334):** Resource Group-level Contributor

#### Resource 7: Key Vault (Lines 335-370)
**Condition:** `enableKeyVault = true AND keyVaultOption = 'new'`

**Key Features (Lines 344-369):**
- Soft delete: 90 days (line 363)
- Purge protection: true (line 364)
- UAMI access policy: get, list secrets (lines 350-357)
- Network ACLs: conditional based on private endpoint (lines 365-368)

#### Resource 8: Key Vault Secret (Lines 371-386)
**Secret Name:** `tacitred-api-key`  
**Value:** `[parameters('tacitRedApiKey')]`  
**Content Type:** `TacitRed API Key for Sentinel Connector`

#### Resource 9: Private Endpoint (Lines 387-410)
**Condition:** `enableKeyVault AND enablePrivateEndpoint AND subnetId not empty`  
**Service Connection:** Key Vault vault group

#### Resource 10: Key Vault RBAC (Lines 411-426)
**Role:** Key Vault Secrets User (`4633458b-17de-408a-b874-0445c86b69e6`)  
**Assignee:** UAMI

#### Resource 11: Key Vault Diagnostics (Lines 427-451)
**Logs:** AuditEvent  
**Metrics:** AllMetrics  
**Destination:** Sentinel workspace

#### Resource 12: Deployment Script (Lines 452-512)
**Condition:** `false` (DISABLED)  
**Status:** ⚠️ DEPRECATED - CCF now deployed via ARM-native resources

**Historical Purpose:**
- Created connector definition via Azure CLI (lines 510-511 contain bash script)
- Configured connector instance
- Used managed identity for authentication

#### Resource 13: CCF Connector Definition (Lines 513-588)
**Type:** `dataConnectorDefinitions`  
**API:** `2024-09-01`  
**Name:** `TacitRedThreatIntel`  
**Kind:** `Customizable`

**Key Configuration (Lines 524-586):**
- Title: `TacitRed Compromised Credentials` (line 526)
- Graph queries table: `TacitRed_Findings_CL` (line 529)
- Sample query (lines 537-541)
- Data types: `TacitRed_Findings_CL` (line 545)
- Permissions: Workspace read/write (lines 559-571)

#### Resource 14: CCF Connector Instance (Lines 589-644)
**Type:** `dataConnectors`  
**API:** `2023-02-01-preview`  
**Name:** `TacitRedFindings`  
**Kind:** `RestApiPoller`

**Critical Configuration:**
| Lines | Property | Value |
|-------|----------|-------|
| 601 | connectorDefinitionName | TacitRedThreatIntel |
| 602 | dataType | TacitRed_Findings_CL |
| 604 | streamName | Custom-TacitRed_Findings_CL |
| 605-606 | DCE & DCR | Runtime references |
| 609-611 | auth | APIKey / Authorization header |
| 614 | apiEndpoint | https://app.tacitred.com/api/v1/findings |
| 615 | httpMethod | GET |
| 617 | page_size | 100 |
| 619 | queryWindowInMin | 60 |
| 620 | queryTimeFormat | yyyy-MM-ddTHH:mm:ssZ |
| 621-622 | Time parameters | from/until |
| 623 | rateLimitQps | 10 |
| 624 | retryCount | 3 |
| 625 | timeoutInSeconds | 60 |
| 632 | pagingType | LinkHeader |
| 637-639 | eventsJsonPaths | $.results |

#### Resource 15-20: Workbooks (Lines 645-734)
**6 Workbooks Total:**

| Lines | GUID Identifier | Display Name |
|-------|----------------|--------------|
| 645-659 | workbook-ti-command-center | Threat Intelligence Command Center |
| 660-674 | workbook-ti-command-center-enhanced | Threat Intelligence Command Center (Enhanced) |
| 675-689 | workbook-executive-risk-dashboard | Executive Risk Dashboard |
| 690-704 | workbook-executive-risk-dashboard-enhanced | Executive Risk Dashboard (Enhanced) |
| 705-719 | workbook-threat-hunters-arsenal | Threat Hunter's Arsenal |
| 720-734 | workbook-threat-hunters-arsenal-enhanced | Threat Hunter's Arsenal (Enhanced) |

**All Workbooks:**
- Condition: `deployWorkbooks = true`
- Category: sentinel
- sourceId: Workspace resource ID
- serializedData: JSON (KQL queries embedded)

#### Resource 21: Analytics Rule (Lines 735-807)
**Type:** `Microsoft.SecurityInsights/alertRules`  
**Kind:** `Scheduled`  
**Name:** `TacitRed - Repeat Compromise Detection`

**Configuration:**
| Lines | Property | Value |
|-------|----------|-------|
| 746 | displayName | TacitRed - Repeat Compromise Detection |
| 748 | severity | High |
| 749 | enabled | true |
| 750 | query | KQL (inline, ~15 lines) |
| 751 | queryFrequency | PT1H |
| 752 | queryPeriod | P7D |
| 753-754 | trigger | GreaterThan, 0 |
| 757-762 | tactics/techniques | CredentialAccess, T1110 |
| 763-776 | incidentConfiguration | Group by Account |
| 780-784 | alertDetailsOverride | Dynamic title/severity |
| 785-790 | customDetails | CompromiseCount, etc. |
| 791-805 | entityMappings | Account (Email, Username) |

**Detection Query (Line 750):**
```kql
let lookbackPeriod = 7d;
let threshold = 2;
TacitRed_Findings_CL
| where TimeGenerated >= ago(lookbackPeriod)
| extend Email = tostring(email_s), Username = tostring(username_s)
| summarize CompromiseCount = count() by Email, Username
| where CompromiseCount >= threshold
| extend Severity = case(CompromiseCount >= 5, 'Critical', CompromiseCount >= 3, 'High', 'Medium')
```

### Outputs Section (Lines 809-822)
| Lines | Output | Description |
|-------|--------|-------------|
| 810-813 | dceEndpoint | DCE ingestion URL |
| 814-817 | tacitRedDcrImmutableId | DCR immutable ID |
| 818-821 | deploymentMessage | Success message |

---

## FILE: createUiDefinition.json (243 lines)

### Header (Lines 1-5)
```json
{
  "$schema": "https://schema.management.azure.com/schemas/0.1.2-preview/CreateUIDefinition.MultiVm.json#",
  "handler": "Microsoft.Azure.CreateUIDef",
  "version": "0.1.2-preview"
}
```

### Config Section (Lines 6-35)
- **Description (Line 9):** TacitRed solution summary
- **Workspace validation (Lines 10-23):** Read permissions check
- **Resource providers (Lines 19-22):** Sentinel + Log Analytics

### Basics Step (Lines 36-59)
- **getLAWorkspace (Lines 38-46):** ARM API control to fetch workspaces
- **workspace dropdown (Lines 48-58):** Workspace selector

### Data Connectors Step (Lines 61-99)
| Lines | Control | Type | Purpose |
|-------|---------|------|---------|
| 67-72 | dataconnectors-text | TextBlock | Instructions |
| 74-90 | tacitRedApiKey | PasswordBox | API key input (UUID validation) |
| 92-97 | deployConnectors | CheckBox | Toggle connector deployment |

**API Key Validation (Line 83):**
```regex
^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$
```

### Analytics Step (Lines 100-120)
- **deployAnalytics checkbox (Lines 113-118):** Toggle analytics rule

### Security Step (Lines 121-204)
**Key Vault Configuration:**
| Lines | Control | Purpose |
|-------|---------|---------|
| 134-139 | enableKeyVault | Enable KV toggle |
| 147-165 | keyVaultOption | new/existing dropdown |
| 167-177 | keyVaultName | KV name input |
| 179-185 | keyVaultResourceGroup | Resource selector (existing KV) |
| 187-192 | enablePrivateEndpoint | Private endpoint toggle |
| 194-200 | subnetSelector | Subnet picker |

### Workbooks Step (Lines 205-225)
- **deployWorkbooks checkbox (Lines 218-223):** Toggle workbook deployment

### Outputs Section (Lines 227-240)
Maps UI inputs to ARM template parameters:
```json
{
  "workspace": "[basics('workspace')]",
  "tacitRedApiKey": "[steps('dataconnectors').tacitRedApiKey]",
  "deployConnectors": "[steps('dataconnectors').deployConnectors]",
  "enableKeyVault": "[steps('security').enableKeyVault]",
  ...
}
```

---

## FILE: packageMetadata.json (52 lines)

### Core Metadata (Lines 1-12)
```json
{
  "version": "1.0.0",
  "kind": "Solution",
  "contentSchemaVersion": "3.0.0",
  "contentId": "TacitRedCompromisedCredentials",
  "displayName": "TacitRed Compromised Credentials",
  "publisherDisplayName": "TacitRed"
}
```

### Description (Lines 9-10)
HTML description with solution components

### MITRE ATT&CK (Lines 13-14)
- **Tactics:** CredentialAccess, InitialAccess
- **Techniques:** T1110, T1078, T1589

### Categories (Lines 15-17)
- Identity
- Security - Threat Protection

### Support & Author (Lines 18-26)
- **Tier:** Partner
- **Contact:** support@tacitred.com

### Dependencies (Lines 31-50)
| Lines | Type | Content ID |
|-------|------|-----------|
| 34-38 | DataConnector | TacitRedThreatIntel |
| 39-43 | AnalyticsRule | TacitRedRepeatCompromise |
| 44-48 | Workbook | TacitRedCompromisedCredentials |

---

## KEY CODE PATTERNS

### Pattern 1: Conditional Resource Deployment
```json
{
  "condition": "[parameters('enableKeyVault')]",
  "type": "Microsoft.KeyVault/vaults",
  ...
}
```

### Pattern 2: ARM Template Dependencies
```json
{
  "dependsOn": [
    "[resourceId('Microsoft.Insights/dataCollectionEndpoints', variables('dceName'))]",
    "[resourceId('Microsoft.Insights/dataCollectionRules', variables('tacitRedDcrName'))]"
  ]
}
```

### Pattern 3: Reference() Function for Runtime Values
```json
"dataCollectionEndpoint": "[reference(resourceId('Microsoft.Insights/dataCollectionEndpoints', variables('dceName')), '2022-06-01', 'full').properties.logsIngestion.endpoint]"
```

### Pattern 4: Securestring Parameter Handling
```json
{
  "type": "securestring",
  "ApiKey": "[parameters('tacitRedApiKey')]"
}
```

### Pattern 5: GUID Generation for Unique Names
```json
"name": "[guid(resourceGroup().id, 'workbook-ti-command-center')]"
```

---

## CRITICAL LINE REFERENCES

### Most Important Lines:
- **Line 453:** Deployment script condition = `false` (script disabled)
- **Line 604:** DCR stream name = `Custom-TacitRed_Findings_CL`
- **Line 614:** TacitRed API endpoint
- **Line 619:** Polling interval = 60 minutes
- **Line 750:** Analytics rule KQL query (inline)
- **Line 83 (createUiDefinition):** API key UUID validation regex

---

## FILE INTERDEPENDENCIES

```
mainTemplate.json
  ↓ References
createUiDefinition.json (parameter mapping)
  ↓ Metadata
packageMetadata.json (Content Hub registration)
```

**Deployment Flow:**
1. User fills createUiDefinition.json wizard
2. Outputs mapped to mainTemplate.json parameters
3. ARM deploys all resources
4. packageMetadata.json used by Content Hub for catalog listing

---

**Status:** ✅ Complete code mapping for TacitRed CCF implementation

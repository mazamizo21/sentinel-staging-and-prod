# TacitRed CCF - Complete Architecture Analysis

**Generated:** 2025-11-14  
**Status:** Production-Ready Content Hub Solution

---

## 1. SOLUTION IDENTITY

- **Name:** TacitRed Compromised Credentials
- **Version:** 1.0.0
- **Type:** Microsoft Sentinel Content Hub Solution
- **Publisher:** TacitRed
- **Content ID:** `TacitRedCompromisedCredentials`
- **MITRE ATT&CK:** T1110, T1078, T1589

---

## 2. FILE STRUCTURE

```
Tacitred-CCF/
├── mainTemplate.json (824 lines) - Main ARM template with all resources
├── createUiDefinition.json (243 lines) - Portal deployment wizard
├── README.md (162 lines) - User documentation
├── DEPLOYMENT-SUMMARY.md (325 lines) - Technical guide
├── PACKAGE-COMPLETE.md (66 lines) - Package summary
└── Package/packageMetadata.json (52 lines) - Content Hub metadata
```

---

## 3. ARM TEMPLATE PARAMETERS

### Required
- `workspace` (string) - Sentinel workspace name
- `workspace-location` (string) - Azure region
- `tacitRedApiKey` (securestring) - TacitRed API key (UUID format)

### Optional
- `deployAnalytics` (bool, default: true) - Deploy analytics rule
- `deployWorkbooks` (bool, default: true) - Deploy 6 workbooks
- `deployConnectors` (bool, default: true) - Configure CCF connector
- `enableKeyVault` (bool, default: false) - Enable Key Vault
- `keyVaultOption` (string, default: "new") - new|existing
- `keyVaultName` (string) - Key Vault name
- `enablePrivateEndpoint` (bool, default: false) - Private endpoint for KV
- `subnetId` (string) - Subnet for private endpoint

---

## 4. INFRASTRUCTURE RESOURCES (14 Total)

### 4.1 Data Collection Endpoint (DCE)
- **Type:** `Microsoft.Insights/dataCollectionEndpoints`
- **Name:** `dce-threatintel-feeds`
- **API:** 2022-06-01
- **Purpose:** Ingestion endpoint for threat intel data
- **Output:** DCE URL (e.g., `https://dce-threatintel-feeds-1hsz.eastus-1.ingest.monitor.azure.com`)

### 4.2 Custom Table
- **Type:** `Microsoft.OperationalInsights/workspaces/tables`
- **Name:** `TacitRed_Findings_CL`
- **API:** 2023-09-01
- **Columns:** 16 (TimeGenerated, email_s, domain_s, confidence_d, etc.)

**Schema Mapping:**
| Column | Type | Description |
|--------|------|-------------|
| TimeGenerated | datetime | Auto-generated ingestion time |
| email_s | string | Compromised email |
| domain_s | string | Associated domain |
| findingType_s | string | Type of compromise |
| confidence_d | int | Confidence score (0-100) |
| firstSeen_t | datetime | First detection |
| lastSeen_t | datetime | Last detection |
| source_s | string | Intel source |
| severity_s | string | Severity level |

### 4.3 Data Collection Rule (DCR)
- **Type:** `Microsoft.Insights/dataCollectionRules`
- **Name:** `dcr-tacitred-findings`
- **API:** 2022-06-01
- **Stream:** `Custom-TacitRed_Findings_CL`
- **Transform KQL:** `source | extend TimeGenerated = now()`
- **Output:** DCR Immutable ID

**Key Point:** DCR removes `_s`, `_d`, `_t` suffixes from API data and adds them back when writing to table.

### 4.4 User-Assigned Managed Identity (UAMI)
- **Type:** `Microsoft.ManagedIdentity/userAssignedIdentities`
- **Name:** `uami-ccf-deployment`
- **API:** 2023-01-31
- **Purpose:** Execute connector operations

**Role Assignments (2x):**
1. Workspace-level Sentinel Contributor (role: `b24988ac-6180-42a0-ab88-20f7382dd24c`)
2. Resource Group-level Contributor (role: `b24988ac-6180-42a0-ab88-20f7382dd24c`)

### 4.5 Azure Key Vault (Optional)
- **Type:** `Microsoft.KeyVault/vaults`
- **Name:** `kv-tacitred-<uniqueString>`
- **Condition:** `enableKeyVault = true`
- **Features:**
  - Stores API key secret: `tacitred-api-key`
  - Soft delete: 90 days
  - Purge protection: Enabled
  - Diagnostic logging to Sentinel workspace
  - Optional private endpoint

**Related Resources:**
- Key Vault Secrets User role assignment to UAMI
- Private endpoint (if enabled)
- Diagnostic settings

---

## 5. CCF DATA CONNECTOR

### 5.1 Connector Definition
- **Type:** `Microsoft.OperationalInsights/workspaces/providers/dataConnectorDefinitions`
- **Name:** `TacitRedThreatIntel`
- **API:** 2024-09-01
- **Kind:** Customizable
- **Visibility:** Microsoft Sentinel Data Connectors blade

### 5.2 Connector Instance
- **Type:** `Microsoft.OperationalInsights/workspaces/providers/dataConnectors`
- **Name:** `TacitRedFindings`
- **API:** 2023-02-01-preview
- **Kind:** RestApiPoller

**Configuration:**
```json
{
  "connectorDefinitionName": "TacitRedThreatIntel",
  "dataType": "TacitRed_Findings_CL",
  "dcrConfig": {
    "streamName": "Custom-TacitRed_Findings_CL",
    "dataCollectionEndpoint": "[DCE URL]",
    "dataCollectionRuleImmutableId": "[DCR immutable ID]"
  },
  "auth": {
    "type": "APIKey",
    "ApiKeyName": "Authorization",
    "ApiKey": "[tacitRedApiKey]"
  },
  "request": {
    "apiEndpoint": "https://app.tacitred.com/api/v1/findings",
    "httpMethod": "GET",
    "queryParameters": {"page_size": 100},
    "queryWindowInMin": 60,
    "queryTimeFormat": "yyyy-MM-ddTHH:mm:ssZ",
    "startTimeAttributeName": "from",
    "endTimeAttributeName": "until",
    "rateLimitQps": 10,
    "retryCount": 3,
    "timeoutInSeconds": 60,
    "headers": {
      "Accept": "application/json",
      "User-Agent": "Microsoft-Sentinel-TacitRed/1.0"
    }
  },
  "paging": {
    "pagingType": "LinkHeader",
    "linkHeaderRelLinkName": "rel=next"
  },
  "response": {
    "eventsJsonPaths": ["$.results"],
    "format": "json"
  }
}
```

**Data Flow:**
1. Poll API every 60 minutes
2. Query last 60 minutes of data (`from` to `until`)
3. Parse `$.results` JSON array
4. Map to DCR stream (no suffixes)
5. Send to DCE
6. DCR transforms and adds TimeGenerated
7. Write to table (with suffixes)

**Field Mapping:**
- API: `"email": "user@example.com"` → Stream: `email` (string) → Table: `email_s` (string)
- API: `"confidence": 85` → Stream: `confidence` (int) → Table: `confidence_d` (int)
- API: `"firstSeen": "2025-11-14T10:00:00Z"` → Stream: `firstSeen` (datetime) → Table: `firstSeen_t` (datetime)

---

## 6. ANALYTICS RULE

**Name:** TacitRed - Repeat Compromise Detection  
**Type:** `Microsoft.SecurityInsights/alertRules` (Scheduled)  
**API:** 2023-02-01  
**Condition:** `deployAnalytics = true`

**Configuration:**
- **Severity:** High
- **Frequency:** Hourly (PT1H)
- **Lookback:** 7 days (P7D)
- **Threshold:** 2+ compromises per user
- **MITRE ATT&CK:** T1110 (Brute Force)
- **Tactic:** CredentialAccess

**Detection Query:**
```kql
let lookbackPeriod = 7d;
let threshold = 2;
TacitRed_Findings_CL
| where TimeGenerated >= ago(lookbackPeriod)
| extend Email = tostring(email_s), Username = tostring(username_s)
| summarize 
    CompromiseCount = count(), 
    FirstCompromise = min(firstSeen_t), 
    LatestCompromise = max(lastSeen_t)
  by Email, Username
| where CompromiseCount >= threshold
| extend Severity = case(
    CompromiseCount >= 5, 'Critical',
    CompromiseCount >= 3, 'High',
    'Medium'
  )
```

**Alert Details:**
- **Title:** `Repeat Compromise: {{Email}} ({{CompromiseCount}}x)`
- **Dynamic Severity:** Critical (≥5), High (≥3), Medium (2)

**Entity Mapping:**
- Account.FullName → Email
- Account.Name → Username

**Incident Grouping:**
- Group by: Account entity
- Lookback: 7 days
- Method: AlertPerResult

---

## 7. WORKBOOKS (6 Total)

### 7.1 Threat Intelligence Command Center
**Features:**
- Real-time threat score timeline
- Threat velocity & acceleration
- Statistical analysis

### 7.2 Threat Intelligence Command Center (Enhanced)
Extended version with additional metrics

### 7.3 Executive Risk Dashboard
**Business Metrics:**
- Overall risk level
- Total threats (7d, 30d)
- Active threats (last 48h)
- Trend analysis

### 7.4 Executive Risk Dashboard (Enhanced)
Extended executive reporting

### 7.5 Threat Hunter's Arsenal
**Advanced Hunting:**
- Rapid credential reuse detection
- Persistent infrastructure identification
- Attack chain reconstruction
- MITRE ATT&CK mapping

### 7.6 Threat Hunter's Arsenal (Enhanced)
Extended hunting capabilities

**All workbooks:**
- Query `TacitRed_Findings_CL` exclusively
- Originally included Cyren cross-feed queries (now removed)
- Time range parameters (1h, 24h, 7d, 30d)

---

## 8. DEPLOYMENT FLOW

```
1. DCE → 2. Custom Table → 3. DCR → 4. UAMI → 5. RBAC
   ↓
6. [Optional] Key Vault + Secret + Diagnostics + Private Endpoint
   ↓
7. CCF Connector Definition → 8. CCF Connector Instance
   ↓
9. [Optional] Analytics Rule → 10. [Optional] 6x Workbooks
   ↓
11. Outputs (DCE URL, DCR ID, Message)
```

**Duration:** 2-3 minutes average  
**Critical Path:** DCE → DCR → Connector

---

## 9. DATA FLOW ARCHITECTURE

```
┌────────────────────────────────────────────────────┐
│  TacitRed API (app.tacitred.com/api/v1/findings)  │
└────────────────────────────────────────────────────┘
                     ↓ (HTTPS GET, every 60 min)
┌────────────────────────────────────────────────────┐
│  CCF Connector (RestApiPoller)                     │
│  - Auth: Bearer token                              │
│  - Pagination: Link header                         │
│  - Parse: $.results array                          │
└────────────────────────────────────────────────────┘
                     ↓ (JSON payload, no suffixes)
┌────────────────────────────────────────────────────┐
│  Data Collection Endpoint (DCE)                    │
│  dce-threatintel-feeds                             │
└────────────────────────────────────────────────────┘
                     ↓
┌────────────────────────────────────────────────────┐
│  Data Collection Rule (DCR)                        │
│  Stream: Custom-TacitRed_Findings_CL               │
│  Transform: source | extend TimeGenerated = now()  │
└────────────────────────────────────────────────────┘
                     ↓ (adds suffixes)
┌────────────────────────────────────────────────────┐
│  Log Analytics Custom Table                        │
│  TacitRed_Findings_CL                              │
│  (email_s, confidence_d, firstSeen_t, etc.)        │
└────────────────────────────────────────────────────┘
                     ↓
┌────────────────────────────────────────────────────┐
│  Microsoft Sentinel                                │
│  ├─ Analytics Rule (Repeat Compromise)            │
│  ├─ Workbooks (6x visualization)                   │
│  └─ Incidents (grouped by Account)                 │
└────────────────────────────────────────────────────┘
```

---

## 10. KEY VAULT INTEGRATION (Optional)

**When Enabled:**
1. API key stored as secret: `tacitred-api-key`
2. UAMI granted Key Vault Secrets User role
3. Audit logs sent to Sentinel workspace
4. Optional private endpoint for network isolation

**Security Features:**
- Soft delete: 90 days
- Purge protection: Enabled
- Access policy: UAMI read-only (get, list secrets)
- Network ACLs: Public access or deny (if private endpoint)

---

## 11. POST-DEPLOYMENT VERIFICATION

### Check Connector Status
```kql
TacitRed_Findings_CL
| where TimeGenerated > ago(24h)
| summarize Count = count(), Latest = max(TimeGenerated)
```

### Validate Data Quality
```kql
TacitRed_Findings_CL
| summarize 
    TotalFindings = count(),
    UniqueEmails = dcount(email_s),
    UniqueDomains = dcount(domain_s),
    AvgConfidence = avg(confidence_d)
```

### Check Analytics Rule
```kql
SecurityIncident
| where TimeGenerated > ago(7d)
| where Title contains "Repeat Compromise"
| project TimeGenerated, Title, Severity, Status
```

---

## 12. IMPORTANT NOTES

### Deployment Script Deprecated
The `deploymentScripts` resource is **disabled** (`condition: false`). Modern approach uses ARM-native CCF resources directly.

### Workbook Refactoring
All 6 workbooks originally had cross-feed queries combining Cyren and TacitRed. **All Cyren references removed**—now TacitRed-only.

### Polling Behavior
- **First poll:** 0-60 minutes after deployment
- **Subsequent polls:** Every 60 minutes
- **Expected latency:** 60-120 minutes for first data

### Schema Suffix Convention
- `_s` = string
- `_d` = numeric (int/double)
- `_t` = datetime
- `_CL` = Custom Log table

---

## 13. SUPPORT & DOCUMENTATION

- **TacitRed Support:** support@tacitred.com
- **Documentation:** https://www.tacitred.com/docs
- **Sentinel Docs:** https://docs.microsoft.com/azure/sentinel
- **CCF Docs:** https://docs.microsoft.com/azure/sentinel/create-codeless-connector

---

**Status:** ✅ Production-Ready for Microsoft Sentinel Content Hub

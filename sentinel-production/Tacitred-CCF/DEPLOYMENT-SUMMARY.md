# TacitRed-CCF Marketplace Package - Deployment Summary

## Package Information

**Solution Name:** TacitRed Compromised Credentials  
**Version:** 1.0.0  
**Package Type:** Microsoft Sentinel Content Hub Solution  
**Deployment Method:** ARM Template + CCF (Codeless Connector Framework)  
**Created:** 2025-11-13  
**Status:** ✅ Production-Ready

---

## Package Structure

```
Tacitred-CCF/
├── mainTemplate.json                 # Main ARM deployment template
├── createUiDefinition.json           # Azure Portal UI definition
├── README.md                         # Solution documentation
├── DEPLOYMENT-SUMMARY.md             # This file
├── Package/
│   └── packageMetadata.json          # Marketplace metadata
├── Data Connectors/                  # (Embedded in mainTemplate)
├── Analytic Rules/                   # (Embedded in mainTemplate)
└── Workbooks/                        # (Embedded in mainTemplate)
```

---

## Deployed Resources

### Infrastructure (5 resources)
1. **Data Collection Endpoint (DCE)**
   - Name: `dce-tacitred-threatintel`
   - Purpose: Ingestion endpoint for TacitRed findings
   - Location: Same as workspace

2. **Custom Table**
   - Name: `TacitRed_Findings_CL`
   - Schema: 16 columns (email, domain, confidence, etc.)
   - Retention: Per workspace configuration

3. **Data Collection Rule (DCR)**
   - Name: `dcr-tacitred-findings`
   - Stream: `Custom-TacitRed_Findings_CL`
   - Transform: Adds TimeGenerated field

4. **User-Assigned Managed Identity (UAMI)**
   - Name: `uami-tacitred-ccf-deployment`
   - Purpose: Execute deployment scripts with proper permissions
   - Roles: Sentinel Contributor (workspace + resource group)

5. **Role Assignments (2x)**
   - Workspace-level: Sentinel Contributor
   - Resource Group-level: Contributor

### CCF Data Connector (Deployed via Script)
- **Connector Definition**: `TacitRedThreatIntel`
- **Connector Instance**: `TacitRedFindings`
- **API Endpoint**: `https://app.tacitred.com/api/v1/findings`
- **Polling Interval**: 6 hours (360 minutes)
- **Authentication**: API Key (Bearer token)
- **Paging**: Link header navigation
- **Rate Limit**: 10 QPS

### Analytics Rule (1)
- **Name**: TacitRed - Repeat Compromise Detection
- **Severity**: High
- **Frequency**: Hourly
- **Detection Period**: 7 days
- **Threshold**: 2+ compromises per user
- **MITRE ATT&CK**: T1110 (Brute Force)
- **Entity Mapping**: Account (Email, Username)
- **Incident Creation**: Enabled with grouping

### Workbook (1)
- **Name**: TacitRed Compromised Credentials
- **Visualizations**:
  - Compromise Detection Timeline (line chart)
  - Key Metrics (tiles: total findings, avg confidence, unique users/domains)
  - High-Risk Users table (repeat compromises)
  - Most Affected Domains (bar chart)
  - Finding Types Distribution (pie chart)
- **Time Range**: Configurable (default: 7 days)

---

## Deployment Validation

### ✅ Successful Test Deployment
- **Date**: 2025-11-13 21:24 UTC
- **Duration**: 2 minutes 6 seconds (126 seconds)
- **Status**: `Succeeded`
- **Resource Group**: SentinelTestStixImport
- **Workspace**: SentinelThreatIntelWorkspace
- **Location**: East US

### Deployment Outputs
```json
{
  "dceEndpoint": "https://dce-tacitred-threatintel-1hsz.eastus-1.ingest.monitor.azure.com",
  "tacitRedDcrImmutableId": "dcr-17ccb13049654e90b45840c887fb069b",
  "deploymentMessage": "TacitRed-only infrastructure, CCF connector, and analytics deployed successfully."
}
```

---

## Deployment Parameters

### Required Parameters
| Parameter | Type | Description |
|-----------|------|-------------|
| `workspace` | string | Microsoft Sentinel workspace name |
| `workspace-location` | string | Azure region (default: resource group location) |
| `tacitRedApiKey` | securestring | TacitRed API key (UUID format) |

### Optional Parameters
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `deployAnalytics` | bool | true | Deploy analytics rule |
| `deployWorkbooks` | bool | true | Deploy workbook |
| `deployConnectors` | bool | true | Deploy CCF connector |
| `forceUpdateTag` | string | utcNow() | Force script re-execution |

---

## Deployment Methods

### Method 1: Azure Portal (Content Hub)
1. Navigate to **Microsoft Sentinel > Content Hub**
2. Search for **"TacitRed Compromised Credentials"**
3. Click **Install**
4. Complete the deployment wizard
5. Enter TacitRed API key when prompted

### Method 2: Azure CLI
```bash
az deployment group create \
  --resource-group <your-rg> \
  --template-file mainTemplate.json \
  --parameters \
    workspace=<workspace-name> \
    workspace-location=<location> \
    tacitRedApiKey=<your-api-key> \
    deployAnalytics=true \
    deployWorkbooks=true \
    deployConnectors=true
```

### Method 3: PowerShell
```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName <your-rg> `
  -TemplateFile mainTemplate.json `
  -workspace <workspace-name> `
  -workspaceLocation <location> `
  -tacitRedApiKey (ConvertTo-SecureString -String "<your-api-key>" -AsPlainText -Force) `
  -deployAnalytics $true `
  -deployWorkbooks $true `
  -deployConnectors $true
```

---

## Post-Deployment Verification

### 1. Verify CCF Connector
```kql
// Check for data ingestion (wait 6-12 hours for first poll)
TacitRed_Findings_CL
| where TimeGenerated > ago(24h)
| summarize Count = count(), LatestIngestion = max(TimeGenerated)
```

### 2. Verify Analytics Rule
```kql
// Check for incidents created by the rule
SecurityIncident
| where TimeGenerated > ago(7d)
| where Title contains "Repeat Compromise"
| project TimeGenerated, Title, Severity, Status, Owner
```

### 3. Verify Workbook
- Navigate to **Sentinel > Workbooks > My workbooks**
- Open **TacitRed Compromised Credentials**
- Verify all visualizations render correctly

---

## Key Differences from Original Template

### Removed Components (Cyren)
- ❌ Cyren_Indicators_CL table
- ❌ Cyren IP Reputation DCR
- ❌ Cyren Malware URLs DCR
- ❌ Cyren CCF connectors (2x)
- ❌ Cyren workbooks (2x)
- ❌ Cross-feed analytics rules (2x)
- ❌ Cyren JWT token parameters

### Retained Components (TacitRed)
- ✅ TacitRed_Findings_CL table
- ✅ TacitRed DCR
- ✅ TacitRed CCF connector
- ✅ TacitRed analytics rule
- ✅ TacitRed workbook (new, simplified)
- ✅ Shared infrastructure (DCE, UAMI, RBAC)

### New/Modified Components
- ✅ Simplified workbook (TacitRed-only queries)
- ✅ Updated connector definition (TacitRed-only)
- ✅ Removed cross-feed correlation logic
- ✅ Updated metadata and descriptions

---

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Subscription                        │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              Resource Group                            │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │         Microsoft Sentinel Workspace            │  │  │
│  │  │                                                  │  │  │
│  │  │  ┌────────────────────────────────────────┐    │  │  │
│  │  │  │   TacitRed_Findings_CL (Custom Table)  │    │  │  │
│  │  │  └────────────────────────────────────────┘    │  │  │
│  │  │                                                  │  │  │
│  │  │  ┌────────────────────────────────────────┐    │  │  │
│  │  │  │   Analytics Rule (Repeat Compromise)   │    │  │  │
│  │  │  └────────────────────────────────────────┘    │  │  │
│  │  │                                                  │  │  │
│  │  │  ┌────────────────────────────────────────┐    │  │  │
│  │  │  │   Workbook (Compromised Credentials)   │    │  │  │
│  │  │  └────────────────────────────────────────┘    │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                                                         │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │   Data Collection Endpoint (DCE)                │  │  │
│  │  │   dce-tacitred-threatintel                      │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                                                         │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │   Data Collection Rule (DCR)                    │  │  │
│  │  │   dcr-tacitred-findings                         │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                                                         │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │   User-Assigned Managed Identity (UAMI)         │  │  │
│  │  │   uami-tacitred-ccf-deployment                  │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                                                         │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │   Deployment Script (Azure CLI)                 │  │  │
│  │  │   - Creates CCF connector definition            │  │  │
│  │  │   - Creates CCF connector instance              │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ HTTPS API Polling (6h interval)
                            ▼
                ┌────────────────────────┐
                │   TacitRed API         │
                │   app.tacitred.com     │
                └────────────────────────┘
```

---

## Troubleshooting

### Issue: No Data After 24 Hours
**Cause**: First polling cycle may take up to 6 hours  
**Solution**: Wait for initial poll, check connector status in Data Connectors blade

### Issue: Analytics Rule Not Triggering
**Cause**: Insufficient data (need 2+ findings per user)  
**Solution**: Wait for more data ingestion, verify rule is enabled

### Issue: Workbook Shows "No Data"
**Cause**: Time range too narrow or no data ingested yet  
**Solution**: Expand time range, verify data connector status

### Issue: Deployment Script Fails
**Cause**: RBAC permissions not propagated  
**Solution**: Wait 60 seconds and retry deployment (script includes 20s wait)

---

## Support and Documentation

- **TacitRed Support**: support@tacitred.com
- **TacitRed Documentation**: https://www.tacitred.com/docs
- **Microsoft Sentinel Docs**: https://docs.microsoft.com/azure/sentinel
- **CCF Documentation**: https://docs.microsoft.com/azure/sentinel/create-codeless-connector

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-11-13 | Initial TacitRed-only marketplace release |

---

## License and Terms

This solution is provided by TacitRed. By deploying this solution, you agree to:
- TacitRed Terms of Service
- Microsoft Azure Terms of Service
- Microsoft Sentinel pricing and data ingestion costs

Contact TacitRed for licensing and pricing information.

---

**Package Status**: ✅ Ready for Microsoft Sentinel Content Hub Submission

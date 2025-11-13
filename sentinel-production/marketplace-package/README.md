# Threat Intelligence Feeds for Microsoft Sentinel

## Overview

Deploy threat intelligence connectors for TacitRed and Cyren to Microsoft Sentinel using the Codeless Connector Framework (CCF). This solution provides automated ingestion of:

- **TacitRed:** Compromised credentials and domain findings
- **Cyren IP Reputation:** Malicious IP address indicators
- **Cyren Malware URLs:** Malicious URL and file hash indicators

## What's Deployed

### Data Connectors (CCF)
- **TacitRedFindings:** Polls TacitRed API every 6 hours for compromised credentials
- **CyrenIPReputation:** Polls Cyren API for IP reputation indicators
- **CyrenMalwareURLs:** Polls Cyren API for malware URL indicators

### Analytics Rules (3)
1. **Repeat Compromise Detection** - Identifies users compromised multiple times
2. **Malware Infrastructure Detection** - Correlates Tacit Red findings with Cyren malware indicators
3. **Cross-Feed Correlation** - Detects compromised users accessing malicious infrastructure

### Workbooks (4)
1. **Threat Intelligence Command Center** - Central monitoring dashboard
2. **Executive Risk Dashboard** - High-level risk metrics
3. **Threat Hunter Arsenal** - Investigation tools
4. **Cyren Threat Intelligence** - Cyren-specific visualizations

### Infrastructure
- 1 Data Collection Endpoint (DCE)
- 3 Data Collection Rules (DCRs) with KQL transformations
- 2 Custom Log Tables

## Prerequisites

✅ **Microsoft Sentinel workspace** - Must exist before deployment
✅ **TacitRed API Key** - Obtain from TacitRed admin console
✅ **Cyren JWT Tokens (2)** - Obtain from Cyren portal:
   - IP Reputation feed token
   - Malware URLs feed token

## Deployment

### From Azure Marketplace

1. Click "Get It Now" on the marketplace listing
2. Select your Azure subscription and resource group
3. Select your Microsoft Sentinel workspace
4. Enter API credentials (stored securely)
5. Configure polling frequency (default: 6 hours)
6. Review and deploy

**Deployment Time:** ~10 minutes

### Using Deploy Button

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2F<your-repo>%2Fmain%2Fmarketplace-package%2FmainTemplate.json)

## Post-Deployment

### Verify Connectors

1. Navigate to **Microsoft Sentinel** → **Configuration** → **Data connectors**
2. Search for **"Threat Intelligence Feeds"**
3. Verify status shows **"Connected"**
4. Check "Last log received" shows recent timestamp

### Validate Data Ingestion

Run this KQL query to confirm data is flowing:

```kql
union TacitRed_Findings_CL, Cyren_Indicators_CL
| summarize Count = count(), Latest = max(TimeGenerated) by Type
```

**Expected:** Data appears within 30 minutes of first poll

### Enable Analytics Rules

1. Navigate to **Microsoft Sentinel** → **Analytics**
2. Verify 3 rules are enabled:
   - TacitRed - Repeat Compromise Detection
   - Malware Infrastructure Detection
   - Cross-Feed Correlation

### View Workbooks

1. Navigate to **Microsoft Sentinel** → **Workbooks**
2. Open **Threat Intelligence Command Center**
3. Explore visualizations and metrics

## Architecture

```
External APIs (TacitRed, Cyren)
    ↓
CCF Data Connectors (Automated Polling)
    ↓
Data Collection Endpoint (DCE)
    ↓
Data Collection Rules (DCRs with KQL transforms)
    ↓
Log Analytics Custom Tables
    ↓
Analytics Rules + Workbooks
```

## Data Tables

### TacitRed_Findings_CL
Contains compromised credential findings from TacitRed:
- Email addresses
- Domains
- Finding types (compromised_credential, domain_takeover, etc.)
- Confidence scores
- First/last seen timestamps

### Cyren_Indicators_CL
Contains threat indicators from Cyren:
- IP addresses
- URLs
- File hashes
- Domains
- Risk scores and categories

## Polling Schedule

**Default:** Every 6 hours  
**Configurable:** 1, 6, 12, or 24 hours

Each connector polls independently:
- **TacitRed:** Retrieves findings from last 6 hours
- **Cyren IP:** Retrieves latest IP reputation indicators
- **Cyren Malware:** Retrieves latest malware URL indicators

## Cost Estimate

| Component | Monthly Cost* |
|-----------|--------------|
| Data ingestion (~5GB) | ~$12.50 |
| Data retention (90 days) | ~$5.00 |
| Analytics compute | ~$2.00 |
| **Total** | **~$19.50/month** |

*Based on standard Log Analytics pricing. Actual costs vary by data volume.

## Security

### Credential Storage
- API keys and JWT tokens are stored as **securestring** parameters
- Never logged or written to disk
- Encrypted at rest in Azure Key Vault (if configured)

### Network Security
- All API calls use HTTPS/TLS 1.2+
- Data Collection Endpoint supports private endpoints
- Can be deployed with network isolation

### Access Control
- Requires **Microsoft Sentinel Contributor** role for deployment
- Connectors run with system-assigned managed identity
- RBAC controls for workbook and analytics access

## Troubleshooting

### No Data Appearing

**Check connector status:**
```kql
// Verify connectors exist
az sentinel data-connector list -g <rg> -w <workspace>
```

**Check for errors:**
- Navigate to connector → Configuration
- Verify API credentials are correct
- Check "Last connection" timestamp

### Connector Shows "Disconnected"

**Solution:**
1. Re-enter API credentials in connector configuration
2. Verify API keys/tokens are still valid
3. Check API endpoint accessibility from Azure

### Analytics Rules Not Triggering

**Verify data exists:**
```kql
TacitRed_Findings_CL
| where TimeGenerated > ago(24h)
| count
```

**Check rule configuration:**
- Ensure rule is **Enabled**
- Verify query frequency matches data arrival

## Support

- **Documentation:** [Link to docs]
- **Issues:** [Link to GitHub issues]
- **Community:** [Link to community forum]

## License

[Specify license - MIT, Apache 2.0, etc.]

## Contributing

[Contribution guidelines if applicable]

---

**Version:** 1.0.0  
**Last Updated:** November 2025  
**Publisher:** [Your organization]

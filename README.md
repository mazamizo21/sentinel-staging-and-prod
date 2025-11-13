# Sentinel Threat Intelligence - Staging and Production

Complete Azure Sentinel Threat Intelligence deployment with automated setup for TacitRed and Cyren feeds.

## Repository Structure

```
├── sentinel-staging/       # Development and testing environment
│   ├── DEPLOY-COMPLETE.ps1
│   ├── client-config-COMPLETE.json
│   ├── infrastructure/
│   ├── analytics/
│   └── workbooks/
│
└── sentinel-production/    # Production-ready deployment
    ├── DEPLOY-COMPLETE.ps1
    ├── client-config-COMPLETE.json
    ├── infrastructure/
    ├── analytics/
    └── workbooks/
```

## Quick Start - Production Deployment

### Prerequisites
- Azure CLI installed (`az login` authenticated)
- PowerShell 5.1 or later
- Contributor access to Azure subscription
- Valid API credentials:
  - TacitRed API Key
  - Cyren JWT Tokens (IP Reputation & Malware URLs)

### Deployment Steps

1. **Navigate to production folder:**
   ```powershell
   cd sentinel-production
   ```

2. **Update configuration:**
   ```powershell
   notepad client-config-COMPLETE.json
   ```
   Update:
   - `subscriptionId`
   - `resourceGroupName`
   - `workspaceName`
   - `tacitRed.apiKey`
   - `cyren.ipReputation.jwtToken`
   - `cyren.malwareUrls.jwtToken`

3. **Run deployment:**
   ```powershell
   .\DEPLOY-COMPLETE.ps1
   ```

4. **Validate (wait 30-60 minutes for RBAC propagation):**
   ```powershell
   .\VALIDATE-DEPLOYMENT.ps1
   ```

## What Gets Deployed

### Infrastructure (Phase 2)
- ✅ Data Collection Endpoint (DCE)
- ✅ 3 Data Collection Rules (DCRs):
  - TacitRed Findings
  - Cyren IP Reputation
  - Cyren Malware URLs
- ✅ 2 Custom Log Analytics Tables
- ✅ 3 Logic Apps with Managed Identities

### RBAC (Phase 3)
- ✅ Automatic role assignments
- ✅ Monitoring Metrics Publisher role on DCR + DCE

### Analytics (Phase 4)
- ✅ 6 Detection Rules:
  - TacitRed - Repeat Compromise Detection
  - TacitRed - High-Risk User Compromised
  - TacitRed - Active Compromised Account
  - Cyren + TacitRed - Malware Infrastructure
  - TacitRed + Cyren - Cross-Feed Correlation
  - TacitRed - Department Compromise Cluster

### Workbooks (Phase 5)
- ✅ 8 Interactive Dashboards:
  - Threat Intelligence Command Center (Standard + Enhanced)
  - Executive Risk Dashboard (Standard + Enhanced)
  - Threat Hunter's Arsenal (Standard + Enhanced)
  - Cyren Threat Intelligence (Standard + Enhanced)

## Key Features

### Automated Deployment
- ⚡ One-click deployment via `DEPLOY-COMPLETE.ps1`
- 🔄 Automatic resource dependency handling
- 🛡️ Built-in RBAC configuration
- 📊 Full logging and diagnostics

### Data Ingestion
- 🔁 Automated polling from TacitRed and Cyren APIs
- 🔄 Hourly refresh for TacitRed (configurable)
- 🔄 6-hour refresh for Cyren feeds (configurable)
- 🎯 Direct ingestion to Log Analytics via DCR/DCE

### Security Best Practices
- 🔐 Managed Identity authentication
- 🔒 No hardcoded credentials in Logic Apps
- 🔑 API keys stored in parameters only
- 🚀 Least-privilege RBAC assignments

## Staging vs Production

### Staging Folder
- Contains all development files and scripts
- Includes testing utilities, debug scripts, and historical logs
- Use for development, testing, and troubleshooting

### Production Folder
- **Clean, minimal, production-ready deployment**
- Contains only essential deployment files
- No development artifacts, debug scripts, or old logs
- **Recommended for production deployments**

## Deployment Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| Deployment | 5-10 min | Deploys all resources |
| RBAC Propagation | 30-60 min | Azure RBAC permissions propagate |
| First Data Ingestion | 1-6 hours | Logic Apps start collecting data |
| Analytics Activation | 24 hours | Detection rules begin triggering |

## Troubleshooting

### Logic Apps Show 403 Errors
- **Expected** during first 30-60 minutes (RBAC propagation)
- Wait and re-run validation: `.\VALIDATE-DEPLOYMENT.ps1`

### No Data in Tables
- Check Logic App run history in Azure Portal
- Verify API credentials in `client-config-COMPLETE.json`
- Ensure external APIs are accessible

### Analytics Rules Not Triggering
- Rules require 24+ hours of historical data
- Check that data is ingesting to tables:
  ```kql
  TacitRed_Findings_CL | take 10
  Cyren_Indicators_CL | take 10
  ```

## Documentation

- **Production:** `sentinel-production/README.md`
- **Deployment Guide:** `sentinel-production/README-DEPLOYMENT.md`
- **Staging:** `sentinel-staging/README-DEPLOYMENT.md`

## Support & Updates

### File Locations
- Deployment logs: `sentinel-production/docs/deployment-logs/`
- Configuration: `sentinel-production/client-config-COMPLETE.json`

### Key Scripts
- Main deployment: `DEPLOY-COMPLETE.ps1`
- Validation: `VALIDATE-DEPLOYMENT.ps1`

## Version

- **Version:** 1.0.0
- **Last Updated:** November 2025
- **Compatibility:** Azure Sentinel / Microsoft Sentinel

---

## ⚠️ Important Security Notes

1. **Never commit actual API keys to Git** - Update config locally only
2. **Review .gitignore** before committing sensitive files
3. **Use Azure Key Vault** for production API key management (recommended)
4. **Rotate API keys** regularly per your security policy

---

**Ready to Deploy?** Navigate to `sentinel-production` and run `DEPLOY-COMPLETE.ps1`

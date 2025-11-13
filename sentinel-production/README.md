# Sentinel Threat Intelligence - Production Deployment

This is the **production-ready** copy of the Sentinel Threat Intelligence deployment.

## What's Included

All files necessary for a complete deployment:

### Core Files (4)
- ✅ DEPLOY-COMPLETE.ps1 - Main deployment script
- ✅ client-config-COMPLETE.json - Configuration file
- ✅ VALIDATE-DEPLOYMENT.ps1 - Post-deployment validation
- ✅ README-DEPLOYMENT.md - Deployment guide

### Infrastructure Files (12)
- ✅ 3 DCR Bicep templates (Cyren IP, Cyren Malware, TacitRed)
- ✅ 3 Logic App Bicep templates (Cyren IP, Cyren Malware, TacitRed)
- ✅ 2 KQL transformation files
- ✅ 4 Logic App templates (backward compatibility)

### Analytics Files (1 + rules)
- ✅ analytics-rules.bicep - Main analytics deployment
- ✅ All KQL rule files in analytics\rules\

### Workbooks Files (8)
- ✅ Threat Intelligence Command Center (2 versions)
- ✅ Executive Risk Dashboard (2 versions)
- ✅ Threat Hunter's Arsenal (2 versions)
- ✅ Cyren Threat Intelligence (2 versions)

## Quick Start

1. **Review Configuration**
   ```powershell
   notepad .\client-config-COMPLETE.json
   ```

2. **Run Deployment**
   ```powershell
   .\DEPLOY-COMPLETE.ps1
   ```

3. **Validate Deployment** (after 30-60 minutes)
   ```powershell
   .\VALIDATE-DEPLOYMENT.ps1
   ```

## Prerequisites

- Azure CLI installed and authenticated
- PowerShell 5.1 or later
- Contributor access to Azure subscription
- Valid API keys for TacitRed and Cyren

## Configuration

Edit client-config-COMPLETE.json to update:
- Azure subscription ID, resource group, workspace name
- TacitRed API key
- Cyren JWT tokens
- Workbook enable/disable flags

## Support

For issues or questions, refer to:
- README-DEPLOYMENT.md for detailed deployment guide
- docs/ folder for troubleshooting logs

---
**Version:** 1.0.0
**Created:** 2025-11-12 20:04:12
**Source:** Sentinel-Full-deployment-production/sentinel-staging

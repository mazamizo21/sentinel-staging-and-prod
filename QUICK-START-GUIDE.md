# Quick Start Guide - Sentinel Threat Intelligence

## ✅ Everything is Ready!

Your Sentinel deployment has been successfully created, tested, and published to GitHub.

---

## 📦 What You Have

### 1. GitHub Repository
**URL:** https://github.com/mazamizo21/sentinel-staging-and-prod

**Contains:**
- ✅ `sentinel-staging/` - Full development environment with all scripts and logs
- ✅ `sentinel-production/` - Clean, production-ready deployment
- ✅ Complete documentation and deployment guides

### 2. Production Folder (Local)
**Path:** `d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production`

**Validated:** ✅ Deployment tested successfully (15.4 minutes, all components working)

---

## 🚀 Deploy to Any Environment

### Option 1: From Local Production Folder

```powershell
cd d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production

# 1. Update configuration
notepad client-config-COMPLETE.json

# 2. Run deployment
.\DEPLOY-COMPLETE.ps1

# 3. Wait 30-60 minutes for RBAC propagation, then validate
.\VALIDATE-DEPLOYMENT.ps1
```

### Option 2: Clone from GitHub

```powershell
# Clone repository
git clone https://github.com/mazamizo21/sentinel-staging-and-prod.git
cd sentinel-staging-and-prod/sentinel-production

# Update configuration
notepad client-config-COMPLETE.json

# Deploy
.\DEPLOY-COMPLETE.ps1

# Validate (after 30-60 min)
.\VALIDATE-DEPLOYMENT.ps1
```

---

## 📋 Configuration Checklist

Before deploying, update `client-config-COMPLETE.json`:

| Field | Example | Your Value |
|-------|---------|------------|
| **subscriptionId** | `774bee0e-...` | Update for target subscription |
| **resourceGroupName** | `SentinelTestStixImport` | Update for target RG |
| **workspaceName** | `SentinelThreatIntelWorkspace` | Update for target workspace |
| **location** | `eastus` | Update for target region |
| **TacitRed API Key** | `a2be534e-...` | Keep or update |
| **Cyren IP JWT** | `eyJ0eXAi...` | Keep or update |
| **Cyren Malware JWT** | `eyJ0eXAi...` | Keep or update |

---

## 📊 What Gets Deployed

### Infrastructure (5-10 minutes)
1. ✅ **DCE** - Data Collection Endpoint
2. ✅ **3 DCRs** - Data Collection Rules (TacitRed, Cyren IP, Cyren Malware)
3. ✅ **2 Tables** - Custom Log Analytics tables with full schemas
4. ✅ **3 Logic Apps** - Automated data ingestion with managed identities
5. ✅ **RBAC** - Monitoring Metrics Publisher roles assigned

### Analytics & Workbooks (2-5 minutes)
6. ✅ **6 Analytics Rules** - Threat detection rules
7. ✅ **6 Workbooks** - Interactive dashboards

**Total Time:** ~15 minutes

---

## 🧪 Validation

### Immediate Validation (Right After Deployment)
```powershell
# Check if resources exist
az monitor data-collection rule list -g <ResourceGroup> -o table
az logic workflow list -g <ResourceGroup> -o table
```

### Full Validation (After 30-60 min)
```powershell
# Run comprehensive validation
.\VALIDATE-DEPLOYMENT.ps1
```

### Check Data Ingestion
```kql
// In Log Analytics workspace
TacitRed_Findings_CL | take 10
Cyren_Indicators_CL | take 10
```

---

## 📁 Repository Structure

```
sentinel-staging-and-prod/
├── README.md                           # Main documentation
├── DEPLOYMENT-SUCCESS-REPORT.md        # Detailed success report
├── QUICK-START-GUIDE.md                # This guide
│
├── sentinel-staging/                   # Full development environment
│   ├── DEPLOY-COMPLETE.ps1
│   ├── All development scripts
│   ├── Historical logs
│   └── Debug utilities
│
└── sentinel-production/                # Production-ready (RECOMMENDED)
    ├── DEPLOY-COMPLETE.ps1             # Main deployment script
    ├── VALIDATE-DEPLOYMENT.ps1         # Validation script
    ├── client-config-COMPLETE.json     # Configuration file
    ├── README.md                       # Production docs
    ├── infrastructure/                 # 6 Bicep templates + KQL
    ├── analytics/                      # Analytics rules
    └── workbooks/                      # 8 workbooks + templates
```

---

## ⚡ Common Commands

### Deploy Everything
```powershell
.\DEPLOY-COMPLETE.ps1
```

### Validate Deployment
```powershell
.\VALIDATE-DEPLOYMENT.ps1
```

### Check Logic App Status
```powershell
az logic workflow list -g <ResourceGroup> -o table
az logic workflow show -g <ResourceGroup> -n logic-cyren-ip-reputation
```

### Check DCR Status
```powershell
az monitor data-collection rule list -g <ResourceGroup> -o table
```

### Trigger Logic App Manually
```powershell
az logic workflow trigger run -g <ResourceGroup> --name logic-cyren-ip-reputation --trigger-name Recurrence
```

---

## 🎯 Success Indicators

After deployment, you should see:

✅ **Azure Portal - Logic Apps:**
- 3 Logic Apps with "Enabled" status
- Run history showing successful executions
- Managed Identity assigned

✅ **Azure Portal - Data Collection Rules:**
- 3 DCRs with "Succeeded" provisioning state
- Associated with correct Log Analytics workspace

✅ **Azure Portal - Log Analytics:**
- 2 custom tables visible: `TacitRed_Findings_CL`, `Cyren_Indicators_CL`
- Data appearing in tables (after first Logic App run)

✅ **Azure Portal - Sentinel:**
- 6 Analytics Rules in "Active" state
- 6 Workbooks available in Workbooks section

---

## 🔒 Security Best Practices

1. **API Keys:**
   - ⚠️ Never commit actual API keys to public repositories
   - Use Azure Key Vault for production
   - Rotate keys regularly

2. **RBAC:**
   - Review and approve all role assignments
   - Use least-privilege principle
   - Monitor Logic App identities

3. **Monitoring:**
   - Enable diagnostic logs on Logic Apps
   - Set up alerts for failed runs
   - Monitor data ingestion rates

---

## 📞 Support

### Documentation
- Production README: `sentinel-production/README.md`
- Deployment Guide: `sentinel-production/README-DEPLOYMENT.md`
- Success Report: `DEPLOYMENT-SUCCESS-REPORT.md`

### Logs
All deployment logs stored at:
```
sentinel-production/docs/deployment-logs/complete-YYYYMMDDHHMMSS/
```

### Troubleshooting
1. Check deployment logs in `docs/deployment-logs/`
2. Run validation script: `.\VALIDATE-DEPLOYMENT.ps1`
3. Review Logic App run history in Azure Portal
4. Check RBAC assignments (takes 30-60 min to propagate)

---

## 🎉 Ready to Deploy!

Your production deployment has been:
- ✅ Created and validated locally
- ✅ Published to GitHub
- ✅ Tested successfully (15.4 minutes)
- ✅ Fully documented

**Next Action:** Deploy to your target environment using the commands above!

---

**Version:** 1.0.0  
**Last Updated:** November 12, 2025  
**Repository:** https://github.com/mazamizo21/sentinel-staging-and-prod

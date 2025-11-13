# Complete File Manifest - Sentinel Threat Intelligence

**Repository:** https://github.com/mazamizo21/sentinel-staging-and-prod  
**Last Updated:** November 12, 2025, 8:30 PM UTC-05:00  
**Total Production Files:** 50

---

## ✅ Production Deployment Files (50 Total)

### 📦 Core Deployment (5 files)
| File | Purpose | Required |
|------|---------|----------|
| `DEPLOY-COMPLETE.ps1` | Main deployment script | ✅ YES |
| `client-config-COMPLETE.json` | Configuration file | ✅ YES |
| `VALIDATE-DEPLOYMENT.ps1` | Post-deployment validation | ✅ YES |
| `README.md` | Production documentation | ✅ YES |
| `README-DEPLOYMENT.md` | Detailed deployment guide | ✅ YES |
| `OPTIONAL-FEATURES.md` | Optional features guide | ℹ️ INFO |

---

### 🏗️ Infrastructure - Active (10 files)

#### Bicep Templates (6 files) - DEPLOYED BY DEFAULT
| File | Purpose | Status |
|------|---------|--------|
| `infrastructure/bicep/dcr-cyren-ip.bicep` | Cyren IP DCR | ✅ Active |
| `infrastructure/bicep/dcr-cyren-malware.bicep` | Cyren Malware DCR | ✅ Active |
| `infrastructure/bicep/dcr-tacitred-findings.bicep` | TacitRed DCR | ✅ Active |
| `infrastructure/bicep/logicapp-cyren-ip-reputation.bicep` | Cyren IP Logic App | ✅ Active |
| `infrastructure/bicep/logicapp-cyren-malware-urls.bicep` | Cyren Malware Logic App | ✅ Active |
| `infrastructure/bicep/logicapp-tacitred-ingestion.bicep` | TacitRed Logic App | ✅ Active |

#### Legacy/Backward Compatibility (2 files)
| File | Purpose | Status |
|------|---------|--------|
| `infrastructure/logicapp-cyren-ip-reputation.bicep` | Cyren IP (legacy path) | ✅ Included |
| `infrastructure/logicapp-cyren-malware-urls.bicep` | Cyren Malware (legacy path) | ✅ Included |

#### KQL Transformation Files (2 files)
| File | Purpose | Status |
|------|---------|--------|
| `infrastructure/cyren-dcr-transformation.kql` | Cyren data transformation | ✅ Active |
| `infrastructure/tacitred-dcr-transformation.kql` | TacitRed data transformation | ✅ Active |

---

### 🔄 Infrastructure - CCF (5 files) - OPTIONAL/DISABLED

#### CCF Connectors - **NOT DEPLOYED BY DEFAULT**
| File | Purpose | Status |
|------|---------|--------|
| `infrastructure/bicep/ccf-connector-cyren.bicep` | Cyren CCF standard | 🔄 Available |
| `infrastructure/bicep/ccf-connector-cyren-enhanced.bicep` | Cyren CCF enhanced | 🔄 Available |
| `infrastructure/bicep/ccf-connector-tacitred.bicep` | TacitRed CCF standard | 🔄 Available |
| `infrastructure/bicep/ccf-connector-tacitred-enhanced.bicep` | TacitRed CCF enhanced | 🔄 Available |
| `infrastructure/bicep/cyren-main-with-ccf.bicep` | Combined CCF deployment | 🔄 Available |

**Why Disabled?** CCF is still being developed and refined. Logic Apps are the proven, stable approach.  
**How to Enable:** See `OPTIONAL-FEATURES.md`

---

### 📊 Analytics - Active (8 files)

#### Main Analytics (1 file) - DEPLOYED BY DEFAULT
| File | Purpose | Status |
|------|---------|--------|
| `analytics/analytics-rules.bicep` | Main analytics deployment | ✅ Active |

#### Detection Rules (6 files) - DEPLOYED BY DEFAULT
| File | Rule Name | Status |
|------|-----------|--------|
| `analytics/rules/rule-active-compromised-account.kql` | Active Compromised Account | ✅ Active |
| `analytics/rules/rule-cross-feed-correlation.kql` | Cross-Feed Correlation | ✅ Active |
| `analytics/rules/rule-department-compromise-cluster.kql` | Department Compromise | ✅ Active |
| `analytics/rules/rule-high-risk-user-compromised.kql` | High-Risk User | ✅ Active |
| `analytics/rules/rule-malware-infrastructure.kql` | Malware Infrastructure | ✅ Active |
| `analytics/rules/rule-repeat-compromise.kql` | Repeat Compromise | ✅ Active |

---

### 📊 Analytics - Optional Parsers (4 files) - OPTIONAL

#### Parser Functions - **NOT DEPLOYED BY DEFAULT**
| File | Purpose | Status |
|------|---------|--------|
| `analytics/parsers/parser-cyren-indicators.kql` | Cyren full parser | 📊 Available |
| `analytics/parsers/parser-cyren-query-only.kql` | Cyren query parser | 📊 Available |
| `analytics/parsers/parser-tacitred-findings.kql` | TacitRed full parser | 📊 Available |
| `analytics/parsers/parser-tacitred-query-only.kql` | TacitRed query parser | 📊 Available |

**Why Optional?** Analytics rules work directly against tables. Parsers add abstraction layer.  
**How to Deploy:** Run `analytics/scripts/deploy-parser-functions.ps1`

---

### 🔨 Analytics - Helper Scripts (3 files) - OPTIONAL

#### Development & Troubleshooting Scripts
| File | Purpose | Status |
|------|---------|--------|
| `analytics/scripts/deploy-parser-functions.ps1` | Deploy parser functions | 🔨 Utility |
| `analytics/scripts/deploy-phase2-dev.ps1` | Development deployment | 🔨 Utility |
| `analytics/scripts/fix-malware-infrastructure-rule.ps1` | Rule troubleshooting | 🔨 Utility |

**Purpose:** Helper scripts for advanced users and development workflows

---

### 📈 Workbooks (12 files)

#### Workbook Bicep Templates (9 files) - DEPLOYED BY DEFAULT
| File | Workbook Name | Status |
|------|---------------|--------|
| `workbooks/bicep/workbook-threat-intelligence-command-center.bicep` | Command Center | ✅ Active |
| `workbooks/bicep/workbook-threat-intelligence-command-center-enhanced.bicep` | Command Center Enhanced | ✅ Active |
| `workbooks/bicep/workbook-executive-risk-dashboard.bicep` | Executive Dashboard | ✅ Active |
| `workbooks/bicep/workbook-executive-risk-dashboard-enhanced.bicep` | Executive Dashboard Enhanced | ✅ Active |
| `workbooks/bicep/workbook-threat-hunters-arsenal.bicep` | Threat Hunter Arsenal | ✅ Active |
| `workbooks/bicep/workbook-threat-hunters-arsenal-enhanced.bicep` | Threat Hunter Arsenal Enhanced | ✅ Active |
| `workbooks/bicep/workbook-cyren-threat-intelligence.bicep` | Cyren Intelligence | ✅ Active |
| `workbooks/bicep/workbook-cyren-threat-intelligence-enhanced.bicep` | Cyren Intelligence Enhanced | ✅ Active |
| `workbooks/bicep/deploy-all-workbooks.bicep` | Deploy all workbooks | 🔨 Utility |

#### Workbook Templates (3 files) - REQUIRED FOR SOME WORKBOOKS
| File | Purpose | Status |
|------|---------|--------|
| `workbooks/templates/command-center-workbook-template.json` | Template for Command Center | ✅ Included |
| `workbooks/templates/executive-dashboard-template.json` | Template for Executive Dashboard | ✅ Included |
| `workbooks/templates/threat-hunters-arsenal-template.json` | Template for Threat Hunter | ✅ Included |

---

## 📂 Folder Structure

```
sentinel-production/
├── 📄 DEPLOY-COMPLETE.ps1                           [Main Deployment]
├── 📄 client-config-COMPLETE.json                   [Configuration]
├── 📄 VALIDATE-DEPLOYMENT.ps1                       [Validation]
├── 📄 README.md                                     [Documentation]
├── 📄 README-DEPLOYMENT.md                          [Deployment Guide]
├── 📄 OPTIONAL-FEATURES.md                          [Optional Features]
│
├── 📁 infrastructure/
│   ├── 📁 bicep/
│   │   ├── ✅ dcr-cyren-ip.bicep                    [ACTIVE]
│   │   ├── ✅ dcr-cyren-malware.bicep               [ACTIVE]
│   │   ├── ✅ dcr-tacitred-findings.bicep           [ACTIVE]
│   │   ├── ✅ logicapp-cyren-ip-reputation.bicep    [ACTIVE]
│   │   ├── ✅ logicapp-cyren-malware-urls.bicep     [ACTIVE]
│   │   ├── ✅ logicapp-tacitred-ingestion.bicep     [ACTIVE]
│   │   ├── 🔄 ccf-connector-cyren.bicep             [OPTIONAL - CCF]
│   │   ├── 🔄 ccf-connector-cyren-enhanced.bicep    [OPTIONAL - CCF]
│   │   ├── 🔄 ccf-connector-tacitred.bicep          [OPTIONAL - CCF]
│   │   ├── 🔄 ccf-connector-tacitred-enhanced.bicep [OPTIONAL - CCF]
│   │   └── 🔄 cyren-main-with-ccf.bicep             [OPTIONAL - CCF]
│   ├── ✅ cyren-dcr-transformation.kql              [ACTIVE]
│   ├── ✅ tacitred-dcr-transformation.kql           [ACTIVE]
│   ├── ✅ logicapp-cyren-ip-reputation.bicep        [LEGACY PATH]
│   └── ✅ logicapp-cyren-malware-urls.bicep         [LEGACY PATH]
│
├── 📁 analytics/
│   ├── ✅ analytics-rules.bicep                     [ACTIVE]
│   ├── 📁 rules/
│   │   ├── ✅ rule-active-compromised-account.kql   [ACTIVE]
│   │   ├── ✅ rule-cross-feed-correlation.kql       [ACTIVE]
│   │   ├── ✅ rule-department-compromise-cluster.kql [ACTIVE]
│   │   ├── ✅ rule-high-risk-user-compromised.kql   [ACTIVE]
│   │   ├── ✅ rule-malware-infrastructure.kql       [ACTIVE]
│   │   └── ✅ rule-repeat-compromise.kql            [ACTIVE]
│   ├── 📁 parsers/
│   │   ├── 📊 parser-cyren-indicators.kql           [OPTIONAL]
│   │   ├── 📊 parser-cyren-query-only.kql           [OPTIONAL]
│   │   ├── 📊 parser-tacitred-findings.kql          [OPTIONAL]
│   │   └── 📊 parser-tacitred-query-only.kql        [OPTIONAL]
│   └── 📁 scripts/
│       ├── 🔨 deploy-parser-functions.ps1           [UTILITY]
│       ├── 🔨 deploy-phase2-dev.ps1                 [UTILITY]
│       └── 🔨 fix-malware-infrastructure-rule.ps1   [UTILITY]
│
├── 📁 workbooks/
│   ├── 📁 bicep/
│   │   ├── ✅ deploy-all-workbooks.bicep            [UTILITY]
│   │   ├── ✅ workbook-threat-intelligence-command-center.bicep
│   │   ├── ✅ workbook-threat-intelligence-command-center-enhanced.bicep
│   │   ├── ✅ workbook-executive-risk-dashboard.bicep
│   │   ├── ✅ workbook-executive-risk-dashboard-enhanced.bicep
│   │   ├── ✅ workbook-threat-hunters-arsenal.bicep
│   │   ├── ✅ workbook-threat-hunters-arsenal-enhanced.bicep
│   │   ├── ✅ workbook-cyren-threat-intelligence.bicep
│   │   └── ✅ workbook-cyren-threat-intelligence-enhanced.bicep
│   └── 📁 templates/
│       ├── ✅ command-center-workbook-template.json [REQUIRED]
│       ├── ✅ executive-dashboard-template.json     [REQUIRED]
│       └── ✅ threat-hunters-arsenal-template.json  [REQUIRED]
│
└── 📁 docs/
    └── 📁 deployment-logs/
        └── (Generated during deployment)
```

---

## 🎯 Status Legend

| Symbol | Status | Meaning |
|--------|--------|---------|
| ✅ | **Active** | Deployed by default, required for core functionality |
| 🔄 | **Optional - CCF** | Available but disabled. Enable when CCF is stable |
| 📊 | **Optional - Parser** | Available but not deployed. Enable for query abstraction |
| 🔨 | **Utility** | Helper script or deployment tool |
| ℹ️ | **Info** | Documentation or informational file |

---

## 📊 File Count Summary

| Category | Count | Status |
|----------|-------|--------|
| **Core Deployment** | 6 | ✅ Required |
| **Infrastructure - Active** | 10 | ✅ Deployed |
| **Infrastructure - CCF** | 5 | 🔄 Optional |
| **Analytics - Active** | 8 | ✅ Deployed |
| **Analytics - Parsers** | 4 | 📊 Optional |
| **Analytics - Scripts** | 3 | 🔨 Optional |
| **Workbooks** | 12 | ✅ Deployed |
| **Templates** | 3 | ✅ Required |
| **TOTAL** | **50** | |

---

## ✅ What's Deployed by Default

Running `DEPLOY-COMPLETE.ps1` deploys:
- ✅ 6 Core files (scripts + config + docs)
- ✅ 10 Infrastructure files (DCE, DCRs, Logic Apps, KQL transforms)
- ✅ 8 Analytics files (1 bicep + 6 rules + 1 script auto-runs)
- ✅ 12 Workbook files (9 workbooks + 3 templates)

**Default Deployment:** 36 files actively used  
**Optional Features:** 14 files ready to enable

---

## 🔄 What's Available But Not Deployed

### CCF Connectors (5 files)
- Status: Included but disabled
- Reason: Still being developed/refined
- Enable: Update config `ccf.enabled = true`
- See: `OPTIONAL-FEATURES.md` for details

### Parser Functions (4 files)
- Status: Included but not deployed
- Reason: Analytics work without them (optional abstraction)
- Enable: Run `analytics/scripts/deploy-parser-functions.ps1`
- See: `OPTIONAL-FEATURES.md` for details

### Helper Scripts (3 files)
- Status: Included for advanced users
- Reason: Utilities for development/troubleshooting
- Use: As needed for specific tasks

---

## 🚀 Quick Start

### Deploy Everything (Default)
```powershell
cd sentinel-production
.\DEPLOY-COMPLETE.ps1
```

**This deploys:** 36 active files (excludes CCF, parsers, and helper scripts)

### Enable Optional Features
See `OPTIONAL-FEATURES.md` for:
- How to enable CCF connectors
- How to deploy parser functions
- How to use helper scripts

---

## ✅ Verification

All 50 files are present in:
- **Local:** `d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production`
- **GitHub:** https://github.com/mazamizo21/sentinel-staging-and-prod

### Verify Locally
```powershell
cd d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production
Get-ChildItem -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.bicep','.json','.kql','.md') } | Measure-Object
# Should show: Count = 50
```

### Verify on GitHub
```bash
git clone https://github.com/mazamizo21/sentinel-staging-and-prod.git
cd sentinel-staging-and-prod/sentinel-production
# All 50 files should be present
```

---

## 📞 Support

- **Quick Start:** See `README.md`
- **Deployment:** See `README-DEPLOYMENT.md`  
- **Optional Features:** See `OPTIONAL-FEATURES.md`
- **Validation:** Run `VALIDATE-DEPLOYMENT.ps1`

---

**Version:** 1.0.0  
**Last Updated:** November 12, 2025  
**Repository:** https://github.com/mazamizo21/sentinel-staging-and-prod  
**Status:** ✅ **COMPLETE - ALL FILES INCLUDED**

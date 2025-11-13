# Optional Features - Sentinel Threat Intelligence

This deployment includes optional features that are **disabled by default** but ready to activate when needed.

---

## 📦 What's Included

### ✅ Active (Deployed by Default)
- ✅ 3 DCRs (Data Collection Rules) - Standard approach
- ✅ 3 Logic Apps - Automated ingestion
- ✅ 6 Analytics Rules - Basic detection
- ✅ 8 Workbooks - All dashboards

### 🔄 Optional (Ready to Enable)
- 🔄 **CCF Connectors** - Codeless Connector Framework (5 files)
- 🔄 **Parser Functions** - KQL parser functions (4 files)
- 🔄 **Advanced Analytics Scripts** - Helper deployment scripts (3 files)

---

## 🔧 Option 1: CCF (Codeless Connector Framework)

### What is CCF?
CCF is Microsoft's Codeless Connector Framework for ingesting threat intelligence data without Logic Apps. It's a newer, more integrated approach.

### Files Included (5 Total)

#### Standard CCF Connectors
1. `infrastructure/bicep/ccf-connector-cyren.bicep` - Cyren CCF connector
2. `infrastructure/bicep/ccf-connector-tacitred.bicep` - TacitRed CCF connector

#### Enhanced CCF Connectors
3. `infrastructure/bicep/ccf-connector-cyren-enhanced.bicep` - Enhanced Cyren CCF
4. `infrastructure/bicep/ccf-connector-tacitred-enhanced.bicep` - Enhanced TacitRed CCF

#### CCF Main Template
5. `infrastructure/bicep/cyren-main-with-ccf.bicep` - Combined deployment with CCF

### Current Status
⚠️ **DISABLED** - CCF is still being refined and tested

### Why Not Active?
- CCF is a newer technology still being developed
- Current Logic App approach is proven and stable
- CCF provides alternative ingestion method when ready

### How to Enable CCF (When Ready)

#### Option A: Update Config (Recommended)
Edit `client-config-COMPLETE.json`:
```json
"ccf": {
  "value": {
    "enabled": true,
    "deployTacitRedCCF": true,
    "deployCyrenCCF": true
  }
}
```

Then run:
```powershell
.\DEPLOY-COMPLETE.ps1
```

#### Option B: Manual Deployment
```powershell
# Deploy Cyren CCF
az deployment group create `
  -g <ResourceGroup> `
  --template-file .\infrastructure\bicep\ccf-connector-cyren.bicep `
  --parameters workspaceName=<WorkspaceName>

# Deploy TacitRed CCF
az deployment group create `
  -g <ResourceGroup> `
  --template-file .\infrastructure\bicep\ccf-connector-tacitred.bicep `
  --parameters workspaceName=<WorkspaceName>
```

### Benefits of CCF vs Logic Apps

| Feature | Logic Apps (Current) | CCF (Future) |
|---------|---------------------|--------------|
| **Maturity** | ✅ Proven, stable | 🔄 Newer technology |
| **Configuration** | Code-based | UI-based in portal |
| **Monitoring** | Logic App runs | Built-in Sentinel |
| **Cost** | Per-execution | Included in Sentinel |
| **Flexibility** | High (custom code) | Medium (predefined) |

---

## 📊 Option 2: Parser Functions

### What are Parsers?
Parser functions are KQL functions that normalize and parse threat intelligence data for easier querying.

### Files Included (4 Total)

#### Cyren Parsers
1. `analytics/parsers/parser-cyren-indicators.kql` - Full Cyren parser
2. `analytics/parsers/parser-cyren-query-only.kql` - Query-only version

#### TacitRed Parsers
3. `analytics/parsers/parser-tacitred-findings.kql` - Full TacitRed parser
4. `analytics/parsers/parser-tacitred-query-only.kql` - Query-only version

### Current Status
✅ **AVAILABLE** - Ready to deploy but not required

### Why Not Active?
- Analytics rules work directly against tables (simpler)
- Parsers add abstraction layer (optional)
- Deploy when standardization needed across queries

### How to Deploy Parsers

#### Option A: Automated Deployment
```powershell
cd analytics\scripts
.\deploy-parser-functions.ps1
```

#### Option B: Manual Deployment
Navigate to **Log Analytics Workspace → Logs → Functions**, then:

1. Create new function
2. Paste content from parser file
3. Save with function name (e.g., `CyrenIndicators`)

### Example Usage

**Without Parser:**
```kql
Cyren_Indicators_CL
| where risk_d > 70
| project TimeGenerated, ip_s, category_s, risk_d
```

**With Parser:**
```kql
CyrenIndicators()
| where Risk > 70
| project Timestamp, IP, Category, Risk
```

### Benefits of Parsers
- ✅ **Normalized field names** - Consistent across queries
- ✅ **Type conversion** - Automatic data type handling
- ✅ **Field mapping** - Simplified schema
- ✅ **Reusability** - Use across workbooks and rules
- ✅ **Future-proof** - Schema changes isolated to parser

---

## 🔨 Option 3: Analytics Helper Scripts

### Files Included (3 Total)

1. `analytics/scripts/deploy-parser-functions.ps1`
   - Automated parser function deployment
   - Creates all 4 parser functions in workspace

2. `analytics/scripts/deploy-phase2-dev.ps1`
   - Development deployment script
   - Used for testing new analytics rules

3. `analytics/scripts/fix-malware-infrastructure-rule.ps1`
   - Helper script for specific rule fixes
   - Example of rule troubleshooting

### Current Status
✅ **AVAILABLE** - Helper utilities for advanced users

### When to Use
- Deploying parser functions
- Testing new analytics rules
- Troubleshooting specific rules
- Development and iteration

---

## 📋 Summary: What's Deployed vs Available

### Currently Deployed (Default)
```
✅ DCE (Data Collection Endpoint)
✅ 3 DCRs (Standard)
✅ 3 Logic Apps
✅ 2 Log Analytics Tables
✅ 6 Analytics Rules (Direct table queries)
✅ 8 Workbooks (Direct table queries)
✅ RBAC Assignments
```

### Ready to Enable (Optional)
```
🔄 5 CCF Connectors (Alternative ingestion method)
📊 4 Parser Functions (Query abstraction layer)
🔨 3 Helper Scripts (Deployment utilities)
```

---

## 🚀 Enabling Optional Features

### For CCF (When Ready)
1. Test in development environment first
2. Update `client-config-COMPLETE.json` → `ccf.enabled = true`
3. Re-run `DEPLOY-COMPLETE.ps1`
4. Validate CCF connectors in Sentinel portal

### For Parsers (Anytime)
1. Run `analytics\scripts\deploy-parser-functions.ps1`
2. Update workbook queries to use parser functions
3. Update analytics rules to use parser functions (optional)

### For Helper Scripts
- Use as needed for development and troubleshooting
- Not required for production deployment

---

## 🎯 Recommended Approach

### Phase 1: Current (✅ Done)
- Deploy with Logic Apps + DCRs
- Use direct table queries
- Validate data ingestion

### Phase 2: Parsers (📊 Optional, Low Risk)
- Deploy parser functions when ready
- Gradually migrate queries to use parsers
- Improves maintainability

### Phase 3: CCF (🔄 Future, When Stable)
- Test CCF in isolated environment
- Migrate from Logic Apps to CCF when proven
- More integrated with Sentinel

---

## 📞 Support

### Documentation
- CCF: Official Microsoft Sentinel documentation
- Parsers: `analytics/parsers/*.kql` files
- Scripts: `analytics/scripts/*.ps1` files

### Decision Matrix

| Scenario | Use Logic Apps | Use CCF | Use Parsers |
|----------|---------------|---------|-------------|
| **Production now** | ✅ Yes | ❌ Wait | 🤔 Optional |
| **Development** | ✅ Yes | ✅ Test | ✅ Yes |
| **Long-term** | 🤔 Migrate | ✅ Future | ✅ Yes |
| **Simplicity** | ✅ Simple | ⚠️ Simpler | ⚠️ Adds layer |
| **Cost optimization** | 💰 Per-run | 💰 Included | 💰 Free |

---

## 🔒 Important Notes

1. **CCF is disabled** because it's still being refined
2. **Parsers are optional** - analytics work without them
3. **All files are included** - no confusion about missing features
4. **Enable when ready** - no re-download needed
5. **No impact on current deployment** - optional features don't interfere

---

**Bottom Line:** The production deployment works perfectly without these optional features. Enable them when you're ready and have tested them in your environment.

---

**Version:** 1.0.0  
**Last Updated:** November 12, 2025  
**Status:** All optional features included and documented

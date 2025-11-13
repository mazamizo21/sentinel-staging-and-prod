# Deployment Scripts - Clear Comparison

**Updated:** November 12, 2025, 9:35 PM  
**Purpose:** Clarify the difference between the two main deployment scripts

---

## 📋 QUICK REFERENCE

| Script | Ingestion Method | Components Deployed |
|--------|------------------|---------------------|
| **DEPLOY-CCF-CORRECTED.ps1** | ✅ **CCF** (Codeless Connector Framework) | DCE, DCRs, Tables, **CCF Connectors**, Analytics, Workbooks |
| **DEPLOY-COMPLETE.ps1** | ✅ **Logic Apps** (Proven, Stable) | DCE, DCRs, Tables, **Logic Apps**, RBAC, Analytics, Workbooks |

---

## 🎯 WHEN TO USE EACH SCRIPT

### Use `DEPLOY-CCF-CORRECTED.ps1` when:

✅ You want **modern CCF-based ingestion**  
✅ You prefer **Microsoft-managed polling** (no Logic App maintenance)  
✅ You're deploying to **marketplace** (customers enter API keys in Sentinel UI)  
✅ You want **unified connector UI** in Sentinel portal

**Command:**
```powershell
.\DEPLOY-CCF-CORRECTED.ps1
```

### Use `DEPLOY-COMPLETE.ps1` when:

✅ You want **proven, stable Logic Apps** (battle-tested)  
✅ You need **full control** over polling logic  
✅ You want **easier troubleshooting** (Logic App runs visible in portal)  
✅ You prefer **traditional Azure automation** workflows

**Command:**
```powershell
.\DEPLOY-COMPLETE.ps1
```

---

## 🔧 DETAILED COMPARISON

### DEPLOY-CCF-CORRECTED.ps1

**Full Name:** CCF Complete Deployment - Production Ready  
**Ingestion:** Codeless Connector Framework (CCF)

#### Phases (5 Total)

1. **Infrastructure** (~5 minutes)
   - Data Collection Endpoint (DCE)
   - 3 Data Collection Rules (DCRs)
   - 2 Custom Log Tables
   - **Total:** 6 resources

2. **Connector Definition** (~1 minute)
   - Single unified UI: "Threat Intelligence Feeds (TacitRed + Cyren)"
   - **Total:** 1 definition

3. **Data Connectors** (~3 minutes)
   - TacitRedFindings (RestApiPoller)
   - CyrenIPReputation (RestApiPoller)
   - CyrenMalwareURLs (RestApiPoller)
   - **Total:** 3 connectors

4. **Analytics Rules** (~2 minutes)
   - 6 detection rules
   - **Total:** 6 rules

5. **Workbooks** (~3 minutes)
   - Threat Intelligence Command Center
   - Executive Dashboard
   - Threat Hunter's Arsenal
   - Cyren Threat Intelligence
   - **Total:** 4-8 workbooks (depending on config)

**Total Time:** ~15 minutes  
**Total Resources:** 15-20 resources

#### CCF Advantages

✅ **Microsoft-managed polling** - No custom code to maintain  
✅ **Unified UI** - Single connector in Sentinel portal  
✅ **Marketplace-ready** - Customers enter credentials in UI  
✅ **Modern architecture** - Latest Sentinel capabilities  
✅ **Auto-scaling** - Microsoft handles scaling and retries

#### CCF Disadvantages

⚠️ **Multiple credential inputs required** - 3 separate API keys/tokens (see below)  
⚠️ **Less control** - Cannot customize polling logic  
⚠️ **Newer technology** - Less community knowledge vs Logic Apps  
⚠️ **Limited debugging** - Cannot see individual poll attempts

---

### DEPLOY-COMPLETE.ps1

**Full Name:** Complete Automated Deployment - Sentinel Threat Intelligence  
**Ingestion:** Azure Logic Apps

#### Phases (6 Total)

1. **Prerequisites** (~1 minute)
   - Workspace validation
   - Service principal propagation
   - **Total:** Configuration only

2. **Infrastructure** (~10 minutes)
   - Data Collection Endpoint (DCE)
   - 3 Data Collection Rules (DCRs)
   - 2 Custom Log Tables
   - 3 Logic Apps (TacitRed, Cyren IP, Cyren Malware)
   - **Total:** 9 resources

3. **RBAC Assignment** (~2 minutes)
   - Monitoring Metrics Publisher roles for 3 Logic Apps
   - Roles on DCE and DCRs
   - **Total:** 6 role assignments

4. **Analytics Rules** (~2 minutes)
   - 6 detection rules
   - **Total:** 6 rules

5. **Workbooks** (~3 minutes)
   - Threat Intelligence Command Center
   - Executive Dashboard
   - Threat Hunter's Arsenal
   - Cyren Threat Intelligence
   - **Total:** 4-8 workbooks

6. **Initial Testing** (~1 minute)
   - Trigger Logic Apps for test run
   - **Total:** 3 test triggers

**Total Time:** ~20 minutes  
**Total Resources:** 25-30 resources

#### Logic App Advantages

✅ **Full control** - Customize polling frequency, error handling  
✅ **Easy debugging** - See every run in Logic App portal  
✅ **Single credential input** - API keys in deployment script  
✅ **Proven stability** - Battle-tested Azure service  
✅ **Flexible** - Can add custom logic (filtering, transformation)

#### Logic App Disadvantages

⚠️ **Manual maintenance** - Need to update Logic App code  
⚠️ **More resources** - 3 separate Logic Apps vs 3 connectors  
⚠️ **RBAC complexity** - Need to manage role assignments  
⚠️ **Not marketplace-standard** - Sentinel Solutions prefer CCF

---

## 🔑 API KEY INPUT COMPARISON

### CCF (DEPLOY-CCF-CORRECTED.ps1)

**How Customers Enter Credentials:**

When customers open the "Threat Intelligence Feeds" connector in Sentinel portal, they see:

```
┌─────────────────────────────────────────────────┐
│ Configuration                                    │
├─────────────────────────────────────────────────┤
│                                                  │
│ 1. Configure TacitRed API Access                │
│    ┌──────────────────────────────────────┐    │
│    │ TacitRed API Key                      │    │
│    │ [Enter your TacitRed API Key______]  │    │
│    └──────────────────────────────────────┘    │
│                                                  │
│ 2. Configure Cyren API Access                   │
│    ┌──────────────────────────────────────┐    │
│    │ Cyren IP Reputation JWT Token         │    │
│    │ [Enter JWT token for IP Reputation_] │    │
│    └──────────────────────────────────────┘    │
│                                                  │
│    ┌──────────────────────────────────────┐    │
│    │ Cyren Malware URLs JWT Token          │    │
│    │ [Enter JWT token for Malware URLs__] │    │
│    └──────────────────────────────────────┘    │
│                                                  │
│ 3. Connect to Microsoft Sentinel                │
│    [ Connect ]                                   │
└─────────────────────────────────────────────────┘
```

**Why 3 Inputs?**

This is **by design** in CCF architecture:
- Each `dataConnector` resource requires its own authentication
- TacitRed uses 1 API key
- Cyren IP Reputation uses 1 JWT token
- Cyren Malware URLs uses 1 JWT token (separate feed)

**Is This Normal?**

✅ **YES** - This is the standard CCF pattern per Microsoft docs  
✅ **Example:** Cisco Meraki CCF has 3 separate inputs for 3 feeds  
✅ **Security:** Each connector can have different credentials if needed

**Alternative (Not Recommended):**

We COULD create a single connector that handles all 3 feeds, but:
- ❌ Would lose separation of concerns
- ❌ Cannot have different polling schedules
- ❌ Error in one feed would affect all feeds
- ❌ Not the Microsoft recommended pattern

---

### Logic Apps (DEPLOY-COMPLETE.ps1)

**How Customers Enter Credentials:**

Credentials are entered **once** during deployment script run:

```powershell
# In client-config-COMPLETE.json
{
  "tacitRed": {
    "value": {
      "apiKey": "your-api-key-here"
    }
  },
  "cyren": {
    "value": {
      "ipReputation": {
        "jwtToken": "your-jwt-token-here"
      },
      "malwareUrls": {
        "jwtToken": "your-jwt-token-here"
      }
    }
  }
}
```

**Advantage:** Customer enters once, applies to all Logic Apps  
**Disadvantage:** Credentials stored in config file (not Sentinel UI)

---

## 🚀 DEPLOYMENT RECOMMENDATIONS

### For Production (Stable, Proven)

✅ **Use:** `DEPLOY-COMPLETE.ps1` (Logic Apps)  
**Reason:** Battle-tested, easier debugging, full control

### For Marketplace (Modern, Standard)

✅ **Use:** `DEPLOY-CCF-CORRECTED.ps1` (CCF)  
**Reason:** Sentinel Solutions standard, customer-friendly UI

### For Testing/Development

✅ **Use:** Either script (test both!)  
**Reason:** Validate both architectures work

---

## 📊 SIDE-BY-SIDE MATRIX

| Feature | CCF Script | Logic Apps Script |
|---------|------------|-------------------|
| **Deployment Time** | ~15 min | ~20 min |
| **Total Resources** | 15-20 | 25-30 |
| **Credential Input** | Portal UI (3 fields) | Config file (once) |
| **Polling Control** | Microsoft-managed | Full control |
| **Debugging** | Limited | Full visibility |
| **Maintenance** | Zero | Logic App updates |
| **Marketplace** | ✅ Ready | ⚠️ Not standard |
| **Stability** | Good | Excellent |
| **Community Support** | Growing | Extensive |

---

## 🔄 SWITCHING BETWEEN CCF AND LOGIC APPS

### From Logic Apps to CCF

1. **Delete Logic Apps:**
   ```powershell
   az logic workflow delete -g SentinelTestStixImport -n logic-tacitred-ingestion
   az logic workflow delete -g SentinelTestStixImport -n logic-cyren-ip-reputation
   az logic workflow delete -g SentinelTestStixImport -n logic-cyren-malware-urls
   ```

2. **Keep existing:** DCE, DCRs, Tables, Analytics, Workbooks

3. **Deploy CCF:**
   ```powershell
   .\DEPLOY-CCF-CORRECTED.ps1
   ```

### From CCF to Logic Apps

1. **Delete CCF connectors:**
   ```powershell
   az sentinel data-connector delete -g SentinelTestStixImport -w SentinelThreatIntelWorkspace -n TacitRedFindings
   az sentinel data-connector delete -g SentinelTestStixImport -w SentinelThreatIntelWorkspace -n CyrenIPReputation
   az sentinel data-connector delete -g SentinelTestStixImport -w SentinelThreatIntelWorkspace -n CyrenMalwareURLs
   ```

2. **Keep existing:** DCE, DCRs, Tables, Analytics, Workbooks

3. **Deploy Logic Apps:**
   ```powershell
   .\DEPLOY-COMPLETE.ps1
   ```

---

## 💡 BEST PRACTICES

### CCF Deployment

1. ✅ Test API credentials in Postman/curl before deployment
2. ✅ Document the 3-input requirement for customers
3. ✅ Use the unified connector definition (ThreatIntelligenceFeeds)
4. ✅ Monitor DCE logs for polling issues
5. ✅ Set reasonable polling windows (360 min default)

### Logic Apps Deployment

1. ✅ Secure config file with API keys (do not commit to Git)
2. ✅ Monitor Logic App runs for failures
3. ✅ Set alerts on Logic App failures
4. ✅ Review RBAC assignments periodically
5. ✅ Test manual triggers before relying on schedule

---

## 📞 TROUBLESHOOTING

### "Which script should I use?"

**Answer:** Start with `DEPLOY-COMPLETE.ps1` (Logic Apps) for production stability. Use `DEPLOY-CCF-CORRECTED.ps1` if preparing for marketplace.

### "Can I use both CCF and Logic Apps?"

**Answer:** ❌ No - They would both write to the same tables, causing duplicates.

### "Why do I see multiple connectors in portal?"

**Answer:** Old connector definitions may still exist. Refresh portal or run cleanup script.

### "CCF asks for 3 API keys - is this a bug?"

**Answer:** ✅ No - This is correct CCF behavior. See "API KEY INPUT COMPARISON" section above.

---

## ✅ SUMMARY

- ✅ **DEPLOY-CCF-CORRECTED.ps1** = Modern CCF with Analytics + Workbooks (NO Logic Apps)
- ✅ **DEPLOY-COMPLETE.ps1** = Proven Logic Apps with Analytics + Workbooks (NO CCF)
- ✅ Both deploy **complete solutions** with all components
- ✅ CCF requires 3 credential inputs by design (this is normal)
- ✅ Choose based on your use case: Production vs Marketplace

---

**Last Updated:** November 12, 2025  
**Maintained By:** AI Security Engineer

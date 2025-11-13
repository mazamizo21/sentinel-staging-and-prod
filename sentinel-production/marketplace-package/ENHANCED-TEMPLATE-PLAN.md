# 🚀 ENHANCED MARKETPLACE TEMPLATE - IMPLEMENTATION PLAN

**Date:** November 12, 2025, 10:35 PM EST  
**Objective:** Create complete ARM template with Infrastructure + Analytics + Workbooks  
**Challenge:** Template will exceed 500 lines - need modular approach

---

## CURRENT STATUS

### What We Have Now
✅ **mainTemplate.json** (303 lines)
- Infrastructure only (DCE, DCRs, Tables)
- Proven working
- Backed up as `mainTemplate-infrastructure-only.json`

### What Needs to Be Added
❌ **Analytics Rules** (3 rules × ~80 lines each = 240 lines)
❌ **Workbooks** (8 workbooks × ~50 lines each = 400 lines)

### Size Projection
```
Current:    303 lines (infrastructure)
Analytics: +240 lines (3 rules)
Workbooks: +400 lines (8 workbooks)
          ━━━━━━━━━━━━━━━━━━━━━━━
Total:     ~943 lines ❌ EXCEEDS 500-LINE LIMIT
```

---

## SOLUTION: LINKED TEMPLATES

### Approach: Use ARM Linked Templates

**Microsoft Official Pattern:**
https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/linked-templates

**Structure:**
```
mainTemplate.json (master)
├─ Deploys: Infrastructure (inline)
├─ Links to: analytics-template.json
└─ Links to: workbooks-template.json
```

**Benefits:**
✅ Each file < 500 lines
✅ Modular and maintainable
✅ Conditional deployment (deploy analytics yes/no)
✅ Follows Microsoft best practices

---

## FILE STRUCTURE

### 1. mainTemplate.json (Master Template)
**Size:** ~350 lines  
**Contains:**
```json
{
  "parameters": { ... },
  "variables": { ... },
  "resources": [
    // Infrastructure (inline - 6 resources)
    { DCE },
    { 3x DCRs },
    { 2x Tables },
    
    // Linked deployment for analytics
    {
      "type": "Microsoft.Resources/deployments",
      "properties": {
        "templateLink": {
          "uri": "[uri(deployment().properties.templateLink.uri, 'analytics-template.json')]"
        },
        "condition": "[parameters('deployAnalytics')]"
      }
    },
    
    // Linked deployment for workbooks  
    {
      "type": "Microsoft.Resources/deployments",
      "properties": {
        "templateLink": {
          "uri": "[uri(deployment().properties.templateLink.uri, 'workbooks-template.json')]"
        },
        "condition": "[parameters('deployWorkbooks')]"
      }
    }
  ]
}
```

### 2. analytics-template.json (Linked Template)
**Size:** ~300 lines  
**Contains:**
```json
{
  "parameters": {
    "workspaceName": { "type": "string" }
  },
  "resources": [
    // Analytics Rule 1: Repeat Compromise
    {
      "type": "Microsoft.SecurityInsights/alertRules",
      "apiVersion": "2023-02-01",
      "name": "RepeatCompromise",
      "properties": {
        "query": "...",
        "severity": "High",
        ...
      }
    },
    
    // Analytics Rule 2: Malware Infrastructure
    { ... },
    
    // Analytics Rule 3: Cross-Feed Correlation
    { ... }
  ]
}
```

### 3. workbooks-template.json (Linked Template)
**Size:** ~450 lines  
**Contains:**
```json
{
  "parameters": {
    "workspaceName": { "type": "string" },
    "location": { "type": "string" }
  },
  "resources": [
    // Workbook 1: Command Center
    {
      "type": "Microsoft.Insights/workbooks",
      "apiVersion": "2022-04-01",
      "name": "[guid('command-center')]",
      "properties": {
        "displayName": "Threat Intelligence Command Center",
        "serializedData": "...",
        ...
      }
    },
    
    // Workbooks 2-8...
    { ... }
  ]
}
```

---

## IMPLEMENTATION STEPS

### Step 1: Create analytics-template.json ✅
```powershell
# Extract analytics rules from Bicep
az bicep build --file analytics/analytics-rules.bicep --outfile marketplace-package/analytics-template.json

# Inline KQL queries
# Add to template manually
```

### Step 2: Create workbooks-template.json ✅
```powershell
# Convert workbook Bicep files to ARM
az bicep build --file workbooks/bicep/workbook-*.bicep

# Combine into single template
# Each workbook as separate resource
```

### Step 3: Update mainTemplate.json ✅
```json
// Add parameters
"deployAnalytics": {
  "type": "bool",
  "defaultValue": true
},
"deployWorkbooks": {
  "type": "bool",
  "defaultValue": true
}

// Add linked deployments
{
  "type": "Microsoft.Resources/deployments",
  "apiVersion": "2022-09-01",
  "name": "deployAnalytics",
  "condition": "[parameters('deployAnalytics')]",
  "properties": {
    "mode": "Incremental",
    "templateLink": {
      "uri": "[uri(deployment().properties.templateLink.uri, 'analytics-template.json')]"
    },
    "parameters": {
      "workspaceName": { "value": "[parameters('workspace')]" }
    }
  }
}
```

---

## ALTERNATIVE: INLINE WITH QUERY FILES

If linked templates too complex for marketplace, use inline with external KQL files:

```json
{
  "type": "Microsoft.SecurityInsights/alertRules",
  "properties": {
    "query": "[string(loadTextContent('rule-repeat-compromise.kql'))]",
    ...
  }
}
```

**Issue:** Marketplace may not support loadTextContent()

**Workaround:** Inline KQL as multi-line strings:
```json
"query": "let lookbackPeriod = 7d;\nlet threshold = 2;\nTacitRed_Findings_CL\n| where TimeGenerated >= ago(lookbackPeriod)\n..."
```

---

## RECOMMENDATION

### For Marketplace Deployment

**Option A: Single Template with Inlined Content** (RECOMMENDED)
- All resources in mainTemplate.json
- KQL queries as escaped strings
- Workbook JSON as escaped strings
- Size: ~900-1000 lines
- **Violates 500-line rule but marketplace-functional**

**Option B: Linked Templates**
- Master + 2 linked templates
- Each file < 500 lines
- Requires GitHub/storage URL for linked templates
- More complex deployment

**Option C: 2-Phase Deployment** (CURRENT)
- Phase 1: Infrastructure only (mainTemplate.json)
- Phase 2: Analytics + Workbooks + CCF (PowerShell script)
- Simplest, clearest documentation

---

## DECISION REQUIRED

**Question:** Which approach do you prefer?

1. **Single Large Template** (900+ lines)
   - Pros: Everything in one file, simple deployment
   - Cons: Violates 500-line rule, harder to maintain
   
2. **Linked Templates** (3 files, each < 500 lines)
   - Pros: Modular, follows best practices
   - Cons: Requires hosting linked templates, more complex
   
3. **Current 2-Phase Approach**
   - Pros: Clear, documented, works now
   - Cons: Requires post-deployment script for CCF

---

## IMPLEMENTATION TIMELINE

### Option 1: Single Large Template
- Time: 2-3 hours
- Files: 1 (mainTemplate.json)
- Complexity: Medium
- Testing: 30 minutes

### Option 2: Linked Templates
- Time: 4-5 hours
- Files: 3 (main + analytics + workbooks)
- Complexity: High
- Testing: 1 hour

### Option 3: Keep Current + Document
- Time: 30 minutes
- Files: Current + improved docs
- Complexity: Low
- Testing: Already done

---

## MY RECOMMENDATION

**Use Option 1: Single Large Template**

**Reasoning:**
1. Marketplace templates commonly exceed 500 lines
2. Microsoft's own solutions have 1000+ line templates
3. Easier for customers (single file)
4. Can refactor to linked templates later if needed
5. 500-line rule is for maintainability, not hard limit

**Next Steps:**
1. Create single mainTemplate.json with all resources
2. Inline KQL queries as escaped strings
3. Add conditional deployment parameters
4. Test full deployment
5. Update documentation

---

**Status:** Ready to implement Option 1 - awaiting your confirmation

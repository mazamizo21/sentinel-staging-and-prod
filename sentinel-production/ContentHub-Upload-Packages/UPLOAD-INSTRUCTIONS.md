# Microsoft Sentinel Content Hub Upload Instructions

## 📦 Package Overview

**Created:** November 13, 2025  
**Status:** Ready for Content Hub Upload  
**Packages:** 2 Solutions (TacitRed-CCF, Cyren-CCF)

---

## 🎯 Upload Packages

### Package 1: TacitRed-CCF-Solution.zip
- **Solution Name:** TacitRed Compromised Credentials
- **Publisher:** TacitRed
- **Content ID:** TacitRedCompromisedCredentials
- **Components:** 1 Data Connector, 6 Workbooks, 1 Analytics Rule

### Package 2: Cyren-CCF-Solution.zip
- **Solution Name:** Cyren Threat Intelligence
- **Publisher:** Cyren
- **Content ID:** CyrenThreatIntelligence
- **Components:** 2 Data Connectors, 2 Workbooks

---

## 🔐 Microsoft Partner Center Access

### Prerequisites:
1. **Microsoft Partner Center Account** with Sentinel Content Hub access
2. **Publisher Verification** completed
3. **Azure Marketplace Publisher Agreement** signed

### Access URLs:
- **Partner Center:** https://partner.microsoft.com/
- **Content Hub Submissions:** https://partner.microsoft.com/dashboard/marketplace-offers/overview
- **Sentinel Content Hub:** https://docs.microsoft.com/azure/sentinel/sentinel-solutions

---

## 📋 Step-by-Step Upload Process

### Step 1: Login to Partner Center
1. Go to https://partner.microsoft.com/
2. Sign in with the provided Microsoft Store account
3. Navigate to **Marketplace offers** → **Overview**

### Step 2: Create New Offer (For Each Package)

#### For TacitRed-CCF:
1. Click **+ New offer** → **Azure Application**
2. **Offer ID:** `tacitred-compromised-credentials`
3. **Offer alias:** `TacitRed Compromised Credentials`
4. Click **Create**

#### For Cyren-CCF:
1. Click **+ New offer** → **Azure Application**
2. **Offer ID:** `cyren-threat-intelligence`
3. **Offer alias:** `Cyren Threat Intelligence`
4. Click **Create**

### Step 3: Configure Offer Setup
1. **Offer type:** Solution Template
2. **Customer leads:** Configure lead management
3. **Test drive:** Not required for Sentinel solutions
4. **Review and publish:** Check when ready

### Step 4: Properties Configuration
1. **Categories:** 
   - Primary: Security
   - Secondary: Identity & Access Management
2. **Legal:** Use standard Microsoft agreement
3. **Offer listing:** Fill in description and details

### Step 5: Preview Audience
1. **Subscription IDs:** Add test subscription IDs
2. **Preview audience:** Add Microsoft emails for testing

### Step 6: Technical Configuration

#### For TacitRed-CCF:
1. **Package file:** Upload `TacitRed-CCF-Solution.zip`
2. **Version:** 1.0.0
3. **Deployment mode:** Incremental
4. **Package details:** Auto-populated from packageMetadata.json

#### For Cyren-CCF:
1. **Package file:** Upload `Cyren-CCF-Solution.zip`
2. **Version:** 1.0.0
3. **Deployment mode:** Incremental
4. **Package details:** Auto-populated from packageMetadata.json

### Step 7: Plan Overview
1. **Plan ID:** `standard`
2. **Plan name:** `Standard Plan`
3. **Pricing model:** Free (for Sentinel solutions)

### Step 8: Plan Listing
1. **Plan title:** Same as solution name
2. **Plan summary:** Brief description
3. **Plan description:** Detailed feature list

### Step 9: Plan Technical Configuration
1. **Version:** 1.0.0
2. **Package file:** Same as Step 6
3. **ARM template:** Validated automatically

### Step 10: Review and Publish
1. **Review all sections** for completeness
2. **Publish to preview** first
3. **Test in preview environment**
4. **Go live** after successful testing

---

## ✅ Pre-Upload Validation Checklist

### Required Files (Both Packages):
- [x] mainTemplate.json - ARM template
- [x] createUiDefinition.json - Portal UI definition
- [x] packageMetadata.json - Solution metadata
- [x] README.md - Documentation

### ARM Template Validation:
- [x] Valid JSON syntax
- [x] All parameters defined
- [x] Secure strings for API keys
- [x] Proper resource dependencies
- [x] Output variables defined

### UI Definition Validation:
- [x] Valid schema version
- [x] Parameter mapping correct
- [x] Validation rules in place
- [x] Help text provided

### Metadata Validation:
- [x] Content ID unique
- [x] Version specified
- [x] Categories assigned
- [x] Dependencies listed

---

## 🧪 Testing Instructions

### After Upload to Preview:
1. **Deploy from Content Hub Preview**
2. **Verify all resources created:**
   - Data Collection Endpoints
   - Data Collection Rules
   - Custom Tables
   - Managed Identities
   - CCF Connectors
   - Analytics Rules
   - Workbooks

3. **Test Data Ingestion:**
   - Verify API connectivity
   - Check data flow to tables
   - Validate analytics rules trigger
   - Test workbook visualizations

4. **Security Testing:**
   - Verify secure parameter handling
   - Test RBAC permissions
   - Validate managed identity access

---

## 🚨 Important Notes

### API Keys Required:
- **TacitRed:** API Key format (UUID)
- **Cyren:** JWT tokens (2 separate tokens for IP and Malware feeds)

### Deployment Time:
- **Infrastructure:** 5-10 minutes
- **CCF Connectors:** 2-5 minutes
- **First Data Poll:** 5 minutes (TacitRed) / 6 hours (Cyren default)

### Support Information:
- **TacitRed Support:** Include TacitRed contact details
- **Cyren Support:** Include Cyren contact details
- **Technical Issues:** Reference this documentation

---

## 📞 Support Contacts

### For Upload Issues:
- **Microsoft Partner Support:** https://partner.microsoft.com/support
- **Sentinel Content Hub:** sentinel-solutions@microsoft.com

### For Technical Issues:
- **Package Creator:** [Your contact information]
- **Deployment Issues:** Reference deployment logs in docs/ folder

---

## 📁 Package Contents Reference

### TacitRed-CCF-Solution.zip:
```
├── mainTemplate.json (ARM template with 6 workbooks, 1 analytics rule)
├── createUiDefinition.json (Portal UI with API key input)
├── README.md (User documentation)
├── DEPLOYMENT-SUMMARY.md (Technical details)
└── Package/
    └── packageMetadata.json (Solution metadata)
```

### Cyren-CCF-Solution.zip:
```
├── mainTemplate.json (ARM template with 2 workbooks, 2 connectors)
├── createUiDefinition.json (Portal UI with JWT token inputs)
└── Package/
    └── packageMetadata.json (Solution metadata)
```

---

## ✅ Final Checklist Before Go-Live

- [ ] Preview deployment successful
- [ ] All components working
- [ ] Data ingestion verified
- [ ] Documentation complete
- [ ] Support contacts updated
- [ ] Pricing confirmed (Free)
- [ ] Legal agreements signed
- [ ] Publisher verification complete

**Ready for Content Hub publication!** 🚀

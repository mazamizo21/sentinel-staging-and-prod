# Workbook serializedData Deployment Issue

**Date:** November 13, 2025 09:45 AM  
**Issue:** serializedData shows as 0 chars when queried via Azure REST API, despite being 4,640 chars in mainTemplate.json  
**Status:** ⚠️ INVESTIGATING

---

## Problem

### What's Happening
1. mainTemplate.json contains correct serializedData (4,640 characters)
2. Deployment succeeds without errors
3. Workbook resource is created in Azure
4. **BUT:** When queried via REST API, serializedData shows as 0 chars

### Verification

**Template Content:**
```powershell
$template = Get-Content "mainTemplate.json" | ConvertFrom-Json
$cyrenWb = $template.resources | Where-Object { $_.properties.displayName -eq "Cyren Threat Intelligence (Enhanced)" }
$cyrenWb.properties.serializedData.Length
# Result: 4640 chars ✓
```

**Deployed Workbook:**
```powershell
az rest --method GET --url "/subscriptions/.../workbooks/9305546c-32ec-5402-a7f4-4df4215a562f?api-version=2022-04-01"
# Result: serializedData.Length = 0 chars ✗
```

---

## Possible Causes

### 1. Azure API Response Limitation
- REST API might not return serializedData in GET response
- serializedData might be too large for API response
- Need to check workbook in Portal UI directly

### 2. JSON Escaping Issue
- serializedData might be incorrectly escaped
- Azure might be rejecting the content silently
- Need to validate JSON structure

### 3. API Version Issue
- API version 2022-04-01 might have limitations
- Try different API version

---

## Next Steps

### Step 1: Check Workbook in Portal UI
**Action:** Open workbook directly in Azure Portal  
**URL:** https://portal.azure.com → Sentinel → Workbooks → "Cyren Threat Intelligence (Enhanced)"

**If workbook shows content:**
- ✓ Deployment is successful
- ✓ REST API just doesn't return serializedData
- ✓ This is normal Azure behavior

**If workbook is blank:**
- ✗ Deployment failed to apply serializedData
- ✗ Need to investigate JSON escaping
- ✗ May need alternative deployment method

### Step 2: Try Direct REST API Creation
Instead of ARM template, try creating workbook directly via REST API:

```powershell
$workbookJson = Get-Content "mainTemplate.json" | ConvertFrom-Json -Depth 100
$cyrenWb = $workbookJson.resources | Where-Object { $_.properties.displayName -eq "Cyren Threat Intelligence (Enhanced)" }

$body = @{
    location = "eastus"
    kind = "shared"
    properties = @{
        displayName = "Cyren Threat Intelligence (Enhanced) - Direct"
        serializedData = $cyrenWb.properties.serializedData
        version = "1.0"
        sourceId = "/subscriptions/.../workspaces/SentinelThreatIntelWorkspace"
        category = "sentinel"
    }
} | ConvertTo-Json -Depth 100

az rest --method PUT \
  --url "/subscriptions/.../workbooks/[new-guid]?api-version=2022-04-01" \
  --body $body
```

### Step 3: Validate JSON Structure
Check if serializedData is valid JSON:

```powershell
$template = Get-Content "mainTemplate.json" | ConvertFrom-Json -Depth 100
$cyrenWb = $template.resources | Where-Object { $_.properties.displayName -eq "Cyren Threat Intelligence (Enhanced)" }
$serialized = $cyrenWb.properties.serializedData
$parsed = $serialized | ConvertFrom-Json
Write-Host "Items count: $($parsed.items.Count)"
Write-Host "Version: $($parsed.version)"
```

---

## Workaround

If ARM template deployment continues to fail, use PowerShell script to create workbook directly:

```powershell
# Read template
$template = Get-Content "mainTemplate.json" | ConvertFrom-Json -Depth 100
$cyrenWb = $template.resources | Where-Object { $_.properties.displayName -eq "Cyren Threat Intelligence (Enhanced)" }

# Create workbook via REST API
$workspaceId = "/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/SentinelTestStixImport/providers/Microsoft.OperationalInsights/workspaces/SentinelThreatIntelWorkspace"
$newGuid = [guid]::NewGuid().ToString()

$body = @{
    location = "eastus"
    kind = "shared"
    properties = @{
        displayName = "Cyren Threat Intelligence (Enhanced)"
        serializedData = $cyrenWb.properties.serializedData
        version = "1.0"
        sourceId = $workspaceId
        category = "sentinel"
    }
}

$bodyJson = $body | ConvertTo-Json -Depth 100
$bodyFile = [System.IO.Path]::GetTempFileName()
$bodyJson | Out-File -FilePath $bodyFile -Encoding UTF8

az rest --method PUT \
  --url "/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/SentinelTestStixImport/providers/Microsoft.Insights/workbooks/${newGuid}?api-version=2022-04-01" \
  --body @$bodyFile

Remove-Item $bodyFile
```

---

## Status

**Current:** Waiting for user to check workbook in Azure Portal UI

**If workbook shows content in Portal:**
- Issue is just REST API not returning serializedData
- Deployment is successful
- No further action needed

**If workbook is blank in Portal:**
- Need to use direct REST API creation workaround
- Or investigate JSON escaping issue further

---

**Investigation Date:** November 13, 2025 09:45 AM  
**Next Action:** User to check workbook in Portal UI

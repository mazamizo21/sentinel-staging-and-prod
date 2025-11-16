# ============================================================================
# Fix Cyren CCF Connector DCR ImmutableId
# ============================================================================
# This script fixes immutableId mismatches for both Cyren connectors
# Run this if connectors were deployed but not ingesting data
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceName = ""
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Fix Cyren CCF Connector ImmutableId ===" -ForegroundColor Cyan
Write-Host "This will update both Cyren connectors with correct DCR ImmutableIds`n" -ForegroundColor Yellow

# Prompt for parameters if not provided
if ([string]::IsNullOrEmpty($SubscriptionId)) {
    $SubscriptionId = Read-Host "Enter Subscription ID"
}

if ([string]::IsNullOrEmpty($ResourceGroupName)) {
    $ResourceGroupName = Read-Host "Enter Resource Group Name"
}

if ([string]::IsNullOrEmpty($WorkspaceName)) {
    $WorkspaceName = Read-Host "Enter Workspace Name"
}

Write-Host "`nConfiguration:" -ForegroundColor Cyan
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor White
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "  Workspace: $WorkspaceName`n" -ForegroundColor White

# Set subscription
Write-Host "Setting subscription..." -ForegroundColor Gray
az account set --subscription $SubscriptionId

$workspaceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"

# Fix IP Reputation Connector
Write-Host "`n--- Fixing IP Reputation Connector ---" -ForegroundColor Cyan

Write-Host "Reading actual DCR immutableId..." -ForegroundColor Gray
$ipDcrId = az monitor data-collection rule show `
    --resource-group $ResourceGroupName `
    --name "dcr-cyren-ip-reputation" `
    --query immutableId `
    --output tsv

if ([string]::IsNullOrEmpty($ipDcrId)) {
    Write-Host "❌ Failed to read IP Reputation DCR" -ForegroundColor Red
    exit 1
}

Write-Host "  Actual DCR ImmutableId: $ipDcrId" -ForegroundColor White

Write-Host "Reading current connector configuration..." -ForegroundColor Gray
$ipConnectorUri = "${workspaceId}/providers/Microsoft.SecurityInsights/dataConnectors/CyrenIPReputation?api-version=2023-02-01-preview"

try {
    $ipConnector = az rest --method GET --url $ipConnectorUri 2>$null | ConvertFrom-Json
    
    $currentIpDcrId = $ipConnector.properties.dcrConfig.dataCollectionRuleImmutableId
    Write-Host "  Current Connector ImmutableId: $currentIpDcrId" -ForegroundColor White
    
    if ($currentIpDcrId -eq $ipDcrId) {
        Write-Host "  ✅ ImmutableId already correct - no fix needed" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  ImmutableId mismatch detected - applying fix..." -ForegroundColor Yellow
        
        # Update immutableId
        $ipConnector.properties.dcrConfig.dataCollectionRuleImmutableId = $ipDcrId
        
        $ipConnectorJson = $ipConnector | ConvertTo-Json -Depth 10
        $ipConnectorJson | Out-File "temp-ip-connector.json" -Encoding UTF8
        
        az rest --method PUT --url $ipConnectorUri --body "@temp-ip-connector.json" 2>&1 | Out-Null
        
        Remove-Item "temp-ip-connector.json" -ErrorAction SilentlyContinue
        
        # Verify fix
        Start-Sleep -Seconds 3
        $verifyIp = az rest --method GET --url $ipConnectorUri | ConvertFrom-Json
        $newIpDcrId = $verifyIp.properties.dcrConfig.dataCollectionRuleImmutableId
        
        if ($newIpDcrId -eq $ipDcrId) {
            Write-Host "  ✅ IP Reputation connector fixed successfully" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Fix verification failed" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Fix Malware URLs Connector
Write-Host "`n--- Fixing Malware URLs Connector ---" -ForegroundColor Cyan

Write-Host "Reading actual DCR immutableId..." -ForegroundColor Gray
$malwareDcrId = az monitor data-collection rule show `
    --resource-group $ResourceGroupName `
    --name "dcr-cyren-malware-urls" `
    --query immutableId `
    --output tsv

if ([string]::IsNullOrEmpty($malwareDcrId)) {
    Write-Host "❌ Failed to read Malware URLs DCR" -ForegroundColor Red
    exit 1
}

Write-Host "  Actual DCR ImmutableId: $malwareDcrId" -ForegroundColor White

Write-Host "Reading current connector configuration..." -ForegroundColor Gray
$malwareConnectorUri = "${workspaceId}/providers/Microsoft.SecurityInsights/dataConnectors/CyrenMalwareURLs?api-version=2023-02-01-preview"

try {
    $malwareConnector = az rest --method GET --url $malwareConnectorUri 2>$null | ConvertFrom-Json
    
    $currentMalwareDcrId = $malwareConnector.properties.dcrConfig.dataCollectionRuleImmutableId
    Write-Host "  Current Connector ImmutableId: $currentMalwareDcrId" -ForegroundColor White
    
    if ($currentMalwareDcrId -eq $malwareDcrId) {
        Write-Host "  ✅ ImmutableId already correct - no fix needed" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  ImmutableId mismatch detected - applying fix..." -ForegroundColor Yellow
        
        # Update immutableId
        $malwareConnector.properties.dcrConfig.dataCollectionRuleImmutableId = $malwareDcrId
        
        $malwareConnectorJson = $malwareConnector | ConvertTo-Json -Depth 10
        $malwareConnectorJson | Out-File "temp-malware-connector.json" -Encoding UTF8
        
        az rest --method PUT --url $malwareConnectorUri --body "@temp-malware-connector.json" 2>&1 | Out-Null
        
        Remove-Item "temp-malware-connector.json" -ErrorAction SilentlyContinue
        
        # Verify fix
        Start-Sleep -Seconds 3
        $verifyMalware = az rest --method GET --url $malwareConnectorUri | ConvertFrom-Json
        $newMalwareDcrId = $verifyMalware.properties.dcrConfig.dataCollectionRuleImmutableId
        
        if ($newMalwareDcrId -eq $malwareDcrId) {
            Write-Host "  ✅ Malware URLs connector fixed successfully" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Fix verification failed" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Fix Complete ===" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Wait 60-90 minutes for first poll (connectors poll every 60 minutes)" -ForegroundColor White
Write-Host "2. Verify data ingestion with KQL:" -ForegroundColor White
Write-Host "   Cyren_Indicators_CL | summarize count() by bin(TimeGenerated, 1h)`n" -ForegroundColor Gray

Read-Host "Press Enter to exit"

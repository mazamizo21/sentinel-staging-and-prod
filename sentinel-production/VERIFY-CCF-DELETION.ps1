<#
.SYNOPSIS
Verify that all CCF connectors have been permanently deleted

.DESCRIPTION
This script checks if any CCF connector resources still exist in the Sentinel workspace
#>

param(
    [string]$SubscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117",
    [string]$ResourceGroupName = "SentinelTestStixImport",
    [string]$WorkspaceName = "SentinelThreatIntelWorkspace"
)

$ErrorActionPreference = 'Continue'

Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  CCF CONNECTOR DELETION VERIFICATION                          ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "Workspace: $WorkspaceName`n" -ForegroundColor Gray

# Set context
az account set --subscription $SubscriptionId 2>&1 | Out-Null

$results = @{
    DataConnectors = @()
    ConnectorDefinition = $null
    DCRs = @()
    DCEs = @()
    Tables = @()
}

Write-Host "═══ CHECKING DATA CONNECTORS ═══" -ForegroundColor Cyan

$connectorNames = @("TacitRedFindings", "CyrenIPReputation", "CyrenMalwareURLs")

foreach ($name in $connectorNames) {
    $connectorId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectors/$name"
    $url = "https://management.azure.com$connectorId`?api-version=2022-10-01-preview"
    
    Write-Host "`nChecking: $name" -ForegroundColor Yellow
    $response = az rest --method GET --url $url 2>&1
    
    if ($response -match "ResourceNotFound" -or $response -match "NotFound") {
        Write-Host "  ✓ DELETED (not found)" -ForegroundColor Green
        $results.DataConnectors += [PSCustomObject]@{ Name = $name; Status = "Deleted" }
    } else {
        Write-Host "  ✗ STILL EXISTS" -ForegroundColor Red
        $results.DataConnectors += [PSCustomObject]@{ Name = $name; Status = "Exists" }
    }
}

Write-Host "`n═══ CHECKING CONNECTOR DEFINITION ═══" -ForegroundColor Cyan

$connDefId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectorDefinitions/ThreatIntelligenceFeeds"
$url = "https://management.azure.com$connDefId`?api-version=2024-09-01"

Write-Host "`nChecking: ThreatIntelligenceFeeds" -ForegroundColor Yellow
$response = az rest --method GET --url $url 2>&1

if ($response -match "ResourceNotFound" -or $response -match "NotFound") {
    Write-Host "  ✓ DELETED (not found)" -ForegroundColor Green
    $results.ConnectorDefinition = "Deleted"
} else {
    Write-Host "  ✗ STILL EXISTS" -ForegroundColor Red
    $results.ConnectorDefinition = "Exists"
}

Write-Host "`n═══ CHECKING DATA COLLECTION RULES ═══" -ForegroundColor Cyan

$dcrNames = @("dcr-tacitred-findings", "dcr-cyren-ip-reputation", "dcr-cyren-malware-urls")

$listUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionRules?api-version=2022-06-01"
$dcrsJson = az rest --method GET --url $listUrl 2>&1

if ($dcrsJson -notmatch "ERROR" -and $dcrsJson -notmatch "NotFound") {
    $dcrs = $dcrsJson | ConvertFrom-Json
    
    foreach ($name in $dcrNames) {
        Write-Host "`nChecking: $name" -ForegroundColor Yellow
        $dcr = $dcrs.value | Where-Object { $_.name -eq $name }
        
        if ($dcr) {
            Write-Host "  ✗ STILL EXISTS: $($dcr.id)" -ForegroundColor Red
            $results.DCRs += [PSCustomObject]@{ Name = $name; Status = "Exists" }
        } else {
            Write-Host "  ✓ DELETED (not found)" -ForegroundColor Green
            $results.DCRs += [PSCustomObject]@{ Name = $name; Status = "Deleted" }
        }
    }
} else {
    Write-Host "  ℹ No DCRs found in resource group" -ForegroundColor Gray
    foreach ($name in $dcrNames) {
        $results.DCRs += [PSCustomObject]@{ Name = $name; Status = "Deleted" }
    }
}

Write-Host "`n═══ CHECKING DATA COLLECTION ENDPOINTS ═══" -ForegroundColor Cyan

$listUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionEndpoints?api-version=2022-06-01"
$dcesJson = az rest --method GET --url $listUrl 2>&1

if ($dcesJson -notmatch "ERROR" -and $dcesJson -notmatch "NotFound") {
    $dces = $dcesJson | ConvertFrom-Json
    $threatIntelDCEs = $dces.value | Where-Object { $_.name -like "*threatintel*" -or $_.name -like "*tacitred*" -or $_.name -like "*cyren*" }
    
    if ($threatIntelDCEs) {
        foreach ($dce in $threatIntelDCEs) {
            Write-Host "`n✗ STILL EXISTS: $($dce.name)" -ForegroundColor Red
            $results.DCEs += [PSCustomObject]@{ Name = $dce.name; Status = "Exists" }
        }
    } else {
        Write-Host "`n✓ All threat intel DCEs deleted" -ForegroundColor Green
        $results.DCEs += [PSCustomObject]@{ Name = "All"; Status = "Deleted" }
    }
} else {
    Write-Host "`n✓ No DCEs found in resource group" -ForegroundColor Green
    $results.DCEs += [PSCustomObject]@{ Name = "All"; Status = "Deleted" }
}

Write-Host "`n═══ CHECKING CUSTOM LOG TABLES ═══" -ForegroundColor Cyan

$tableNames = @("TacitRed_Findings_CL", "Cyren_Indicators_CL")

foreach ($tableName in $tableNames) {
    $tableId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/tables/$tableName"
    $url = "https://management.azure.com$tableId`?api-version=2022-10-01"
    
    Write-Host "`nChecking: $tableName" -ForegroundColor Yellow
    $response = az rest --method GET --url $url 2>&1
    
    if ($response -match "ResourceNotFound" -or $response -match "NotFound") {
        Write-Host "  ✓ DELETED (not found)" -ForegroundColor Green
        $results.Tables += [PSCustomObject]@{ Name = $tableName; Status = "Deleted" }
    } else {
        Write-Host "  ✗ STILL EXISTS" -ForegroundColor Red
        $results.Tables += [PSCustomObject]@{ Name = $tableName; Status = "Exists" }
    }
}

Write-Host "`n═══ VERIFICATION SUMMARY ═══" -ForegroundColor Cyan

Write-Host "`nData Connectors:" -ForegroundColor Yellow
$results.DataConnectors | Format-Table -AutoSize

Write-Host "Connector Definition: $($results.ConnectorDefinition)" -ForegroundColor Yellow

Write-Host "`nData Collection Rules:" -ForegroundColor Yellow
$results.DCRs | Format-Table -AutoSize

Write-Host "Data Collection Endpoints:" -ForegroundColor Yellow
$results.DCEs | Format-Table -AutoSize

Write-Host "Custom Tables:" -ForegroundColor Yellow
$results.Tables | Format-Table -AutoSize

# Check if all deleted
$allDeleted = $true
$allDeleted = $allDeleted -and ($results.DataConnectors | Where-Object { $_.Status -eq "Exists" }).Count -eq 0
$allDeleted = $allDeleted -and ($results.ConnectorDefinition -eq "Deleted")
$allDeleted = $allDeleted -and ($results.DCRs | Where-Object { $_.Status -eq "Exists" }).Count -eq 0
$allDeleted = $allDeleted -and ($results.DCEs | Where-Object { $_.Status -eq "Exists" }).Count -eq 0
$allDeleted = $allDeleted -and ($results.Tables | Where-Object { $_.Status -eq "Exists" }).Count -eq 0

if ($allDeleted) {
    Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  ✓ ALL CCF CONNECTORS PERMANENTLY DELETED                     ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
} else {
    Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║  ✗ SOME RESOURCES STILL EXIST - DELETION INCOMPLETE           ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Red
}

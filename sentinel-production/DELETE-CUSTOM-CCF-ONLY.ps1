<#
.SYNOPSIS
Delete ONLY custom CCF connectors (TacitRed, Cyren) - NOT native Microsoft connectors

.DESCRIPTION
This script removes resource locks and deletes only custom CCF connectors.
It preserves all native Microsoft connectors like Defender, Microsoft 365, etc.

.NOTES
Author: Security Engineer
Date: 2025-11-13
#>

param(
    [string]$SubscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117",
    [string]$ResourceGroupName = "SentinelTestStixImport",
    [string]$WorkspaceName = "SentinelThreatIntelWorkspace"
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Create log directory
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = "d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production\Project\Docs\custom-ccf-deletion-$timestamp"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Start-Transcript -Path "$logDir\deletion-transcript.log"

Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  DELETE CUSTOM CCF CONNECTORS ONLY (Preserve Native)         ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "Workspace: $WorkspaceName`n" -ForegroundColor Gray

# Set context
az account set --subscription $SubscriptionId 2>&1 | Out-Null

# Custom CCF identifiers (only these will be deleted)
$customCCFPatterns = @(
    "*tacitred*",
    "*cyren*",
    "*ThreatIntelligenceFeeds*",
    "*Compromised*Credentials*"
)

$results = @{
    LocksRemoved = @()
    DataConnectors = @()
    ConnectorDefinitions = @()
    DCRs = @()
    DCEs = @()
    Tables = @()
}

Write-Host "═══ PHASE 1: REMOVE RESOURCE LOCKS ═══" -ForegroundColor Cyan

# Check for locks on resource group
Write-Host "`nChecking resource group locks..." -ForegroundColor Yellow
$rgLocks = az lock list --resource-group $ResourceGroupName 2>&1 | ConvertFrom-Json

if ($rgLocks -and $rgLocks.Count -gt 0) {
    foreach ($lock in $rgLocks) {
        Write-Host "  Found lock: $($lock.name) (Type: $($lock.level))" -ForegroundColor Yellow
        
        try {
            az lock delete --name $lock.name --resource-group $ResourceGroupName 2>&1 | Out-Null
            Write-Host "  ✓ Removed lock: $($lock.name)" -ForegroundColor Green
            $results.LocksRemoved += [PSCustomObject]@{
                Name = $lock.name
                Type = $lock.level
                Status = "Removed"
            }
        } catch {
            Write-Host "  ✗ Failed to remove lock: $($lock.name) - $_" -ForegroundColor Red
            $results.LocksRemoved += [PSCustomObject]@{
                Name = $lock.name
                Type = $lock.level
                Status = "Failed"
                Error = $_.Exception.Message
            }
        }
    }
} else {
    Write-Host "  ℹ No resource group locks found" -ForegroundColor Gray
}

# Check for locks on workspace
Write-Host "`nChecking workspace locks..." -ForegroundColor Yellow
$wsLocks = az lock list --resource $WorkspaceName --resource-group $ResourceGroupName --resource-type "Microsoft.OperationalInsights/workspaces" 2>&1

if ($wsLocks -and $wsLocks -ne "[]") {
    $wsLocksJson = $wsLocks | ConvertFrom-Json
    foreach ($lock in $wsLocksJson) {
        Write-Host "  Found workspace lock: $($lock.name) (Type: $($lock.level))" -ForegroundColor Yellow
        
        try {
            az lock delete --ids $lock.id 2>&1 | Out-Null
            Write-Host "  ✓ Removed workspace lock: $($lock.name)" -ForegroundColor Green
            $results.LocksRemoved += [PSCustomObject]@{
                Name = $lock.name
                Type = $lock.level
                Resource = "Workspace"
                Status = "Removed"
            }
        } catch {
            Write-Host "  ✗ Failed to remove workspace lock: $($lock.name) - $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  ℹ No workspace locks found" -ForegroundColor Gray
}

Start-Sleep -Seconds 3

Write-Host "`n═══ PHASE 2: IDENTIFY CUSTOM CCF CONNECTORS ═══" -ForegroundColor Cyan

# Get all connector definitions
$defUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectorDefinitions?api-version=2024-09-01"
$allDefs = az rest --method GET --url $defUrl 2>&1 | ConvertFrom-Json

Write-Host "`nAll Connector Definitions:" -ForegroundColor Yellow
$customDefs = @()

foreach ($def in $allDefs.value) {
    $isCustom = $false
    foreach ($pattern in $customCCFPatterns) {
        if ($def.name -like $pattern -or $def.properties.connectorUiConfig.title -like $pattern) {
            $isCustom = $true
            break
        }
    }
    
    if ($isCustom) {
        Write-Host "  🎯 CUSTOM CCF: $($def.name)" -ForegroundColor Red
        $customDefs += $def
    } else {
        Write-Host "  ✓ Native (Keep): $($def.name)" -ForegroundColor Green
    }
}

# Get all data connectors
$connUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2022-10-01-preview"
$allConnectors = az rest --method GET --url $connUrl 2>&1 | ConvertFrom-Json

Write-Host "`nAll Data Connectors:" -ForegroundColor Yellow
$customConnectors = @()

foreach ($conn in $allConnectors.value) {
    $isCustom = $false
    $connDefName = $conn.properties.connectorDefinitionName
    
    # Check if this connector uses a custom definition
    foreach ($pattern in $customCCFPatterns) {
        if ($conn.name -like $pattern -or $connDefName -like $pattern) {
            $isCustom = $true
            break
        }
    }
    
    if ($isCustom) {
        Write-Host "  🎯 CUSTOM CCF: $($conn.name) (Def: $connDefName)" -ForegroundColor Red
        $customConnectors += $conn
    } else {
        Write-Host "  ✓ Native (Keep): $($conn.name) (Kind: $($conn.kind))" -ForegroundColor Green
    }
}

Write-Host "`n═══ PHASE 3: DELETE CUSTOM DATA CONNECTORS ═══" -ForegroundColor Cyan

foreach ($conn in $customConnectors) {
    Write-Host "`nDeleting custom connector: $($conn.name)" -ForegroundColor Yellow
    
    try {
        $deleteUrl = "https://management.azure.com$($conn.id)?api-version=2022-10-01-preview"
        az rest --method DELETE --url $deleteUrl 2>&1 | Out-File "$logDir\delete-connector-$($conn.name).log"
        
        Start-Sleep -Seconds 2
        $verify = az rest --method GET --url $deleteUrl 2>&1
        
        if ($verify -match "ResourceNotFound" -or $verify -match "NotFound") {
            Write-Host "  ✓ Successfully deleted: $($conn.name)" -ForegroundColor Green
            $results.DataConnectors += [PSCustomObject]@{
                Name = $conn.name
                Status = "Deleted"
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        } else {
            Write-Host "  ⚠ May still exist: $($conn.name)" -ForegroundColor Yellow
            $results.DataConnectors += [PSCustomObject]@{
                Name = $conn.name
                Status = "DeleteRequested"
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    } catch {
        Write-Host "  ✗ Failed to delete: $($conn.name) - $_" -ForegroundColor Red
        $results.DataConnectors += [PSCustomObject]@{
            Name = $conn.name
            Status = "Failed"
            Error = $_.Exception.Message
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

Write-Host "`n═══ PHASE 4: DELETE CUSTOM CONNECTOR DEFINITIONS ═══" -ForegroundColor Cyan

foreach ($def in $customDefs) {
    Write-Host "`nDeleting custom definition: $($def.name)" -ForegroundColor Yellow
    
    try {
        $deleteUrl = "https://management.azure.com$($def.id)?api-version=2024-09-01"
        az rest --method DELETE --url $deleteUrl 2>&1 | Out-File "$logDir\delete-definition-$($def.name).log"
        
        Start-Sleep -Seconds 2
        $verify = az rest --method GET --url $deleteUrl 2>&1
        
        if ($verify -match "ResourceNotFound" -or $verify -match "NotFound") {
            Write-Host "  ✓ Successfully deleted: $($def.name)" -ForegroundColor Green
            $results.ConnectorDefinitions += [PSCustomObject]@{
                Name = $def.name
                Status = "Deleted"
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        } else {
            Write-Host "  ⚠ May still exist: $($def.name)" -ForegroundColor Yellow
            $results.ConnectorDefinitions += [PSCustomObject]@{
                Name = $def.name
                Status = "DeleteRequested"
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    } catch {
        Write-Host "  ✗ Failed to delete: $($def.name) - $_" -ForegroundColor Red
        $results.ConnectorDefinitions += [PSCustomObject]@{
            Name = $def.name
            Status = "Failed"
            Error = $_.Exception.Message
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

Write-Host "`n═══ PHASE 5: DELETE CUSTOM DCRs ═══" -ForegroundColor Cyan

$dcrListUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionRules?api-version=2022-06-01"
$allDCRs = az rest --method GET --url $dcrListUrl 2>&1 | ConvertFrom-Json

Write-Host "`nSearching for custom CCF DCRs..." -ForegroundColor Yellow

foreach ($dcr in $allDCRs.value) {
    $isCustom = $false
    foreach ($pattern in $customCCFPatterns) {
        if ($dcr.name -like $pattern) {
            $isCustom = $true
            break
        }
    }
    
    if ($isCustom) {
        Write-Host "  🎯 Custom DCR: $($dcr.name)" -ForegroundColor Red
        
        try {
            $deleteUrl = "https://management.azure.com$($dcr.id)?api-version=2022-06-01"
            az rest --method DELETE --url $deleteUrl 2>&1 | Out-File "$logDir\delete-dcr-$($dcr.name).log"
            
            Start-Sleep -Seconds 2
            Write-Host "  ✓ Deleted: $($dcr.name)" -ForegroundColor Green
            $results.DCRs += [PSCustomObject]@{
                Name = $dcr.name
                Status = "Deleted"
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        } catch {
            Write-Host "  ✗ Failed: $($dcr.name) - $_" -ForegroundColor Red
            $results.DCRs += [PSCustomObject]@{
                Name = $dcr.name
                Status = "Failed"
                Error = $_.Exception.Message
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    }
}

Write-Host "`n═══ PHASE 6: DELETE CUSTOM DCEs ═══" -ForegroundColor Cyan

$dceListUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionEndpoints?api-version=2022-06-01"
$allDCEs = az rest --method GET --url $dceListUrl 2>&1 | ConvertFrom-Json

Write-Host "`nSearching for custom CCF DCEs..." -ForegroundColor Yellow

foreach ($dce in $allDCEs.value) {
    $isCustom = $false
    foreach ($pattern in $customCCFPatterns) {
        if ($dce.name -like $pattern) {
            $isCustom = $true
            break
        }
    }
    
    if ($isCustom) {
        Write-Host "  🎯 Custom DCE: $($dce.name)" -ForegroundColor Red
        
        try {
            $deleteUrl = "https://management.azure.com$($dce.id)?api-version=2022-06-01"
            az rest --method DELETE --url $deleteUrl 2>&1 | Out-File "$logDir\delete-dce-$($dce.name).log"
            
            Start-Sleep -Seconds 2
            Write-Host "  ✓ Deleted: $($dce.name)" -ForegroundColor Green
            $results.DCEs += [PSCustomObject]@{
                Name = $dce.name
                Status = "Deleted"
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        } catch {
            Write-Host "  ✗ Failed: $($dce.name) - $_" -ForegroundColor Red
            $results.DCEs += [PSCustomObject]@{
                Name = $dce.name
                Status = "Failed"
                Error = $_.Exception.Message
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    }
}

Write-Host "`n═══ PHASE 7: DELETE CUSTOM TABLES ═══" -ForegroundColor Cyan

$customTables = @("TacitRed_Findings_CL", "Cyren_Indicators_CL")

foreach ($tableName in $customTables) {
    Write-Host "`nDeleting custom table: $tableName" -ForegroundColor Yellow
    
    try {
        $tableId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/tables/$tableName"
        $deleteUrl = "https://management.azure.com$tableId`?api-version=2022-10-01"
        
        az rest --method DELETE --url $deleteUrl 2>&1 | Out-File "$logDir\delete-table-$tableName.log"
        
        Start-Sleep -Seconds 2
        Write-Host "  ✓ Deleted: $tableName" -ForegroundColor Green
        $results.Tables += [PSCustomObject]@{
            Name = $tableName
            Status = "Deleted"
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    } catch {
        if ($_.Exception.Message -match "NotFound") {
            Write-Host "  ℹ Already deleted: $tableName" -ForegroundColor Gray
            $results.Tables += [PSCustomObject]@{
                Name = $tableName
                Status = "NotFound"
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        } else {
            Write-Host "  ✗ Failed: $tableName - $_" -ForegroundColor Red
            $results.Tables += [PSCustomObject]@{
                Name = $tableName
                Status = "Failed"
                Error = $_.Exception.Message
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    }
}

Write-Host "`n═══ DELETION SUMMARY ═══" -ForegroundColor Cyan

if ($results.LocksRemoved.Count -gt 0) {
    Write-Host "`nLocks Removed:" -ForegroundColor Yellow
    $results.LocksRemoved | Format-Table -AutoSize
}

if ($results.DataConnectors.Count -gt 0) {
    Write-Host "`nData Connectors:" -ForegroundColor Yellow
    $results.DataConnectors | Format-Table -AutoSize
}

if ($results.ConnectorDefinitions.Count -gt 0) {
    Write-Host "`nConnector Definitions:" -ForegroundColor Yellow
    $results.ConnectorDefinitions | Format-Table -AutoSize
}

if ($results.DCRs.Count -gt 0) {
    Write-Host "`nData Collection Rules:" -ForegroundColor Yellow
    $results.DCRs | Format-Table -AutoSize
}

if ($results.DCEs.Count -gt 0) {
    Write-Host "`nData Collection Endpoints:" -ForegroundColor Yellow
    $results.DCEs | Format-Table -AutoSize
}

if ($results.Tables.Count -gt 0) {
    Write-Host "`nCustom Tables:" -ForegroundColor Yellow
    $results.Tables | Format-Table -AutoSize
}

# Save results
$results | ConvertTo-Json -Depth 10 | Out-File "$logDir\deletion-results.json"

Write-Host "`n✓ Deletion complete. Logs saved to: $logDir" -ForegroundColor Green

Stop-Transcript

Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✓ CUSTOM CCF CONNECTORS DELETED (Native Preserved)          ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

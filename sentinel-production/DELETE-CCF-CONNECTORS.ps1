<#
.SYNOPSIS
Permanently delete TacitRed and Cyren CCF connectors from Microsoft Sentinel

.DESCRIPTION
This script deletes all CCF connectors (TacitRed and Cyren) by their resource IDs.
It ensures complete removal including:
- Data Connector Definitions
- Data Connectors (TacitRedFindings, CyrenIPReputation, CyrenMalwareURLs)
- Associated DCRs (Data Collection Rules)
- Associated DCE (Data Collection Endpoint)
- Custom Log Tables

.NOTES
Author: Security Engineer
Date: 2025-11-13
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "SentinelTestStixImport",
    
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceName = "SentinelThreatIntelWorkspace"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Create log directory
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = "d:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-production\Project\Docs\ccf-deletion-$timestamp"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

# Start transcript
Start-Transcript -Path "$logDir\deletion-transcript.log"

Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  CCF CONNECTOR PERMANENT DELETION SCRIPT                      ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Get Azure context
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "No Azure context found. Logging in..." -ForegroundColor Yellow
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    # Use provided or default values - no prompts
    Write-Host "Using configuration:" -ForegroundColor Yellow
    Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Gray
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
    Write-Host "  Workspace: $WorkspaceName" -ForegroundColor Gray
    
    Write-Host "✓ Azure Context:" -ForegroundColor Green
    Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Gray
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
    Write-Host "  Workspace: $WorkspaceName`n" -ForegroundColor Gray
    
} catch {
    Write-Host "✗ Failed to get Azure context: $_" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Set subscription context
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

# Define connector names and IDs
$connectorDefinitionName = "ThreatIntelligenceFeeds"
$dataConnectorNames = @(
    "TacitRedFindings",
    "CyrenIPReputation", 
    "CyrenMalwareURLs"
)

$dcrNames = @(
    "dcr-tacitred-findings",
    "dcr-cyren-ip-reputation",
    "dcr-cyren-malware-urls"
)

$dceName = "dce-threatintel-feeds"

$customTables = @(
    "TacitRed_Findings_CL",
    "Cyren_Indicators_CL"
)

# Results tracking
$results = @{
    DataConnectors = @()
    ConnectorDefinition = $null
    DCRs = @()
    DCE = $null
    Tables = @()
}

Write-Host "`n═══ PHASE 1: DELETE DATA CONNECTORS ═══" -ForegroundColor Cyan

foreach ($connectorName in $dataConnectorNames) {
    Write-Host "`nDeleting data connector: $connectorName" -ForegroundColor Yellow
    
    try {
        # Build resource ID
        $connectorId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectors/$connectorName"
        
        Write-Host "  Resource ID: $connectorId" -ForegroundColor Gray
        
        # Check if connector exists
        $checkUrl = "https://management.azure.com$connectorId`?api-version=2022-10-01-preview"
        
        try {
            $existingJson = az rest --method GET --url $checkUrl 2>&1
            $existing = $existingJson | ConvertFrom-Json
            
            if ($existing) {
                Write-Host "  ✓ Connector found, proceeding with deletion..." -ForegroundColor Yellow
                
                # Delete the connector
                $deleteUrl = "https://management.azure.com$connectorId`?api-version=2022-10-01-preview"
                az rest --method DELETE --url $deleteUrl 2>&1 | Out-File "$logDir\delete-$connectorName.log"
                
                # Verify deletion
                Start-Sleep -Seconds 3
                try {
                    $verify = az rest --method GET --url $checkUrl 2>&1
                    if ($verify -match "ResourceNotFound" -or $verify -match "NotFound") {
                        Write-Host "  ✓ Successfully deleted: $connectorName" -ForegroundColor Green
                        $results.DataConnectors += [PSCustomObject]@{
                            Name = $connectorName
                            Status = "Deleted"
                            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                        }
                    } else {
                        throw "Connector still exists after deletion"
                    }
                } catch {
                    if ($_.Exception.Message -match "ResourceNotFound" -or $_.Exception.Message -match "NotFound") {
                        Write-Host "  ✓ Successfully deleted: $connectorName" -ForegroundColor Green
                        $results.DataConnectors += [PSCustomObject]@{
                            Name = $connectorName
                            Status = "Deleted"
                            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                        }
                    } else {
                        throw $_
                    }
                }
            }
        } catch {
            if ($_.Exception.Message -match "ResourceNotFound" -or $_.Exception.Message -match "NotFound") {
                Write-Host "  ℹ Connector not found (already deleted): $connectorName" -ForegroundColor Gray
                $results.DataConnectors += [PSCustomObject]@{
                    Name = $connectorName
                    Status = "NotFound"
                    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
            } else {
                throw $_
            }
        }
        
    } catch {
        Write-Host "  ✗ Failed to delete $connectorName : $_" -ForegroundColor Red
        $results.DataConnectors += [PSCustomObject]@{
            Name = $connectorName
            Status = "Failed"
            Error = $_.Exception.Message
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

Write-Host "`n═══ PHASE 2: DELETE CONNECTOR DEFINITION ═══" -ForegroundColor Cyan

try {
    Write-Host "`nDeleting connector definition: $connectorDefinitionName" -ForegroundColor Yellow
    
    $connDefId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectorDefinitions/$connectorDefinitionName"
    
    Write-Host "  Resource ID: $connDefId" -ForegroundColor Gray
    
    $checkUrl = "https://management.azure.com$connDefId`?api-version=2024-09-01"
    
    try {
        $existing = az rest --method GET --url $checkUrl 2>&1 | ConvertFrom-Json
        
        if ($existing) {
            Write-Host "  ✓ Connector definition found, proceeding with deletion..." -ForegroundColor Yellow
            
            $deleteUrl = "https://management.azure.com$connDefId`?api-version=2024-09-01"
            az rest --method DELETE --url $deleteUrl 2>&1 | Out-File "$logDir\delete-connector-definition.log"
            
            Start-Sleep -Seconds 3
            try {
                $verify = az rest --method GET --url $checkUrl 2>&1
                if ($verify -match "ResourceNotFound" -or $verify -match "NotFound") {
                    Write-Host "  ✓ Successfully deleted connector definition" -ForegroundColor Green
                    $results.ConnectorDefinition = "Deleted"
                } else {
                    throw "Connector definition still exists after deletion"
                }
            } catch {
                if ($_.Exception.Message -match "ResourceNotFound" -or $_.Exception.Message -match "NotFound") {
                    Write-Host "  ✓ Successfully deleted connector definition" -ForegroundColor Green
                    $results.ConnectorDefinition = "Deleted"
                } else {
                    throw $_
                }
            }
        }
    } catch {
        if ($_.Exception.Message -match "ResourceNotFound" -or $_.Exception.Message -match "NotFound") {
            Write-Host "  ℹ Connector definition not found (already deleted)" -ForegroundColor Gray
            $results.ConnectorDefinition = "NotFound"
        } else {
            throw $_
        }
    }
    
} catch {
    Write-Host "  ✗ Failed to delete connector definition: $_" -ForegroundColor Red
    $results.ConnectorDefinition = "Failed: $($_.Exception.Message)"
}

Write-Host "`n═══ PHASE 3: DELETE DATA COLLECTION RULES (DCRs) ═══" -ForegroundColor Cyan

foreach ($dcrName in $dcrNames) {
    Write-Host "`nDeleting DCR: $dcrName" -ForegroundColor Yellow
    
    try {
        # List all DCRs and find matching one
        $listUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionRules?api-version=2022-06-01"
        $dcrsJson = az rest --method GET --url $listUrl 2>&1
        $dcrs = $dcrsJson | ConvertFrom-Json
        $dcr = $dcrs.value | Where-Object { $_.name -eq $dcrName }
        
        if ($dcr) {
            Write-Host "  ✓ DCR found: $($dcr.id)" -ForegroundColor Yellow
            
            $deleteUrl = "https://management.azure.com$($dcr.id)?api-version=2022-06-01"
            az rest --method DELETE --url $deleteUrl 2>&1 | Out-File "$logDir\delete-dcr-$dcrName.log"
            
            Start-Sleep -Seconds 3
            $verifyJson = az rest --method GET --url $deleteUrl 2>&1
            
            if ($verifyJson -match "ResourceNotFound" -or $verifyJson -match "NotFound") {
                Write-Host "  ✓ Successfully deleted DCR: $dcrName" -ForegroundColor Green
                $results.DCRs += [PSCustomObject]@{
                    Name = $dcrName
                    Status = "Deleted"
                    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
            } else {
                Write-Host "  ⚠ DCR may still exist: $dcrName" -ForegroundColor Yellow
                $results.DCRs += [PSCustomObject]@{
                    Name = $dcrName
                    Status = "DeleteRequested"
                    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
            }
        } else {
            Write-Host "  ℹ DCR not found (already deleted): $dcrName" -ForegroundColor Gray
            $results.DCRs += [PSCustomObject]@{
                Name = $dcrName
                Status = "NotFound"
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
        
    } catch {
        Write-Host "  ✗ Failed to delete DCR $dcrName : $_" -ForegroundColor Red
        $results.DCRs += [PSCustomObject]@{
            Name = $dcrName
            Status = "Failed"
            Error = $_.Exception.Message
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

Write-Host "`n═══ PHASE 4: DELETE DATA COLLECTION ENDPOINT (DCE) ═══" -ForegroundColor Cyan

try {
    Write-Host "`nSearching for DCE: $dceName" -ForegroundColor Yellow
    
    # List all DCEs and find matching ones
    $listUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionEndpoints?api-version=2022-06-01"
    $dcesJson = az rest --method GET --url $listUrl 2>&1
    $dces = $dcesJson | ConvertFrom-Json
    $matchingDCE = $dces.value | Where-Object { $_.name -like "*$dceName*" -or $_.name -like "*threatintel*" }
    
    if ($matchingDCE) {
        foreach ($dce in $matchingDCE) {
            Write-Host "  ✓ DCE found: $($dce.name)" -ForegroundColor Yellow
            
            $deleteUrl = "https://management.azure.com$($dce.id)?api-version=2022-06-01"
            az rest --method DELETE --url $deleteUrl 2>&1 | Out-File "$logDir\delete-dce-$($dce.name).log"
            
            Start-Sleep -Seconds 3
            $verifyJson = az rest --method GET --url $deleteUrl 2>&1
            
            if ($verifyJson -match "ResourceNotFound" -or $verifyJson -match "NotFound") {
                Write-Host "  ✓ Successfully deleted DCE: $($dce.name)" -ForegroundColor Green
                $results.DCE = "Deleted: $($dce.name)"
            } else {
                Write-Host "  ⚠ DCE may still exist: $($dce.name)" -ForegroundColor Yellow
                $results.DCE = "DeleteRequested: $($dce.name)"
            }
        }
    } else {
        Write-Host "  ℹ DCE not found (already deleted)" -ForegroundColor Gray
        $results.DCE = "NotFound"
    }
    
} catch {
    Write-Host "  ✗ Failed to delete DCE: $_" -ForegroundColor Red
    $results.DCE = "Failed: $($_.Exception.Message)"
}

Write-Host "`n═══ PHASE 5: DELETE CUSTOM LOG TABLES ═══" -ForegroundColor Cyan

foreach ($tableName in $customTables) {
    Write-Host "`nDeleting custom table: $tableName" -ForegroundColor Yellow
    
    try {
        $tableId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/tables/$tableName"
        
        Write-Host "  Resource ID: $tableId" -ForegroundColor Gray
        
        $checkUrl = "https://management.azure.com$tableId`?api-version=2022-10-01"
        
        try {
            $existing = az rest --method GET --url $checkUrl 2>&1 | ConvertFrom-Json
            
            if ($existing) {
                Write-Host "  ✓ Table found, proceeding with deletion..." -ForegroundColor Yellow
                
                $deleteUrl = "https://management.azure.com$tableId`?api-version=2022-10-01"
                az rest --method DELETE --url $deleteUrl 2>&1 | Out-File "$logDir\delete-table-$tableName.log"
                
                Start-Sleep -Seconds 3
                try {
                    $verify = az rest --method GET --url $checkUrl 2>&1
                    if ($verify -match "ResourceNotFound" -or $verify -match "NotFound") {
                        Write-Host "  ✓ Successfully deleted table: $tableName" -ForegroundColor Green
                        $results.Tables += [PSCustomObject]@{
                            Name = $tableName
                            Status = "Deleted"
                            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                        }
                    } else {
                        Write-Host "  ⚠ Table may still exist (soft delete): $tableName" -ForegroundColor Yellow
                        $results.Tables += [PSCustomObject]@{
                            Name = $tableName
                            Status = "SoftDeleted"
                            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                        }
                    }
                } catch {
                    if ($_.Exception.Message -match "ResourceNotFound" -or $_.Exception.Message -match "NotFound") {
                        Write-Host "  ✓ Successfully deleted table: $tableName" -ForegroundColor Green
                        $results.Tables += [PSCustomObject]@{
                            Name = $tableName
                            Status = "Deleted"
                            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                        }
                    } else {
                        throw $_
                    }
                }
            }
        } catch {
            if ($_.Exception.Message -match "ResourceNotFound" -or $_.Exception.Message -match "NotFound") {
                Write-Host "  ℹ Table not found (already deleted): $tableName" -ForegroundColor Gray
                $results.Tables += [PSCustomObject]@{
                    Name = $tableName
                    Status = "NotFound"
                    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
            } else {
                throw $_
            }
        }
        
    } catch {
        Write-Host "  ✗ Failed to delete table $tableName : $_" -ForegroundColor Red
        $results.Tables += [PSCustomObject]@{
            Name = $tableName
            Status = "Failed"
            Error = $_.Exception.Message
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

Write-Host "`n═══ DELETION SUMMARY ═══" -ForegroundColor Cyan

Write-Host "`nData Connectors:" -ForegroundColor Yellow
$results.DataConnectors | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "Connector Definition: $($results.ConnectorDefinition)" -ForegroundColor Yellow

Write-Host "`nData Collection Rules:" -ForegroundColor Yellow
$results.DCRs | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "Data Collection Endpoint: $($results.DCE)" -ForegroundColor Yellow

Write-Host "`nCustom Tables:" -ForegroundColor Yellow
$results.Tables | Format-Table -AutoSize | Out-String | Write-Host

# Save results to JSON
$results | ConvertTo-Json -Depth 10 | Out-File "$logDir\deletion-results.json"

Write-Host "`n✓ Deletion complete. All logs saved to: $logDir" -ForegroundColor Green

Stop-Transcript

Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  CCF CONNECTORS PERMANENTLY DELETED                           ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

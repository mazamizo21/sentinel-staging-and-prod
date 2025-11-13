# Diagnostic Script for DCR Authentication Issues
# This script helps diagnose and fix authentication issues with Data Collection Rules

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = 'd:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-staging\client-config-COMPLETE.json',
    
    [Parameter(Mandatory=$false)]
    [string]$DcrImmutableId = ''  # Will auto-detect if not specified
)

# Ensure script runs from correct directory
$ScriptDir = Split-Path -Parent $PSCommandPath
Set-Location $ScriptDir
Write-Host "Working directory: $ScriptDir" -ForegroundColor Gray

$ErrorActionPreference = "Stop"

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          DCR AUTHENTICATION DIAGNOSTIC TOOL                 ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Load configuration
if (Test-Path $ConfigFile) {
    $config = (Get-Content $ConfigFile | ConvertFrom-Json).parameters
    $sub = $config.azure.value.subscriptionId
    $rg = $config.azure.value.resourceGroupName
    $ws = $config.azure.value.workspaceName
    $loc = $config.azure.value.location
    Write-Host "✓ Configuration loaded from: $ConfigFile" -ForegroundColor Green
    Write-Host "  Subscription: $sub" -ForegroundColor Gray
    Write-Host "  Resource Group: $rg" -ForegroundColor Gray
    Write-Host "  Workspace: $ws" -ForegroundColor Gray
} else {
    Write-Host "✗ Configuration file not found: $ConfigFile" -ForegroundColor Red
    Write-Host "Please provide a valid configuration file path." -ForegroundColor Red
    exit 1
}

# Set subscription context
Write-Host "`n═══ PHASE 1: AZURE CONTEXT ═══" -ForegroundColor Cyan
az account set --subscription $sub
Write-Host "✓ Azure context set to subscription: $sub" -ForegroundColor Green

# Get DCR details
Write-Host "`n═══ PHASE 2: DCR DETAILS ═══" -ForegroundColor Cyan
try {
    $dcrList = az monitor data-collection rule list --resource-group $rg -o json | ConvertFrom-Json
    
    # If DcrImmutableId is not specified, try to find the TacitRed DCR
    if ([string]::IsNullOrEmpty($DcrImmutableId)) {
        $dcr = $dcrList | Where-Object { $_.name -like "*tacitred*" -or $_.name -like "*findings*" }
        if ($dcr) {
            $DcrImmutableId = $dcr.properties.immutableId
            Write-Host "✓ Auto-detected TacitRed DCR: $($dcr.name)" -ForegroundColor Green
        } else {
            # If no TacitRed DCR found, use the first available DCR
            if ($dcrList.Count -gt 0) {
                $dcr = $dcrList[0]
                $DcrImmutableId = $dcr.properties.immutableId
                Write-Host "⚠ No TacitRed DCR found, using first available DCR: $($dcr.name)" -ForegroundColor Yellow
            } else {
                Write-Host "✗ No DCRs found in resource group '$rg'" -ForegroundColor Red
                exit 1
            }
        }
    } else {
        # Use the specified DcrImmutableId
        $dcr = $dcrList | Where-Object { $_.properties.immutableId -eq $DcrImmutableId }
        if (-not $dcr) {
            Write-Host "✗ DCR with immutable ID '$DcrImmutableId' not found in resource group '$rg'" -ForegroundColor Red
            Write-Host "Available DCRs:" -ForegroundColor Yellow
            $dcrList | ForEach-Object {
                Write-Host "  - $($_.name) (Immutable ID: $($_.properties.immutableId))" -ForegroundColor Gray
            }
            exit 1
        }
    }
    
    Write-Host "✓ Found DCR with immutable ID: $DcrImmutableId" -ForegroundColor Green
    Write-Host "  DCR Name: $($dcr.name)" -ForegroundColor Gray
    Write-Host "  DCR ID: $($dcr.id)" -ForegroundColor Gray
    Write-Host "  DCR Location: $($dcr.location)" -ForegroundColor Gray
    
    if ($dcr.properties.dataCollectionEndpointId) {
        Write-Host "  DCE ID: $($dcr.properties.dataCollectionEndpointId)" -ForegroundColor Gray
        $dceName = ($dcr.properties.dataCollectionEndpointId -split '/')[-1]
    } else {
        Write-Host "  ⚠ No DCE associated with this DCR" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Error retrieving DCR details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Get DCE details if available
$dceEndpoint = ""
if ($dceName) {
    try {
        $dce = az monitor data-collection endpoint show --name $dceName --resource-group $rg -o json | ConvertFrom-Json
        $dceEndpoint = $dce.properties.logsIngestion.endpoint
        Write-Host "✓ DCE Endpoint: $dceEndpoint" -ForegroundColor Green
    } catch {
        Write-Host "✗ Error retrieving DCE details: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Check Logic Apps and their managed identities
Write-Host "`n═══ PHASE 3: LOGIC APPS AND MANAGED IDENTITIES ═══" -ForegroundColor Cyan
$logicApps = @(
    'logic-cyren-ip-reputation',
    'logic-cyren-malware-urls',
    'logic-tacitred-ingestion'
)

$logicAppDetails = @()
foreach ($laName in $logicApps) {
    try {
        $la = az logic workflow show --resource-group $rg --name $laName -o json | ConvertFrom-Json
        if ($la) {
            $principalId = $la.identity.principalId
            $logicAppDetails += @{
                Name = $laName
                PrincipalId = $principalId
                State = $la.properties.state
                Id = $la.id
            }
            Write-Host "✓ Logic App: $laName" -ForegroundColor Green
            Write-Host "  Principal ID: $principalId" -ForegroundColor Gray
            Write-Host "  State: $($la.properties.state)" -ForegroundColor Gray
        } else {
            Write-Host "✗ Logic App not found: $laName" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ Error checking Logic App '$laName': $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Check RBAC assignments
Write-Host "`n═══ PHASE 4: RBAC ASSIGNMENTS ═══" -ForegroundColor Cyan
$monitoringMetricsPublisherRole = "3913510d-42f4-4e42-8a64-420c390055eb"

foreach ($la in $logicAppDetails) {
    if ($la.PrincipalId) {
        Write-Host "`nChecking RBAC for: $($la.Name)" -ForegroundColor Yellow
        
        # Check DCR role assignment
        try {
            $dcrRoleAssignments = az role assignment list --resource $dcr.id --query "[?principalId=='$($la.PrincipalId)' && roleDefinitionId=='$monitoringMetricsPublisherRole']" -o json | ConvertFrom-Json
            if ($dcrRoleAssignments.Count -gt 0) {
                Write-Host "  ✓ Has Monitoring Metrics Publisher role on DCR" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Missing Monitoring Metrics Publisher role on DCR" -ForegroundColor Red
            }
        } catch {
            Write-Host "  ✗ Error checking DCR role assignment: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # Check DCE role assignment if DCE exists
        if ($dceName) {
            try {
                $dceRoleAssignments = az role assignment list --resource $dce.id --query "[?principalId=='$($la.PrincipalId)' && roleDefinitionId=='$monitoringMetricsPublisherRole']" -o json | ConvertFrom-Json
                if ($dceRoleAssignments.Count -gt 0) {
                    Write-Host "  ✓ Has Monitoring Metrics Publisher role on DCE" -ForegroundColor Green
                } else {
                    Write-Host "  ✗ Missing Monitoring Metrics Publisher role on DCE" -ForegroundColor Red
                }
            } catch {
                Write-Host "  ✗ Error checking DCE role assignment: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

# Test authentication
Write-Host "`n═══ PHASE 5: AUTHENTICATION TEST ═══" -ForegroundColor Cyan
if ($dceEndpoint -and $DcrImmutableId) {
    foreach ($la in $logicAppDetails) {
        if ($la.PrincipalId) {
            Write-Host "`nTesting authentication for: $($la.Name)" -ForegroundColor Yellow
            
            try {
                # Get a token for the Logic App's managed identity
                $tokenUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$($la.Name)?api-version=2018-07-01-preview"
                $tokenResponse = az account get-access-token --resource "https://management.azure.com/" --query accessToken -o tsv
                
                # Try to call the DCE ingestion endpoint with the Logic App's identity
                # Note: This is a simplified test - in reality, we'd need to use the Logic App's managed identity
                $testUri = "$dceEndpoint/dataCollectionRules/$DcrImmutableId/streams/Custom-TacitRed_Findings_Raw?api-version=2023-01-01"
                Write-Host "  Test URI: $testUri" -ForegroundColor Gray
                
                # This will likely fail with 401/403 since we're using the user's token, not the Logic App's
                # But it helps verify the endpoint exists
                $response = az rest --method GET --uri $testUri 2>$null
                Write-Host "  ✓ Endpoint accessible (with user token)" -ForegroundColor Green
            } catch {
                Write-Host "  ⚠ Endpoint test failed (expected with user token): $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

# Recommendations
Write-Host "`n═══ PHASE 6: RECOMMENDATIONS ═══" -ForegroundColor Cyan
Write-Host "Based on the diagnostic results, here are the recommended actions:" -ForegroundColor White

Write-Host "`n1. If RBAC assignments are missing:" -ForegroundColor Yellow
Write-Host "   Run the following commands to assign the required roles:" -ForegroundColor Gray
foreach ($la in $logicAppDetails) {
    if ($la.PrincipalId) {
        Write-Host "   # For $($la.Name)" -ForegroundColor Cyan
        Write-Host "   az role assignment create --assignee $($la.PrincipalId) --role 'Monitoring Metrics Publisher' --scope $($dcr.id)" -ForegroundColor White
        if ($dceName) {
            Write-Host "   az role assignment create --assignee $($la.PrincipalId) --role 'Monitoring Metrics Publisher' --scope $($dce.id)" -ForegroundColor White
        }
    }
}

Write-Host "`n2. If Logic Apps are in a failed state:" -ForegroundColor Yellow
Write-Host "   Check the Logic App run history for specific error details:" -ForegroundColor Gray
foreach ($la in $logicAppDetails) {
    Write-Host "   az logic workflow run list --resource-group $rg --name $($la.Name) --query '[0].{Name:name,Status:properties.status,Trigger:properties.trigger}' -o json" -ForegroundColor White
}

Write-Host "`n3. If the issue persists:" -ForegroundColor Yellow
Write-Host "   - Wait 30-60 minutes for RBAC assignments to propagate in Azure" -ForegroundColor Gray
Write-Host "   - Restart the Logic Apps after RBAC propagation" -ForegroundColor Gray
Write-Host "   - Check if there are any conditional access policies affecting the managed identity" -ForegroundColor Gray

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ DIAGNOSTIC COMPLETE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
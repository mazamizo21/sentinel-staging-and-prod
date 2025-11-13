# Fix Script for DCR Authentication Issues
# This script fixes authentication issues by ensuring proper RBAC assignments

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = 'd:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-staging\client-config-COMPLETE.json',
    
    [Parameter(Mandatory=$false)]
    [string]$DcrImmutableId = '',  # Will auto-detect if not specified
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Ensure script runs from correct directory
$ScriptDir = Split-Path -Parent $PSCommandPath
Set-Location $ScriptDir
Write-Host "Working directory: $ScriptDir" -ForegroundColor Gray

$ErrorActionPreference = "Stop"

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          DCR AUTHENTICATION FIX SCRIPT                      ║" -ForegroundColor Cyan
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
    
    if ($dcr.properties.dataCollectionEndpointId) {
        Write-Host "  DCE ID: $($dcr.properties.dataCollectionEndpointId)" -ForegroundColor Gray
        $dceName = ($dcr.properties.dataCollectionEndpointId -split '/')[-1]
        
        # Get DCE details
        $dce = az monitor data-collection endpoint show --name $dceName --resource-group $rg -o json | ConvertFrom-Json
        $dceEndpoint = $dce.properties.logsIngestion.endpoint
        Write-Host "  DCE Endpoint: $dceEndpoint" -ForegroundColor Gray
    } else {
        Write-Host "  ⚠ No DCE associated with this DCR" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Error retrieving DCR details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Get Logic Apps and their managed identities
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

# Fix RBAC assignments
Write-Host "`n═══ PHASE 4: FIX RBAC ASSIGNMENTS ═══" -ForegroundColor Cyan
$monitoringMetricsPublisherRole = "3913510d-42f4-4e42-8a64-420c390055eb"  # Monitoring Metrics Publisher
$fixesApplied = 0

foreach ($la in $logicAppDetails) {
    if ($la.PrincipalId) {
        Write-Host "`nFixing RBAC for: $($la.Name)" -ForegroundColor Yellow
        
        # Check and fix DCR role assignment
        try {
            $dcrRoleAssignments = az role assignment list --resource $dcr.id --query "[?principalId=='$($la.PrincipalId)' && roleDefinitionId=='$monitoringMetricsPublisherRole']" -o json | ConvertFrom-Json
            if ($dcrRoleAssignments.Count -eq 0 -or $Force) {
                Write-Host "  Assigning Monitoring Metrics Publisher role on DCR..." -ForegroundColor Gray
                az role assignment create --assignee $la.PrincipalId --role "Monitoring Metrics Publisher" --scope $dcr.id -o none
                Write-Host "  ✓ Monitoring Metrics Publisher role assigned on DCR" -ForegroundColor Green
                $fixesApplied++
            } else {
                Write-Host "  ✓ Monitoring Metrics Publisher role already exists on DCR" -ForegroundColor Green
            }
        } catch {
            Write-Host "  ✗ Error fixing DCR role assignment: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # Check and fix DCE role assignment if DCE exists
        if ($dceName) {
            try {
                $dceRoleAssignments = az role assignment list --resource $dce.id --query "[?principalId=='$($la.PrincipalId)' && roleDefinitionId=='$monitoringMetricsPublisherRole']" -o json | ConvertFrom-Json
                if ($dceRoleAssignments.Count -eq 0 -or $Force) {
                    Write-Host "  Assigning Monitoring Metrics Publisher role on DCE..." -ForegroundColor Gray
                    az role assignment create --assignee $la.PrincipalId --role "Monitoring Metrics Publisher" --scope $dce.id -o none
                    Write-Host "  ✓ Monitoring Metrics Publisher role assigned on DCE" -ForegroundColor Green
                    $fixesApplied++
                } else {
                    Write-Host "  ✓ Monitoring Metrics Publisher role already exists on DCE" -ForegroundColor Green
                }
            } catch {
                Write-Host "  ✗ Error fixing DCE role assignment: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

# Restart Logic Apps if fixes were applied
if ($fixesApplied -gt 0) {
    Write-Host "`n═══ PHASE 5: RESTART LOGIC APPS ═══" -ForegroundColor Cyan
    Write-Host "RBAC fixes were applied. Restarting Logic Apps to ensure they pick up the new permissions..." -ForegroundColor Yellow
    
    foreach ($la in $logicAppDetails) {
        try {
            Write-Host "  Restarting: $($la.Name)" -ForegroundColor Gray
            az logic workflow restart --resource-group $rg --name $la.Name -o none
            Write-Host "  ✓ $($la.Name) restarted" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Error restarting $($la.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host "`nWaiting 60 seconds for Logic Apps to initialize..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
}

# Test the fix
Write-Host "`n═══ PHASE 6: TEST THE FIX ═══" -ForegroundColor Cyan
Write-Host "Triggering Logic Apps to test the authentication fix..." -ForegroundColor Yellow

foreach ($la in $logicAppDetails) {
    try {
        Write-Host "  Triggering: $($la.Name)" -ForegroundColor Gray
        az logic workflow trigger run -g $rg --name $la.Name --trigger-name "Recurrence" -o none
        Write-Host "  ✓ $($la.Name) triggered" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Error triggering $($la.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nWaiting 90 seconds for runs to complete..." -ForegroundColor Yellow
Start-Sleep -Seconds 90

# Check results
Write-Host "`nChecking Logic App run results..." -ForegroundColor Yellow
$successCount = 0
foreach ($la in $logicAppDetails) {
    try {
        $runsUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$($la.Name)/runs?api-version=2019-05-01&`$top=1"
        $runs = az rest --method GET --uri $runsUri 2>$null | ConvertFrom-Json
        
        if ($runs.value -and $runs.value.Count -gt 0) {
            $latestRun = $runs.value[0]
            $sendUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$($la.Name)/runs/$($latestRun.name)/actions/Send_to_DCE?api-version=2019-05-01"
            $send = az rest --method GET --uri $sendUri 2>$null | ConvertFrom-Json
            
            if ($send) {
                $status = $send.properties.status
                $errorCode = if ($send.properties.error) { $send.properties.error.code } else { "None" }
                
                $color = if ($status -eq 'Succeeded') { 'Green' } elseif ($status -match 'Running') { 'Yellow' } else { 'Red' }
                Write-Host "  $($la.Name) : $status" -ForegroundColor $color
                
                if ($status -eq 'Succeeded') {
                    $successCount++
                } elseif ($errorCode -ne "None") {
                    Write-Host "    Error: $errorCode" -ForegroundColor Yellow
                }
            }
        }
    } catch {
        Write-Host "  $($la.Name) : Unable to check" -ForegroundColor Gray
    }
}

# Summary
Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ FIX COMPLETE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "  • RBAC fixes applied: $fixesApplied" -ForegroundColor Gray
Write-Host "  • Logic Apps succeeded: $successCount/$($logicAppDetails.Count)" -ForegroundColor Gray

if ($successCount -eq $logicAppDetails.Count) {
    Write-Host "`n✅ All Logic Apps are now working correctly!" -ForegroundColor Green
} elseif ($successCount -gt 0) {
    Write-Host "`n⚠ Some Logic Apps are still having issues. This may be due to:" -ForegroundColor Yellow
    Write-Host "  • RBAC propagation delay (wait another 15-30 minutes)" -ForegroundColor Gray
    Write-Host "  • Other configuration issues" -ForegroundColor Gray
    Write-Host "  • Network connectivity problems" -ForegroundColor Gray
} else {
    Write-Host "`n⚠ Logic Apps are still failing. Check the following:" -ForegroundColor Yellow
    Write-Host "  1. Run the diagnostic script for more details:" -ForegroundColor Gray
    Write-Host "     .\docs\diagnostic-dcr-authentication.ps1" -ForegroundColor White
    Write-Host "  2. Check individual Logic App run histories in the Azure portal" -ForegroundColor Gray
    Write-Host "  3. Verify the DCR and DCE configurations" -ForegroundColor Gray
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  1. If issues persist, wait 30 minutes for full RBAC propagation" -ForegroundColor Gray
Write-Host "  2. Run this script again with -Force if needed" -ForegroundColor Gray
Write-Host "  3. Check data ingestion in Log Analytics after successful runs" -ForegroundColor Gray
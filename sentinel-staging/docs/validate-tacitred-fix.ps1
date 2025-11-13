# =============================================================================
# Validate TacitRed Logic App Fix
# Verifies RBAC permissions and stream name configuration
# =============================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "SentinelTestStixImport",
    
    [Parameter(Mandatory=$false)]
    [string]$LogicAppName = "logic-tacitred-ingestion",
    
    [Parameter(Mandatory=$false)]
    [string]$DcrImmutableId = "dcr-346df82716844a28a1bdfd7e11b88347",
    
    [Parameter(Mandatory=$false)]
    [string]$DceEndpoint = "https://dce-sentinel-ti-9fdo.eastus-1.ingest.monitor.azure.com"
)

Write-Host "=== Validating TacitRed Logic App Fix ===" -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName"
Write-Host "Logic App: $LogicAppName"
Write-Host ""

# Check Logic App exists
$logicApp = Get-AzLogicApp -ResourceGroupName $ResourceGroupName -Name $LogicAppName -ErrorAction SilentlyContinue
if (-not $logicApp) {
    Write-Host "❌ Logic App '$LogicAppName' not found in resource group '$ResourceGroupName'" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Logic App found: $($logicApp.Name)" -ForegroundColor Green
Write-Host "   State: $($logicApp.State)"
Write-Host "   Principal ID: $($logicApp.Identity.PrincipalId)"
Write-Host "   Created: $($logicApp.CreatedTime)"
Write-Host "   Changed: $($logicApp.ChangedTime)"
Write-Host ""

# Check Logic App configuration
Write-Host "=== Checking Logic App Configuration ===" -ForegroundColor Cyan

# Get Logic App definition
$definition = $logicApp.Definition | ConvertFrom-Json

# Check stream name in parameters
$streamName = $definition.parameters.streamName.defaultValue
Write-Host "Stream Name in Logic App: $streamName"

if ($streamName -eq "Custom-TacitRed_Findings_CL") {
    Write-Host "✅ Stream name is correct" -ForegroundColor Green
} else {
    Write-Host "❌ Stream name mismatch. Expected: Custom-TacitRed_Findings_CL, Found: $streamName" -ForegroundColor Red
}

# Check DCR Immutable ID
$dcrId = $definition.parameters.dcrImmutableId.defaultValue
Write-Host "DCR Immutable ID: $dcrId"

if ($dcrId -eq $DcrImmutableId) {
    Write-Host "✅ DCR Immutable ID matches" -ForegroundColor Green
} else {
    Write-Host "❌ DCR Immutable ID mismatch" -ForegroundColor Red
}

# Check DCE Endpoint
$dceEndpointParam = $definition.parameters.dceEndpoint.defaultValue
Write-Host "DCE Endpoint: $dceEndpointParam"

if ($dceEndpointParam -eq $DceEndpoint) {
    Write-Host "✅ DCE Endpoint matches" -ForegroundColor Green
} else {
    Write-Host "❌ DCE Endpoint mismatch" -ForegroundColor Red
}

Write-Host ""

# Check RBAC permissions
Write-Host "=== Checking RBAC Permissions ===" -ForegroundColor Cyan

$principalId = $logicApp.Identity.PrincipalId
$monitoringMetricsPublisherRoleId = "3913510d-42f4-4e42-8a64-420c390055eb"

# Get DCR and DCE resource names
$dcrName = ($DcrImmutableId -split '-')[0]
$dceName = ($DceEndpoint -split '/')[2]

# Check DCR role assignment
$dcrScope = "/subscriptions/$(Get-AzContext).Subscription.Id/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionRules/$dcrName"
$dcrRoleAssignments = Get-AzRoleAssignment -Scope $dcrScope -ObjectId $principalId -ErrorAction SilentlyContinue

if ($dcrRoleAssignments) {
    Write-Host "✅ DCR role assignment found" -ForegroundColor Green
    foreach ($assignment in $dcrRoleAssignments) {
        Write-Host "   Role: $($assignment.RoleDefinitionName)"
        Write-Host "   Scope: $($assignment.Scope)"
    }
} else {
    Write-Host "❌ DCR role assignment NOT found" -ForegroundColor Red
    Write-Host "   Expected role: Monitoring Metrics Publisher"
    Write-Host "   Scope: $dcrScope"
}

# Check DCE role assignment
$dceScope = "/subscriptions/$(Get-AzContext).Subscription.Id/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionEndpoints/$dceName"
$dceRoleAssignments = Get-AzRoleAssignment -Scope $dceScope -ObjectId $principalId -ErrorAction SilentlyContinue

if ($dceRoleAssignments) {
    Write-Host "✅ DCE role assignment found" -ForegroundColor Green
    foreach ($assignment in $dceRoleAssignments) {
        Write-Host "   Role: $($assignment.RoleDefinitionName)"
        Write-Host "   Scope: $($assignment.Scope)"
    }
} else {
    Write-Host "❌ DCE role assignment NOT found" -ForegroundColor Red
    Write-Host "   Expected role: Monitoring Metrics Publisher"
    Write-Host "   Scope: $dceScope"
}

Write-Host ""

# Test DCR configuration
Write-Host "=== Checking DCR Configuration ===" -ForegroundColor Cyan

try {
    $dcr = Get-AzDataCollectionRule -ResourceGroupName $ResourceGroupName -Name $dcrName -ErrorAction SilentlyContinue
    if ($dcr) {
        Write-Host "✅ DCR found: $($dcr.Name)" -ForegroundColor Green
        Write-Host "   Immutable ID: $($dcr.ImmutableId)"
        Write-Host "   Location: $($dcr.Location)"
        
        # Check stream declarations
        $streamDeclarations = $dcr.Properties.StreamDeclarations
        if ($streamDeclarations.ContainsKey("Custom-TacitRed_Findings_CL")) {
            Write-Host "✅ DCR has Custom-TacitRed_Findings_CL stream" -ForegroundColor Green
        } else {
            Write-Host "❌ DCR missing Custom-TacitRed_Findings_CL stream" -ForegroundColor Red
            Write-Host "   Available streams:"
            foreach ($stream in $streamDeclarations.Keys) {
                Write-Host "     - $stream"
            }
        }
    } else {
        Write-Host "❌ DCR not found: $dcrName" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error checking DCR: $_" -ForegroundColor Red
}

Write-Host ""

# Test DCE configuration
Write-Host "=== Checking DCE Configuration ===" -ForegroundColor Cyan

try {
    $dce = Get-AzDataCollectionEndpoint -ResourceGroupName $ResourceGroupName -Name $dceName -ErrorAction SilentlyContinue
    if ($dce) {
        Write-Host "✅ DCE found: $($dce.Name)" -ForegroundColor Green
        Write-Host "   Location: $($dce.Location)"
        Write-Host "   Log Ingestion Endpoint: $($dce.Properties.LogIngestionEndpoint)"
    } else {
        Write-Host "❌ DCE not found: $dceName" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error checking DCE: $_" -ForegroundColor Red
}

Write-Host ""

# Summary
Write-Host "=== Validation Summary ===" -ForegroundColor Yellow

$issues = @()

if ($streamName -ne "Custom-TacitRed_Findings_CL") {
    $issues += "Stream name mismatch"
}

if (-not $dcrRoleAssignments) {
    $issues += "Missing DCR role assignment"
}

if (-not $dceRoleAssignments) {
    $issues += "Missing DCE role assignment"
}

if ($issues.Count -eq 0) {
    Write-Host "✅ All validations passed!" -ForegroundColor Green
    Write-Host "The TacitRed Logic App should now be able to ingest data successfully." -ForegroundColor Green
} else {
    Write-Host "❌ Issues found:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "   - $issue" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Please run the deployment script to fix these issues:" -ForegroundColor Yellow
    Write-Host ".\deploy-fixed-tacitred-logic-app.ps1" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next steps after successful validation:" -ForegroundColor Cyan
Write-Host "1. Trigger a manual Logic App run in Azure Portal"
Write-Host "2. Check the run history for successful execution"
Write-Host "3. Verify data appears in Log Analytics Custom-TacitRed_Findings_CL table"
Write-Host "4. Monitor for regular successful runs every 15 minutes"
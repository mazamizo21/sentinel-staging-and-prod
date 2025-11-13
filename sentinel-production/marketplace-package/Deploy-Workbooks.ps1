# ═══════════════════════════════════════════════════════════════
# DEPLOY WORKBOOKS - SENTINEL THREAT INTELLIGENCE SOLUTION
# ═══════════════════════════════════════════════════════════════
# Description: Deploys 8 visualization workbooks for threat intelligence
# Prerequisites: Infrastructure deployed via mainTemplate.json
# Duration: ~2 minutes
# ═══════════════════════════════════════════════════════════════

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "SentinelTestStixImport",
    
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceName = "SentinelThreatIntelWorkspace",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus"
)

$ErrorActionPreference = "Stop"
$start = Get-Date

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   DEPLOYING THREAT INTELLIGENCE WORKBOOKS                    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host "  Workspace: $WorkspaceName" -ForegroundColor Gray
Write-Host "  Location: $Location`n" -ForegroundColor Gray

# Validate prerequisites
Write-Host "[1/3] Validating prerequisites..." -ForegroundColor Yellow
try {
    $workspace = az monitor log-analytics workspace show `
        --resource-group $ResourceGroup `
        --workspace-name $WorkspaceName `
        -o json 2>$null | ConvertFrom-Json
    
    if (-not $workspace) {
        throw "Workspace '$WorkspaceName' not found in resource group '$ResourceGroup'"
    }
    Write-Host "  ✓ Workspace validated" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Error: $_" -ForegroundColor Red
    exit 1
}

# Check if bicep files exist
$bicepPath = "..\workbooks\bicep"
if (-not (Test-Path $bicepPath)) {
    Write-Host "  ✗ Workbooks bicep folder not found: $bicepPath" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Workbook templates found`n" -ForegroundColor Green

# Define workbooks to deploy
$workbooks = @(
    @{Name="Threat Intelligence Command Center"; File="workbook-threat-intelligence-command-center.bicep"},
    @{Name="Threat Intelligence Command Center (Enhanced)"; File="workbook-threat-intelligence-command-center-enhanced.bicep"},
    @{Name="Executive Risk Dashboard"; File="workbook-executive-risk-dashboard.bicep"},
    @{Name="Executive Risk Dashboard (Enhanced)"; File="workbook-executive-risk-dashboard-enhanced.bicep"},
    @{Name="Threat Hunter's Arsenal"; File="workbook-threat-hunters-arsenal.bicep"},
    @{Name="Threat Hunter's Arsenal (Enhanced)"; File="workbook-threat-hunters-arsenal-enhanced.bicep"},
    @{Name="Cyren Threat Intelligence"; File="workbook-cyren-threat-intelligence.bicep"},
    @{Name="Cyren Threat Intelligence (Enhanced)"; File="workbook-cyren-threat-intelligence-enhanced.bicep"}
)

Write-Host "[2/3] Deploying workbooks (8 total)...`n" -ForegroundColor Yellow

$deploymentResults = @()
$successCount = 0
$failCount = 0

foreach ($workbook in $workbooks) {
    $workbookFile = Join-Path $bicepPath $workbook.File
    
    if (-not (Test-Path $workbookFile)) {
        Write-Host "  ⚠ Skipping: $($workbook.Name) (file not found)" -ForegroundColor Yellow
        $deploymentResults += @{Name=$workbook.Name; Status="Skipped"; Reason="File not found"}
        continue
    }
    
    Write-Host "  Deploying: $($workbook.Name)..." -ForegroundColor Gray
    
    $deploymentName = "workbook-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    try {
        $result = az deployment group create `
            --resource-group $ResourceGroup `
            --name $deploymentName `
            --template-file $workbookFile `
            --parameters workspaceName=$WorkspaceName location=$Location `
            --mode Incremental `
            -o json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✓ $($workbook.Name) deployed" -ForegroundColor Green
            $successCount++
            $deploymentResults += @{Name=$workbook.Name; Status="Success"}
        } else {
            Write-Host "    ✗ $($workbook.Name) FAILED" -ForegroundColor Red
            $failCount++
            $deploymentResults += @{Name=$workbook.Name; Status="Failed"; Error=$result}
        }
    } catch {
        Write-Host "    ✗ $($workbook.Name) ERROR: $_" -ForegroundColor Red
        $failCount++
        $deploymentResults += @{Name=$workbook.Name; Status="Error"; Error=$_.Exception.Message}
    }
    
    Start-Sleep -Milliseconds 500
}

Write-Host "`n[3/3] Validation..." -ForegroundColor Yellow

# Verify workbooks deployed
$deployedWorkbooks = az monitor app-insights workbook list `
    --resource-group $ResourceGroup `
    --query "[?properties.category=='sentinel'].{Name:properties.displayName, Category:properties.category}" `
    -o json 2>$null | ConvertFrom-Json

if ($deployedWorkbooks) {
    Write-Host "  ✓ Found $($deployedWorkbooks.Count) Sentinel workbooks" -ForegroundColor Green
} else {
    Write-Host "  ⚠ No workbooks found (may take a moment to index)" -ForegroundColor Yellow
}

# Summary
$duration = ((Get-Date) - $start).TotalMinutes

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  WORKBOOK DEPLOYMENT COMPLETE ($($duration.ToString('0.0')) minutes)            ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

Write-Host "Deployment Summary:" -ForegroundColor Cyan
Write-Host "  Successful: $successCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor $(if($failCount -gt 0){'Red'}else{'Green'})
Write-Host "  Total: $($workbooks.Count)`n" -ForegroundColor White

if ($failCount -gt 0) {
    Write-Host "Failed Workbooks:" -ForegroundColor Red
    foreach ($result in $deploymentResults | Where-Object {$_.Status -ne "Success"}) {
        Write-Host "  - $($result.Name): $($result.Status)" -ForegroundColor Gray
        if ($result.Error) {
            Write-Host "    Error: $($result.Error)" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

Write-Host "✅ Workbooks can be accessed in:" -ForegroundColor Green
Write-Host "   Azure Portal → Microsoft Sentinel → Workbooks → My workbooks`n" -ForegroundColor Gray

Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. View workbooks in Sentinel UI" -ForegroundColor White
Write-Host "  2. Wait 15-30 minutes for data ingestion" -ForegroundColor White
Write-Host "  3. Workbooks will show data once tables populated`n" -ForegroundColor White

exit $(if($failCount -gt 0){1}else{0})

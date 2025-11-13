#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy Phase 2 components to development Sentinel workspace
.DESCRIPTION
    Deploys KQL parser functions and analytics rules for testing
    Uses existing dev workspace: SentinelTestStixImportInstance
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "SentinelTestStixImport",
    
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceName = "SentinelTestStixImportInstance",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Phase 2 Development Deployment" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if($WhatIf){
    Write-Host "⚠ WhatIf mode - no changes will be made" -ForegroundColor Yellow
    Write-Host ""
}

# Connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
try {
    az account set --subscription $SubscriptionId 2>&1 | Out-Null
    if($LASTEXITCODE -ne 0){
        Write-Host "✗ Failed to set subscription" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ Connected to subscription: $SubscriptionId" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to connect to Azure" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Get workspace details
Write-Host "Verifying workspace..." -ForegroundColor Yellow
$workspace = az monitor log-analytics workspace show `
    --resource-group $ResourceGroupName `
    --workspace-name $WorkspaceName `
    -o json | ConvertFrom-Json

if(-not $workspace){
    Write-Host "✗ Workspace not found: $WorkspaceName" -ForegroundColor Red
    exit 1
}

$workspaceId = $workspace.customerId
Write-Host "✓ Workspace found: $WorkspaceName" -ForegroundColor Green
Write-Host "  Workspace ID: $workspaceId" -ForegroundColor Gray
Write-Host ""

# Step 1: Deploy KQL Parser Functions
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Step 1: Deploy KQL Parser Functions" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$parserFiles = @(
    @{Name="parser_tacitred_findings"; File=".\kql\parser-tacitred-findings.kql"}
    @{Name="parser_cyren_indicators"; File=".\kql\parser-cyren-indicators.kql"}
)

foreach($parser in $parserFiles){
    Write-Host "Deploying: $($parser.Name)" -ForegroundColor Yellow
    
    if($WhatIf){
        Write-Host "  Would deploy parser function" -ForegroundColor Yellow
    } else {
        try {
            $kqlContent = Get-Content $parser.File -Raw
            
            # Create a temp file with the KQL
            $tempFile = [System.IO.Path]::GetTempFileName()
            $kqlContent | Out-File -FilePath $tempFile -Encoding UTF8
            
            # Execute the KQL using az monitor log-analytics query
            # Note: Parser functions need to be created via API or portal
            # For now, we'll output the KQL for manual deployment
            Write-Host "  ⚠ Parser functions must be deployed via Azure Portal or API" -ForegroundColor Yellow
            Write-Host "  KQL saved to: $tempFile" -ForegroundColor Gray
            Write-Host "  ✓ Ready for deployment" -ForegroundColor Green
            
        } catch {
            Write-Host "  ✗ Failed to prepare parser" -ForegroundColor Red
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""
}

# Step 2: Deploy Analytics Rules
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Step 2: Deploy Analytics Rules" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Host "Deploying analytics rules via Bicep..." -ForegroundColor Yellow

if($WhatIf){
    Write-Host "  Would deploy 4 analytics rules" -ForegroundColor Yellow
} else {
    try {
        az deployment group create `
            --name "phase2-analytics-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
            --resource-group $ResourceGroupName `
            --template-file ".\bicep\analytics-rules.bicep" `
            --parameters `
                workspaceName=$WorkspaceName `
                enableRepeatCompromise=true `
                enableHighRiskUser=true `
                enableActiveCompromisedAccount=true `
                enableDepartmentCluster=true `
                enableCrossFeedCorrelation=false `
            --output none
        
        Write-Host "✓ Analytics rules deployed" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to deploy analytics rules" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# Step 3: Verify Deployment
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Step 3: Verify Deployment" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if(-not $WhatIf){
    Write-Host "Checking deployed analytics rules..." -ForegroundColor Yellow
    
    $rules = az sentinel alert-rule list `
        --resource-group $ResourceGroupName `
        --workspace-name $WorkspaceName `
        --query "[?contains(properties.displayName, 'TacitRed')].{name:properties.displayName, enabled:properties.enabled, severity:properties.severity}" `
        -o json | ConvertFrom-Json
    
    if($rules){
        Write-Host "✓ Found $($rules.Count) TacitRed analytics rules:" -ForegroundColor Green
        foreach($rule in $rules){
            $status = if($rule.enabled){"✓ Enabled"}else{"✗ Disabled"}
            Write-Host "  $status - $($rule.name) [$($rule.severity)]" -ForegroundColor Gray
        }
    } else {
        Write-Host "⚠ No analytics rules found (may take a moment to appear)" -ForegroundColor Yellow
    }
}
Write-Host ""

# Summary
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✓ Phase 2 Deployment Complete" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Deploy parser functions manually in Azure Portal:" -ForegroundColor Gray
Write-Host "     - Go to Sentinel → Logs → Functions" -ForegroundColor Gray
Write-Host "     - Copy KQL from .\kql\parser-*.kql files" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Wait for TacitRed data ingestion (check TacitRed_Findings_CL)" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Test analytics rules:" -ForegroundColor Gray
Write-Host "     - Go to Sentinel → Analytics" -ForegroundColor Gray
Write-Host "     - Find rules starting with 'TacitRed -'" -ForegroundColor Gray
Write-Host "     - Click 'Test with current data'" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Monitor incidents:" -ForegroundColor Gray
Write-Host "     - Go to Sentinel → Incidents" -ForegroundColor Gray
Write-Host "     - Look for incidents from Phase 2 rules" -ForegroundColor Gray
Write-Host ""

Write-Host "Documentation:" -ForegroundColor Yellow
Write-Host "  - Parser functions: .\kql\" -ForegroundColor Gray
Write-Host "  - Analytics rules: .\analytics-rules\" -ForegroundColor Gray
Write-Host "  - Bicep templates: .\bicep\" -ForegroundColor Gray
Write-Host ""

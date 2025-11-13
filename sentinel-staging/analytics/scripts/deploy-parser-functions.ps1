#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy KQL parser functions to Log Analytics workspace
.DESCRIPTION
    Uses Log Analytics API to deploy parser functions programmatically
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "SentinelTestStixImport",
    
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceName = "SentinelTestStixImportInstance"
)

$ErrorActionPreference = "Stop"

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Deploy Parser Functions" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Get workspace details
Write-Host "Getting workspace details..." -ForegroundColor Yellow
$workspace = az monitor log-analytics workspace show `
    --resource-group $ResourceGroupName `
    --workspace-name $WorkspaceName `
    -o json | ConvertFrom-Json

if(-not $workspace){
    Write-Host "✗ Workspace not found" -ForegroundColor Red
    exit 1
}

$workspaceId = $workspace.customerId
Write-Host "✓ Workspace found: $WorkspaceName" -ForegroundColor Green
Write-Host "  Workspace ID: $workspaceId" -ForegroundColor Gray
Write-Host ""

# Deploy parser functions using KQL
$parserFunctions = @(
    @{
        Name = "parser_tacitred_findings"
        File = ".\kql\parser-tacitred-findings.kql"
        Description = "Normalize TacitRed compromised credential findings"
    },
    @{
        Name = "parser_cyren_indicators"
        File = ".\kql\parser-cyren-indicators.kql"
        Description = "Normalize Cyren threat intelligence indicators"
    }
)

foreach($parser in $parserFunctions){
    Write-Host "Deploying: $($parser.Name)" -ForegroundColor Yellow
    
    try {
        # Read KQL file
        $kqlContent = Get-Content $parser.File -Raw
        
        # Execute KQL to create function
        Write-Host "  Executing KQL..." -ForegroundColor Gray
        
        $result = az monitor log-analytics query `
            --workspace $workspaceId `
            --analytics-query $kqlContent `
            --output json 2>&1
        
        if($LASTEXITCODE -eq 0){
            Write-Host "  ✓ Function deployed: $($parser.Name)" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ Function may already exist or deployment pending" -ForegroundColor Yellow
            Write-Host "  Result: $result" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host "  ⚠ Error deploying function" -ForegroundColor Yellow
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
    
    Write-Host ""
}

# Verify functions
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Verifying Parser Functions" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

foreach($parser in $parserFunctions){
    Write-Host "Testing: $($parser.Name)" -ForegroundColor Yellow
    
    try {
        $testQuery = "$($parser.Name)() | take 1"
        
        $result = az monitor log-analytics query `
            --workspace $workspaceId `
            --analytics-query $testQuery `
            --output json 2>&1
        
        if($LASTEXITCODE -eq 0){
            Write-Host "  ✓ Function is working" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Function not found or error" -ForegroundColor Red
            Write-Host "  Result: $result" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host "  ✗ Error testing function" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
    
    Write-Host ""
}

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Parser Function Deployment Complete" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. If functions deployed successfully, run:" -ForegroundColor Gray
Write-Host "     .\deploy-phase2-dev.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. If functions failed to deploy, deploy manually via Azure Portal:" -ForegroundColor Gray
Write-Host "     - Go to Sentinel → Logs → Functions" -ForegroundColor Gray
Write-Host "     - Copy content from kql/*.kql files" -ForegroundColor Gray
Write-Host ""

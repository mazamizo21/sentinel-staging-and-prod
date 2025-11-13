#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Creates required custom tables for Analytics rules

.DESCRIPTION
    Creates TacitRed_Findings_CL and Cyren_Indicators_CL tables in Log Analytics workspace.
    These tables are required for the Analytics rules to work.

.PARAMETER SubscriptionId
    Azure subscription ID

.PARAMETER ResourceGroupName
    Resource group containing the Log Analytics workspace

.PARAMETER WorkspaceName
    Name of the Log Analytics workspace

.EXAMPLE
    .\create-required-tables.ps1 -SubscriptionId "774bee0e-b281-4f70-8e40-199e35b65117" -ResourceGroupName "rg-sentinel" -WorkspaceName "sentinel-workspace"

.NOTES
    Author: AI Security Engineer
    Date: November 10, 2025
    Requires: Azure CLI
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Color output functions
function Write-Header { param([string]$Message) Write-Host "`n═══ $Message ═══" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host "ℹ️  $Message" -ForegroundColor Blue }
function Write-Warning { param([string]$Message) Write-Host "⚠️  $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }

Write-Header "Create Custom Log Tables for Analytics Rules"

# Validate Azure CLI
Write-Info "Validating Azure CLI..."
try {
    $azVersion = az version --query '\"azure-cli\"' -o tsv 2>$null
    if (-not $azVersion) { throw "Azure CLI not found" }
    Write-Success "Azure CLI version: $azVersion"
} catch {
    Write-Error "Azure CLI is not installed or not in PATH"
    exit 1
}

# Set subscription
Write-Info "Setting subscription: $SubscriptionId"
az account set --subscription $SubscriptionId 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set subscription. Run 'az login' first."
    exit 1
}

# Get workspace
Write-Info "Getting workspace details..."
$workspace = az monitor log-analytics workspace show `
    --resource-group $ResourceGroupName `
    --workspace-name $WorkspaceName `
    -o json 2>$null | ConvertFrom-Json

if (-not $workspace) {
    Write-Error "Workspace not found: $WorkspaceName in $ResourceGroupName"
    exit 1
}

$workspaceId = $workspace.id
Write-Success "Found workspace: $WorkspaceName"
Write-Info "Workspace ID: $workspaceId"

# Define TacitRed_Findings_CL schema
$tacitredSchema = @"
{
  "properties": {
    "schema": {
      "name": "TacitRed_Findings_CL",
      "columns": [
        {"name": "TimeGenerated", "type": "datetime"},
        {"name": "email_s", "type": "string"},
        {"name": "domain_s", "type": "string"},
        {"name": "findingType_s", "type": "string"},
        {"name": "confidence_d", "type": "int"},
        {"name": "firstSeen_t", "type": "datetime"},
        {"name": "lastSeen_t", "type": "datetime"},
        {"name": "notes_s", "type": "string"},
        {"name": "source_s", "type": "string"},
        {"name": "severity_s", "type": "string"},
        {"name": "status_s", "type": "string"},
        {"name": "campaign_id_s", "type": "string"},
        {"name": "user_id_s", "type": "string"},
        {"name": "username_s", "type": "string"},
        {"name": "detection_ts_t", "type": "datetime"},
        {"name": "metadata_s", "type": "string"}
      ]
    }
  }
}
"@

# Define Cyren_Indicators_CL schema
$cyrenSchema = @"
{
  "properties": {
    "schema": {
      "name": "Cyren_Indicators_CL",
      "columns": [
        {"name": "TimeGenerated", "type": "datetime"},
        {"name": "url_s", "type": "string"},
        {"name": "ip_s", "type": "string"},
        {"name": "fileHash_s", "type": "string"},
        {"name": "domain_s", "type": "string"},
        {"name": "protocol_s", "type": "string"},
        {"name": "port_d", "type": "int"},
        {"name": "category_s", "type": "string"},
        {"name": "risk_d", "type": "int"},
        {"name": "firstSeen_t", "type": "datetime"},
        {"name": "lastSeen_t", "type": "datetime"},
        {"name": "source_s", "type": "string"},
        {"name": "relationships_s", "type": "string"},
        {"name": "detection_methods_s", "type": "string"},
        {"name": "action_s", "type": "string"},
        {"name": "type_s", "type": "string"},
        {"name": "identifier_s", "type": "string"},
        {"name": "detection_ts_t", "type": "datetime"},
        {"name": "object_type_s", "type": "string"}
      ]
    }
  }
}
"@

# Create temp files
$tacitredFile = [System.IO.Path]::GetTempFileName()
$cyrenFile = [System.IO.Path]::GetTempFileName()
$tacitredSchema | Out-File -FilePath $tacitredFile -Encoding UTF8
$cyrenSchema | Out-File -FilePath $cyrenFile -Encoding UTF8

try {
    Write-Header "Creating TacitRed_Findings_CL Table"
    
    $result = az rest --method PUT `
        --uri "$workspaceId/tables/TacitRed_Findings_CL?api-version=2022-10-01" `
        --body "@$tacitredFile" `
        2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Success "TacitRed_Findings_CL table created"
    } else {
        if ($result -match "already exists") {
            Write-Warning "TacitRed_Findings_CL already exists (OK)"
        } else {
            Write-Error "Failed to create TacitRed_Findings_CL: $result"
        }
    }

    Write-Header "Creating Cyren_Indicators_CL Table"
    
    $result = az rest --method PUT `
        --uri "$workspaceId/tables/Cyren_Indicators_CL?api-version=2022-10-01" `
        --body "@$cyrenFile" `
        2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Cyren_Indicators_CL table created"
    } else {
        if ($result -match "already exists") {
            Write-Warning "Cyren_Indicators_CL already exists (OK)"
        } else {
            Write-Error "Failed to create Cyren_Indicators_CL: $result"
        }
    }

    Write-Header "Waiting for Table Propagation"
    Write-Info "Waiting 60 seconds for tables to propagate in Azure..."
    Start-Sleep -Seconds 60

    Write-Header "Verification"
    Write-Info "Verify tables exist by running in Log Analytics:"
    Write-Host ""
    Write-Host "  TacitRed_Findings_CL | getschema" -ForegroundColor Yellow
    Write-Host "  Cyren_Indicators_CL | getschema" -ForegroundColor Yellow
    Write-Host ""

    Write-Success "Table creation complete!"
    Write-Info "Next steps:"
    Write-Info "1. Verify tables exist using queries above"
    Write-Info "2. Deploy Analytics rule with corrected query"
    Write-Info "3. Configure data ingestion (Function App / Logic Apps)"

} finally {
    # Cleanup
    Remove-Item $tacitredFile -ErrorAction SilentlyContinue
    Remove-Item $cyrenFile -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Success "Script completed successfully!"

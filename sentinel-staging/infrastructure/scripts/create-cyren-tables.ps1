#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Create custom tables for Cyren threat intelligence data
.DESCRIPTION
    Creates Cyren_IpReputation_CL and Cyren_MalwareUrls_CL tables in Log Analytics
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ParametersFile = ".\parameters.dev.json"
)

$ErrorActionPreference = "Stop"

Write-Host "Creating Cyren custom tables..." -ForegroundColor Yellow

# Load parameters
$params = Get-Content $ParametersFile | ConvertFrom-Json
$subscriptionId = $params.parameters.subscriptionId.value
$resourceGroupName = $params.parameters.resourceGroupName.value
$workspaceName = $params.parameters.workspaceName.value

# Connect to Azure
az account set --subscription $subscriptionId

# Get workspace
$workspace = az monitor log-analytics workspace show `
    --resource-group $resourceGroupName `
    --workspace-name $workspaceName `
    -o json | ConvertFrom-Json

$workspaceId = $workspace.id

# IP Reputation table schema
$ipRepSchema = @'
{
  "properties": {
    "schema": {
      "name": "Cyren_IpReputation_CL",
      "columns": [
        {"name": "TimeGenerated", "type": "datetime"},
        {"name": "ip_address", "type": "string"},
        {"name": "threat_type", "type": "string"},
        {"name": "risk_score", "type": "int"},
        {"name": "confidence", "type": "int"},
        {"name": "first_seen", "type": "datetime"},
        {"name": "last_seen", "type": "datetime"},
        {"name": "country_code", "type": "string"},
        {"name": "asn", "type": "int"},
        {"name": "categories", "type": "string"},
        {"name": "tags", "type": "string"},
        {"name": "source", "type": "string"},
        {"name": "feed_offset", "type": "long"}
      ]
    }
  }
}
'@

# Malware URLs table schema
$malwareSchema = @'
{
  "properties": {
    "schema": {
      "name": "Cyren_MalwareUrls_CL",
      "columns": [
        {"name": "TimeGenerated", "type": "datetime"},
        {"name": "url", "type": "string"},
        {"name": "domain", "type": "string"},
        {"name": "malware_family", "type": "string"},
        {"name": "threat_type", "type": "string"},
        {"name": "risk_score", "type": "int"},
        {"name": "confidence", "type": "int"},
        {"name": "first_seen", "type": "datetime"},
        {"name": "last_seen", "type": "datetime"},
        {"name": "categories", "type": "string"},
        {"name": "tags", "type": "string"},
        {"name": "status", "type": "string"},
        {"name": "source", "type": "string"},
        {"name": "feed_offset", "type": "long"}
      ]
    }
  }
}
'@

# Save schemas to temp files
$ipRepFile = [System.IO.Path]::GetTempFileName()
$malwareFile = [System.IO.Path]::GetTempFileName()
$ipRepSchema | Out-File -FilePath $ipRepFile -Encoding UTF8
$malwareSchema | Out-File -FilePath $malwareFile -Encoding UTF8

try {
    # Create IP Reputation table
    Write-Host "Creating Cyren_IpReputation_CL table..." -ForegroundColor Gray
    az rest --method PUT `
        --uri "$workspaceId/tables/Cyren_IpReputation_CL?api-version=2022-10-01" `
        --body "@$ipRepFile" `
        --output none
    
    if($LASTEXITCODE -eq 0){
        Write-Host "✓ Cyren_IpReputation_CL table created" -ForegroundColor Green
    }
    
    # Create Malware URLs table
    Write-Host "Creating Cyren_MalwareUrls_CL table..." -ForegroundColor Gray
    az rest --method PUT `
        --uri "$workspaceId/tables/Cyren_MalwareUrls_CL?api-version=2022-10-01" `
        --body "@$malwareFile" `
        --output none
    
    if($LASTEXITCODE -eq 0){
        Write-Host "✓ Cyren_MalwareUrls_CL table created" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "✓ Custom tables created successfully!" -ForegroundColor Green
    Write-Host "  Waiting 30 seconds for tables to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    
} finally {
    Remove-Item $ipRepFile -ErrorAction SilentlyContinue
    Remove-Item $malwareFile -ErrorAction SilentlyContinue
}

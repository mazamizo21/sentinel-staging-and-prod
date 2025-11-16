# CREATE-CCF-DEFINITION.ps1
# Create the CCF connector definition

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   CREATE CCF CONNECTOR DEFINITION" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$ResourceGroup = "TacitRedCCFTest"
$WorkspaceName = "TacitRedCCFWorkspace"

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId

az account set --subscription $sub | Out-Null

# Get workspace ID
$wsId = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query id -o tsv

Write-Host "Workspace: $wsId`n" -ForegroundColor Gray

# Create connector definition
Write-Host "Creating connector definition..." -ForegroundColor Yellow

$connDefUri = "https://management.azure.com$wsId/providers/Microsoft.SecurityInsights/dataConnectorDefinitions/TacitRedThreatIntel?api-version=2024-09-01"

$connDefBody = @{
    kind = "Customizable"
    properties = @{
        connectorUiConfig = @{
            title = "TacitRed Threat Intelligence"
            publisher = "TacitRed"
            descriptionMarkdown = "TacitRed connector for compromised credentials testing"
            graphQueries = @(
                @{
                    metricName = "Total data received"
                    legend = "TacitRed Findings"
                    baseQuery = "TacitRed_Findings_CL"
                }
            )
            dataTypes = @(
                @{
                    name = "TacitRed_Findings_CL"
                    lastDataReceivedQuery = "TacitRed_Findings_CL | summarize Time = max(TimeGenerated) | where isnotempty(Time)"
                }
            )
            connectivityCriteria = @(
                @{
                    type = "IsConnectedQuery"
                    value = @(
                        "TacitRed_Findings_CL | summarize LastLogReceived = max(TimeGenerated) | project IsConnected = LastLogReceived > ago(30d)"
                    )
                }
            )
            availability = @{
                status = 1
                isPreview = $true
            }
            permissions = @{
                resourceProvider = @(
                    @{
                        provider = "Microsoft.OperationalInsights/workspaces"
                        permissionsDisplayText = "read and write permissions."
                        providerDisplayName = "Workspace"
                        scope = "Workspace"
                        requiredPermissions = @{
                            write = $true
                            read = $true
                        }
                    }
                )
            }
            instructionSteps = @(
                @{
                    title = "Connect TacitRed"
                    description = "Configure TacitRed connection"
                }
            )
        }
    }
}

$connDefFile = "$env:TEMP\conn-def-create.json"
$connDefBody | ConvertTo-Json -Depth 20 | Out-File -FilePath $connDefFile -Encoding UTF8 -Force

Write-Host "Sending create request..." -ForegroundColor Gray

try {
    $result = az rest --method PUT --uri $connDefUri --headers "Content-Type=application/json" --body "@$connDefFile" 2>&1
    Remove-Item $connDefFile -Force -ErrorAction SilentlyContinue
    
    if($LASTEXITCODE -eq 0){
        Write-Host "✅ Connector definition created!" -ForegroundColor Green
        
        # Verify
        Write-Host "`nVerifying..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        
        $connDef = az rest --method GET --uri $connDefUri 2>$null | ConvertFrom-Json
        
        if($connDef){
            Write-Host "✓ Verified: Definition exists" -ForegroundColor Green
            Write-Host "  Name: $($connDef.name)" -ForegroundColor Gray
            Write-Host "  Kind: $($connDef.kind)" -ForegroundColor Gray
            Write-Host "`n✅ Ready to create connector instance!" -ForegroundColor Green
            Write-Host "  Run: .\FIX-CCF-CONNECTOR-INSTANCE.ps1" -ForegroundColor White
        }else{
            Write-Host "⚠ Could not verify (may need more time)" -ForegroundColor Yellow
        }
        
    }else{
        Write-Host "✗ Failed to create definition" -ForegroundColor Red
        Write-Host "  Error: $result" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $connDefFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

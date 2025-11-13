# Test script to validate workbook deployment fixes
# This script tests only the workbook deployment section

param(
    [string]$ConfigFile = ".\client-config-COMPLETE.json"
)

$ErrorActionPreference = "Stop"
$start = Get-Date

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   WORKBOOK DEPLOYMENT TEST - VALIDATING FIXES                ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Load config
$config = (Get-Content $ConfigFile | ConvertFrom-Json).parameters
$sub = $config.azure.value.subscriptionId
$rg = $config.azure.value.resourceGroupName
$ws = $config.azure.value.workspaceName

Write-Host "Subscription: $sub" -ForegroundColor Gray
Write-Host "Resource Group: $rg" -ForegroundColor Gray
Write-Host "Workspace: $ws`n" -ForegroundColor Gray

# Set subscription
az account set --subscription $sub

# Test workbook deployment only
Write-Host "═══ WORKBOOK DEPLOYMENT TEST ═══" -ForegroundColor Cyan
$wbId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws"
$wbCount = 0
$ts = Get-Date -Format "yyyyMMddHHmmss"
$logDir = ".\docs\deployment-logs\workbook-test-$ts"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

foreach($wb in $config.workbooks.value.workbooks){
    if($wb.enabled -eq $true) {
        Write-Host "  Deploying: $($wb.bicepFile)" -ForegroundColor Gray
        
        # Sanitize workbook name for deployment name (remove spaces and special chars)
        $sanitizedName = $wb.name -replace '[^a-zA-Z0-9\-\.]', '-'
        $sanitizedName = $sanitizedName -replace '-+', '-'  # Replace multiple dashes with single dash
        $sanitizedName = $sanitizedName.Trim('-')          # Remove leading/trailing dashes
        
        Write-Host "    Sanitized name: $sanitizedName" -ForegroundColor Yellow
        
        az deployment group create -g $rg `
            --template-file ".\workbooks\bicep\$($wb.bicepFile)" `
            --parameters workspaceId=$wbId `
            -n "wb-test-$sanitizedName-$ts" `
            -o none 2>&1 | Out-File "$logDir\wb-test-$($wb.name).log"
        
        if($LASTEXITCODE -eq 0) {
            Write-Host "    ✓ Deployed" -ForegroundColor Green
            $wbCount++
        } else {
            Write-Host "    ✗ Failed" -ForegroundColor Red
            Write-Host "    Check log: $logDir\wb-test-$($wb.name).log" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n✓ Test complete: $wbCount workbooks deployed successfully`n" -ForegroundColor Green

$duration = ((Get-Date) - $start).TotalMinutes
Write-Host "Test duration: $($duration.ToString('0.0')) minutes" -ForegroundColor Gray
Write-Host "Test logs: $logDir" -ForegroundColor Gray
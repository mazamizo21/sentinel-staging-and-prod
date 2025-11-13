# Simple DCR Authentication Fix
# This script fixes the DCR authentication issue by assigning required RBAC roles

# Load configuration
$ConfigFile = 'd:\REPO\Upwork-Clean\Sentinel-Full-deployment-production\sentinel-staging\client-config-COMPLETE.json'
$config = (Get-Content $ConfigFile | ConvertFrom-Json).parameters
$sub = $config.azure.value.subscriptionId
$rg = $config.azure.value.resourceGroupName

Write-Host "Setting Azure context..." -ForegroundColor Yellow
az account set --subscription $sub

Write-Host "Getting DCR details..." -ForegroundColor Yellow
$dcrList = az monitor data-collection rule list --resource-group $rg -o json | ConvertFrom-Json

# Find TacitRed DCR
$dcr = $dcrList | Where-Object { $_.name -like "*tacitred*" -or $_.name -like "*findings*" }
if (-not $dcr) {
    $dcr = $dcrList[0]
}

Write-Host "Using DCR: $($dcr.name)" -ForegroundColor Green
$dcrId = $dcr.id

# Get DCE details
$dceName = ($dcr.properties.dataCollectionEndpointId -split '/')[-1]
$dce = az monitor data-collection endpoint show --name $dceName --resource-group $rg -o json | ConvertFrom-Json
$dceId = $dce.id

Write-Host "Getting Logic Apps..." -ForegroundColor Yellow
$logicApps = @(
    'logic-cyren-ip-reputation',
    'logic-cyren-malware-urls',
    'logic-tacitred-ingestion'
)

foreach ($laName in $logicApps) {
    try {
        $la = az logic workflow show --resource-group $rg --name $laName -o json | ConvertFrom-Json
        $principalId = $la.identity.principalId
        
        Write-Host "Fixing RBAC for: $laName" -ForegroundColor Yellow
        
        # Assign role on DCR
        Write-Host "  Assigning Monitoring Metrics Publisher role on DCR..." -ForegroundColor Gray
        az role assignment create --assignee $principalId --role "Monitoring Metrics Publisher" --scope $dcrId -o none
        
        # Assign role on DCE
        Write-Host "  Assigning Monitoring Metrics Publisher role on DCE..." -ForegroundColor Gray
        az role assignment create --assignee $principalId --role "Monitoring Metrics Publisher" --scope $dceId -o none
        
        Write-Host "  ✓ RBAC fixed for $laName" -ForegroundColor Green
        
        # Restart Logic App
        Write-Host "  Restarting $laName..." -ForegroundColor Gray
        az logic workflow restart --resource-group $rg --name $laName -o none
        Write-Host "  ✓ $laName restarted" -ForegroundColor Green
        
    } catch {
        Write-Host "  ✗ Error with $laName`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nWaiting 60 seconds for Logic Apps to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

# Test the fix
Write-Host "Testing the fix..." -ForegroundColor Yellow
foreach ($laName in $logicApps) {
    try {
        Write-Host "  Triggering: $laName" -ForegroundColor Gray
        az logic workflow trigger run -g $rg --name $laName --trigger-name "Recurrence" -o none
        Write-Host "  ✓ $laName triggered" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Error triggering $laName`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nWaiting 90 seconds for runs to complete..." -ForegroundColor Yellow
Start-Sleep -Seconds 90

Write-Host "`n✅ DCR Authentication Fix Complete!" -ForegroundColor Green
Write-Host "Check the Logic App run history in the Azure portal to verify success." -ForegroundColor Gray
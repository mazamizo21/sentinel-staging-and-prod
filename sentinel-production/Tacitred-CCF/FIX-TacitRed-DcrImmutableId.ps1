[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $SubscriptionId,
    [Parameter(Mandatory = $false)] [string] $ResourceGroupName,
    [Parameter(Mandatory = $false)] [string] $WorkspaceName,
    [Parameter(Mandatory = $false)] [string] $DcrName = "dcr-tacitred-findings",
    [Parameter(Mandatory = $false)] [string] $ConnectorName = "TacitRedFindings"
)

$ErrorActionPreference = "Stop"

Write-Host "=== TacitRed DCR ImmutableId Fix ===`n" -ForegroundColor Cyan

# Interactive prompts if parameters not provided
if (-not $SubscriptionId) {
    $SubscriptionId = Read-Host "Enter your Azure Subscription ID"
}

if (-not $ResourceGroupName) {
    $ResourceGroupName = Read-Host "Enter Resource Group name (where TacitRed solution is deployed)"
}

if (-not $WorkspaceName) {
    $WorkspaceName = Read-Host "Enter Workspace name (your Sentinel workspace)"
}

Write-Host "`nUsing:" -ForegroundColor Yellow
Write-Host "  Subscription:    $SubscriptionId"
Write-Host "  Resource Group:  $ResourceGroupName"
Write-Host "  Workspace:       $WorkspaceName"
Write-Host "  DCR Name:        $DcrName"
Write-Host "  Connector Name:  $ConnectorName`n"

az account set --subscription $SubscriptionId | Out-Null

$dcrId = az monitor data-collection rule show `
  --subscription $SubscriptionId `
  --resource-group $ResourceGroupName `
  --name $DcrName `
  --query immutableId -o tsv | Out-String
$dcrId = $dcrId.Trim()

if (-not $dcrId) {
  throw "Could not resolve immutableId for DCR $DcrName"
}

$uri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectors/${ConnectorName}?api-version=2023-02-01-preview"

Write-Host "DCR immutableId resolved: $dcrId"
Write-Host "Connector URI: $uri`n"

$tmpFile = "tacitred-connector-fix.json"

Write-Host "Fetching connector configuration..."
$getResult = az rest --method get --uri "$uri" 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host "ERROR: Failed to get connector. Details:"
  Write-Host $getResult
  throw "Could not retrieve connector $ConnectorName"
}

$getResult | Out-File $tmpFile -Encoding UTF8
$conn = Get-Content $tmpFile | ConvertFrom-Json

if (-not $conn.properties.dcrConfig) {
  throw "Connector does not have dcrConfig block."
}

$conn.properties.dcrConfig.dataCollectionRuleImmutableId = $dcrId

$conn | ConvertTo-Json -Depth 20 | Out-File $tmpFile -Encoding UTF8

# Update connector. Some back-end validations may emit warnings (for example about ApiKey),
# but we rely on the verification step below to confirm the immutableId was updated.
az rest --method put --uri "$uri" --body "@$tmpFile" *> $null

$verify = az rest --method get --uri "$uri" --query "properties.dcrConfig.dataCollectionRuleImmutableId" -o tsv | Out-String
$verify = $verify.Trim()

Write-Host "`n=== Verification ===" -ForegroundColor Cyan
Write-Host "DCR immutableId:       $dcrId"
Write-Host "Connector immutableId: $verify`n"

if ($verify -eq $dcrId) {
  Write-Host "✓ SUCCESS: Connector now points to correct DCR!" -ForegroundColor Green
  Write-Host "`nNext steps:" -ForegroundColor Yellow
  Write-Host "  1. Wait 60-90 minutes for the first polling cycle"
  Write-Host "  2. Check data ingestion in your workspace with this query:"
  Write-Host "     TacitRed_Findings_CL | where TimeGenerated > ago(2h) | summarize count()`n"
} else {
  Write-Host "✗ WARNING: Connector immutableId still does not match." -ForegroundColor Red
  Write-Host "  Expected: $dcrId"
  Write-Host "  Got:      $verify`n"
}

Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

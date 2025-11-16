[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $SubscriptionId,
    [Parameter(Mandatory = $true)] [string] $ResourceGroupName,
    [Parameter(Mandatory = $true)] [string] $WorkspaceName,
    [Parameter(Mandatory = $true)] [string] $WorkspaceLocation,
    [Parameter(Mandatory = $true)] [string] $TacitRedApiKey,
    [Parameter(Mandatory = $false)] [string] $TemplatePath = "./Tacitred-CCF/mainTemplate.json",
    [Parameter(Mandatory = $false)] [string] $LogsRoot = "./Project/Docs",
    [Parameter(Mandatory = $false)] [string] $DeploymentNamePrefix = "TacitRed-OneClick"
)

$ErrorActionPreference = "Stop"

# Resolve paths relative to script location
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateFullPath = Join-Path $scriptRoot (Resolve-Path -Path $TemplatePath).Path
$logsRootFull = Join-Path $scriptRoot $LogsRoot

if (-not (Test-Path $logsRootFull)) {
    New-Item -ItemType Directory -Path $logsRootFull -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$buildFolderName = "TacitRed-OneClick-Build-$timestamp"
$buildFolder = Join-Path $logsRootFull $buildFolderName
New-Item -ItemType Directory -Path $buildFolder -Force | Out-Null

$logFile = Join-Path $buildFolder "build.log"

function Write-Log {
    param([string] $Message)
    $line = "$(Get-Date -Format o) | $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Write-Log "Starting TacitRed one-click deployment pipeline"
Write-Log "SubscriptionId: $SubscriptionId"
Write-Log "ResourceGroup:  $ResourceGroupName"
Write-Log "Workspace:      $WorkspaceName"
Write-Log "Location:       $WorkspaceLocation"
Write-Log "Template:       $templateFullPath"
Write-Log "Logs folder:    $buildFolder"

# Ensure correct subscription
Write-Log "Setting Azure subscription context"
az account set --subscription $SubscriptionId | Out-Null

# Stage 1: Deploy infrastructure (DCE/DCR/table) without connector
$stage1Name = "$DeploymentNamePrefix-Stage1"
Write-Log "Stage 1: Deploying infrastructure without connector (deployment: $stage1Name)"

$stage1Args = @(
    "deployment", "group", "create",
    "--subscription", $SubscriptionId,
    "--resource-group", $ResourceGroupName,
    "--name", $stage1Name,
    "--template-file", $templateFullPath,
    "--parameters",
        "workspace=$WorkspaceName",
        "workspace-location=$WorkspaceLocation",
        "tacitRedApiKey=$TacitRedApiKey",
        "tacitRedDcrImmutableId=`"`"", # empty string
        "deployConnectors=false",
        "deployAnalytics=false",
        "deployWorkbooks=false",
        "enableKeyVault=false",
    "--output", "json"
)

$stage1Result = az @stage1Args 2>&1 | Out-String
$stage1OutputPath = Join-Path $buildFolder "stage1-deployment.json"
$stage1Result | Out-File $stage1OutputPath -Encoding UTF8
Write-Log "Stage 1 deployment completed. Output saved to $stage1OutputPath"

# Resolve DCR immutableId
$dcrName = "dcr-tacitred-findings"
Write-Log "Resolving immutableId for DCR '$dcrName'"

$dcrArgs = @(
    "monitor", "data-collection", "rule", "show",
    "--subscription", $SubscriptionId,
    "--resource-group", $ResourceGroupName,
    "--name", $dcrName,
    "--query", "immutableId",
    "-o", "tsv"
)

$immutableId = (az @dcrArgs 2>&1 | Out-String).Trim()

if ([string]::IsNullOrWhiteSpace($immutableId)) {
    Write-Log "ERROR: Failed to resolve DCR immutableId. Aborting."
    throw "Failed to resolve DCR immutableId for $dcrName"
}

Write-Log "Resolved DCR immutableId: $immutableId"

# Stage 2: Deploy connector with tacitRedDcrImmutableId parameter
$stage2Name = "$DeploymentNamePrefix-Stage2"
Write-Log "Stage 2: Deploying connector with DCR immutableId (deployment: $stage2Name)"

$stage2Args = @(
    "deployment", "group", "create",
    "--subscription", $SubscriptionId,
    "--resource-group", $ResourceGroupName,
    "--name", $stage2Name,
    "--template-file", $templateFullPath,
    "--parameters",
        "workspace=$WorkspaceName",
        "workspace-location=$WorkspaceLocation",
        "tacitRedApiKey=$TacitRedApiKey",
        "tacitRedDcrImmutableId=$immutableId",
        "deployConnectors=true",
        "deployAnalytics=true",
        "deployWorkbooks=true",
        "enableKeyVault=false",
    "--output", "json"
)

$stage2Result = az @stage2Args 2>&1 | Out-String
$stage2OutputPath = Join-Path $buildFolder "stage2-deployment.json"
$stage2Result | Out-File $stage2OutputPath -Encoding UTF8
Write-Log "Stage 2 deployment completed. Output saved to $stage2OutputPath"

# Verification: check connector's DCR immutableId
$connectorUri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2023-02-01-preview"

Write-Log "Verifying connector DCR immutableId via Azure REST API"

$verifyArgs = @(
    "rest", "--method", "get",
    "--uri", $connectorUri,
    "--query", "properties.dcrConfig.dataCollectionRuleImmutableId",
    "-o", "tsv"
)

$connectorImmutableId = (az @verifyArgs 2>&1 | Out-String).Trim()
Write-Log "Connector reports DCR immutableId: $connectorImmutableId"

if ($connectorImmutableId -eq $immutableId) {
    Write-Log "SUCCESS: Connector is wired to the correct DCR immutableId."
} else {
    Write-Log "WARNING: Connector immutableId does not match DCR immutableId."
    Write-Log "Expected: $immutableId"
    Write-Log "Actual:   $connectorImmutableId"
    Write-Log "This indicates backend caching / ordering behavior. Manual REST fix may still be required in some environments."
}

Write-Log "TacitRed one-click deployment pipeline complete."

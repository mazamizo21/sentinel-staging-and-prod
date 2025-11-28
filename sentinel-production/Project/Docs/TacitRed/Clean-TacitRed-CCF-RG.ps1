$ErrorActionPreference = 'Stop'

$subscriptionId = '774bee0e-b281-4f70-8e40-199e35b65117'
$resourceGroup  = 'Tacitred-CCF-Hub-v2'
$workspaceName  = 'Tacitred-CCF-Hub-v2-ws'

$ts      = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $PSScriptRoot "TacitRed-CCF-RG-Cleanup-$ts.log"

function Write-Log {
    param(
        [string] $Message,
        [string] $Color = 'Gray'
    )
    $line = "$(Get-Date -Format o) $Message"
    Write-Host $line -ForegroundColor $Color
    $line | Out-File -FilePath $logFile -Encoding UTF8 -Append
}

Write-Log "Starting cleanup for resource group '$resourceGroup' (keeping only workspace '$workspaceName')" 'Cyan'

az account set --subscription $subscriptionId | Out-Null

# Resolve the workspace resource ID
$wsJson = az monitor log-analytics workspace show -g $resourceGroup -n $workspaceName -o json 2>$null
if (-not $wsJson) {
    Write-Log "Workspace '$workspaceName' not found in resource group '$resourceGroup'" 'Red'
    exit 1
}

$workspace   = $wsJson | ConvertFrom-Json
$workspaceId = $workspace.id

Write-Log "Workspace resourceId: $workspaceId" 'Gray'

# List all resources in the resource group
$resourcesJson = az resource list -g $resourceGroup -o json
$resources     = $resourcesJson | ConvertFrom-Json

if (-not $resources -or $resources.Count -eq 0) {
    Write-Log "No resources found in resource group '$resourceGroup'" 'Yellow'
    exit 0
}

$toDelete = @()
foreach ($r in $resources) {
    if ($r.id -ne $workspaceId) {
        $toDelete += $r
    }
}

if (-not $toDelete -or $toDelete.Count -eq 0) {
    Write-Log "Nothing to delete; only the workspace is present." 'Green'
    exit 0
}

Write-Log "Resources to delete (excluding workspace):" 'Yellow'
foreach ($r in $toDelete) {
    Write-Log "  - $($r.type)  $($r.name)  id=$($r.id)" 'Gray'
}

foreach ($r in $toDelete) {
    Write-Log "Deleting $($r.type) '$($r.name)'" 'Yellow'
    az resource delete --ids $r.id --verbose
}

Write-Log "Cleanup complete. Resource group '$resourceGroup' should now contain only the workspace '$workspaceName'." 'Green'
Write-Log "Cleanup log written to $logFile" 'Cyan'

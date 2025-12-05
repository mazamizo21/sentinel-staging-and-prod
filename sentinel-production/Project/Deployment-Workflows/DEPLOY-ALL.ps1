#pwsh -NoLogo -ExecutionPolicy Bypass -File ./DEPLOY-ALL.ps1

[CmdletBinding()]
param(
    [string]$BranchName = "feature/tacitred-ccf-hub-v2threatintelligence",
    [string]$RemoteName = "fork",
    [string]$CommitMessage = "fix: sync all solutions from staging"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath

# List of solutions to deploy
# Format: @{ Name="SolutionName"; Script="ScriptName.ps1" }
$solutions = @(
    @{ Name = "TacitRedThreatIntelligence"; Script = "UPLOAD-TacitRedCCF-To-AzureSentinel.ps1" },
    @{ Name = "CyrenThreatIntelligence"; Script = "UPLOAD-CyrenSolution-To-AzureSentinel.ps1" },
    @{ Name = "TacitRed-IOC-CrowdStrike"; Script = "UPLOAD-TacitRedIOC-To-Crowdstrike.ps1" },
    @{ Name = "TacitRed-SentinelOne"; Script = "UPLOAD-TacitRedIOC-To-SentinelOne.ps1" }
)

Write-Host "=== Starting Global Deployment for All Solutions ===" -ForegroundColor Cyan
Write-Host "Branch: $BranchName"
Write-Host "Remote: $RemoteName"
Write-Host "------------------------------------------------"

foreach ($sol in $solutions) {
    $solName = $sol.Name
    $scriptFile = Join-Path $scriptDir $sol.Script

    Write-Host "`n>>> Processing Solution: $solName" -ForegroundColor Yellow
    
    if (Test-Path $scriptFile) {
        try {
            # Execute the individual upload script
            # We pass the common parameters to ensure consistency
            & $scriptFile -BranchName $BranchName -RemoteName $RemoteName -CommitMessage "$CommitMessage ($solName)"
            
            Write-Host ">>> Successfully processed $solName" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to process $solName. Error: $_"
            # We continue to the next solution even if one fails, or you could 'throw' to stop everything.
            # throw "Stopping global deployment due to failure in $solName"
        }
    }
    else {
        Write-Warning "Script not found for $solName: $scriptFile"
    }
}

Write-Host "`n=== Global Deployment Complete ===" -ForegroundColor Cyan

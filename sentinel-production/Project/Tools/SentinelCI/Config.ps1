# Config.ps1 - Configuration for Sentinel CI/CD scripts
# Edit these values to match your environment

$script:Config = @{
    # Your GitHub username
    GitHubUsername = "mazamizo21"
    
    # Path to your Azure-Sentinel fork (relative to repo root)
    AzureSentinelPath = "Project/Tools/Azure-Sentinel"
    
    # Path to arm-ttk module (relative to repo root)
    ArmTtkPath = "Project/Tools/arm-ttk/arm-ttk/arm-ttk.psd1"
    
    # Path where logs are stored (relative to repo root)
    LogsPath = "Project/Docs/Logs"
    
    # Solution naming pattern - solutions should be in folders like "MySolution-Hub"
    SolutionSuffix = "-Hub"
    
    # GitHub remote name in Azure-Sentinel repo
    GitHubRemoteName = "fork"
    
    # Default branch name prefix for PRs
    BranchPrefix = "feature/"
}

function Get-SentinelConfig {
    return $script:Config
}

function Get-RepoRoot {
    # Find repo root by looking for Project/Tools folder
    $current = $PSScriptRoot
    while ($current -and -not (Test-Path (Join-Path $current "Project/Tools"))) {
        $current = Split-Path $current -Parent
    }
    if (-not $current) {
        # Fallback: go up from SentinelCI folder
        $current = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    }
    return $current
}

function Get-FullPath {
    param([string]$RelativePath)
    $root = Get-RepoRoot
    return Join-Path $root $RelativePath
}

# Export functions when loaded as module (optional)
# Export-ModuleMember -Function Get-SentinelConfig, Get-RepoRoot, Get-FullPath -Variable Config

# Deploy-ToGitHub.ps1
# Deploy a Sentinel solution to your Azure-Sentinel GitHub fork
# Usage: ./Deploy-ToGitHub.ps1 -SolutionName "Cyren" -GitHubToken "ghp_xxx"

param(
    [Parameter(Mandatory=$true)]
    [string]$SolutionName,
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken,
    
    [Parameter(Mandatory=$false)]
    [string]$BranchName,
    
    [Parameter(Mandatory=$false)]
    [string]$CommitMessage,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipPush
)

$ErrorActionPreference = "Stop"

# Load config
. "$PSScriptRoot/Config.ps1"
$config = Get-SentinelConfig
$repoRoot = Get-RepoRoot

Write-Host "=== Deploy to GitHub ===" -ForegroundColor Cyan
Write-Host "Solution: $SolutionName" -ForegroundColor Gray

# Find solution folder
$solutionPatterns = @(
    "$SolutionName$($config.SolutionSuffix)",
    "$SolutionName-CCF-Hub", 
    "$SolutionName-Hub",
    $SolutionName
)

$solutionPath = $null
foreach ($pattern in $solutionPatterns) {
    $testPath = Join-Path $repoRoot $pattern
    if (Test-Path $testPath) {
        $solutionPath = $testPath
        break
    }
}

if (-not $solutionPath) {
    Write-Host "[ERROR] Solution folder not found" -ForegroundColor Red
    exit 1
}

Write-Host "Source: $solutionPath" -ForegroundColor Gray

# Azure-Sentinel fork path
$azSentinelPath = Get-FullPath $config.AzureSentinelPath
if (-not (Test-Path $azSentinelPath)) {
    Write-Host "[ERROR] Azure-Sentinel fork not found: $azSentinelPath" -ForegroundColor Red
    exit 1
}

# Determine solution name for GitHub (remove -Hub suffix, add ThreatIntelligence if needed)
$githubSolutionName = $SolutionName -replace "-CCF-Hub$", "" -replace "-Hub$", ""
if ($githubSolutionName -notmatch "ThreatIntelligence$") {
    $githubSolutionName = "${githubSolutionName}ThreatIntelligence"
}

$destPath = Join-Path $azSentinelPath "Solutions/$githubSolutionName"
Write-Host "Destination: $destPath" -ForegroundColor Gray

# Create destination folders
Write-Host "`nCopying solution files..." -ForegroundColor Yellow
if (Test-Path $destPath) {
    Remove-Item -Path $destPath -Recurse -Force
}

New-Item -ItemType Directory -Path $destPath -Force | Out-Null
New-Item -ItemType Directory -Path "$destPath/Package" -Force | Out-Null
New-Item -ItemType Directory -Path "$destPath/Data" -Force | Out-Null
New-Item -ItemType Directory -Path "$destPath/Data Connectors" -Force | Out-Null

# Copy files
$filesToCopy = @(
    @{ Src = "Package/*"; Dest = "Package/" },
    @{ Src = "Data/*"; Dest = "Data/" },
    @{ Src = "Data Connectors/*"; Dest = "Data Connectors/" },
    @{ Src = "SolutionMetadata.json"; Dest = "" },
    @{ Src = "ReleaseNotes.md"; Dest = "" },
    @{ Src = "README.md"; Dest = "" }
)

foreach ($file in $filesToCopy) {
    $srcPath = Join-Path $solutionPath $file.Src
    $dstPath = Join-Path $destPath $file.Dest
    if (Test-Path $srcPath) {
        Copy-Item -Path $srcPath -Destination $dstPath -Recurse -Force
        Write-Host "  [+] $($file.Src)" -ForegroundColor Green
    }
}

# Git operations
Write-Host "`nGit operations..." -ForegroundColor Yellow
Push-Location $azSentinelPath

try {
    # Set git config if not set
    $userName = git config user.name 2>$null
    if (-not $userName) {
        git config user.name $config.GitHubUsername
        git config user.email "$($config.GitHubUsername)@users.noreply.github.com"
    }
    
    # Create/checkout branch
    if (-not $BranchName) {
        $BranchName = "$($config.BranchPrefix)$($githubSolutionName.ToLower())"
    }
    
    $branchExists = git branch --list $BranchName
    if ($branchExists) {
        git checkout $BranchName
    } else {
        git checkout -b $BranchName
    }
    Write-Host "  [+] Branch: $BranchName" -ForegroundColor Green
    
    # Stage changes
    git add "Solutions/$githubSolutionName"
    Write-Host "  [+] Staged changes" -ForegroundColor Green
    
    # Commit
    if (-not $CommitMessage) {
        $CommitMessage = "Add $githubSolutionName Sentinel solution`n`n- CCF data connector`n- Workbooks and analytics rules`n- All templates pass arm-ttk validation"
    }
    
    git commit -m $CommitMessage
    Write-Host "  [+] Committed" -ForegroundColor Green
    
    # Push
    if (-not $SkipPush) {
        if (-not $GitHubToken) {
            git push $config.GitHubRemoteName $BranchName
            Write-Host "  [+] Pushed to GitHub (remote: $($config.GitHubRemoteName))" -ForegroundColor Green
            
            Write-Host "`n=== Success! ===" -ForegroundColor Green
            Write-Host "Create PR at:" -ForegroundColor Yellow
            Write-Host "  https://github.com/$($config.GitHubUsername)/Azure-Sentinel/pull/new/$BranchName" -ForegroundColor Cyan
        } else {
            $pushUrl = "https://$($config.GitHubUsername):$GitHubToken@github.com/$($config.GitHubUsername)/Azure-Sentinel.git"
            git push $pushUrl $BranchName
            Write-Host "  [+] Pushed to GitHub" -ForegroundColor Green
            
            Write-Host "`n=== Success! ===" -ForegroundColor Green
            Write-Host "Create PR at:" -ForegroundColor Yellow
            Write-Host "  https://github.com/$($config.GitHubUsername)/Azure-Sentinel/pull/new/$BranchName" -ForegroundColor Cyan
        }
    } else {
        Write-Host "`n[INFO] Push skipped. Run manually:" -ForegroundColor Yellow
        Write-Host "  cd $azSentinelPath" -ForegroundColor Gray
        Write-Host "  git push fork $BranchName" -ForegroundColor Gray
    }
    
} finally {
    Pop-Location
}

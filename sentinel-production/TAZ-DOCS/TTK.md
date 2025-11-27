# Sentinel CI/CD Scripts
# Location: Project/Tools/SentinelCI/

## Quick Commands (Mac/Linux/Windows)

```powershell
# Navigate to repo
cd /Users/tazjack/Documents/sentinel-staging-and-prod/sentinel-production

# === VALIDATE A SOLUTION ===
pwsh ./Project/Tools/SentinelCI/Validate-Solution.ps1 -SolutionName "Cyren-CCF"
pwsh ./Project/Tools/SentinelCI/Validate-Solution.ps1 -SolutionName "Tacitred-CCF"

# === FIX COMMON ISSUES ===
pwsh ./Project/Tools/SentinelCI/Fix-CommonIssues.ps1 -SolutionName "Cyren-CCF"

# === DEPLOY TO GITHUB ===
pwsh ./Project/Tools/SentinelCI/Deploy-ToGitHub.ps1 -SolutionName "Cyren-CCF" -GitHubToken "ghp_xxx"

# === FULL PIPELINE (Validate + Deploy) ===
pwsh ./Project/Tools/SentinelCI/Run-Pipeline.ps1 -SolutionName "Cyren-CCF" -GitHubToken "ghp_xxx"

# === CREATE NEW SOLUTION ===
pwsh ./Project/Tools/SentinelCI/New-Solution.ps1 -SolutionName "MyConnector" -Publisher "MyCompany" -TableName "MyData_CL"
```

## Available Scripts

| Script | Description |
|--------|-------------|
| `Validate-Solution.ps1` | Run arm-ttk validation |
| `Deploy-ToGitHub.ps1` | Copy to Azure-Sentinel fork and push |
| `Run-Pipeline.ps1` | Full pipeline (validate → deploy) |
| `New-Solution.ps1` | Scaffold new CCF connector solution |
| `Fix-CommonIssues.ps1` | Auto-fix common arm-ttk failures |
| `Config.ps1` | Configuration (GitHub username, paths) |

## End-to-End Validation (Both Solutions)

```powershell
pwsh ./Project/Tools/run-e2e-validation.ps1
```

## Manual GitHub Push (if needed)

```bash
cd ./Project/Tools/Azure-Sentinel
git remote -v  # Verify 'fork' remote exists
git push fork feature/threat-intelligence-solutions
```

## Create PR
https://github.com/mazamizo21/Azure-Sentinel/pulls
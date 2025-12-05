# Project Context, Structure, and Workflow Memory

## Active Pull Request & Status
**PR #13204**: [Azure-Sentinel Pull Request](https://github.com/Azure/Azure-Sentinel/pull/13204)
- **Status**: Active / In Review
- **Source Branch (Fork)**: [`feature/tacitred-ccf-hub-v2threatintelligence`](https://github.com/mazamizo21/Azure-Sentinel/tree/feature/tacitred-ccf-hub-v2threatintelligence)
- **Target Branch**: `Azure/Azure-Sentinel:master`

### Important Links
- **TacitRedThreatIntelligence (Master)**: [Link](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/TacitRedThreatIntelligence)
- **CyrenThreatIntelligence (Master)**: [Link](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/CyrenThreatIntelligence)
- **TacitRed-IOC-CrowdStrike (Master)**: [Link](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/TacitRed-IOC-CrowdStrike)
- **TacitRed-IOC-CrowdStrike (Fork/PR Context)**: [Link](https://github.com/mazamizo21/Azure-Sentinel/tree/feature/tacitred-ccf-hub-v2threatintelligence/Solutions/TacitRed-IOC-CrowdStrike)

---

## Standard Operating Procedure (SOP)

### 1. Development (Staging)
- **Action**: Make all code changes, edits, and fixes in the **Staging** environment.
- **Locations**:
    - **TacitRed CCF**: `sentinel-production/Tacitred-CCF-Hub-v2`
    - **Cyren CCF**: `sentinel-production/Cyren-CCF-Hub`
    - **TacitRed CrowdStrike**: `sentinel-production/TacitRed-IOC-CrowdStrike`
    - **TacitRed SentinelOne**: `sentinel-production/TacitRed-SentinelOne`
- **Note**: These folders are the **Source of Truth**. Any changes made directly to the Production folder will be overwritten by the Deployment script.

### 2. Validation (Local)
- **Action**: Run validation tools locally against the **Staging** files to catch errors before uploading.
- **Location**: `sentinel-production/Project/Deployment-Workflows/`
- **Tools**:
    - **ARM-TTK**: Run `RUN-TTK-Validation.ps1 -SolutionName "Tacitred-CCF-Hub-v2"` (or other solution name).
    - **TruffleHog**: Automatically run as part of the deployment script, or manually via `TruffleHog/run_safe_scan.sh`.
    - **.NET Detection Schema**: Automatically run as part of the deployment script, or manually via `RUN-DOTNET-VALIDATION.ps1`.
    - **.NET KQL Validation**: Automatically run as part of the deployment script, or manually via `RUN-KQL-VALIDATION.ps1`.
    - **Structure Validation**: Automatically run as part of the deployment script (`Test-SolutionStructure`).

### 3. Promotion & Deployment (Unified)
- **Action**: Run the **Unified Deployment Script** to handle everything end-to-end.
- **Script**: `DEPLOY-UNIFIED.ps1`
- **Location**: `sentinel-production/Project/Deployment-Workflows/`
- **Usage**: 
    - **Live Deployment (All)**: `pwsh -NoLogo -ExecutionPolicy Bypass -File ./Project/Deployment-Workflows/DEPLOY-UNIFIED.ps1`
    - **Live Deployment (Single)**: `pwsh -NoLogo -ExecutionPolicy Bypass -File ./Project/Deployment-Workflows/DEPLOY-UNIFIED.ps1 -SolutionName "TacitRedThreatIntelligence"`
    - **Dry Run (Test)**: `pwsh -NoLogo -ExecutionPolicy Bypass -File ./Project/Deployment-Workflows/DEPLOY-UNIFIED.ps1 -DryRun`
- **What this SINGLE script does**:
    1.  **Security Scan**: Runs TruffleHog once for the whole project.
    2.  **Detection Validation**: Runs `.NET` schema validation for detection templates.
    3.  **KQL Validation**: Runs `.NET` KQL syntax validation for queries.
    4.  **Upstream Sync**: Syncs your repo with Microsoft's `master` branch once.
    5.  **Loop Through Solutions** (All or Single):
        *   **Structure Check**: Verifies `Package` folder, `mainTemplate.json`, and `createUiDefinition.json` exist. Fails immediately if missing.
        *   **Auto-Versioning**: Increments version in `packageMetadata.json` (and `mainTemplate.json` if applicable).
        *   **Clean Packaging**: Creates a temporary folder, copies files, **removes logs/junk** (`*.log`, `.DS_Store`, etc.), and zips the clean content.
        *   **Zip Cleanup**: Removes *old* zip files from the staging folder so only the latest version exists.
        *   **Promote**: Copies all files to the Production folder.
        *   **Git Stage**: Adds changes to git staging area.
    6.  **Commit & Push**: Commits all changes for all solutions in one go and pushes to GitHub.

### 4. CI/CD (Remote)
- **Action**: Monitor the Pull Request on GitHub.
- **Check**: Ensure "SolutionValidations", "TruffleHog", and other Microsoft CI checks pass.

---

## Environments & Structure

### Staging
- **TacitRed CCF**: `sentinel-production/Tacitred-CCF-Hub-v2`
- **Cyren CCF**: `sentinel-production/Cyren-CCF-Hub`
- **TacitRed CrowdStrike**: `sentinel-production/TacitRed-IOC-CrowdStrike`
- **TacitRed SentinelOne**: `sentinel-production/TacitRed-SentinelOne`

### Production
- **Location**: `sentinel-production/Project/Tools/Azure-Sentinel/Solutions/`
- **Purpose**: The official production version of the solutions, located within the Azure-Sentinel solutions repository structure.

## Tools

### ARM TTK (Template Test Kit)
- **Location**: `sentinel-production/Project/Tools/arm-ttk`
- **Runner Script**: `sentinel-production/Project/Deployment-Workflows/RUN-TTK-Validation.ps1`

### Sentinel CI
- **Location**: `sentinel-production/Project/Tools/SentinelCI`

## Workflows

### Unified Deployment
- **Directory**: `sentinel-production/Project/Deployment-Workflows`
- **Script**: `DEPLOY-UNIFIED.ps1`
- **Features**: 
    - **Auto-Versioning**: Increments patch versions automatically.
    - **Clean Packaging**: Filters out logs and temporary files before zipping.
    - **Zip Cleanup**: Ensures only the latest zip file remains.
    - **Structure Validation**: Enforces correct folder structure.
    - **Security**: Integrated TruffleHog scan.
    - **Validation**: Integrated .NET Detection and KQL validation.
    - **Sync**: Automated upstream sync.
    - **Single Solution Mode**: Can target specific solutions via `-SolutionName`.

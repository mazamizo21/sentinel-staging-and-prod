# Project Context, Structure, and Workflow Memory

## Active Pull Request & Status

### 1. TacitRed CCF Hub v2 Threat Intelligence
- **PR #13204**: [Azure-Sentinel Pull Request](https://github.com/Azure/Azure-Sentinel/pull/13204)
- **Status**: Active / In Review
- **Source Branch (Fork)**: [`feature/tacitred-ccf-hub-v2threatintelligence`](https://github.com/mazamizo21/Azure-Sentinel/tree/feature/tacitred-ccf-hub-v2threatintelligence)

### 4. TacitRed SentinelOne
- **PR #13243**: [Azure-Sentinel Pull Request](https://github.com/Azure/Azure-Sentinel/pull/13243)
- **Status**: **Updated / Waiting for CI** (Deployed v1.0.2)
- **Source Branch**: [`feature/tacitred-sentinelone-v1`](https://github.com/mazamizo21/Azure-Sentinel/tree/feature/tacitred-sentinelone-v1)

### 5. TacitRed Defender Threat Intelligence
- **PR #13247**: [Azure-Sentinel Pull Request](https://github.com/Azure/Azure-Sentinel/pull/13247)
- **Status**: **Submitted / Waiting for CI**
- **Source Branch**: [`feature/tacitred-defender-ti`](https://github.com/mazamizo21/Azure-Sentinel/tree/feature/tacitred-defender-ti)
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

### 3. Promotion & Deployment (Unified)
- **Action**: Run the **Unified Deployment Script** to handle everything end-to-end.
- **Script**: `DEPLOY-UNIFIED.ps1`
- **Location**: `sentinel-production/Project/Deployment-Workflows/`
- **Usage**: 
    - **Live Deployment**: `pwsh -NoLogo -ExecutionPolicy Bypass -File ./Project/Deployment-Workflows/DEPLOY-UNIFIED.ps1`
    - **Dry Run (Test)**: `pwsh -NoLogo -ExecutionPolicy Bypass -File ./Project/Deployment-Workflows/DEPLOY-UNIFIED.ps1 -DryRun`
- **What this SINGLE script does**:
    1.  **Security Scan**: Runs TruffleHog once for the whole project.
    2.  **Upstream Sync**: Syncs your repo with Microsoft's `master` branch once.
    3.  **Loop Through All Solutions**:
        *   **Auto-Versioning**: Increments version in `packageMetadata.json` (and `mainTemplate.json` if applicable).
        *   **Packaging**: Zips the appropriate folder (`Data Connectors` or `Playbooks`) into a versioned zip (e.g., `3.0.1.zip`).
        *   **Promote**: Copies all files to the Production folder.
        *   **Git Stage**: Adds changes to git staging area.
    4.  **Commit & Push**: Commits all changes for all solutions in one go and pushes to GitHub.

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
- **Features**: Auto-versioning, Auto-zipping, TruffleHog Scan, Upstream Sync, Git Push.

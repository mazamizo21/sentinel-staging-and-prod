# ARM-TTK and Sentinel Solution Packaging Tooling

## 1. Repository Layout

- **arm-ttk (Template Test Toolkit)**
  - Recommended path in this repo: `Project/Tools/arm-ttk/`
  - Source: official Microsoft repo https://github.com/Azure/arm-ttk

- **Sentinel Solution Packaging Tools**
  - Recommended path: `Project/Tools/Azure-Sentinel/Tools/Create-Azure-Sentinel-Solution/`
  - Source: official Microsoft repo https://github.com/Azure/Azure-Sentinel

> These tools are vendored directly from Microsoft GitHub to ensure we always test against the same logic used by Microsoft validation pipelines.

## 2. How to Fetch/Update the Tools (local developer workflow)

From the repo root (`sentinel-production`):

1. Ensure the tools folder exists:
   - `mkdir -p Project/Tools`

2. Clone **arm-ttk**:
   - `cd Project/Tools`
   - `git clone https://github.com/Azure/arm-ttk.git`

3. Clone **Azure-Sentinel** (for the packaging tools only):
   - `cd Project/Tools`
   - `git clone https://github.com/Azure/Azure-Sentinel.git`
   - Packaging scripts will live under:
     - `Project/Tools/Azure-Sentinel/Tools/Create-Azure-Sentinel-Solution/`

> Optionally use Git sparse checkout in `Project/Tools/Azure-Sentinel` to pull only the `Tools/Create-Azure-Sentinel-Solution` tree if repo size becomes an issue.

## 3. Running ARM-TTK Locally

### 3.1. Prerequisites

- PowerShell 7+ installed on the local machine.
- On macOS, `brew install coreutils` as recommended by `arm-ttk` docs.

### 3.2. Import module and run tests

From the repo root:

- Import module (PowerShell):
  - `Import-Module ./Project/Tools/arm-ttk/arm-ttk/arm-ttk.psd1 -Force`

- Run tests for a specific template or folder (example for Cyren solution package):
  - `Test-AzTemplate -TemplatePath ./Cyren-CCF-Hub/Package/mainTemplate.json`
  - `Test-AzTemplate -TemplatePath ./Cyren-CCF-Hub/Package/createUiDefinition.json`

### 3.3. Capturing logs into `Project/Docs`

- Always tee results into a log file under `Project/Docs/Logs`:
  - `Test-AzTemplate -TemplatePath ./Cyren-CCF-Hub/Package/mainTemplate.json | Tee-Object -FilePath ./Project/Docs/Logs/arm-ttk-Cyren-mainTemplate.log`

- For detailed inspection:
  - `$results = Test-AzTemplate -TemplatePath ./path`
  - `$failures = $results | Where-Object { -not $_.Passed }`

## 4. Using the Sentinel Solution Packaging Tools (V3)

### 4.1. Tool location and entry points

- Scripts are located under:
  - `Project/Tools/Azure-Sentinel/Tools/Create-Azure-Sentinel-Solution/V3/`
- Key entry scripts:
  - `createSolutionV3.ps1` – generates `Package/mainTemplate.json`, `Package/createUiDefinition.json`, and `Package/packageMetadata.json` from a data file.

### 4.2. Data and metadata files (inputs)

For each solution (example: Cyren):

- Data input file under the solution's **Data** folder, e.g.:
  - `Solutions/CyrenThreatIntelligence/Data/Solution_Cyren.json`
- Solution metadata file at the solution root:
  - `Solutions/CyrenThreatIntelligence/SolutionMetadata.json`
- Data connectors and other assets listed in the data file must exist at the paths it references.

### 4.3. Running `createSolutionV3.ps1`

From `Project/Tools/Azure-Sentinel` (or via absolute path):

- `./Tools/Create-Azure-Sentinel-Solution/V3/createSolutionV3.ps1 -SolutionDataFolderPath "<full-path-to-Solutions>/<SolutionName>/Data"`

Example for this repo (Cyren solution when staged inside Azure-Sentinel fork):

- `./Tools/Create-Azure-Sentinel-Solution/V3/createSolutionV3.ps1 -SolutionDataFolderPath "C:\GitHub\Azure-Sentinel\Solutions\CyrenThreatIntelligence\Data"`

> The script locates the data file in the `Data` folder, reads `BasePath`, `Metadata`, and asset paths, then generates the full Content Hub package into the solution's `Package` folder.

### 4.4. Logs and diagnostics

- Capture console output from `createSolutionV3.ps1` runs into:
  - `Project/Docs/Logs/createSolutionV3-<solution-name>-<timestamp>.log`
- Any validation or error details during packaging must be stored under `Project/Docs/Logs` for traceability.

## 5. Combined Validation Flow for Any Sentinel Solution

For any solution in this repo (Cyren, TacitRed, etc.):

1. **Prepare / update data + metadata**
   - Ensure `Data/Solution_*.json` and `SolutionMetadata.json` are correct and paths match this repo.

2. **Generate or refresh package** using V3 tooling.

3. **Run ARM-TTK** on:
   - `Package/mainTemplate.json`
   - `Package/createUiDefinition.json` (if applicable)

4. **Store logs** for both steps under `Project/Docs/Logs/<SolutionName>/`.

5. **Only after green tests** should we open or update PRs to Microsoft (Azure-Sentinel) using the prepared `Solutions/<SolutionName>` tree.

## 6. Notes vs. Baseline Knowledge

- ARM-TTK and `createSolutionV3.ps1` are the **same tools used by Microsoft** in marketplace and Content Hub validation.
- For Sentinel Content Hub solutions, we treat `createSolutionV3.ps1` as the **single source of truth** for generating `mainTemplate.json` and `createUiDefinition.json`. Any manual edits must be followed by:
  - Re-running ARM-TTK.
  - Logging results under `Project/Docs/Logs`.
- This document serves as the internal reference for how we integrate these tools into our local and CI workflows for Sentinel solutions.

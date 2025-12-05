# TacitRed SentinelOne Solution Deployment

## Overview
Created a new Sentinel solution `TacitRed-SentinelOne` mirroring the structure of `TacitRed-IOC-CrowdStrike`. This solution automates the synchronization of compromised credentials from TacitRed to SentinelOne IOCs.

## Steps Taken
1. **Directory Structure**: Created `TacitRed-SentinelOne` with `Data`, `Package`, and `Playbooks` subdirectories.
2. **API Reference**: Created `SentinelOne-API-Reference.md` with details on SentinelOne API (Management Console, Postman).
3. **Solution Files**:
   - Adapted `SolutionMetadata.json` and `ReleaseNotes.md`.
   - Created `Data/Solution_TacitRedSentinelOneAutomation.json`.
   - Created `Playbooks/TacitRedToSentinelOne_Playbook.json` implementing the logic to fetch findings from TacitRed and post to SentinelOne `threat-intelligence/indicators` API.
   - Created `Package` files: `mainTemplate.json` (embedding the playbook), `createUiDefinition.json`, `packageMetadata.json`, `deploymentParameters.json`, `testParameters.json`.
4. **Packaging**:
   - Created `TAZ-DOCS/PREPARE-TacitRed-SentinelOne-Package.ps1` to zip the `Playbooks` folder into `Package/1.0.0.zip`.
   - Executed the prepare script.
5. **Upload**:
   - Created `TAZ-DOCS/UPLOAD-TacitRedIOC-To-SentinelOne.ps1` to sync the package to the `Azure-Sentinel` fork.
   - Executed the upload script, pushing changes to `feature/tacitred-ccf-hub-v2threatintelligence` branch.

## Key Configurations
- **SentinelOne API**: Uses `POST /web/api/v2.1/threat-intelligence/indicators`.
- **Authentication**: Uses `ApiToken` header.
- **Playbook**: Runs every 6 hours, fetches `compromised_credentials` from TacitRed, and maps them to SentinelOne IOC format.

## Outcome
Successfully deployed and uploaded the new solution to the staging fork.

# TacitRed Connector – Post-Deployment Fix (DCR ImmutableId)

This file explains what your customer should do **after** installing the TacitRed solution from Content Hub.

## 1. Why this script exists

The connector sometimes gets the **wrong Data Collection Rule (DCR) immutableId** when deployed only with ARM.

If that happens, the connector is active but:
- No data is ingested into `TacitRed_Findings_CL`
- No diagnostics appear for the DCR/DCE

The script `FIX-TacitRed-DcrImmutableId.ps1` fixes this by:
1. Reading the **real** immutableId of the DCR
2. Updating the TacitRed connector to use that immutableId

You only need to run it **once** per workspace after deployment.

## 2. Prerequisites

- Azure CLI installed (`az` command)
- You are already logged in: `az login`
- You know:
  - Subscription ID
  - Resource Group name where the solution is deployed
  - Workspace name

Defaults used by the script:
- DCR name: `dcr-tacitred-findings`
- Connector name: `TacitRedFindings`

## 3. Script location

The script file name is:

- `Tacitred-CCF/FIX-TacitRed-DcrImmutableId.ps1`

You can download it from the solution package repository or receive it from the publisher.

## 4. How to run the fix script

### Option A: Double-click (easiest for most users)

1. **Right-click** on `FIX-TacitRed-DcrImmutableId.ps1`
2. Select **"Run with PowerShell"**
3. The script will prompt you for:
   - Azure Subscription ID
   - Resource Group name
   - Workspace name
4. Enter each value when prompted
5. The script will run and show results

### Option B: Command line (for automation or scripting)

From a PowerShell terminal:

```powershell
# Example values – replace with your actual values
$sub  = "<YOUR-SUBSCRIPTION-ID>"
$rg   = "<YOUR-RESOURCE-GROUP>"      # e.g. TacitRedCCFTest
$ws   = "<YOUR-WORKSPACE-NAME>"      # e.g. TacitRedCCFWorkspace

# Run the fix script
.\FIX-TacitRed-DcrImmutableId.ps1 `
  -SubscriptionId  $sub `
  -ResourceGroupName $rg `
  -WorkspaceName   $ws
```

What the script does:
1. Gets the DCR immutableId via `az monitor data-collection rule show`
2. Gets the current connector configuration via `az rest`
3. Updates `properties.dcrConfig.dataCollectionRuleImmutableId` on the connector
4. Verifies that connector immutableId == DCR immutableId

If successful, you will see output similar to:

```text
DCR immutableId:       dcr-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Connector immutableId: dcr-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
SUCCESS: Connector now points to correct DCR.
```

## 5. After running the script

- The connector is now wired to the correct DCR.
- No restart is required.
- Wait at least **one polling interval** (for TacitRed: 60 minutes) and then check data:

```kusto
TacitRed_Findings_CL
| where TimeGenerated > ago(2h)
| summarize Count = count(), Latest = max(TimeGenerated)
```

If `Count > 0`, data is flowing correctly.

## 6. Safety notes

- The script **only** modifies a single connector:
  - `Microsoft.SecurityInsights/dataConnectors/TacitRedFindings`
- It does **not** delete or recreate any resources.
- It is safe to run multiple times; each run just re-applies the correct immutableId.

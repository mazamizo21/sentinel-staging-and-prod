# TacitRed CCF – Microsoft Sentinel Support Evidence (2025-11-19)

## 1. Environment

- **Subscription**: `774bee0e-b281-4f70-8e40-199e35b65117`
- **Resource Group**: `TacitRed-Production-Test-RG`
- **Workspace**: `TacitRed-Production-Test-Workspace`
- **Workspace CustomerId**: `72e125d2-4f75-4497-a6b5-90241feb387a`
- **Region**: `eastus`

## 2. Current TacitRed CCF Objects

### 2.1 Data Collection Endpoint (DCE)

- **Name**: `dce-threatintel-feeds`
- **Resource ID**:  
  `/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/TacitRed-Production-Test-RG/providers/Microsoft.Insights/dataCollectionEndpoints/dce-threatintel-feeds`
- **ImmutableId**: `dce-d859b7d246f0467c94e9f56293270f78`
- **logsIngestion.endpoint**:  
  `https://dce-threatintel-feeds-rmtc.eastus-1.ingest.monitor.azure.com`
- **ProvisioningState**: `Succeeded`

### 2.2 Data Collection Rule (DCR)

- **Name**: `dcr-tacitred-findings`
- **Resource ID**:  
  `/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/TacitRed-Production-Test-RG/providers/Microsoft.Insights/dataCollectionRules/dcr-tacitred-findings`
- **ImmutableId**: `dcr-b1551b742b5e458ba7e0a22e74799d4c`
- **Workspace Destination**: `TacitRed-Production-Test-Workspace`

#### 2.2.1 Stream Declarations

```json
"streamDeclarations": {
  "Custom-TacitRed_Findings_CL": {
    "columns": [
      { "name": "TimeGenerated",   "type": "datetime" },
      { "name": "email_s",         "type": "string"   },
      { "name": "domain_s",        "type": "string"   },
      { "name": "findingType_s",   "type": "string"   },
      { "name": "confidence_d",    "type": "int"      },
      { "name": "firstSeen_t",     "type": "datetime" },
      { "name": "lastSeen_t",      "type": "datetime" },
      { "name": "notes_s",         "type": "string"   },
      { "name": "source_s",        "type": "string"   },
      { "name": "severity_s",      "type": "string"   },
      { "name": "status_s",        "type": "string"   },
      { "name": "campaign_id_s",   "type": "string"   },
      { "name": "user_id_s",       "type": "string"   },
      { "name": "username_s",      "type": "string"   },
      { "name": "detection_ts_t",  "type": "datetime" },
      { "name": "metadata_s",      "type": "string"   }
    ]
  },
  "Custom-TacitRed_Findings_Raw": {
    "columns": [
      { "name": "finding",  "type": "dynamic" },
      { "name": "severity", "type": "string"  }
    ]
  }
}
```

#### 2.2.2 Data Flow / Transform KQL

```json
"dataFlows": [
  {
    "streams": [
      "Custom-TacitRed_Findings_Raw"
    ],
    "destinations": [
      "clv2ws1"
    ],
    "outputStream": "Custom-TacitRed_Findings_CL",
    "transformKql": "source | extend p = parse_json(finding) | extend s = p.supporting_data | extend TimeGenerated = datetime(null) | project TimeGenerated, email_s=tostring(s.credential), domain_s=tostring(s.domain), findingType_s='credential', confidence_d=int(75), firstSeen_t=TimeGenerated, lastSeen_t=TimeGenerated, notes_s='test', source_s='test', severity_s=tostring(severity), status_s='test', campaign_id_s='test', user_id_s='test', username_s='test', detection_ts_t=TimeGenerated, metadata_s=tostring(finding)"
  }
]
```

**Key point:** DCR is correctly configured in a **two-stream pattern** (Raw → Typed CL) with `parse_json()` and explicit type conversions, per Azure Monitor / Sentinel DCR guidance.

### 2.3 Sentinel CCF Connector (RestApiPoller)

- **Name**: `TacitRedFindings`
- **Kind**: `RestApiPoller`
- **Resource ID**:  
  `/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/TacitRed-Production-Test-RG/providers/Microsoft.OperationalInsights/workspaces/TacitRed-Production-Test-Workspace/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings`

#### 2.3.1 Current Properties (GET)

```json
{
  "kind": "RestApiPoller",
  "properties": {
    "connectorDefinitionName": "TacitRedThreatIntel",
    "dataType": "TacitRed_Findings_CL",
    "isActive": true,
    "dcrConfig": {
      "dataCollectionEndpoint": "https://dce-threatintel-feeds-vbk9.eastus-1.ingest.monitor.azure.com",
      "dataCollectionRuleImmutableId": "dcr-5ba1aee090ed412ea5dcbd1485aa2ab2",     // OLD DCR ID
      "streamName": "Custom-TacitRed_Findings_CL"                                   // CL, not Raw
    },
    "request": {
      "apiEndpoint": "https://app.tacitred.com/api/v1/findings",
      "httpMethod": "GET",
      "queryParameters": {
        "page_size": 100,
        "types[]": "compromised_credentials"
      },
      "queryWindowInMin": 60,
      "queryTimeFormat": "yyyy-MM-ddTHH:mm:ssZ",
      "startTimeAttributeName": "from",
      "endTimeAttributeName": "until",
      "rateLimitQPS": 10,
      "retryCount": 3,
      "timeoutInSeconds": 60
    },
    "response": {
      "eventsJsonPaths": [ "$.results" ],
      "format": "json"
    },
    "auth": {
      "type": "APIKey",
      "apiKeyName": "Authorization",
      "apiKeyIdentifier": ""
      // ApiKey value is passed via ARM parameter, not shown here
    },
    "paging": {
      "pagingType": "LinkHeader",
      "linkHeaderTokenJsonPath": "$.next"
    },
    "shouldJoinNestedData": false
  }
}
```

**Mismatch:**

- DCR immutableId **in connector**: `dcr-5ba1aee090ed412ea5dcbd1485aa2ab2` (OLD, from previous deployment).
- Actual DCR immutableId: `dcr-b1551b742b5e458ba7e0a22e74799d4c` (NEW, current).
- Connector `streamName`: `Custom-TacitRed_Findings_CL` (typed stream), while DCR expects input on `Custom-TacitRed_Findings_Raw` and outputs to CL.

This immutibleId + streamName mismatch is a central symptom.

## 3. Custom Table Schema (TacitRed_Findings_CL)

The custom table is created via ARM (same 16 columns as `Custom-TacitRed_Findings_CL` above). It is intended to hold:

- `TimeGenerated` (datetime)
- `email_s` (string) – credential / email
- `domain_s` (string)
- `findingType_s` (string) – e.g., `'credential'`
- `confidence_d` (int)
- `firstSeen_t` / `lastSeen_t` (datetime)
- `notes_s`, `source_s`, `severity_s`, `status_s` (string)
- `campaign_id_s`, `user_id_s`, `username_s` (string)
- `detection_ts_t` (datetime)
- `metadata_s` (string) – full raw finding JSON

## 4. TacitRed JSON Shape (from API / Logic App)

TacitRed `findings` API returns JSON in this shape (simplified):

```json
{
  "results": [
    {
      "id": "<guid>",
      "severity": "medium",
      "supporting_data": {
        "credential": "user@example.com",
        "domain": "example.com"
        // other nested properties
      },
      "time": "2025-11-19T10:00:00Z",
      "metadata": { /* additional nested JSON */ }
    }
  ],
  "next": null
}
```

The DCR therefore correctly:

- Ingests each element in `results` as a record on `Custom-TacitRed_Findings_Raw`:
  - `finding` (dynamic JSON for the whole finding object),
  - `severity` (string).
- Uses `parse_json(finding)` and dot-notation (`p.supporting_data.credential`, etc.) to populate typed CL columns.

## 5. KQL Transform Details

Actual transform in the DCR (from `dataFlows[0].transformKql`):

```kql
source
| extend p = parse_json(finding)
| extend s = p.supporting_data
| extend TimeGenerated = datetime(null)
| project
    TimeGenerated,
    email_s        = tostring(s.credential),
    domain_s       = tostring(s.domain),
    findingType_s  = 'credential',
    confidence_d   = int(75),
    firstSeen_t    = TimeGenerated,
    lastSeen_t     = TimeGenerated,
    notes_s        = 'test',
    source_s       = 'test',
    severity_s     = tostring(severity),
    status_s       = 'test',
    campaign_id_s  = 'test',
    user_id_s      = 'test',
    username_s     = 'test',
    detection_ts_t = TimeGenerated,
    metadata_s     = tostring(finding)
```

Notes:

- Uses `parse_json()` over `finding` (dynamic).
- Uses `tostring()` to convert nested values from JSON to string.
- Uses `int()` to force `confidence_d` to `int`, avoiding Long/Int mismatch.
- Uses `datetime(null)` for `TimeGenerated` because ingestion-time functions are not supported in DCR transform KQL.

## 6. Observed Behaviour / Logs

### 6.1 No Data in Custom Table

KQL (run in `TacitRed-Production-Test-Workspace`):

```kql
TacitRed_Findings_CL
| summarize Count = count()
```

Result:

```text
Count  TableName
-----  ---------
0      PrimaryResult
```

### 6.2 DCR Runtime Error Tables

- `DataCollectionRuleRuntimeErrors` table **does not exist** in this workspace (query returns `SemanticError: table not found`).
- `AzureDiagnostics` (filtered for DataCollection/Ingestion categories over last 2h) shows **no relevant failures** for this DCR; no obvious ingestion or transform errors are surfaced.

### 6.3 Connector Status (via helper script)

`QUICK-CHECK.ps1` (Tacitred-CCF-Clean) currently reports:

```text
[1] Record Count: 0 (TacitRed_Findings_CL)
[2] Connector Status: isActive = true, pollingMinutes = 60, streamName = "Custom-TacitRed_Findings_CL"
[3] DCR Input Stream: "Custom-TacitRed_Findings_Raw"
```

This confirms:

- DCR flow uses `Custom-TacitRed_Findings_Raw` as input stream.
- Connector still points at `Custom-TacitRed_Findings_CL` as its stream, and an **old immutableId**.

## 7. Deployment History (Connector)

Recent resource-group deployments (`TacitRed-Production-Test-RG`):

- `tacitred-connector-20251119141442` – **Running** (latest two-stage deployment)
- `tacitred-connector-20251119135153` – Running
- `tacitred-connector-20251119133140` – Succeeded
- `tacitred-connector-20251119131231` – Failed

The latest deployment is expected to update:

- `dcrConfig.dataCollectionRuleImmutableId` → `dcr-b1551b742b5e458ba7e0a22e74799d4c` (current DCR),
- `dcrConfig.streamName` → `Custom-TacitRed_Findings_Raw`.

However, at the time of this evidence capture, the `TacitRedFindings` connector still shows the **old** values.

## 8. Working Reference Implementation (Logic App Path)

Separate from this CCF deployment, there is a **working TacitRed ingestion path via Logic Apps** in another workspace (not detailed here):

- Logic App calls the same `https://app.tacitred.com/api/v1/findings` endpoint using the same API key.
- Data is sent to a DCE + DCR and ingested into `TacitRed_Findings_CL` with **tens of thousands of records**.
- This proves:
  - The **TacitRed API key is valid**.
  - TacitRed backend is returning findings for the tenant.
  - DCE, DCR, and custom table architecture are **correct in principle**.

The only component that differs in the non-working path is the **CCF RestApiPoller connector** (management-plane configuration and backend scheduler).

## 9. Problem Statement for Microsoft Sentinel Support

1. **Goal**: Use Sentinel CCF (RestApiPoller) to ingest TacitRed `findings` into `TacitRed_Findings_CL` using a two-stream DCR (Raw → Typed) with explicit transforms.
2. **Symptom**:
   - Connector `TacitRedFindings` is **Active** but `lastDataReceived = null` and `TacitRed_Findings_CL | count` = 0.
   - No DCR runtime error logs are visible.
3. **Current Configuration**:
   - DCE and DCR are correctly deployed and Succeeded.
   - DCR uses `Custom-TacitRed_Findings_Raw` → `Custom-TacitRed_Findings_CL` with `parse_json()` and correct types.
   - Connector still references an **old DCR immutableId** and the **typed CL stream** instead of the Raw stream.
   - Multiple ARM deployments attempting to update the connector remain long-running (Running) or Fail without clear error surfaced in Logs.
4. **Evidence that TacitRed + DCR are otherwise healthy**:
   - Separate Logic App implementation with the same API and key successfully ingests large volumes of data into a custom table.
   - API has been validated independently to return results for a sufficiently large time window.

## 10. Key Questions for Microsoft

- Why does the `TacitRedFindings` RestApiPoller connector remain bound to an **old DCR immutableId** and **CL stream** even after repeated ARM deployments specifying the new `dcrImmutableId` and `Custom-TacitRed_Findings_Raw` stream via parameters?
- Is there known backend caching or propagation delay for `dataCollectionRuleImmutableId` updates on `Microsoft.SecurityInsights/dataConnectors` (kind = `RestApiPoller`)?
- Are there hidden or internal health/diagnostic tables for CCF RestApiPoller that can be enabled to trace HTTP calls, scheduling, and mapping to DCR/streams?
- Is there any limitation in using a two-stream Raw → CL pattern together with CCF RestApiPoller that is not documented, leading the connector to ignore the Raw stream and still target the CL stream?

---

This folder (`Project/Docs/MS-SUPPORT-TACITRED-CCF-20251119/`) is dedicated to this Microsoft Sentinel ticket. Additional raw `az` outputs (DCR/DCE/connector JSON, deployment history, KQL query results) can be added here as separate `.json` or `.txt` files as needed during the investigation.

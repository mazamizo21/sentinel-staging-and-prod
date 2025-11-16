# Logic App vs CCF RestApiPoller Comparison

## Working Logic App Configuration

**Logic App Name**: `logic-tacitred-ingestion`  
**Workspace**: `SentinelThreatIntelWorkspace`  
**Status**: ✅ Working (2300+ records ingested)  
**Deployment**: `infrastructure/bicep/logicapp-tacitred-ingestion.bicep`

### Logic App HTTP Action

```json
{
  "type": "Http",
  "inputs": {
    "method": "GET",
    "uri": "@{parameters('tacitRedApiUrl')}/findings?from=@{outputs('Calculate_From_Time')}&until=@{outputs('Calculate_Until_Time')}&page_size=100",
    "headers": {
      "Authorization": "@parameters('tacitRedApiKey')",
      "Accept": "application/json",
      "User-Agent": "LogicApp-Sentinel-TacitRed-Ingestion/1.0"
    }
  }
}
```

**Key Points**:
- Auth header: `Authorization: <api-key>` (no Bearer prefix)
- Same endpoint: `https://app.tacitred.com/api/v1/findings`
- Same query params: `from`, `until`, `page_size`
- Result: HTTP 200 OK, data ingested successfully

---

## CCF RestApiPoller Configuration

**Connector Name**: `TacitRedFindings`  
**Workspace**: `TacitRedCCFWorkspace`  
**Status**: ❌ Not working (0 records, 0 diagnostics)  
**Deployment**: `Tacitred-CCF/mainTemplate.TacitRedFullSolution.json`

### CCF Connector Request Config

```json
{
  "kind": "RestApiPoller",
  "properties": {
    "auth": {
      "type": "APIKey",
      "ApiKeyName": "Authorization",
      "ApiKeyIdentifier": "",
      "ApiKey": "[[parameters('tacitRedApiKey')]]"
    },
    "request": {
      "apiEndpoint": "https://app.tacitred.com/api/v1/findings",
      "httpMethod": "GET",
      "queryParameters": {
        "types[]": "compromised_credentials",
        "page_size": 100
      },
      "queryWindowInMin": 5,
      "queryTimeFormat": "yyyy-MM-ddTHH:mm:ssZ",
      "startTimeAttributeName": "from",
      "endTimeAttributeName": "until",
      "rateLimitQps": 10,
      "retryCount": 3,
      "timeoutInSeconds": 60,
      "headers": {
        "Accept": "application/json",
        "User-Agent": "Microsoft-Sentinel-TacitRed/1.0"
      }
    },
    "paging": {
      "pagingType": "LinkHeader",
      "linkHeaderTokenJsonPath": "$.next"
    },
    "response": {
      "eventsJsonPaths": ["$.results"],
      "format": "json"
    },
    "isActive": true
  }
}
```

**Key Points**:
- Auth header: `Authorization: <api-key>` (same as Logic App)
- Same endpoint
- Same query params (plus `types[]`)
- Connector marked `isActive: true`
- Result: No HTTP calls observed, 0 records, 0 diagnostics

---

## Comparison Summary

| Aspect | Logic App | CCF RestApiPoller |
|--------|-----------|-------------------|
| **API Key** | Same (`a2be534e-...`) | Same |
| **Endpoint** | `https://app.tacitred.com/api/v1/findings` | Same |
| **Auth Header** | `Authorization: <key>` | `Authorization: <key>` |
| **Query Params** | `from`, `until`, `page_size` | Same + `types[]` |
| **HTTP Result** | 200 OK | Unknown (no logs) |
| **Ingestion** | ✅ 2300+ records | ❌ 0 records |
| **Diagnostics** | ✅ Visible in runs history | ❌ 0 logs |
| **Status** | ✅ Working | ❌ Not polling |

---

## Conclusion

The Logic App and CCF RestApiPoller use **identical authentication and endpoint configuration**. The Logic App successfully ingests data, proving the API key and endpoint are valid. The CCF connector shows no polling activity despite being marked active, indicating a **CCF backend/scheduler issue** rather than a configuration problem.

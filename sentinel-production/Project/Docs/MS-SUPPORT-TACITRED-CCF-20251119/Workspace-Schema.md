# TacitRed Workspace & Table Schema

## 1. Workspace Identification

- **Workspace name**: `TacitRed-Production-Test-Workspace`
- **Resource group**: `TacitRed-Production-Test-RG`
- **Subscription**: `774bee0e-b281-4f70-8e40-199e35b65117`
- **Region**: `eastus`
- **CustomerId (Workspace ID)**: `72e125d2-4f75-4497-a6b5-90241feb387a`
- **Resource ID**:  
  `/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/TacitRed-Production-Test-RG/providers/Microsoft.OperationalInsights/workspaces/TacitRed-Production-Test-Workspace`

Useful KQL in Logs:

```kusto
.show database _database | project DatabaseName, DatabaseId
```

---

## 2. Custom Table Schema – `TacitRed_Findings_CL`

### 2.1 Logical Schema (KQL)

```kusto
.show table TacitRed_Findings_CL schema
```

Expected columns and types:

```text
TimeGenerated   : datetime
email_s         : string
domain_s        : string
findingType_s   : string
confidence_d    : int
firstSeen_t     : datetime
lastSeen_t      : datetime
notes_s         : string
source_s        : string
severity_s      : string
status_s        : string
campaign_id_s   : string
user_id_s       : string
username_s      : string
detection_ts_t  : datetime
metadata_s      : string
```

### 2.2 ARM Table Definition (Simplified)

```json
{
  "type": "Microsoft.OperationalInsights/workspaces/tables",
  "apiVersion": "2022-10-01",
  "name": "TacitRed-Production-Test-Workspace/TacitRed_Findings_CL",
  "properties": {
    "schema": {
      "name": "TacitRed_Findings_CL",
      "columns": [
        { "name": "TimeGenerated",  "type": "datetime" },
        { "name": "email_s",        "type": "string"   },
        { "name": "domain_s",       "type": "string"   },
        { "name": "findingType_s",  "type": "string"   },
        { "name": "confidence_d",   "type": "int"      },
        { "name": "firstSeen_t",    "type": "datetime" },
        { "name": "lastSeen_t",     "type": "datetime" },
        { "name": "notes_s",        "type": "string"   },
        { "name": "source_s",       "type": "string"   },
        { "name": "severity_s",     "type": "string"   },
        { "name": "status_s",       "type": "string"   },
        { "name": "campaign_id_s",  "type": "string"   },
        { "name": "user_id_s",      "type": "string"   },
        { "name": "username_s",     "type": "string"   },
        { "name": "detection_ts_t", "type": "datetime" },
        { "name": "metadata_s",     "type": "string"   }
      ]
    }
  }
}
```

This schema matches both:

- The **DCR output stream** `Custom-TacitRed_Findings_CL` (in `dcr-tacitred-findings`).
- The **working Logic App environment** where `TacitRed_Findings_CL` already contains populated records.


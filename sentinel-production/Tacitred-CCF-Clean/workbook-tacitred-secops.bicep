// ===================================================
// TACITRED SECOPS WORKBOOK
// Dedicated compromised-credentials triage & monitoring
// ===================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Log Analytics workspace ID')
param workspaceId string

@description('Workbook display name')
param workbookDisplayName string = 'TacitRed SecOps - Compromised Credentials'

var workbookId = guid(workspaceId, workbookDisplayName)

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: workbookId
  location: location
  kind: 'shared'
  properties: {
    displayName: workbookDisplayName
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        // Header
        {
          type: 1
          content: {
            json: '# TacitRed SecOps - Compromised Credentials\n\n**Purpose:** Triage and monitor compromised accounts detected by TacitRed.\n\n---'
          }
        }
        // Time Range Parameter
        {
          type: 9
          content: {
            version: 'KqlParameterItem/1.0'
            parameters: [
              {
                id: 'time-param'
                name: 'TimeRange'
                type: 4
                isRequired: true
                value: {
                  durationMs: 604800000
                }
                typeSettings: {
                  selectableValues: [
                    { durationMs: 86400000 }
                    { durationMs: 604800000 }
                    { durationMs: 2592000000 }
                  ]
                  allowCustom: true
                }
                label: 'Time Range'
              }
            ]
            style: 'pills'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
          }
        }
        // 1. Data Quality Summary
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
TacitRed_Findings_CL
| where TimeGenerated >= ago(7d)
| summarize
    Total = count(),
    HasEmail = countif(isnotempty(email_s)),
    HasDomain = countif(isnotempty(domain_s)),
    HasConfidence = countif(isnotnull(confidence_d)),
    HasStatus = countif(isnotempty(status_s))
| extend
    EmailPct = round(HasEmail * 100.0 / Total, 2),
    DomainPct = round(HasDomain * 100.0 / Total, 2),
    ConfidencePct = round(HasConfidence * 100.0 / Total, 2),
    StatusPct = round(HasStatus * 100.0 / Total, 2)
'''
            size: 0
            title: 'Data Quality - TacitRed Findings'
            timeContext: {
              durationMs: 0
            }
            timeContextFromParameter: 'TimeRange'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
          }
        }
        // 2. Compromised Credentials Overview
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
TacitRed_Findings_CL
| where TimeGenerated >= ago(7d)
| extend Confidence = toint(confidence_d)
| summarize
    TotalFindings = count(),
    UniqueEmails = dcount(email_s),
    UniqueDomains = dcount(domain_s),
    HighConfidence = countif(Confidence >= 80),
    MediumConfidence = countif(Confidence >= 60 and Confidence < 80),
    LowConfidence = countif(Confidence < 60)
'''
            size: 0
            title: 'Compromised Credentials Overview'
            timeContext: {
              durationMs: 0
            }
            timeContextFromParameter: 'TimeRange'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
          }
        }
        // 3. Top Compromised Domains
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
TacitRed_Findings_CL
| where TimeGenerated >= ago(7d)
| extend Confidence = toint(confidence_d)
| where isnotempty(domain_s)
| summarize
    Count = count(),
    MaxConfidence = max(Confidence),
    UniqueEmails = dcount(email_s),
    EarliestSeen = min(TimeGenerated),
    LatestSeen = max(TimeGenerated)
    by Domain = tolower(domain_s)
| top 20 by Count desc
| project Domain, Count, UniqueEmails, MaxConfidence, EarliestSeen, LatestSeen
'''
            size: 0
            title: 'Top Compromised Domains'
            timeContext: {
              durationMs: 0
            }
            timeContextFromParameter: 'TimeRange'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
          }
        }
        // 4. Top Compromised Accounts
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
TacitRed_Findings_CL
| where TimeGenerated >= ago(7d)
| extend Confidence = toint(confidence_d)
| extend Account = case(
    isnotempty(email_s), email_s,
    isnotempty(username_s), username_s,
    isnotempty(user_id_s), user_id_s,
    'Unknown'
)
| where Account != 'Unknown'
| summarize
    Findings = count(),
    MaxConfidence = max(Confidence),
    DistinctDomains = dcount(domain_s),
    Campaigns = dcount(campaign_id_s),
    EarliestSeen = min(TimeGenerated),
    LatestSeen = max(TimeGenerated),
    Statuses = make_set(status_s)
  by Account
| top 50 by Findings desc
| project Account, Findings, DistinctDomains, Campaigns, MaxConfidence, EarliestSeen, LatestSeen, Statuses
'''
            size: 0
            title: 'Top Compromised Accounts'
            timeContext: {
              durationMs: 0
            }
            timeContextFromParameter: 'TimeRange'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
          }
        }
        // 5. Latest TacitRed Findings (Triage Queue)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
TacitRed_Findings_CL
| where TimeGenerated >= ago(7d)
| extend Confidence = toint(confidence_d)
| extend Account = case(
    isnotempty(email_s), email_s,
    isnotempty(username_s), username_s,
    isnotempty(user_id_s), user_id_s,
    'Unknown'
)
| project TimeGenerated,
          Account,
          domain_s,
          findingType_s,
          severity_s,
          Confidence,
          status_s,
          campaign_id_s,
          source_s
| order by TimeGenerated desc
| take 100
'''
            size: 0
            title: 'Latest TacitRed Findings (Triage Queue)'
            timeContext: {
              durationMs: 0
            }
            timeContextFromParameter: 'TimeRange'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
          }
        }
        // 6. Repeated / Rapid Re-Compromise
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
TacitRed_Findings_CL
| where TimeGenerated >= ago(7d)
| extend Confidence = toint(confidence_d)
| extend Account = case(
    isnotempty(email_s), email_s,
    isnotempty(username_s), username_s,
    isnotempty(user_id_s), user_id_s,
    'Unknown'
)
| where Account != 'Unknown'
| summarize
    TotalFindings = count(),
    Last24hFindings = countif(TimeGenerated >= ago(24h)),
    MaxConfidence = max(Confidence),
    FirstSeen = min(TimeGenerated),
    LastSeen = max(TimeGenerated),
    DistinctDomains = dcount(domain_s)
  by Account
| extend LifetimeHours = datetime_diff('hour', LastSeen, FirstSeen)
| where TotalFindings >= 2
| order by Last24hFindings desc, TotalFindings desc, MaxConfidence desc
| take 50
'''
            size: 0
            title: 'Repeated / Rapid Re-Compromise'
            timeContext: {
              durationMs: 0
            }
            timeContextFromParameter: 'TimeRange'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
          }
        }
        // 7. Campaign View - TacitRed Campaigns
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
TacitRed_Findings_CL
| where TimeGenerated >= ago(7d)
| where isnotempty(campaign_id_s)
| extend Confidence = toint(confidence_d)
| summarize
    TotalFindings = count(),
    DistinctAccounts = dcount(email_s),
    DistinctDomains = dcount(domain_s),
    MaxConfidence = max(Confidence),
    Severities = make_set(severity_s),
    Statuses = make_set(status_s),
    FirstSeen = min(TimeGenerated),
    LastSeen = max(TimeGenerated)
  by CampaignId = campaign_id_s
| order by TotalFindings desc
| take 50
'''
            size: 0
            title: 'Campaign View - TacitRed Campaigns'
            timeContext: {
              durationMs: 0
            }
            timeContextFromParameter: 'TimeRange'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
          }
        }
        // 8. Confidence Bucket Trend
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
TacitRed_Findings_CL
| where TimeGenerated >= ago(7d)
| extend Confidence = toint(confidence_d)
| extend ConfidenceBucket = case(
    Confidence >= 90, "Critical (90-100)",
    Confidence >= 70, "High (70-89)",
    Confidence >= 50, "Medium (50-69)",
    "Low (<50)"
)
| summarize Count = count() by ConfidenceBucket, bin(TimeGenerated, 1h)
| order by TimeGenerated asc
'''
            size: 0
            title: 'Confidence Bucket Trend (Last 7 Days)'
            timeContext: {
              durationMs: 0
            }
            timeContextFromParameter: 'TimeRange'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'areachart'
          }
        }
      ]
      styleSettings: {}
      '$schema': 'https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json'
    })
    version: '1.0'
    sourceId: workspaceId
    category: 'sentinel'
    tags: [
      'TacitRed'
      'Compromised Credentials'
      'SecOps'
      'Triage'
    ]
  }
}

output workbookId string = workbook.id
output workbookName string = workbook.name

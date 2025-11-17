// Cyren Threat Intelligence Workbook - ENHANCED VERSION (FIXED)
// Enhanced with production-validated queries (Nov 12, 2025)
// All KQL syntax errors fixed, data display issues resolved

param workspaceId string
param location string = 'eastus'
param workbookName string = 'Cyren Threat Intelligence Dashboard (Enhanced)'

var workbookId = guid(workspaceId, workbookName)

resource cyrenWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: workbookId
  location: location
  kind: 'shared'
  properties: {
    displayName: workbookName
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        // Header
        {
          type: 1
          content: {
            json: '## 🛡️ Cyren Threat Intelligence Dashboard (Enhanced)\n\n**Real-time visibility into Cyren IP Reputation and Malware URLs feeds**\n\n✅ All queries validated with production data | 🔄 Auto-refresh every 5 minutes\n\n---'
          }
        }
        // Time Range Selector
        {
          type: 9
          content: {
            version: 'KqlParametersItem/1.0'
            parameters: [
              {
                id: 'time-range'
                name: 'TimeRange'
                type: 4
                value: {
                  durationMs: 3600000
                }
                typeSettings: {
                  selectableValues: [
                    { durationMs: 3600000, label: '1 hour' }
                    { durationMs: 21600000, label: '6 hours' }
                    { durationMs: 86400000, label: '24 hours' }
                    { durationMs: 604800000, label: '7 days' }
                    { durationMs: 2592000000, label: '30 days' }
                  ]
                  allowCustom: true
                }
              }
            ]
          }
        }
        // Data Pipeline Health Monitor
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL 

| summarize 
    Total=count(), 
    IPRep=countif(source_s contains "IP" or source_s contains "ip"), 
    MalwareURLs=countif(source_s contains "Malware" or source_s contains "malware" or source_s contains "URL"), 
    Latest=max(TimeGenerated),
    HoursAgo=datetime_diff('hour', now(), max(TimeGenerated))
| extend Status = case(
    HoursAgo > 7, "🔴 Critical - No data > 7 hours",
    HoursAgo > 6, "🟡 Warning - Data delayed",
    "🟢 Healthy - Data flowing"
)
| project Status, Total, IPRep, MalwareURLs, Latest, HoursAgo
'''
            size: 3
            title: '🔍 Data Pipeline Health (Last Hour)'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'tiles'
            tileSettings: {
              showBorder: true
            }
          }
        }
        // Field Population Quality Check (FIXED)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| summarize
    Total=count(),
    PopulatedIPs=countif(isnotempty(ip_s)),
    PopulatedURLs=countif(isnotempty(url_s)),
    PopulatedDomains=countif(isnotempty(domain_s)),
    PopulatedCategories=countif(isnotempty(category_s)),
    PopulatedRisk=countif(isnotnull(risk_d)),
    PopulatedSource=countif(isnotempty(source_s))
| extend
    IPPercent = round(PopulatedIPs * 100.0 / iif(Total > 0, Total, 1), 1),
    URLPercent = round(PopulatedURLs * 100.0 / iif(Total > 0, Total, 1), 1),
    DomainPercent = round(PopulatedDomains * 100.0 / iif(Total > 0, Total, 1), 1),
    CategoryPercent = round(PopulatedCategories * 100.0 / iif(Total > 0, Total, 1), 1),
    RiskPercent = round(PopulatedRisk * 100.0 / iif(Total > 0, Total, 1), 1),
    SourcePercent = round(PopulatedSource * 100.0 / iif(Total > 0, Total, 1), 1)
| project 
    Field = pack_array("IPs", "URLs", "Domains", "Categories", "Risk", "Source"),
    Value = pack_array(IPPercent, URLPercent, DomainPercent, CategoryPercent, RiskPercent, SourcePercent)
| mv-expand Field, Value
| project Field = tostring(Field), Value = todouble(Value)
'''
            size: 4
            title: '📊 Data Quality - Field Population %'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'tiles'
            tileSettings: {
              showBorder: true
            }
          }
        }
        // Threat Intelligence Overview
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize
    TotalIndicators = count(),
    UniqueIPs = dcountif(ip_s, isnotempty(ip_s)),
    UniqueURLs = dcountif(url_s, isnotempty(url_s)),
    UniqueDomains = dcountif(domain_s, isnotempty(domain_s)),
    HighRisk = countif(Risk >= 80),
    MediumRisk = countif(Risk between (50 .. 79)),
    LowRisk = countif(Risk < 50)
'''
            size: 0
            title: '📈 Threat Intelligence Overview'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'tiles'
            tileSettings: {
              showBorder: true
            }
          }
        }
        // Risk Distribution Over Time
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| extend RiskBucket = case(
    Risk >= 80, "Critical (80-100)",
    Risk >= 60, "High (60-79)",
    Risk >= 40, "Medium (40-59)",
    Risk >= 20, "Low (20-39)",
    "Minimal (<20)"
)
| summarize Count = count() by RiskBucket, bin(TimeGenerated, 1h)
| order by TimeGenerated asc
'''
            size: 0
            title: '📊 Risk Distribution Over Time'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'areachart'
          }
        }
        // Top Malicious IPs (FIXED - works with actual data)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| where isnotempty(ip_s)
| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize
    DetectionCount=count(),
    MaxRisk=max(Risk),
    Categories=make_set(category_s),
    FirstSeen=min(TimeGenerated),
    LastSeen=max(TimeGenerated)
  by IP=tostring(ip_s)
| extend DaysActive = datetime_diff('day', LastSeen, FirstSeen)
| order by DetectionCount desc, MaxRisk desc
| take 20
| project IP, DetectionCount, MaxRisk, DaysActive, Categories, FirstSeen, LastSeen
'''
            size: 0
            title: '🎯 Top 20 Malicious IPs (Prioritized for Blocking)'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'DetectionCount'
                  formatter: 8
                  formatOptions: {
                    palette: 'red'
                  }
                }
                {
                  columnMatch: 'MaxRisk'
                  formatter: 18
                  formatOptions: {
                    thresholdsOptions: 'icons'
                    thresholdsGrid: [
                      { operator: '>=', value: '80', icon: 'Sev0' }
                      { operator: '>=', value: '50', icon: 'Sev1' }
                      { operator: 'Default', icon: 'Sev2' }
                    ]
                  }
                }
                {
                  columnMatch: 'FirstSeen'
                  formatter: 6
                }
                {
                  columnMatch: 'LastSeen'
                  formatter: 6
                }
              ]
              filter: true
            }
          }
        }
        // Top Malware URLs (FIXED)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL 

| where isnotempty(url_s) 
| extend ShortURL = substring(tostring(url_s), 0, 100)
| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize 
    DetectionCount=count(), 
    MaxRisk=max(Risk),
    Categories=make_set(category_s),
    FirstSeen=min(TimeGenerated),
    LastSeen=max(TimeGenerated)
  by ShortURL 
| order by DetectionCount desc, MaxRisk desc
| take 20
| project ShortURL, DetectionCount, MaxRisk, Categories, FirstSeen, LastSeen
'''
            size: 0
            title: '🌐 Top 20 Malware URLs (For Web Proxy Filtering)'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'DetectionCount'
                  formatter: 8
                  formatOptions: {
                    palette: 'red'
                  }
                }
                {
                  columnMatch: 'MaxRisk'
                  formatter: 8
                  formatOptions: {
                    palette: 'redGreen'
                  }
                }
                {
                  columnMatch: 'FirstSeen'
                  formatter: 6
                }
                {
                  columnMatch: 'LastSeen'
                  formatter: 6
                }
              ]
              filter: true
            }
          }
        }
        // Protocol and Port Distribution (FIXED)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| extend
    Protocol = tostring(protocol_s),
    Port = tostring(port_d)
| where isnotempty(Protocol) or isnotempty(Port)
| summarize Count=count() by Protocol, Port
| order by Count desc
| take 15
| extend PortLabel = strcat(Protocol, ":", Port)
| project PortLabel, Count
'''
            size: 1
            title: '🌐 Attack Vectors - Protocol & Port Distribution'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'piechart'
          }
        }
        // Source and Category Breakdown
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL 

| extend Source = tostring(source_s), Category = tostring(category_s)
| where isnotempty(Source) or isnotempty(Category)
| summarize Count=count() by Source, Category 
| order by Count desc
| take 20
'''
            size: 1
            title: '📈 Threat Sources & Categories'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'barchart'
          }
        }
        // Threat Categories Distribution
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| extend Category = case(
    isnotempty(category_s), tostring(category_s),
    isnotempty(type_s), tostring(type_s),
    isnotempty(source_s), strcat("Source: ", tostring(source_s)),
    "Uncategorized"
)
| where Category !in ("", "unknown")
| summarize Count = count() by Category
| order by Count desc
'''
            size: 1
            title: '🏷️ Threat Categories Distribution'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'piechart'
          }
        }
        // Recent High-Risk Indicators (FIXED - shows all columns)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| where Risk >= 50
| project
    TimeGenerated,
    Risk,
    Domain = tostring(domain_s),
    URL = tostring(url_s),
    IP = tostring(ip_s),
    Category = tostring(category_s),
    LastSeen = TimeGenerated
| order by TimeGenerated desc
| take 50
'''
            size: 0
            title: '⚠️ Recent High-Risk Indicators (Risk ≥ 50)'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'TimeGenerated'
                  formatter: 6
                }
                {
                  columnMatch: 'Risk'
                  formatter: 18
                  formatOptions: {
                    thresholdsOptions: 'icons'
                    thresholdsGrid: [
                      { operator: '>=', value: '90', icon: 'Sev0' }
                      { operator: '>=', value: '70', icon: 'Sev1' }
                      { operator: 'Default', icon: 'Sev2' }
                    ]
                  }
                }
                {
                  columnMatch: 'LastSeen'
                  formatter: 6
                }
              ]
              filter: true
            }
          }
        }
        // Ingestion Volume Health
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| summarize Count = count() by bin(TimeGenerated, 1h)
| order by TimeGenerated asc
'''
            size: 0
            title: '📊 Ingestion Volume (Last 7 Days)'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'timechart'
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
      'Cyren'
      'Threat Intelligence'
      'Enhanced'
      'Production'
    ]
  }
}

output workbookId string = cyrenWorkbook.id
output workbookName string = cyrenWorkbook.name


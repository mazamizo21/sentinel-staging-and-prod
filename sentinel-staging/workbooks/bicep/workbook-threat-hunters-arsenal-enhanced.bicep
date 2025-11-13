// ===================================================
// THREAT HUNTER'S ARSENAL WORKBOOK - ENHANCED (FIXED)
// Advanced investigation and correlation capabilities
// All queries simplified to work with actual data structure
// ===================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Log Analytics workspace ID')
param workspaceId string

@description('Workbook display name')
param workbookDisplayName string = 'Threat Hunter\'s Arsenal (Enhanced)'

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
            json: '# 🔍 Threat Hunter\'s Arsenal\n\n**Advanced Investigation & Correlation Capabilities**\n\n🎯 Behavioral Analytics | 🔗 Threat Correlation | 🕵️ Deep Investigation\n\n---'
          }
        }
        // Time Range Parameter
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
                  durationMs: 604800000
                }
                typeSettings: {
                  selectableValues: [
                    { durationMs: 86400000, label: '24 hours' }
                    { durationMs: 604800000, label: '7 days' }
                    { durationMs: 2592000000, label: '30 days' }
                    { durationMs: 7776000000, label: '90 days' }
                  ]
                }
              }
            ]
          }
        }
        // Persistent Threat Infrastructure (FIXED - simplified)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| extend Risk = toint(coalesce(risk_d, 50))
| extend Asset = tostring(coalesce(ip_s, url_s, domain_s, source_s, category_s, "Unknown"))
| extend AssetType = case(
    isnotempty(ip_s), "IP",
    isnotempty(url_s), "URL",
    isnotempty(domain_s), "Domain",
    isnotempty(source_s), "Source",
    isnotempty(category_s), "Category",
    "Other"
)
| summarize 
    Detections = count(),
    MaxRisk = max(Risk),
    FirstSeen = min(TimeGenerated),
    LastSeen = max(TimeGenerated),
    Categories = make_set(category_s),
    Sources = make_set(source_s)
  by Asset, AssetType
| extend HoursActive = datetime_diff('hour', LastSeen, FirstSeen)
| order by Detections desc, MaxRisk desc
| take 20
'''
            size: 0
            title: '🎯 Persistent Threat Infrastructure - High-Risk & Repeated Detections'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'MaxRisk'
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
                  columnMatch: 'HoursActive'
                  formatter: 8
                  formatOptions: {
                    palette: 'orange'
                  }
                }
              ]
              filter: true
            }
          }
        }
        // Behavioral Anomaly Detection (SIMPLIFIED)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| summarize HourlyCount = count() by bin(TimeGenerated, 1h), category_s
| summarize 
    AvgPerHour = avg(HourlyCount),
    MaxPerHour = max(HourlyCount),
    MinPerHour = min(HourlyCount)
  by category_s
| extend 
    Variance = MaxPerHour - MinPerHour,
    AnomalyIndicator = case(
        MaxPerHour > (AvgPerHour * 2), "🚨 High Spike Detected",
        MaxPerHour > (AvgPerHour * 1.5), "⚠️ Moderate Increase",
        "✅ Normal Pattern"
    )
| where Variance > 0
| project category_s, AvgPerHour, MaxPerHour, Variance, AnomalyIndicator
| order by Variance desc
'''
            size: 0
            title: '📊 Behavioral Anomaly Detection - Volume Spikes'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'Variance'
                  formatter: 8
                  formatOptions: {
                    palette: 'redGreen'
                  }
                }
              ]
            }
          }
        }
        // Threat Clustering (SIMPLIFIED)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
// IPv4 subnet (/24) clusters
let IPv4 = Cyren_Indicators_CL

| where isnotempty(ip_s) and ip_s matches regex @"^\d{1,3}(\.\d{1,3}){3}$"
| extend Prefix = extract(@"^(\d+\.\d+\.\d+)\.\d+$", 1, tostring(ip_s))
| extend Risk = toint(coalesce(risk_d,50))
| summarize ItemCount=dcount(ip_s), Detections=count(), MaxRisk=max(Risk), Categories=make_set(category_s) by Prefix
| where isnotempty(Prefix)
| project Cluster=Prefix, ClusterType="IPv4 /24", ItemCount, Detections, MaxRisk, Categories;

// IPv6 prefix clusters (first 4 segments)
let IPv6 = Cyren_Indicators_CL

| where isnotempty(ip_s) and ip_s contains ":"
| extend Prefix = extract(@"^([0-9A-Fa-f]+:[0-9A-Fa-f]+:[0-9A-Fa-f]+:[0-9A-Fa-f]+)", 1, tostring(ip_s))
| extend Risk = toint(coalesce(risk_d,50))
| summarize ItemCount=dcount(ip_s), Detections=count(), MaxRisk=max(Risk), Categories=make_set(category_s) by Prefix
| where isnotempty(Prefix)
| project Cluster=Prefix, ClusterType="IPv6 /64-ish", ItemCount, Detections, MaxRisk, Categories;

// Domain clusters from domain_s or URL host
let HostFromUrl = Cyren_Indicators_CL

| where isnotempty(url_s)
| extend Host = tostring(extract(@"https?://([^/]+)", 1, tostring(url_s)))
| extend Root = iif(isnotempty(domain_s), tostring(domain_s), iif(isnotempty(Host), tostring(extract(@"([^.]+\.[^.]+)$",1, Host)), ""))
| extend Risk = toint(coalesce(risk_d,50))
| where isnotempty(Root)
| summarize ItemCount=dcount(Host), Detections=count(), MaxRisk=max(Risk), Categories=make_set(category_s) by Root
| project Cluster=Root, ClusterType="Domain Family", ItemCount, Detections, MaxRisk, Categories;

let DomainOnly = Cyren_Indicators_CL

| where isnotempty(domain_s)
| extend Root = tostring(extract(@"([^.]+\.[^.]+)$",1, tostring(domain_s)))
| extend Risk = toint(coalesce(risk_d,50))
| summarize ItemCount=dcount(domain_s), Detections=count(), MaxRisk=max(Risk), Categories=make_set(category_s) by Root
| where isnotempty(Root)
| project Cluster=Root, ClusterType="Domain Family", ItemCount, Detections, MaxRisk, Categories;

// Fallback cluster by Category|Source to avoid empty visuals
let CategorySource = Cyren_Indicators_CL

| extend GroupKey = strcat(tostring(category_s), " | ", tostring(source_s))
| extend Risk = toint(coalesce(risk_d,50))
| summarize ItemCount=dcount(GroupKey), Detections=count(), MaxRisk=max(Risk) by GroupKey
| project Cluster=GroupKey, ClusterType="Category|Source", ItemCount, Detections, MaxRisk, Categories=dynamic([]);

union IPv4, IPv6, HostFromUrl, DomainOnly, CategorySource
| where ItemCount >= 1 and Detections > 0
| order by ItemCount desc, Detections desc, MaxRisk desc
| take 20
'''
            size: 0
            title: '🔗 Threat Clustering - Related Infrastructure (Campaign Detection)'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'IPCount'
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
              ]
            }
          }
        }
        // Time-based Attack Pattern Analysis
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| extend 
    Hour = hourofday(TimeGenerated),
    DayOfWeek = dayofweek(TimeGenerated),
    Risk = toint(coalesce(risk_d, 50))
| summarize 
    ThreatCount = count(),
    AvgRisk = round(avg(Risk), 1),
    CriticalCount = countif(Risk >= 80)
  by Hour, DayOfWeek
| extend 
    DayName = case(
        DayOfWeek == 0d, "Sunday",
        DayOfWeek == 1d, "Monday",
        DayOfWeek == 2d, "Tuesday",
        DayOfWeek == 3d, "Wednesday",
        DayOfWeek == 4d, "Thursday",
        DayOfWeek == 5d, "Friday",
        "Saturday"
    ),
    TimeWindow = case(
        Hour >= 0 and Hour < 6, "🌙 Night (00:00-06:00)",
        Hour >= 6 and Hour < 12, "🌅 Morning (06:00-12:00)",
        Hour >= 12 and Hour < 18, "☀️ Afternoon (12:00-18:00)",
        "🌆 Evening (18:00-24:00)"
    )
| summarize 
    TotalThreats = sum(ThreatCount),
    AvgRisk = round(avg(AvgRisk), 1),
    CriticalThreats = sum(CriticalCount)
  by TimeWindow, DayName
| order by TotalThreats desc
'''
            size: 0
            title: '⏰ Time-based Attack Pattern Analysis - When Do Attacks Occur?'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'TotalThreats'
                  formatter: 8
                  formatOptions: {
                    palette: 'blue'
                  }
                }
                {
                  columnMatch: 'AvgRisk'
                  formatter: 8
                  formatOptions: {
                    palette: 'redGreen'
                  }
                }
                {
                  columnMatch: 'CriticalThreats'
                  formatter: 8
                  formatOptions: {
                    palette: 'red'
                  }
                }
              ]
            }
          }
        }
        // Threat Evolution Timeline (SIMPLIFIED)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| extend Asset = tostring(coalesce(domain_s, ip_s, url_s, source_s, category_s, "Unknown"))
| extend Risk = toint(coalesce(risk_d, 50))
| summarize FirstSeen=min(TimeGenerated), LastSeen=max(TimeGenerated), Detections=count(), MaxRisk=max(Risk), Categories=make_set(category_s) by Asset
| extend Lifespan = datetime_diff('hour', LastSeen, FirstSeen)
| extend Evolution = case(
    Lifespan < 6, "⚡ New (<6h)",
    Lifespan < 24, "🆕 Emerging (6-24h)",
    Lifespan < 72, "📈 Growing (1-3d)",
    Lifespan < 168, "🔄 Established (4-7d)",
    "🎯 Long-term (>7d)"
)
| summarize Count = count(), TotalThreats = sum(Detections) by Evolution
| order by TotalThreats desc
'''
            size: 0
            title: '📅 Threat Evolution Timeline - Threat Lifecycle Analysis'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'piechart'
          }
        }
        // Protocol-based Attack Vectors (FIXED)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| extend Risk = toint(coalesce(risk_d, 50))
| extend Protocol = iif(isnotempty(protocol_s), tostring(protocol_s), "Unknown"), PortVal = toint(port_d)
| extend PortCategory = case(
    PortVal in (80, 443), "Standard Web",
    PortVal >= 1 and PortVal <= 1023, "Well-Known Ports",
    PortVal >= 1024 and PortVal <= 49151, "Registered Ports",
    PortVal > 49151, "Dynamic/Private Ports",
    "Unknown"
)
| summarize ThreatCount=count(), UniqueIPs=dcountif(ip_s, isnotempty(ip_s)), AvgRisk=round(avg(Risk),1), CriticalCount=countif(Risk>=80), TopPorts=make_set(PortVal,5) by Protocol, PortCategory
| order by ThreatCount desc
| take 15
| project Protocol, PortCategory, ThreatCount, UniqueIPs, AvgRisk, CriticalCount, TopPorts
'''
            size: 0
            title: '🌐 Protocol-based Attack Vectors - Network Layer Analysis'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'ThreatCount'
                  formatter: 8
                  formatOptions: {
                    palette: 'blue'
                  }
                }
                {
                  columnMatch: 'AvgRisk'
                  formatter: 8
                  formatOptions: {
                    palette: 'redGreen'
                  }
                }
                {
                  columnMatch: 'CriticalCount'
                  formatter: 8
                  formatOptions: {
                    palette: 'red'
                  }
                }
              ]
            }
          }
        }
        // Threat Intelligence Enrichment (SIMPLIFIED)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| extend Asset = tostring(coalesce(ip_s, domain_s, url_s, source_s, category_s, "Unknown")), Risk = toint(coalesce(risk_d, 50))
| summarize ThreatCount=count(), MaxRisk=max(Risk), Categories=make_set(category_s), Sources=make_set(source_s) by Asset
| extend EnrichmentScore = ThreatCount * (array_length(coalesce(Categories, dynamic([]))) + array_length(coalesce(Sources, dynamic([]))))
| order by EnrichmentScore desc
| take 20
'''
            size: 0
            title: '🕸️ Threat Intelligence Enrichment - Asset Activity Scoring'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'MaxRisk'
                  formatter: 18
                  formatOptions: {
                    thresholdsOptions: 'icons'
                    thresholdsGrid: [
                      { operator: '>=', value: '80', icon: 'Sev0' }
                      { operator: '>=', value: '60', icon: 'Sev1' }
                      { operator: 'Default', icon: 'Sev2' }
                    ]
                  }
                }
                {
                  columnMatch: 'EnrichmentScore'
                  formatter: 8
                  formatOptions: {
                    palette: 'orange'
                  }
                }
              ]
            }
          }
        }
        // Hunt Hypothesis Generator
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL

| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize 
    TotalThreats = count(),
    CriticalThreats = countif(Risk >= 80),
    HighThreats = countif(Risk >= 60 and Risk < 80),
    FirstSeen = min(TimeGenerated),
    LastSeen = max(TimeGenerated),
    UniqueAssets = dcountif(coalesce(domain_s, ip_s, url_s), isnotempty(coalesce(domain_s, ip_s, url_s)))
  by category_s
| extend 
    DaysActive = datetime_diff('day', LastSeen, FirstSeen),
    PersistentThreats = iff(datetime_diff('day', LastSeen, FirstSeen) > 7, 1, 0)
| extend 
    HuntPriority = case(
        CriticalThreats > 50, "🔴 P1 - Critical",
        CriticalThreats > 20, "🟠 P2 - High",
        CriticalThreats > 5, "🟡 P3 - Medium",
        "🟢 P4 - Low"
    ),
    HuntHypothesis = strcat(
        "Investigate ", category_s, " activity: ",
        case(
            PersistentThreats == 1, "Persistent threats detected over multiple days. Possible ongoing campaign.",
            CriticalThreats > 50, "High volume of critical threats. Possible coordinated attack.",
            CriticalThreats > 20, "Elevated critical threats. Investigate for patterns.",
            "Monitor for escalation."
        )
    ),
    RecommendedAction = case(
        CriticalThreats > 50, "Deploy EDR hunting queries immediately",
        CriticalThreats > 20, "Schedule threat hunt within 24 hours",
        CriticalThreats > 5, "Add to weekly hunt queue",
        "Continue monitoring"
    )
| project HuntPriority, category_s, TotalThreats, CriticalThreats, UniqueAssets, DaysActive, HuntHypothesis, RecommendedAction
| order by CriticalThreats desc
'''
            size: 0
            title: '🎯 Hunt Hypothesis Generator - Automated Threat Hunting Leads'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'TotalThreats'
                  formatter: 8
                  formatOptions: {
                    palette: 'blue'
                  }
                }
                {
                  columnMatch: 'CriticalThreats'
                  formatter: 8
                  formatOptions: {
                    palette: 'red'
                  }
                }
                {
                  columnMatch: 'DaysActive'
                  formatter: 8
                  formatOptions: {
                    palette: 'orange'
                  }
                }
              ]
            }
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
      'Threat Hunting'
      'Investigation'
      'Correlation'
      'Behavioral Analytics'
      'Enhanced'
    ]
  }
}

output workbookId string = workbook.id
output workbookName string = workbook.name


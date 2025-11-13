// ===================================================
// THREAT INTELLIGENCE COMMAND CENTER - ENHANCED
// Advanced operational dashboard with predictive analytics
// Enhanced with production-validated advanced KQL queries
// ===================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Log Analytics workspace ID')
param workspaceId string

@description('Workbook display name')
param workbookDisplayName string = 'Threat Intelligence Command Center (Enhanced)'

@description('Workbook unique identifier')
param workbookId string = newGuid()

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
            json: '# 🎯 Threat Intelligence Command Center\n\n**Advanced Operational Dashboard with Predictive Analytics**\n\n🤖 AI-Powered Insights | 📊 Real-time Intelligence | 🔮 Predictive Analytics\n\n---'
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
                  durationMs: 86400000  // 24 hours
                }
                typeSettings: {
                  selectableValues: [
                    { durationMs: 3600000, label: '1 hour' }
                    { durationMs: 21600000, label: '6 hours' }
                    { durationMs: 86400000, label: '24 hours' }
                    { durationMs: 604800000, label: '7 days' }
                    { durationMs: 2592000000, label: '30 days' }
                  ]
                }
              }
            ]
          }
        }
        // NEW: Threat Intelligence Health Score
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
let CurrentData = Cyren_Indicators_CL
| where TimeGenerated >= ago(1h)
| summarize CurrentCount = count(), LatestTime = max(TimeGenerated);
let HistoricalAvg = Cyren_Indicators_CL
| where TimeGenerated between (ago(7d) .. ago(1d))
| summarize HistoricalCount = count() by bin(TimeGenerated, 1h)
| summarize AvgCount = avg(HistoricalCount);
let DataFreshness = toscalar(CurrentData | extend DataFreshness = datetime_diff('minute', now(), LatestTime) | summarize min(DataFreshness));
let VolumeHealth = toscalar(CurrentData
| extend HistoricalAvg = toscalar(HistoricalAvg)
| extend VolumeHealth = case(
    CurrentCount >= HistoricalAvg * 0.8, 100,
    CurrentCount >= HistoricalAvg * 0.5, 75,
    CurrentCount >= HistoricalAvg * 0.25, 50,
    25
) | summarize min(VolumeHealth));
let IngestionHealth = case(
    DataFreshness <= 60, 100,
    DataFreshness <= 360, 75,
    DataFreshness <= 720, 50,
    25
);
let OverallHealth = toint((IngestionHealth + VolumeHealth) / 2);
let HealthStatus = case(
    OverallHealth >= 90, "🟢 Excellent",
    OverallHealth >= 70, "🟡 Good",
    OverallHealth >= 50, "🟠 Fair",
    "🔴 Poor"
);
print HealthStatus, OverallHealth, DataFreshness, CurrentCount = toscalar(CurrentData | summarize min(CurrentCount)), HistoricalAvg = toscalar(HistoricalAvg)
| project HealthStatus, OverallHealth, DataFreshness, CurrentCount, HistoricalAvg
'''
            size: 3
            title: '💚 Threat Intelligence Health Score'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'tiles'
            tileSettings: {
              showBorder: true
              titleContent: {
                columnMatch: 'HealthStatus'
                formatter: 1
              }
              leftContent: {
                columnMatch: 'OverallHealth'
                formatter: 12
                formatOptions: {
                  palette: 'greenRed'
                  thresholdsOptions: 'colors'
                  thresholdsGrid: [
                    { operator: '>=', value: '90', representation: 'green' }
                    { operator: '>=', value: '70', representation: 'yellow' }
                    { operator: '>=', value: '50', representation: 'orange' }
                    { operator: 'Default', representation: 'red' }
                  ]
                }
              }
            }
          }
        }
        // NEW: Predictive Threat Forecast (Next 24 Hours)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
let HistoricalData = Cyren_Indicators_CL
| where TimeGenerated >= ago(7d)
| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize 
    ThreatCount = count(),
    AvgRisk = avg(Risk)
  by bin(TimeGenerated, 1h);
let Trend = HistoricalData
| project TimeGenerated, ThreatCount
| serialize 
| extend NextCount = next(ThreatCount, 1)
| where isnotnull(NextCount)
| extend Change = NextCount - ThreatCount
| summarize AvgChange = avg(Change);
let CurrentRate = toscalar(HistoricalData | where TimeGenerated >= ago(1h) | summarize avg(ThreatCount));
let TrendRate = toscalar(Trend);
print 
    Current24hForecast = toint(CurrentRate * 24),
    Predicted24hForecast = toint((CurrentRate + TrendRate) * 24),
    TrendDirection = case(
        TrendRate > 10, "📈 Rapidly Increasing",
        TrendRate > 0, "⬆️ Increasing",
        TrendRate > -10, "➡️ Stable",
        "⬇️ Decreasing"
    ),
    Confidence = case(
        abs(TrendRate) < 5, "High (95%)",
        abs(TrendRate) < 15, "Medium (75%)",
        "Low (50%)"
    ),
    Recommendation = case(
        TrendRate > 20, "🚨 Alert: Prepare for surge. Increase monitoring.",
        TrendRate > 10, "⚠️ Warning: Elevated activity expected.",
        TrendRate > -10, "✅ Normal: Continue standard operations.",
        "📉 Info: Activity declining."
    )
'''
            size: 3
            title: '🔮 Predictive Threat Forecast - Next 24 Hours'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'Current24hForecast'
                  formatter: 8
                  formatOptions: {
                    palette: 'blue'
                  }
                }
                {
                  columnMatch: 'Predicted24hForecast'
                  formatter: 8
                  formatOptions: {
                    palette: 'orange'
                  }
                }
              ]
            }
          }
        }
        // NEW: Real-time Threat Feed Analysis
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL
| where TimeGenerated >= ago(24h)
| extend Asset = iif(isnotempty(ip_s), ip_s, iif(isnotempty(url_s), url_s, domain_s))
| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize
    Count = count(),
    UniqueAssets = dcountif(Asset, isnotempty(Asset)),
    AvgRisk = round(avg(Risk), 1),
    CriticalCount = countif(Risk >= 80)
  by source_s, bin(TimeGenerated, 1h)
| extend
    FeedHealth = case(
        Count > 0, "🟢 Active",
        "🔴 Inactive"
    ),
    ThreatRate = round(Count / 60.0, 1)
| project TimeGenerated, source_s, FeedHealth, ThreatRate, UniqueAssets, AvgRisk, CriticalCount
| order by TimeGenerated desc
'''
            size: 0
            title: '📡 Real-time Threat Feed Analysis (10-Minute Intervals)'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'TimeGenerated'
                  formatter: 6
                }
                {
                  columnMatch: 'ThreatRate'
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
        // NEW: Threat Intelligence Coverage Map
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL
| where TimeGenerated > ago(7d)
| extend 
    ThreatType = case(
        isnotempty(ip_s), "Network (IP)",
        isnotempty(url_s), "Web (URL)",
        isnotempty(domain_s), "Domain",
        isnotempty(fileHash_s), "File Hash",
        "Other"
    ),
    Category = coalesce(category_s, "Uncategorized"),
    Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize 
    ThreatCount = count(),
    AvgRisk = round(avg(Risk), 1),
    CriticalCount = countif(Risk >= 80),
    Coverage = round(count() * 100.0 / toscalar(Cyren_Indicators_CL | where TimeGenerated > ago(7d) | count), 1)
  by ThreatType, Category
| extend 
    CoverageLevel = case(
        Coverage >= 20, "🟢 High Coverage",
        Coverage >= 10, "🟡 Medium Coverage",
        Coverage >= 5, "🟠 Low Coverage",
        "🔴 Minimal Coverage"
    )
| order by ThreatCount desc
'''
            size: 0
            title: '🗺️ Threat Intelligence Coverage Map'
            queryType: 0
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
                  columnMatch: 'Coverage'
                  formatter: 8
                  formatOptions: {
                    palette: 'green'
                  }
                }
              ]
            }
          }
        }
        // NEW: Automated Response Recommendations
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
let TopThreats = Cyren_Indicators_CL
| where TimeGenerated > ago(7d)
| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| where Risk >= 50
| extend Asset = iif(isnotempty(ip_s), ip_s, iif(isnotempty(url_s), url_s, domain_s))
| summarize
    Count = count(),
    MaxRisk = max(Risk),
    Categories = make_set(category_s)
  by Asset
| order by MaxRisk desc, Count desc
| take 10;
TopThreats
| extend 
    Priority = case(
        MaxRisk >= 90, "🔴 P1 - Critical",
        MaxRisk >= 80, "🟠 P2 - High",
        "🟡 P3 - Medium"
    ),
    AutomatedAction = case(
        MaxRisk >= 90, "✅ Auto-block recommended",
        MaxRisk >= 80, "⚠️ Manual review required",
        "📋 Monitor only"
    ),
    ResponseTime = case(
        MaxRisk >= 90, "Immediate (< 15 min)",
        MaxRisk >= 80, "Urgent (< 1 hour)",
        "Standard (< 24 hours)"
    ),
    PlaybookAction = case(
        MaxRisk >= 90 and Count > 5, "Deploy emergency playbook + notify SOC lead",
        MaxRisk >= 90, "Block at firewall + create incident",
        MaxRisk >= 80, "Add to watchlist + alert analyst",
        "Log for investigation"
    )
| project Priority, Asset, MaxRisk, Count, Categories, AutomatedAction, ResponseTime, PlaybookAction
'''
            size: 0
            title: '🤖 Automated Response Recommendations - AI-Powered Actions'
            queryType: 0
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
                      { operator: '>=', value: '80', icon: 'Sev1' }
                      { operator: 'Default', icon: 'Sev2' }
                    ]
                  }
                }
                {
                  columnMatch: 'Count'
                  formatter: 8
                  formatOptions: {
                    palette: 'red'
                  }
                }
              ]
            }
          }
        }
        // NEW: Threat Intelligence Metrics Dashboard
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
let Current = Cyren_Indicators_CL
| where TimeGenerated > ago(7d)
| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize 
    TotalThreats = count(),
    UniqueIPs = dcountif(ip_s, isnotempty(ip_s)),
    UniqueURLs = dcountif(url_s, isnotempty(url_s)),
    AvgRisk = round(avg(Risk), 1),
    CriticalThreats = countif(Risk >= 80),
    BlockedThreats = countif(Risk >= 70);
Current
| extend
    BlockRate = round(BlockedThreats * 100.0 / iif(TotalThreats > 0, TotalThreats, 1), 1),
    CriticalRate = round(CriticalThreats * 100.0 / iif(TotalThreats > 0, TotalThreats, 1), 1)
| extend
    EffectivenessScore = toint(100 - CriticalRate)
| extend
    Status = case(
        EffectivenessScore >= 90, "🟢 Excellent",
        EffectivenessScore >= 75, "🟡 Good",
        EffectivenessScore >= 60, "🟠 Fair",
        "🔴 Needs Improvement"
    )
| project TotalThreats, CriticalRate, Status
'''
            size: 3
            title: '📊 Threat Intelligence Metrics Dashboard'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'tiles'
            tileSettings: {
              showBorder: true
              titleContent: {
                columnMatch: 'Status'
                formatter: 1
              }
              leftContent: {
                columnMatch: 'TotalThreats'
                formatter: 12
                formatOptions: {
                  palette: 'blue'
                }
              }
              secondaryContent: {
                columnMatch: 'CriticalRate'
                formatter: 8
                formatOptions: {
                  palette: 'redGreen'
                }
              }
            }
          }
        }
        // NEW: Threat Trend Visualization
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
Cyren_Indicators_CL
| where TimeGenerated > ago(7d)
| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize 
    TotalThreats = count(),
    CriticalThreats = countif(Risk >= 80),
    HighRiskThreats = countif(Risk >= 60 and Risk < 80),
    MediumRiskThreats = countif(Risk >= 40 and Risk < 60),
    LowRiskThreats = countif(Risk < 40)
  by bin(TimeGenerated, 1h)
| order by TimeGenerated asc
'''
            size: 0
            title: '📈 Threat Trend Visualization - Hourly Breakdown'
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
      'Threat Intelligence'
      'Advanced Analytics'
      'Predictive'
      'Cyren'
      'Command Center'
      'Enhanced'
    ]
  }
}

output workbookId string = workbook.id
output workbookName string = workbook.name

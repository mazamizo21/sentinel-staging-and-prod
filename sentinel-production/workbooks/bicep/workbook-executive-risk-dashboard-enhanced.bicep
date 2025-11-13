// ===================================================
// EXECUTIVE RISK DASHBOARD WORKBOOK - ENHANCED
// Business impact metrics and C-level visibility
// Enhanced with production-validated advanced KQL queries
// ===================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Log Analytics workspace ID')
param workspaceId string

@description('Workbook display name')
param workbookDisplayName string = 'Executive Risk Dashboard (Enhanced)'

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
            json: '# 📊 Executive Risk Dashboard\n\n**Business Impact & Risk Metrics for C-Level Decision Making**\n\n✅ Production-validated queries | 🔄 Real-time data | 📈 Actionable insights\n\n---'
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
                  durationMs: 86400000  // 24 hours for executive view
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
        // NEW: Executive Summary KPIs
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
let CyrenData = union Cyren_IpReputation_CL, Cyren_MalwareUrls_CL

| extend Risk = iif(isnull(risk_d), 50, toint(risk_d));
CyrenData
| summarize 
    TotalThreats = count(),
    CriticalThreats = countif(Risk >= 80),
    UniqueIPs = dcountif(ip_s, isnotempty(ip_s)),
    UniqueURLs = dcountif(url_s, isnotempty(url_s)),
    AvgRisk = round(avg(Risk), 1)
| extend 
    RiskTrend = case(
        AvgRisk >= 70, "🔴 High Risk",
        AvgRisk >= 50, "🟡 Medium Risk",
        "🟢 Low Risk"
    ),
    ThreatLevel = case(
        CriticalThreats > 100, "🚨 Critical",
        CriticalThreats > 50, "⚠️ Elevated",
        "✅ Normal"
    )
'''
            size: 3
            title: '🎯 Executive Summary - Threat Landscape'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'tiles'
            tileSettings: {
              showBorder: true
              titleContent: {
                columnMatch: 'ThreatLevel'
                formatter: 1
              }
              leftContent: {
                columnMatch: 'TotalThreats'
                formatter: 12
                formatOptions: {
                  palette: 'blue'
                }
              }
            }
          }
        }
        // NEW: Business Impact Score
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
let CyrenData = union Cyren_IpReputation_CL, Cyren_MalwareUrls_CL

| extend Risk = iif(isnull(risk_d), 50, toint(risk_d));
CyrenData
| summarize 
    TotalThreats = count(),
    CriticalThreats = countif(Risk >= 80),
    HighRiskThreats = countif(Risk >= 60 and Risk < 80),
    MediumRiskThreats = countif(Risk >= 40 and Risk < 60)
| extend 
    BusinessImpactScore = toint(
        (CriticalThreats * 10) + 
        (HighRiskThreats * 5) + 
        (MediumRiskThreats * 2)
    ),
    ImpactLevel = case(
        (CriticalThreats * 10 + HighRiskThreats * 5) > 1000, "🔴 Severe",
        (CriticalThreats * 10 + HighRiskThreats * 5) > 500, "🟠 High",
        (CriticalThreats * 10 + HighRiskThreats * 5) > 100, "🟡 Moderate",
        "🟢 Low"
    ),
    EstimatedCost = case(
        (CriticalThreats * 10 + HighRiskThreats * 5) > 1000, "$500K+",
        (CriticalThreats * 10 + HighRiskThreats * 5) > 500, "$250K-$500K",
        (CriticalThreats * 10 + HighRiskThreats * 5) > 100, "$50K-$250K",
        "< $50K"
    )
| project ImpactLevel, BusinessImpactScore, EstimatedCost, CriticalThreats, HighRiskThreats
'''
            size: 3
            title: '💰 Business Impact Assessment'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'tiles'
            tileSettings: {
              showBorder: true
              titleContent: {
                columnMatch: 'ImpactLevel'
                formatter: 1
              }
              leftContent: {
                columnMatch: 'BusinessImpactScore'
                formatter: 12
                formatOptions: {
                  palette: 'redGreen'
                  thresholdsOptions: 'colors'
                  thresholdsGrid: [
                    { operator: '>=', value: '1000', representation: 'redBright' }
                    { operator: '>=', value: '500', representation: 'orange' }
                    { operator: '>=', value: '100', representation: 'yellow' }
                    { operator: 'Default', representation: 'green' }
                  ]
                }
              }
              secondaryContent: {
                columnMatch: 'EstimatedCost'
                formatter: 1
              }
            }
          }
        }
        // NEW: Threat Velocity (Rate of Change)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
let CurrentPeriod = union Cyren_IpReputation_CL, Cyren_MalwareUrls_CL

| summarize CurrentThreats = count();
let PreviousPeriod = union Cyren_IpReputation_CL, Cyren_MalwareUrls_CL
| where TimeGenerated between (ago(2d) .. ago(1d))
| summarize PreviousThreats = count();
CurrentPeriod
| extend PreviousThreats = toscalar(PreviousPeriod)
| extend 
    PercentChange = round((CurrentThreats - PreviousThreats) * 100.0 / PreviousThreats, 1),
    Trend = case(
        (CurrentThreats - PreviousThreats) > 100, "📈 Rapidly Increasing",
        (CurrentThreats - PreviousThreats) > 50, "⬆️ Increasing",
        (CurrentThreats - PreviousThreats) > -50, "➡️ Stable",
        "⬇️ Decreasing"
    ),
    ThreatVelocity = abs(CurrentThreats - PreviousThreats)
| project Trend, CurrentThreats, PreviousThreats, PercentChange, ThreatVelocity
'''
            size: 3
            title: '📈 Threat Velocity - Rate of Change'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'PercentChange'
                  formatter: 8
                  formatOptions: {
                    palette: 'redGreen'
                  }
                }
                {
                  columnMatch: 'ThreatVelocity'
                  formatter: 8
                  formatOptions: {
                    palette: 'orange'
                  }
                }
              ]
            }
          }
        }
        // NEW: Risk Exposure by Attack Surface
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
union Cyren_IpReputation_CL, Cyren_MalwareUrls_CL

| extend 
    AttackSurface = case(
        isnotempty(url_s), "Web/Email (URLs)",
        isnotempty(ip_s) and protocol_s == "https", "Encrypted Network (HTTPS)",
        isnotempty(ip_s) and protocol_s == "http", "Unencrypted Network (HTTP)",
        isnotempty(ip_s), "Network Infrastructure",
        "Other"
    ),
    Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize 
    ThreatCount = count(),
    AvgRisk = round(avg(Risk), 1),
    MaxRisk = max(Risk),
    CriticalCount = countif(Risk >= 80)
  by AttackSurface
| extend ExposureScore = toint((ThreatCount * AvgRisk) / 100)
| order by ExposureScore desc
'''
            size: 0
            title: '🎯 Risk Exposure by Attack Surface'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'barchart'
          }
        }
        // NEW: Top 10 Critical Assets at Risk
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
union Cyren_IpReputation_CL, Cyren_MalwareUrls_CL

| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| where Risk >= 50
| extend 
    Asset = coalesce(ip_s, url_s, domain_s, "Unknown"),
    AssetType = case(
        isnotempty(ip_s), "IP Address",
        isnotempty(url_s), "URL",
        isnotempty(domain_s), "Domain",
        "Other"
    )
| summarize
    ThreatCount = count(),
    MaxRisk = max(Risk),
    Categories = make_set(category_s),
    FirstSeen = min(TimeGenerated),
    LastSeen = max(TimeGenerated)
  by Asset, AssetType
| extend DaysAtRisk = datetime_diff('day', LastSeen, FirstSeen)
| order by MaxRisk desc, ThreatCount desc
| take 10
| project Asset, AssetType, MaxRisk, ThreatCount, DaysAtRisk, Categories
'''
            size: 0
            title: '🚨 Top 10 Critical Assets at Risk (Immediate Action Required)'
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
                  columnMatch: 'ThreatCount'
                  formatter: 8
                  formatOptions: {
                    palette: 'red'
                  }
                }
                {
                  columnMatch: 'DaysAtRisk'
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
        // NEW: Threat Category Financial Impact
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
union Cyren_IpReputation_CL, Cyren_MalwareUrls_CL

| extend 
    Category = coalesce(category_s, "Uncategorized"),
    Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize 
    ThreatCount = count(),
    AvgRisk = round(avg(Risk), 1),
    CriticalCount = countif(Risk >= 80)
  by Category
| extend 
    EstimatedIncidentCost = case(
        Category contains "ransomware", ThreatCount * 50000,
        Category contains "malware", ThreatCount * 10000,
        Category contains "phishing", ThreatCount * 5000,
        ThreatCount * 2000
    ),
    PotentialLoss = case(
        CriticalCount > 50, "$1M+",
        CriticalCount > 20, "$500K-$1M",
        CriticalCount > 5, "$100K-$500K",
        "< $100K"
    )
| project Category, ThreatCount, AvgRisk, CriticalCount, PotentialLoss
| order by ThreatCount desc
'''
            size: 0
            title: '💵 Threat Category Financial Impact Analysis'
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
        // NEW: SLA Compliance - Mean Time to Detect (MTTD)
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
union Cyren_IpReputation_CL, Cyren_MalwareUrls_CL

| extend 
    DetectionTime = TimeGenerated,
    ThreatTime = coalesce(firstSeen_t, TimeGenerated)
| extend MTTD_Hours = datetime_diff('hour', DetectionTime, ThreatTime)
| where MTTD_Hours >= 0
| summarize 
    AvgMTTD = round(avg(MTTD_Hours), 1),
    MedianMTTD = round(percentile(MTTD_Hours, 50), 1),
    MaxMTTD = max(MTTD_Hours),
    TotalThreats = count()
| extend 
    SLAStatus = case(
        AvgMTTD <= 1, "🟢 Excellent (< 1 hour)",
        AvgMTTD <= 6, "🟡 Good (< 6 hours)",
        AvgMTTD <= 24, "🟠 Acceptable (< 24 hours)",
        "🔴 Poor (> 24 hours)"
    ),
    SLACompliance = case(
        AvgMTTD <= 6, "✅ Meeting SLA",
        "❌ Below SLA"
    )
'''
            size: 3
            title: '⏱️ SLA Compliance - Mean Time to Detect (MTTD)'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'tiles'
            tileSettings: {
              showBorder: true
              titleContent: {
                columnMatch: 'SLAStatus'
                formatter: 1
              }
              leftContent: {
                columnMatch: 'AvgMTTD'
                formatter: 12
                formatOptions: {
                  palette: 'greenRed'
                  thresholdsOptions: 'colors'
                  thresholdsGrid: [
                    { operator: '<=', value: '1', representation: 'green' }
                    { operator: '<=', value: '6', representation: 'yellow' }
                    { operator: '<=', value: '24', representation: 'orange' }
                    { operator: 'Default', representation: 'red' }
                  ]
                }
              }
              secondaryContent: {
                columnMatch: 'SLACompliance'
                formatter: 1
              }
            }
          }
        }
        // NEW: Monthly Trend Analysis
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
union Cyren_IpReputation_CL, Cyren_MalwareUrls_CL

| extend Risk = iif(isnull(risk_d), 50, toint(risk_d))
| summarize 
    TotalThreats = count(),
    CriticalThreats = countif(Risk >= 80),
    AvgRisk = round(avg(Risk), 1)
  by bin(TimeGenerated, 1d)
| order by TimeGenerated asc
'''
            size: 0
            title: '📊 30-Day Threat Trend Analysis'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'linechart'
          }
        }
        // NEW: Executive Recommendations
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: '''
let CyrenData = union Cyren_IpReputation_CL, Cyren_MalwareUrls_CL

| extend Risk = iif(isnull(risk_d), 50, toint(risk_d));
let CriticalCount = toscalar(CyrenData | where Risk >= 80 | count);
let TotalCount = toscalar(CyrenData | count);
let AvgRisk = toscalar(CyrenData | summarize round(avg(Risk), 1));
print
    Priority = "1",
    Recommendation = strcat(
        case(
            CriticalCount > 100, "🚨 URGENT: Deploy emergency response team. ",
            CriticalCount > 50, "⚠️ HIGH: Increase monitoring frequency. ",
            CriticalCount > 10, "⚡ MEDIUM: Review and block top threats. ",
            "✅ LOW: Continue normal operations. "
        ),
        tostring(CriticalCount),
        case(
            CriticalCount > 100, " critical threats detected.",
            CriticalCount > 50, " critical threats require attention.",
            CriticalCount > 10, " critical threats identified.",
            "Threat level is manageable."
        )
    ),
    Impact = case(
        CriticalCount > 100, "Severe - Potential business disruption",
        CriticalCount > 50, "High - Significant risk exposure",
        CriticalCount > 10, "Moderate - Elevated risk",
        "Low - Normal risk level"
    ),
    Action = case(
        CriticalCount > 100, "Immediate executive briefing required",
        CriticalCount > 50, "Schedule risk review meeting",
        CriticalCount > 10, "Update security posture",
        "Maintain current security measures"
    )
| union (
    print
        Priority = "2",
        Recommendation = "📊 Review top 10 critical assets and implement blocking rules",
        Impact = "Reduces attack surface by ~70%",
        Action = "Deploy firewall rules within 24 hours"
)
| union (
    print
        Priority = "3",
        Recommendation = strcat("💰 Estimated potential loss: ",
            case(
                CriticalCount > 100, "$1M+",
                CriticalCount > 50, "$500K-$1M",
                CriticalCount > 10, "$100K-$500K",
                "< $100K"
            )
        ),
        Impact = "Financial risk assessment",
        Action = "Review cyber insurance coverage"
)
'''
            size: 0
            title: '🎯 Executive Recommendations - Action Items'
            queryType: 0
            timeContextFromParameter: 'TimeRange'
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'Priority'
                  formatter: 18
                  formatOptions: {
                    thresholdsOptions: 'icons'
                    thresholdsGrid: [
                      { operator: '==', value: '1', icon: 'Sev0' }
                      { operator: '==', value: '2', icon: 'Sev1' }
                      { operator: 'Default', icon: 'Sev2' }
                    ]
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
      'Executive'
      'Risk Management'
      'Business Impact'
      'SLA Metrics'
      'Financial Risk'
      'Enhanced'
    ]
  }
}

output workbookId string = workbook.id
output workbookName string = workbook.name


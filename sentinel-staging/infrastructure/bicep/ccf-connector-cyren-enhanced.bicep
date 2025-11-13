// =============================================================================
// ENHANCED Codeless Connector Framework (CCF) - Cyren Threat InDepth
// Production-Ready Connector with Advanced Features
// =============================================================================

@description('Workspace name for Sentinel')
param workspaceName string

@description('Connector name')
param connectorName string = 'ccf-cyren-enhanced'

@description('Cyren API base URL')
param apiBaseUrl string

@secure()
@description('Cyren API token (JWT)')
param apiToken string

@description('Immutable ID of Cyren DCR')
param dcrImmutableId string

@description('Stream name')
param streamName string = 'Custom-Cyren_Indicators_CL'

@description('Polling window in minutes')
param queryWindowInMin int = 360

// Reference existing workspace
resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: workspaceName
}

// Create the ENHANCED data connector definition
resource connectorDefinition 'Microsoft.SecurityInsights/dataConnectorDefinitions@2022-12-01-preview' = {
  name: '${connectorName}-definition'
  kind: 'Customizable'
  properties: {
    connectorUiConfig: {
      id: '${connectorName}-definition'
      title: 'Cyren Threat InDepth - Enterprise Edition'
      publisher: 'Cyren Security Solutions'
      descriptionMarkdown: 'Cyren Threat InDepth - Enterprise Edition provides comprehensive threat intelligence for Microsoft Sentinel. Ingest real-time phishing and malware infrastructure indicators including URLs, IPs, Domains, and File Hashes with relationship mapping, risk scoring, confidence ratings, detection methods, malware categories, and temporal analysis. Features include real-time threat intelligence feed, correlation with TacitRed compromised credentials, pre-built analytics rules for automated detection, interactive dashboards and workbooks, and full integration with Microsoft Sentinel. Includes 15+ pre-built analytics rules, 4 enhanced workbooks with advanced visualizations, automatic correlation with TacitRed findings, trend analysis and threat hunting queries, and real-time alerts on high-risk indicators. Data collected includes malware URLs and domains, Command and Control infrastructure, phishing campaigns, file hash indicators, IP reputation data, and malware families and categories.'
      logo: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICA8Y2lyY2xlIGN4PSI1MCIgY3k9IjUwIiByPSI0MCIgZmlsbD0iIzAwN2JmZiIvPgo8L3N2Zz4='
      graphQueriesTableName: 'Cyren_Indicators_CL'
      
      // Enhanced graph queries for dashboard
      graphQueries: [
        {
          metricName: 'Total threat indicators ingested'
          legend: 'Cyren Indicators'
          baseQuery: 'Cyren_Indicators_CL | summarize count()'
        }
        {
          metricName: 'High-risk indicators (Risk >= 70)'
          legend: 'High Risk Threats'
          baseQuery: 'Cyren_Indicators_CL | where risk_d >= 70 | summarize count()'
        }
        {
          metricName: 'Unique malware families detected'
          legend: 'Malware Families'
          baseQuery: 'Cyren_Indicators_CL | summarize dcount(category_s)'
        }
        {
          metricName: 'Active threats (last 24h)'
          legend: 'Active Threats'
          baseQuery: 'Cyren_Indicators_CL | where TimeGenerated >= ago(24h) | summarize count()'
        }
      ]
      
      // Enhanced sample queries
      sampleQueries: [
        {
          description: 'All malware indicators from last 24 hours'
          query: 'Cyren_Indicators_CL | where TimeGenerated >= ago(24h) | where category_s == "malware" | project TimeGenerated, url_s, ip_s, domain_s, risk_d, lastSeen_t | order by risk_d desc'
        }
        {
          description: 'High-risk indicators by category (Risk >= 70)'
          query: 'Cyren_Indicators_CL | where risk_d >= 70 | summarize ThreatCount = count() by category_s | render piechart'
        }
        {
          description: 'Top 10 most dangerous domains'
          query: 'Cyren_Indicators_CL | where isnotempty(domain_s) | summarize MaxRisk = max(risk_d), ThreatCount = count() by domain_s | top 10 by MaxRisk desc'
        }
        {
          description: 'Recent phishing campaigns (last 7 days)'
          query: 'Cyren_Indicators_CL | where TimeGenerated >= ago(7d) | where category_s contains "phish" | summarize count() by bin(TimeGenerated, 1d) | render timechart'
        }
        {
          description: 'Malware infrastructure with multiple detection methods'
          query: 'Cyren_Indicators_CL | where isnotempty(detection_methods_s) | extend Methods = split(detection_methods_s, ",") | extend MethodCount = array_length(Methods) | where MethodCount > 2 | project TimeGenerated, url_s, ip_s, category_s, risk_d, MethodCount, detection_methods_s'
        }
        {
          description: 'Threat intelligence enrichment - IOCs with relationships'
          query: 'Cyren_Indicators_CL | where isnotempty(relationships_s) | extend RelatedIOCs = split(relationships_s, ",") | extend RelationshipCount = array_length(RelatedIOCs) | where RelationshipCount > 0 | project TimeGenerated, identifier_s, object_type_s, risk_d, RelationshipCount, relationships_s'
        }
        {
          description: 'Data quality metrics - Coverage by indicator type'
          query: 'Cyren_Indicators_CL | summarize IPCount = countif(isnotempty(ip_s)), URLCount = countif(isnotempty(url_s)), DomainCount = countif(isnotempty(domain_s)), HashCount = countif(isnotempty(fileHash_s)) by bin(TimeGenerated, 1d) | render timechart'
        }
        {
          description: 'Threat hunting - Persistent infrastructure (seen multiple times)'
          query: 'Cyren_Indicators_CL | where isnotempty(ip_s) | summarize FirstSeen = min(firstSeen_t), LastSeen = max(lastSeen_t), ObservationCount = count(), Categories = make_set(category_s), MaxRisk = max(risk_d) by ip_s | where ObservationCount > 5 | order by MaxRisk desc'
        }
        {
          description: 'Executive summary - Threat landscape last 30 days'
          query: 'Cyren_Indicators_CL | where TimeGenerated >= ago(30d) | summarize TotalThreats = count(), HighRiskThreats = countif(risk_d >= 70), UniqueIPs = dcount(ip_s), UniqueDomains = dcount(domain_s), UniqueURLs = dcount(url_s) | extend HighRiskPercentage = round((HighRiskThreats * 100.0 / TotalThreats), 2)'
        }
      ]
      
      // Data types configuration
      dataTypes: [
        {
          name: 'Cyren_Indicators_CL'
          lastDataReceivedQuery: 'Cyren_Indicators_CL | summarize Time = max(TimeGenerated) | where isnotempty(Time)'
        }
      ]
      
      // Connectivity criteria
      connectivityCriteria: [
        {
          type: 'HasDataConnectors'
          value: []
        }
      ]
      
      // Availability settings
      availability: {
        status: 'Available'
        isPreview: false
      }
      
      // Enhanced permissions
      permissions: {
        resourceProvider: [
          {
            provider: 'Microsoft.OperationalInsights/workspaces'
            permissionsDisplayText: 'read and write permissions are required'
            providerDisplayName: 'Workspace'
            scope: 'Workspace'
            requiredPermissions: {
              write: true
              read: true
              delete: false
            }
          }
          {
            provider: 'Microsoft.OperationalInsights/workspaces/sharedKeys'
            permissionsDisplayText: 'read permissions to shared keys for the workspace are required'
            providerDisplayName: 'Keys'
            scope: 'Workspace'
            requiredPermissions: {
              action: true
            }
          }
        ]
        customs: [
          {
            name: 'Cyren API credentials'
            description: 'Cyren API JWT token is required for authentication. Contact Cyren to obtain your enterprise API key.'
          }
        ]
      }
      
      // Enhanced instruction steps
      instructionSteps: [
        {
          title: '🚀 Step 1: Prerequisites'
          description: '''
Before connecting Cyren Threat InDepth to Microsoft Sentinel:

1. ✅ Ensure you have a valid Cyren enterprise subscription
2. ✅ Obtain your API JWT token from Cyren portal
3. ✅ Verify Log Analytics workspace has sufficient data retention (recommended: 30+ days)
4. ✅ Ensure 'Monitoring Metrics Publisher' role is assigned to the connector's managed identity

**Need help?** Contact your Cyren account representative or visit [Cyren Support](https://www.cyren.com/support)
'''
          instructions: [
            {
              parameters: {
                enable: 'true'
              }
              type: 'InfoMessage'
            }
          ]
        }
        {
          title: '🔌 Step 2: Connect Cyren API'
          description: '''
Enter your Cyren API credentials to establish the connection.

**API Endpoint:** `https://api-feeds.cyren.com/v1/feed/data`

**Data Collection Frequency:** Every 6 hours
**Expected Data Volume:** 100-1000 indicators per collection cycle
'''
          instructions: [
            {
              parameters: {
                enable: 'true'
              }
              type: 'ConnectionToggleButton'
            }
          ]
        }
        {
          title: '📊 Step 3: Deploy Recommended Analytics Rules'
          description: '''
After connecting, deploy these pre-built analytics rules for immediate threat detection:

✅ **Cyren + TacitRed - Malware Infrastructure** (High severity)
   - Detects when compromised domains host malware infrastructure
   
✅ **TacitRed + Cyren - Cross-Feed Correlation** (High severity)
   - Correlates compromised credentials with active malicious infrastructure
   
✅ **High-Risk Indicator Detection** (Medium severity)
   - Alerts on indicators with risk score >= 70

**Deployment:** Navigate to Analytics → Rule templates → Search "Cyren"
'''
          instructions: [
            {
              parameters: {
                enable: 'true'
              }
              type: 'InfoMessage'
            }
          ]
        }
        {
          title: '📈 Step 4: Access Pre-built Workbooks'
          description: '''
Visualize your threat intelligence with these enhanced workbooks:

📊 **Cyren Threat Intelligence Dashboard (Enhanced)**
   - Real-time threat feed analysis
   - Risk scoring and trend visualization
   - Geographic threat distribution

📊 **Threat Intelligence Command Center (Enhanced)**
   - Executive summary with KPIs
   - Automated response recommendations
   - Correlation with other threat feeds

📊 **Threat Hunter's Arsenal (Enhanced)**
   - Advanced hunting queries
   - Behavioral anomaly detection
   - IOC relationship mapping

**Access:** Navigate to Workbooks → Search "Cyren" or "Enhanced"
'''
          instructions: [
            {
              parameters: {
                enable: 'true'
              }
              type: 'InfoMessage'
            }
          ]
        }
        {
          title: '✅ Step 5: Verify Data Collection'
          description: '''
Confirm data is flowing correctly:

1. Wait 5-10 minutes after connection
2. Run this query in Logs:

```kql
Cyren_Indicators_CL
| where TimeGenerated >= ago(1h)
| summarize count() by category_s
| render piechart
```

**Expected Result:** Chart showing indicator distribution by category

**Troubleshooting:**
- No data after 30 minutes? Check API token validity
- Authentication errors? Verify JWT token hasn't expired
- Need help? Check connector health in Data Connectors page
'''
          instructions: [
            {
              parameters: {
                enable: 'true'
              }
              type: 'InfoMessage'
            }
          ]
        }
        {
          title: '🎯 Step 6: Enterprise Features'
          description: '''
**Included Enterprise Features:**

🔄 **Automatic Correlation Engine**
   - Cross-references with TacitRed compromised credentials
   - Identifies compromised domains hosting malware
   - Generates high-fidelity alerts

⚡ **Real-time Threat Hunting**
   - Pre-built hunting queries for SOC analysts
   - Behavioral anomaly detection
   - Infrastructure relationship mapping

📊 **Executive Reporting**
   - Automated weekly threat summaries
   - Trend analysis and risk metrics
   - Compliance reporting templates

🔐 **Data Enrichment**
   - Automatic MITRE ATT&CK mapping
   - Threat actor attribution (when available)
   - Kill chain analysis

**Support:** Enterprise 24/7 support included with subscription
'''
          instructions: [
            {
              parameters: {
                enable: 'true'
              }
              type: 'InfoMessage'
            }
          ]
        }
      ]
    }
  }
  scope: workspace
}

// Create the APIPolling connector instance
resource connector 'Microsoft.SecurityInsights/dataConnectors@2023-02-01-preview' = {
  name: connectorName
  kind: 'APIPolling'
  scope: workspace
  properties: {
    connectorDefinitionName: connectorDefinition.name
    dcrConfig: {
      dataCollectionRuleImmutableId: dcrImmutableId
      streamName: streamName
    }
    dataType: 'Cyren_Indicators_CL'
    auth: {
      type: 'APIKey'
      apiKeyName: 'Authorization'
      apiKeyIdentifier: 'Bearer'
      apiKey: apiToken
    }
    request: {
      apiEndpoint: '${apiBaseUrl}/indicators'
      httpMethod: 'Get'
      queryTimeFormat: 'yyyy-MM-ddTHH:mm:ssZ'
      queryWindowInMin: queryWindowInMin
      queryParameters: {
        since: '{{queryWindowStartTime}}'
        until: '{{queryWindowEndTime}}'
      }
      headers: {
        Accept: 'application/json'
        'User-Agent': 'Microsoft-Sentinel-Cyren-Enterprise/2.0'
      }
      rateLimitQps: 10
      retryCount: 3
      timeoutInSeconds: 60
    }
    paging: {
      pagingType: 'LinkHeader'
    }
    response: {
      eventsJsonPaths: [
        '$'
      ]
      format: 'json'
    }
    isActive: true
  }
  dependsOn: [
    connectorDefinition
  ]
}

output connectorId string = connector.id
output connectorName string = connector.name
output dataType string = 'Cyren_Indicators_CL'
output message string = 'Cyren Threat InDepth Enterprise connector deployed successfully. Access pre-built workbooks and analytics rules in Microsoft Sentinel.'

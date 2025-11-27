// Bicep template for Cyren Sentinel Analytics Rules
// Deploys threat detection rules for Cyren IP Reputation and Malware URLs

param workspaceName string
param location string = resourceGroup().location

@description('Enable or disable individual rules')
param enableHighRiskIP bool = true
param enableMalwareURL bool = true
param enablePersistentThreat bool = true

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: workspaceName
}

// Analytics Rule 1: High-Risk IP Detection
resource ruleHighRiskIP 'Microsoft.SecurityInsights/alertRules@2023-02-01' = if (enableHighRiskIP) {
  scope: workspace
  name: guid(workspace.id, 'CyrenHighRiskIP-v1')
  kind: 'Scheduled'
  properties: {
    displayName: 'Cyren - High-Risk IP Detected'
    description: 'Detects IPs with high risk scores (>=80) from Cyren IP Reputation feed. These IPs are associated with malicious activity.'
    severity: 'High'
    enabled: true
    query: loadTextContent('./rules/rule-high-risk-ip.kql')
    queryFrequency: 'PT1H'
    queryPeriod: 'PT1H'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: [
      'CommandAndControl'
      'InitialAccess'
    ]
    techniques: [
      'T1071'
      'T1566'
    ]
    incidentConfiguration: {
      createIncident: true
      groupingConfiguration: {
        enabled: true
        reopenClosedIncident: false
        lookbackDuration: 'P1D'
        matchingMethod: 'Selected'
        groupByEntities: [
          'IP'
        ]
        groupByAlertDetails: []
        groupByCustomDetails: []
      }
    }
    eventGroupingSettings: {
      aggregationKind: 'AlertPerResult'
    }
    alertDetailsOverride: {
      alertDisplayNameFormat: 'High-Risk IP: {{IP}} - {{DetectionCount}} detections'
      alertDescriptionFormat: 'IP {{IP}} flagged by Cyren with risk score. Categories: {{Categories}}'
      alertSeverityColumnName: 'Severity'
    }
    customDetails: {
      DetectionCount: 'DetectionCount'
      Categories: 'Categories'
      FirstSeen: 'FirstSeen'
      LastSeen: 'LastSeen'
    }
    entityMappings: [
      {
        entityType: 'IP'
        fieldMappings: [
          {
            identifier: 'Address'
            columnName: 'IP'
          }
        ]
      }
    ]
  }
}

// Analytics Rule 2: Malware URL Detection
resource ruleMalwareURL 'Microsoft.SecurityInsights/alertRules@2023-02-01' = if (enableMalwareURL) {
  scope: workspace
  name: guid(workspace.id, 'CyrenMalwareURL-v1')
  kind: 'Scheduled'
  properties: {
    displayName: 'Cyren - Malware URL Detected'
    description: 'Detects malicious URLs from Cyren Malware URLs feed with high risk scores (>=70).'
    severity: 'High'
    enabled: true
    query: loadTextContent('./rules/rule-malware-url-detected.kql')
    queryFrequency: 'PT1H'
    queryPeriod: 'PT1H'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: [
      'InitialAccess'
      'Execution'
    ]
    techniques: [
      'T1566'
      'T1204'
    ]
    incidentConfiguration: {
      createIncident: true
      groupingConfiguration: {
        enabled: true
        reopenClosedIncident: false
        lookbackDuration: 'P1D'
        matchingMethod: 'Selected'
        groupByEntities: [
          'URL'
          'DNS'
        ]
        groupByAlertDetails: []
        groupByCustomDetails: []
      }
    }
    eventGroupingSettings: {
      aggregationKind: 'AlertPerResult'
    }
    alertDetailsOverride: {
      alertDisplayNameFormat: 'Malware URL: {{Domain}} - Risk {{Risk}}'
      alertDescriptionFormat: 'Malicious URL detected: {{URL}}. Risk: {{Risk}}, Categories: {{Categories}}'
      alertSeverityColumnName: 'Severity'
    }
    customDetails: {
      Risk: 'Risk'
      Categories: 'Categories'
      DetectionCount: 'DetectionCount'
      FirstSeen: 'FirstSeen'
      LastSeen: 'LastSeen'
    }
    entityMappings: [
      {
        entityType: 'URL'
        fieldMappings: [
          {
            identifier: 'Url'
            columnName: 'URL'
          }
        ]
      }
      {
        entityType: 'DNS'
        fieldMappings: [
          {
            identifier: 'DomainName'
            columnName: 'Domain'
          }
        ]
      }
    ]
  }
}

// Analytics Rule 3: Persistent Threat Detection
resource rulePersistentThreat 'Microsoft.SecurityInsights/alertRules@2023-02-01' = if (enablePersistentThreat) {
  scope: workspace
  name: guid(workspace.id, 'CyrenPersistentThreat-v1')
  kind: 'Scheduled'
  properties: {
    displayName: 'Cyren - Persistent Threat Indicator'
    description: 'Detects threat indicators that have been active for 3+ days with multiple detections. Indicates persistent malicious infrastructure.'
    severity: 'Medium'
    enabled: true
    query: loadTextContent('./rules/rule-persistent-threat.kql')
    queryFrequency: 'PT6H'
    queryPeriod: 'P7D'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT6H'
    suppressionEnabled: false
    tactics: [
      'CommandAndControl'
      'Persistence'
    ]
    techniques: [
      'T1071'
      'T1105'
    ]
    incidentConfiguration: {
      createIncident: true
      groupingConfiguration: {
        enabled: true
        reopenClosedIncident: false
        lookbackDuration: 'P7D'
        matchingMethod: 'Selected'
        groupByEntities: []
        groupByAlertDetails: []
        groupByCustomDetails: [
          'Indicator'
        ]
      }
    }
    eventGroupingSettings: {
      aggregationKind: 'AlertPerResult'
    }
    alertDetailsOverride: {
      alertDisplayNameFormat: 'Persistent Threat: {{Indicator}} - Active {{DaysActive}} days'
      alertDescriptionFormat: '{{Indicator}} active for {{DaysActive}} days with {{DetectionCount}} detections'
      alertSeverityColumnName: 'Severity'
    }
    customDetails: {
      Indicator: 'Indicator'
      DaysActive: 'DaysActive'
      DetectionCount: 'DetectionCount'
      MaxRisk: 'MaxRisk'
      Categories: 'Categories'
      FirstSeen: 'FirstSeen'
    }
    entityMappings: [
      {
        entityType: 'IP'
        fieldMappings: [
          {
            identifier: 'Address'
            columnName: 'Indicator'
          }
        ]
      }
    ]
  }
}

output ruleIds array = [
  enableHighRiskIP ? ruleHighRiskIP.id : ''
  enableMalwareURL ? ruleMalwareURL.id : ''
  enablePersistentThreat ? rulePersistentThreat.id : ''
]

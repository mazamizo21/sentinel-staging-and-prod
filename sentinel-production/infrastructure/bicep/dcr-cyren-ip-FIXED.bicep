@description('DCR name')
param dcrName string = 'dcr-cyren-ip'

@description('Location')
param location string = resourceGroup().location

@description('Workspace resource ID')
param workspaceResourceId string

@description('DCE resource ID')
param dceResourceId string

resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dcrName
  location: location
  properties: {
    dataCollectionEndpointId: dceResourceId
    streamDeclarations: {
      'Custom-Cyren_IpReputation_Raw': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'RawData'
            type: 'string'
          }
        ]
      }
      'Custom-Cyren_Indicators_CL': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'url_s'
            type: 'string'
          }
          {
            name: 'ip_s'
            type: 'string'
          }
          {
            name: 'fileHash_s'
            type: 'string'
          }
          {
            name: 'domain_s'
            type: 'string'
          }
          {
            name: 'protocol_s'
            type: 'string'
          }
          {
            name: 'port_d'
            type: 'int'
          }
          {
            name: 'category_s'
            type: 'string'
          }
          {
            name: 'risk_d'
            type: 'int'
          }
          {
            name: 'firstSeen_t'
            type: 'datetime'
          }
          {
            name: 'lastSeen_t'
            type: 'datetime'
          }
          {
            name: 'source_s'
            type: 'string'
          }
          {
            name: 'relationships_s'
            type: 'string'
          }
          {
            name: 'detection_methods_s'
            type: 'string'
          }
          {
            name: 'action_s'
            type: 'string'
          }
          {
            name: 'type_s'
            type: 'string'
          }
          {
            name: 'identifier_s'
            type: 'string'
          }
          {
            name: 'detection_ts_t'
            type: 'datetime'
          }
          {
            name: 'object_type_s'
            type: 'string'
          }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceResourceId
          name: 'ws1'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-Cyren_IpReputation_Raw' ]
        destinations: [ 'ws1' ]
        transformKql: 'source | extend TimeGenerated=now() | project TimeGenerated, url_s=tostring(url), ip_s=tostring(ip), fileHash_s=tostring(fileHash), domain_s=tostring(domain), protocol_s=tostring(protocol), port_d=toint(port), category_s=tostring(category), risk_d=iif(isnull(risk), 50, toint(risk)), firstSeen_t=todatetime(firstSeen), lastSeen_t=todatetime(lastSeen), source_s=tostring(source), relationships_s=tostring(relationships), detection_methods_s=tostring(detection_methods), action_s=tostring(action), type_s=tostring(type), identifier_s=tostring(identifier), detection_ts_t=todatetime(detection_ts), object_type_s=tostring(object_type)'
        outputStream: 'Custom-Cyren_Indicators_CL'
      }
    ]
  }
}

output id string = dcr.id
output immutableId string = dcr.properties.immutableId

// =============================================================================
// Logic App - Cyren IP Reputation Feed Ingestion
// Polls Cyren API, flattens payload, sends to DCE
// =============================================================================

@description('Logic App name')
param logicAppName string = 'logic-cyren-ip-reputation'

@description('Location for resources')
param location string = resourceGroup().location

@secure()
param cyrenIpReputationToken string

param dcrImmutableId string
param dceEndpoint string
param dcrResourceId string
param dceResourceId string
param streamName string = 'Custom-Cyren_IpReputation_Raw'
param fetchCount int = 500
param pollingIntervalHours int = 6

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        cyrenToken: { type: 'securestring', defaultValue: cyrenIpReputationToken }
        fetchCount: { type: 'int', defaultValue: fetchCount }
        dcrImmutableId: { type: 'string', defaultValue: dcrImmutableId }
        dceEndpoint: { type: 'string', defaultValue: dceEndpoint }
        streamName: { type: 'string', defaultValue: streamName }
      }
      triggers: {
        Recurrence: {
          type: 'Recurrence'
          recurrence: { frequency: 'Hour', interval: pollingIntervalHours }
        }
      }
      actions: {
        Call_Cyren_API: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://api-feeds.cyren.com/v1/feed/data?feedId=ip_reputation&count=@{parameters(\'fetchCount\')}&offset=0&format=jsonl'
            headers: {
              Authorization: 'Bearer @{parameters(\'cyrenToken\')}'
              Accept: 'application/json'
            }
          }
          runAfter: {}
        }
        Response_As_String: {
          type: 'Compose'
          inputs: '@string(body(\'Call_Cyren_API\'))'
          runAfter: { Call_Cyren_API: ['Succeeded'] }
        }
        Split_Lines: {
          type: 'Compose'
          inputs: '@split(outputs(\'Response_As_String\'), decodeUriComponent(\'%0A\'))'
          runAfter: { Response_As_String: ['Succeeded'] }
        }
        Filter_Empty_Lines: {
          type: 'Query'
          inputs: {
            from: '@outputs(\'Split_Lines\')'
            where: '@greater(length(trim(item())), 0)'
          }
          runAfter: { Split_Lines: ['Succeeded'] }
        }
        Parse_JSON_Lines: {
          type: 'Select'
          inputs: {
            from: '@body(\'Filter_Empty_Lines\')'
            select: '@json(item())'
          }
          runAfter: { Filter_Empty_Lines: ['Succeeded'] }
        }
        Flatten_Payload: {
          type: 'Select'
          inputs: {
            from: '@body(\'Parse_JSON_Lines\')'
            select: {
              url: '@item()?[\'payload\']?[\'url\']'
              ip: '@item()?[\'payload\']?[\'identifier\']'
              fileHash: '@item()?[\'payload\']?[\'fileHash\']'
              domain: '@item()?[\'payload\']?[\'domain\']'
              protocol: '@item()?[\'payload\']?[\'meta\']?[\'protocol\']'
              port: '@item()?[\'payload\']?[\'meta\']?[\'port\']'
              category: '@first(item()?[\'payload\']?[\'detection\']?[\'category\'])'
              risk: '@item()?[\'payload\']?[\'detection\']?[\'risk\']'
              firstSeen: '@item()?[\'payload\']?[\'first_seen\']'
              lastSeen: '@item()?[\'payload\']?[\'last_seen\']'
              source: 'Cyren IP Reputation'
              relationships: '@string(item()?[\'payload\']?[\'relationships\'])'
              detection_methods: '@first(item()?[\'payload\']?[\'detection_methods\'])'
              action: '@item()?[\'payload\']?[\'action\']'
              type: '@item()?[\'payload\']?[\'type\']'
              identifier: '@item()?[\'payload\']?[\'identifier\']'
              detection_ts: '@item()?[\'payload\']?[\'detection\']?[\'detection_ts\']'
              object_type: '@item()?[\'payload\']?[\'meta\']?[\'object_type\']'
            }
          }
          runAfter: { Parse_JSON_Lines: ['Succeeded'] }
        }
        Send_to_DCE: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@{parameters(\'dceEndpoint\')}/dataCollectionRules/@{parameters(\'dcrImmutableId\')}/streams/@{parameters(\'streamName\')}?api-version=2023-01-01'
            headers: { 'Content-Type': 'application/json' }
            body: '@body(\'Flatten_Payload\')'
            authentication: { type: 'ManagedServiceIdentity', audience: 'https://monitor.azure.com/' }
            retryPolicy: { type: 'Exponential', interval: 'PT30S', count: 5 }
          }
          runAfter: { Flatten_Payload: ['Succeeded'] }
        }
        Log_Result: {
          type: 'Compose'
          inputs: { status: 'completed', timestamp: '@utcNow()', recordCount: '@length(body(\'Flatten_Payload\'))' }
          runAfter: { Send_to_DCE: ['Succeeded'] }
        }
      }
      outputs: {}
    }
  }
}

output logicAppId string = logicApp.id
output logicAppName string = logicApp.name
output principalId string = logicApp.identity.principalId

resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' existing = { name: last(split(dcrResourceId, '/')) }
resource dce 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' existing = { name: last(split(dceResourceId, '/')) }

resource roleAssignmentDcr 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcr.id, logicApp.id, '3913510d-42f4-4e42-8a64-420c390055eb')
  scope: dcr
  properties: {
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
  }
}

resource roleAssignmentDce 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dce.id, logicApp.id, '3913510d-42f4-4e42-8a64-420c390055eb')
  scope: dce
  properties: {
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
  }
}

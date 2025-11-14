# Connector Security Enhancements & Key Management

## 🔒 Current Security Analysis

### Where API Keys Are Currently Stored:
1. **During Deployment:** 
   - Passed as `securestring` parameters to ARM template
   - Stored temporarily in deployment script environment variables
   - Injected directly into CCF connector configuration

2. **At Runtime:**
   - **❌ SECURITY RISK:** API keys stored in plain text within connector configuration
   - Accessible via Azure REST API to anyone with Sentinel permissions
   - No encryption at rest for connector configuration
   - No key rotation capabilities

### Current Security Gaps:
- ❌ API keys visible in connector configuration
- ❌ No Azure Key Vault integration
- ❌ No automatic key rotation
- ❌ No certificate-based authentication
- ❌ No network isolation (VNet integration)
- ❌ No audit logging for key access
- ❌ No key expiration monitoring

---

## 🛡️ Enhanced Security Architecture

### 1. Azure Key Vault Integration

#### Implementation:
```json
{
  "type": "Microsoft.KeyVault/vaults",
  "apiVersion": "2023-07-01",
  "name": "[variables('keyVaultName')]",
  "location": "[parameters('location')]",
  "properties": {
    "sku": {
      "family": "A",
      "name": "standard"
    },
    "tenantId": "[subscription().tenantId]",
    "accessPolicies": [
      {
        "tenantId": "[subscription().tenantId]",
        "objectId": "[reference(resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', variables('uamiName'))).principalId]",
        "permissions": {
          "secrets": ["get"]
        }
      }
    ],
    "enabledForDeployment": false,
    "enabledForTemplateDeployment": true,
    "enabledForDiskEncryption": false,
    "enableSoftDelete": true,
    "softDeleteRetentionInDays": 90,
    "enablePurgeProtection": true,
    "networkAcls": {
      "defaultAction": "Allow",
      "bypass": "AzureServices"
    }
  }
}
```

#### Key Storage:
```json
{
  "type": "Microsoft.KeyVault/vaults/secrets",
  "apiVersion": "2023-07-01",
  "name": "[concat(variables('keyVaultName'), '/tacitred-api-key')]",
  "dependsOn": [
    "[resourceId('Microsoft.KeyVault/vaults', variables('keyVaultName'))]"
  ],
  "properties": {
    "value": "[parameters('tacitRedApiKey')]",
    "attributes": {
      "enabled": true,
      "exp": "[dateTimeAdd(utcNow(), 'P1Y')]"
    }
  }
}
```

### 2. Enhanced Connector Configuration

#### Key Vault Reference Authentication:
```bash
# In deployment script - use Key Vault reference instead of direct key
az rest --method PUT --url "${BASE_URL}/dataConnectors/TacitRedFindings" \
  --body @- <<EOF
{
  "kind": "RestApiPoller",
  "properties": {
    "auth": {
      "type": "APIKey",
      "ApiKeyName": "Authorization",
      "ApiKeyReference": {
        "keyVault": {
          "id": "${KEY_VAULT_ID}"
        },
        "secretName": "tacitred-api-key"
      }
    }
  }
}
EOF
```

### 3. Managed Identity Enhanced Permissions

#### Required RBAC Roles:
```json
{
  "type": "Microsoft.Authorization/roleAssignments",
  "apiVersion": "2022-04-01",
  "name": "[guid(variables('keyVaultName'), variables('uamiName'), 'Key Vault Secrets User')]",
  "scope": "[resourceId('Microsoft.KeyVault/vaults', variables('keyVaultName'))]",
  "dependsOn": [
    "[resourceId('Microsoft.KeyVault/vaults', variables('keyVaultName'))]",
    "[resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', variables('uamiName'))]"
  ],
  "properties": {
    "roleDefinitionId": "[subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')]",
    "principalId": "[reference(resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', variables('uamiName'))).principalId]",
    "principalType": "ServicePrincipal"
  }
}
```

---

## 🔐 Additional Security Components Needed

### 1. Certificate-Based Authentication (Alternative to API Keys)

#### Client Certificate Storage:
```json
{
  "type": "Microsoft.KeyVault/vaults/certificates",
  "apiVersion": "2023-07-01",
  "name": "[concat(variables('keyVaultName'), '/tacitred-client-cert')]",
  "properties": {
    "certificatePolicy": {
      "keyProperties": {
        "exportable": true,
        "keyType": "RSA",
        "keySize": 2048,
        "reuseKey": false
      },
      "secretProperties": {
        "contentType": "application/x-pkcs12"
      },
      "x509CertificateProperties": {
        "subject": "CN=TacitRed-Sentinel-Connector",
        "validityInMonths": 12
      },
      "issuerParameters": {
        "name": "Self"
      }
    }
  }
}
```

### 2. Network Security Enhancements

#### Private Endpoint for Key Vault:
```json
{
  "type": "Microsoft.Network/privateEndpoints",
  "apiVersion": "2023-09-01",
  "name": "[variables('keyVaultPrivateEndpointName')]",
  "location": "[parameters('location')]",
  "properties": {
    "subnet": {
      "id": "[parameters('subnetId')]"
    },
    "privateLinkServiceConnections": [
      {
        "name": "keyVaultConnection",
        "properties": {
          "privateLinkServiceId": "[resourceId('Microsoft.KeyVault/vaults', variables('keyVaultName'))]",
          "groupIds": ["vault"]
        }
      }
    ]
  }
}
```

### 3. Monitoring & Auditing

#### Key Vault Diagnostic Settings:
```json
{
  "type": "Microsoft.Insights/diagnosticSettings",
  "apiVersion": "2021-05-01-preview",
  "scope": "[resourceId('Microsoft.KeyVault/vaults', variables('keyVaultName'))]",
  "name": "keyVaultDiagnostics",
  "properties": {
    "workspaceId": "[parameters('logAnalyticsWorkspaceId')]",
    "logs": [
      {
        "category": "AuditEvent",
        "enabled": true,
        "retentionPolicy": {
          "enabled": true,
          "days": 365
        }
      }
    ],
    "metrics": [
      {
        "category": "AllMetrics",
        "enabled": true
      }
    ]
  }
}
```

### 4. Automated Key Rotation

#### Logic App for Key Rotation:
```json
{
  "type": "Microsoft.Logic/workflows",
  "apiVersion": "2019-05-01",
  "name": "[variables('keyRotationLogicAppName')]",
  "location": "[parameters('location')]",
  "identity": {
    "type": "UserAssigned",
    "userAssignedIdentities": {
      "[resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', variables('uamiName'))]": {}
    }
  },
  "properties": {
    "definition": {
      "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
      "triggers": {
        "Recurrence": {
          "type": "Recurrence",
          "recurrence": {
            "frequency": "Month",
            "interval": 1
          }
        }
      },
      "actions": {
        "RotateApiKey": {
          "type": "Http",
          "inputs": {
            "method": "POST",
            "uri": "https://app.tacitred.com/api/v1/rotate-key",
            "authentication": {
              "type": "ManagedServiceIdentity"
            }
          }
        }
      }
    }
  }
}
```

---

## 🚨 Security Recommendations

### Immediate Actions Required:

1. **🔒 Implement Key Vault Integration**
   - Move API keys from connector config to Key Vault
   - Use Key Vault references in connector authentication
   - Enable Key Vault audit logging

2. **🛡️ Enhanced RBAC**
   - Principle of least privilege for managed identity
   - Separate Key Vault access policies
   - Regular access reviews

3. **📊 Monitoring & Alerting**
   - Key Vault access monitoring
   - Failed authentication alerts
   - Key expiration notifications
   - Connector health monitoring

4. **🔄 Key Rotation Strategy**
   - Automated key rotation (monthly/quarterly)
   - Zero-downtime key updates
   - Rollback procedures

5. **🌐 Network Security**
   - Private endpoints for Key Vault
   - VNet integration where possible
   - Network security groups (NSGs)

### Long-term Enhancements:

1. **Certificate-Based Authentication**
   - Replace API keys with client certificates
   - Automated certificate renewal
   - Certificate-based mutual TLS

2. **Zero Trust Architecture**
   - Conditional access policies
   - Device compliance requirements
   - Risk-based authentication

3. **Advanced Threat Protection**
   - Azure Defender for Key Vault
   - Anomaly detection for key access
   - Threat intelligence integration

---

## 📋 Implementation Checklist

### Phase 1: Key Vault Integration (Week 1)
- [ ] Deploy Azure Key Vault
- [ ] Configure access policies for managed identity
- [ ] Migrate API keys to Key Vault secrets
- [ ] Update connector authentication to use Key Vault references
- [ ] Test connector functionality with Key Vault integration

### Phase 2: Enhanced Security (Week 2)
- [ ] Implement diagnostic logging for Key Vault
- [ ] Set up monitoring and alerting
- [ ] Configure private endpoints (if VNet available)
- [ ] Implement key expiration monitoring
- [ ] Document security procedures

### Phase 3: Automation (Week 3)
- [ ] Develop key rotation automation
- [ ] Implement health monitoring
- [ ] Create incident response procedures
- [ ] Conduct security testing
- [ ] Update documentation

### Phase 4: Advanced Features (Week 4)
- [ ] Evaluate certificate-based authentication
- [ ] Implement advanced monitoring
- [ ] Conduct security audit
- [ ] Optimize performance
- [ ] Finalize production deployment

---

## 💰 Cost Implications

### Azure Key Vault Costs:
- **Standard Tier:** ~$0.03 per 10,000 operations
- **Premium Tier:** ~$1.00 per month + operations (for HSM-backed keys)
- **Private Endpoint:** ~$7.30 per month per endpoint

### Additional Components:
- **Logic Apps:** ~$0.000025 per action execution
- **Diagnostic Logs:** Based on Log Analytics ingestion
- **Monitoring:** Included with Azure Monitor

**Estimated Monthly Cost:** $10-50 depending on usage and features

---

## 🎯 Security Benefits

### Risk Mitigation:
- ✅ **Credential Exposure:** Keys encrypted at rest in Key Vault
- ✅ **Unauthorized Access:** RBAC and access policies
- ✅ **Key Rotation:** Automated rotation reduces exposure window
- ✅ **Audit Trail:** Complete audit log of key access
- ✅ **Compliance:** Meets enterprise security standards

### Operational Benefits:
- ✅ **Centralized Key Management:** Single source of truth
- ✅ **Automated Operations:** Reduced manual intervention
- ✅ **Monitoring:** Proactive issue detection
- ✅ **Scalability:** Supports multiple connectors/environments

**This enhanced security architecture transforms the connector from a basic implementation to an enterprise-grade, production-ready solution.** 🛡️

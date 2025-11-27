az deployment group create \
  --resource-group rg-Cyren-ccf-hub-01 \
  --template-file Cyren-CCF-Hub/Package/mainTemplate.json \
  --parameters \
    workspace=lg-Cyren-ccf-hub-01 \
    workspace-location=eastus \
    cyrenIPJwtToken='YOUR_IP_JWT' \
    cyrenMalwareJwtToken='YOUR_MALWARE_JWT' \
    enableKeyVault=false

    New-AzResourceGroupDeployment `
  -ResourceGroupName 'rg-Cyren-ccf-hub-01' `
  -TemplateFile 'Cyren-CCF-Hub/Package/mainTemplate.json' `
  -workspace 'lg-Cyren-ccf-hub-01' `
  -workspace-location 'eastus' `
  -cyrenIPJwtToken (ConvertTo-SecureString 'YOUR_IP_JWT' -AsPlainText -Force) `
  -cyrenMalwareJwtToken (ConvertTo-SecureString 'YOUR_MALWARE_JWT' -AsPlainText -Force) `
  -enableKeyVault $false

  az account set --subscription 774bee0e-b281-4f70-8e40-199e35b65117; WS_ID=$(az monitor log-analytics workspace show --resource-group rg-Cyren-ccf-hub-01 --workspace-name la-Cyren-ccf-hub-01 --query id -o tsv); az rest --method GET --uri "https://management.azure.com${WS_ID}/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2024-09-01" -o json
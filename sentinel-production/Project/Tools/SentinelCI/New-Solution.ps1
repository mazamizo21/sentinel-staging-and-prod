# New-Solution.ps1
# Scaffold a new Sentinel CCF connector solution from template
# Usage: ./New-Solution.ps1 -SolutionName "MyConnector" -Publisher "MyCompany" -TableName "MyData_CL"

param(
    [Parameter(Mandatory=$true)]
    [string]$SolutionName,
    
    [Parameter(Mandatory=$true)]
    [string]$Publisher,
    
    [Parameter(Mandatory=$true)]
    [string]$TableName,
    
    [Parameter(Mandatory=$false)]
    [string]$Description = "Ingest data using the Common Connector Framework (CCF).",
    
    [Parameter(Mandatory=$false)]
    [string]$ApiEndpoint = "https://api.example.com/v1/data"
)

$ErrorActionPreference = "Stop"

# Load config
. "$PSScriptRoot/Config.ps1"
$config = Get-SentinelConfig
$repoRoot = Get-RepoRoot

Write-Host "=== Create New Sentinel Solution ===" -ForegroundColor Cyan
Write-Host "Solution: $SolutionName" -ForegroundColor Gray
Write-Host "Publisher: $Publisher" -ForegroundColor Gray
Write-Host "Table: $TableName" -ForegroundColor Gray

# Create solution folder
$solutionPath = Join-Path $repoRoot "$SolutionName-CCF-Hub"

if (Test-Path $solutionPath) {
    Write-Host "[ERROR] Solution folder already exists: $solutionPath" -ForegroundColor Red
    exit 1
}

Write-Host "`nCreating folder structure..." -ForegroundColor Yellow

New-Item -ItemType Directory -Path $solutionPath -Force | Out-Null
New-Item -ItemType Directory -Path "$solutionPath/Package" -Force | Out-Null
New-Item -ItemType Directory -Path "$solutionPath/Data" -Force | Out-Null
New-Item -ItemType Directory -Path "$solutionPath/Data Connectors/${SolutionName}_CCF" -Force | Out-Null

# Generate connector ID
$connectorId = "${SolutionName}ThreatIntel"

# Create Connector Definition
$connectorDef = @{
    name = $connectorId
    apiVersion = "2024-09-01"
    type = "Microsoft.SecurityInsights/dataConnectorDefinitions"
    location = "{{location}}"
    kind = "Customizable"
    properties = @{
        connectorUiConfig = @{
            connectorId = $connectorId
            title = "$SolutionName Data Connector"
            publisher = $Publisher
            descriptionMarkdown = $Description
            graphQueriesTableName = $TableName
            graphQueries = @(
                @{
                    metricName = "Total records received"
                    legend = $SolutionName
                    baseQuery = $TableName
                }
            )
            sampleQueries = @(
                @{
                    description = "Recent records"
                    query = "$TableName | where TimeGenerated >= ago(7d) | take 100"
                }
            )
            dataTypes = @(
                @{
                    name = $TableName
                    lastDataReceivedQuery = "$TableName | summarize Time = max(TimeGenerated) | where isnotempty(Time)"
                }
            )
            connectivityCriteria = @(
                @{
                    type = "HasDataConnectors"
                }
            )
            availability = @{
                status = "Available"
                isPreview = $false
            }
            permissions = @{
                resourceProvider = @(
                    @{
                        provider = "Microsoft.OperationalInsights/workspaces"
                        permissionsDisplayText = "Read and write permissions required"
                        providerDisplayName = "Workspace"
                        scope = "Workspace"
                        requiredPermissions = @{
                            write = $true
                            read = $true
                            delete = $false
                        }
                    }
                )
                customs = @(
                    @{
                        name = "$SolutionName API Key"
                        description = "API key for authentication"
                    }
                )
            }
            instructionSteps = @(
                @{
                    title = "Configure API Access"
                    description = "Provide your API key for authentication."
                }
            )
        }
    }
}

$connectorDefPath = "$solutionPath/Data Connectors/${SolutionName}_CCF/${SolutionName}_ConnectorDefinition.json"
$connectorDef | ConvertTo-Json -Depth 20 | Set-Content -Path $connectorDefPath
Write-Host "  [+] ConnectorDefinition.json" -ForegroundColor Green

# Create Poller Config
$pollerConfig = @(
    @{
        name = "${SolutionName}Poller"
        apiVersion = "2023-02-01-preview"
        type = "Microsoft.SecurityInsights/dataConnectors"
        location = "{{location}}"
        kind = "RestApiPoller"
        properties = @{
            connectorDefinitionName = $connectorId
            dataType = $TableName
            dcrConfig = @{
                streamName = "Custom-$TableName"
                dataCollectionEndpoint = "{{dataCollectionEndpoint}}"
                dataCollectionRuleImmutableId = "{{dcrImmutableId}}"
            }
            auth = @{
                type = "APIKey"
                ApiKeyName = "Authorization"
                ApiKeyIdentifier = "Bearer"
                ApiKey = "{{apiKey}}"
            }
            request = @{
                apiEndpoint = $ApiEndpoint
                httpMethod = "GET"
                queryParameters = @{
                    page_size = 100
                }
                rateLimitQps = 10
                retryCount = 3
                timeoutInSeconds = 60
                headers = @{
                    Accept = "application/json"
                    "User-Agent" = "Microsoft-Sentinel-$SolutionName/1.0"
                }
            }
            paging = @{
                pagingType = "Offset"
                offsetParameterName = "offset"
                pageSize = 100
            }
            response = @{
                eventsJsonPaths = @("$")
                format = "json"
            }
        }
    }
)

$pollerConfigPath = "$solutionPath/Data Connectors/${SolutionName}_CCF/${SolutionName}_PollerConfig.json"
$pollerConfig | ConvertTo-Json -Depth 20 | Set-Content -Path $pollerConfigPath
Write-Host "  [+] PollerConfig.json" -ForegroundColor Green

# Create Table Definition
$tableDef = @{
    name = $TableName
    properties = @{
        schema = @{
            name = $TableName
            columns = @(
                @{ name = "TimeGenerated"; type = "datetime" }
                @{ name = "id_s"; type = "string" }
                @{ name = "data_s"; type = "string" }
            )
        }
        retentionInDays = 90
    }
}

$tableDefPath = "$solutionPath/Data Connectors/${SolutionName}_CCF/${SolutionName}_Table.json"
$tableDef | ConvertTo-Json -Depth 20 | Set-Content -Path $tableDefPath
Write-Host "  [+] Table.json" -ForegroundColor Green

# Create Solution Data file
$solutionData = @{
    Name = "$SolutionName Threat Intelligence"
    Author = "$Publisher - support@$($Publisher.ToLower()).com"
    Logo = "<img src=`"https://raw.githubusercontent.com/Azure/Azure-Sentinel/master/Logos/Azure_Sentinel.svg`"width=`"75px`"height=`"75px`">"
    Description = $Description
    "Data Connectors" = @(
        "$SolutionName-CCF-Hub/Data Connectors/${SolutionName}_CCF/${SolutionName}_ConnectorDefinition.json"
    )
    Metadata = "SolutionMetadata.json"
    BasePath = "C:\One\Azure-Sentinel\Solutions"
    Version = "3.0.0"
    TemplateSpec = $true
    Is1Pconnector = $false
}

$solutionDataPath = "$solutionPath/Data/Solution_$SolutionName.json"
$solutionData | ConvertTo-Json -Depth 10 | Set-Content -Path $solutionDataPath
Write-Host "  [+] Solution_$SolutionName.json" -ForegroundColor Green

# Create SolutionMetadata.json
$solutionMetadata = @{
    publisherId = $Publisher.ToLower()
    offerId = "$($SolutionName.ToLower())-sentinel-solution"
    firstPublishDate = (Get-Date -Format "yyyy-MM-dd")
    providers = @($Publisher)
    categories = @{
        domains = @("Security - Threat Intelligence")
    }
    support = @{
        tier = "Partner"
        name = $Publisher
        email = "support@$($Publisher.ToLower()).com"
        link = "https://www.$($Publisher.ToLower()).com/support"
    }
}

$solutionMetadataPath = "$solutionPath/SolutionMetadata.json"
$solutionMetadata | ConvertTo-Json -Depth 10 | Set-Content -Path $solutionMetadataPath
Write-Host "  [+] SolutionMetadata.json" -ForegroundColor Green

# Create ReleaseNotes.md
$releaseNotes = @"
# Release Notes

## Version 1.0.0
- Initial release
- CCF data connector for $SolutionName
- Custom log table: $TableName
"@

Set-Content -Path "$solutionPath/ReleaseNotes.md" -Value $releaseNotes
Write-Host "  [+] ReleaseNotes.md" -ForegroundColor Green

# Create README.md
$readme = @"
# $SolutionName Sentinel Solution

## Overview
This solution provides a CCF (Codeless Connector Framework) data connector for ingesting data from $SolutionName into Microsoft Sentinel.

## Components
- **Data Connector**: REST API poller using CCF
- **Custom Table**: $TableName

## Deployment
1. Deploy via Azure Portal or ARM template
2. Configure API credentials
3. Verify data ingestion in Sentinel

## Support
Contact: support@$($Publisher.ToLower()).com
"@

Set-Content -Path "$solutionPath/README.md" -Value $readme
Write-Host "  [+] README.md" -ForegroundColor Green

Write-Host "`n=== Solution Created ===" -ForegroundColor Green
Write-Host "Location: $solutionPath" -ForegroundColor Gray
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Edit the connector definition and poller config" -ForegroundColor Gray
Write-Host "2. Update the table schema" -ForegroundColor Gray
Write-Host "3. Run: ./Validate-Solution.ps1 -SolutionName $SolutionName" -ForegroundColor Gray
Write-Host "4. Run: ./Deploy-ToGitHub.ps1 -SolutionName $SolutionName -GitHubToken <token>" -ForegroundColor Gray

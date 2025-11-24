# Apply Official Microsoft Documentation Fix
# Using dynamic type for nested JSON per:
# https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-structure

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  APPLYING OFFICIAL MICROSOFT DOCS FIX - DYNAMIC TYPE         ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$subscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117"
$resourceGroup = "SentinelTestStixImport"
$dcrName = "dcr-tacitred-findings"

# Per official docs: https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-transformations-structure#handling-dynamic-data
$officialTransformKql = 'source | extend parsed_finding = parse_json(finding) | extend supporting_data = parsed_finding.supporting_data | extend types_array = parsed_finding.types | extend time_value = todatetime(column_ifexists("time", "")) | extend TimeGenerated = iif(isnull(time_value), now(), time_value) | project TimeGenerated, email_s=tostring(supporting_data.credential), domain_s=tostring(supporting_data.domain), findingType_s=tostring(types_array[0]), confidence_d=toint(toreal(severity) * 100), firstSeen_t=todatetime(supporting_data.date_compromised), lastSeen_t=todatetime(supporting_data.date_compromised), notes_s=tostring(parsed_finding.title), source_s=tostring(supporting_data.stealer), severity_s=tostring(severity), status_s="active", campaign_id_s="", user_id_s="", username_s="", detection_ts_t=todatetime(supporting_data.date_compromised), metadata_s=tostring(finding)'

Write-Host "Fetching current DCR..." -ForegroundColor Yellow
$dcr = az monitor data-collection rule show -g $resourceGroup -n $dcrName -o json | ConvertFrom-Json

# Update stream declaration to use dynamic type for finding field
# Per https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-structure
Write-Host "Updating stream declaration with 'dynamic' type for nested JSON..." -ForegroundColor Yellow

$newStreamDeclaration = @{
    "Custom-TacitRed_Findings_Raw" = @{
        columns = @(
            @{ name = "finding"; type = "dynamic" },        # ✅ Nested object as dynamic
            @{ name = "severity"; type = "string" },         # ✅ Top-level field
            @{ name = "time"; type = "string" },             # ✅ Top-level field  
            @{ name = "activity_id"; type = "int" },
            @{ name = "category_uid"; type = "int" },
            @{ name = "class_id"; type = "int" },
            @{ name = "severity_id"; type = "int" },
            @{ name = "state_id"; type = "int" }
        )
    }
    "Custom-TacitRed_Findings_CL" = $dcr.streamDeclarations.'Custom-TacitRed_Findings_CL'
}

# Create update payload
$update = @{
    location = $dcr.location
    properties = @{
        dataCollectionEndpointId = $dcr.dataCollectionEndpointId
        streamDeclarations = $newStreamDeclaration
        destinations = $dcr.destinations
        dataFlows = @(
            @{
                streams = $dcr.dataFlows[0].streams
                destinations = $dcr.dataFlows[0].destinations
                transformKql = $officialTransformKql
                outputStream = $dcr.dataFlows[0].outputStream
            }
        )
    }
} | ConvertTo-Json -Depth 10 -Compress

# Save to file
$tempFile = "$env:TEMP\dcr-official-fix.json"
$update | Out-File $tempFile -Encoding UTF8 -NoNewline

Write-Host "`nApplying official Microsoft docs fix..." -ForegroundColor Cyan
az rest `
    --method PUT `
    --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Insights/dataCollectionRules/$dcrName`?api-version=2024-03-11" `
    --body "@$tempFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ SUCCESS! DCR updated with official Microsoft docs approach" -ForegroundColor Green
    Write-Host "`nChanges applied:" -ForegroundColor Cyan
    Write-Host "  1. 'finding' field now type 'dynamic' (not string)" -ForegroundColor Gray
    Write-Host '  2. Transform uses parse_json per official docs' -ForegroundColor Gray
    Write-Host "  3. Nested fields accessed with dot notation" -ForegroundColor Gray
    Write-Host "`nTrigger Logic App to test immediately." -ForegroundColor Yellow
} else {
    Write-Host "`n UPDATE FAILED" -ForegroundColor Red
    Write-Host 'Check error message above' -ForegroundColor Yellow
}

Remove-Item $tempFile -ErrorAction SilentlyContinue

# Fix Logic App DCR - Direct approach
$subscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117"
$resourceGroup = "SentinelTestStixImport"
$dcrName = "dcr-tacitred-findings"

Write-Host "Fetching current DCR..." -ForegroundColor Yellow
$dcr = az monitor data-collection rule show -g $resourceGroup -n $dcrName -o json | ConvertFrom-Json

# Extract only what we need to update
$dcrUpdate = @{
    location = $dcr.location
    properties = @{
        dataCollectionEndpointId = $dcr.properties.dataCollectionEndpointId
        streamDeclarations = $dcr.properties.streamDeclarations
        destinations = $dcr.properties.destinations
        dataFlows = @(
            @{
                streams = $dcr.properties.dataFlows[0].streams
                destinations = $dcr.properties.dataFlows[0].destinations
                transformKql = "source | extend supporting_data = parse_json(tostring(finding)).supporting_data | extend tg = todatetime(time) | extend TimeGenerated = iif(isnull(tg), now(), tg) | project TimeGenerated, email_s=tostring(supporting_data.credential), domain_s=tostring(supporting_data.domain), findingType_s=tostring(parse_json(tostring(finding)).types[0]), confidence_d=toint(toreal(severity) * 100), firstSeen_t=todatetime(supporting_data.date_compromised), lastSeen_t=todatetime(supporting_data.date_compromised), notes_s=tostring(parse_json(tostring(finding)).title), source_s=tostring(supporting_data.stealer), severity_s=tostring(severity), status_s='active', campaign_id_s='', user_id_s='', username_s='', detection_ts_t=todatetime(supporting_data.date_compromised), metadata_s=tostring(finding)"
                outputStream = $dcr.properties.dataFlows[0].outputStream
            }
        )
    }
}

# Save to temp file
$tempFile = "$env:TEMP\dcr-update.json"
$dcrUpdate | ConvertTo-Json -Depth 10 -Compress | Out-File $tempFile -Encoding UTF8 -NoNewline

Write-Host "Updating DCR transform..." -ForegroundColor Yellow
az rest `
    --method PUT `
    --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Insights/dataCollectionRules/$dcrName`?api-version=2024-03-11" `
    --body "@$tempFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ SUCCESS! DCR transform updated." -ForegroundColor Green
    Write-Host "`nNew transform extracts:" -ForegroundColor Cyan
    Write-Host "  • finding.supporting_data.credential → email_s" -ForegroundColor Gray
    Write-Host "  • finding.supporting_data.domain → domain_s" -ForegroundColor Gray  
    Write-Host "  • finding.types[0] → findingType_s" -ForegroundColor Gray
    Write-Host "  • severity * 100 → confidence_d" -ForegroundColor Gray
    Write-Host "`nTrigger Logic App to test immediately." -ForegroundColor Yellow
} else {
    Write-Host "`n❌ Update failed" -ForegroundColor Red
}

Remove-Item $tempFile -ErrorAction SilentlyContinue

# Fix Logic App DCR - Update transform to extract nested fields
# The current transform tries to extract flat fields that don't exist
# We need to use parse_json-like logic to extract finding.supporting_data.* fields

$subscriptionId = "774bee0e-b281-4f70-8e40-199e35b65117"
$resourceGroup = "SentinelTestStixImport"
$dcrName = "dcr-tacitred-findings"

Write-Host "Updating Logic App DCR transform to extract nested fields..." -ForegroundColor Yellow

# The corrected transform KQL that extracts nested fields
$newTransformKql = @"
source 
| extend supporting_data = parse_json(tostring(finding)).supporting_data
| extend tg = todatetime(time)
| extend TimeGenerated = iif(isnull(tg), now(), tg)
| project 
    TimeGenerated,
    email_s = tostring(supporting_data.credential),
    domain_s = tostring(supporting_data.domain),
    findingType_s = tostring(parse_json(tostring(finding)).types[0]),
    confidence_d = toint(toreal(severity) * 100),
    firstSeen_t = todatetime(supporting_data.date_compromised),
    lastSeen_t = todatetime(supporting_data.date_compromised),
    notes_s = tostring(parse_json(tostring(finding)).title),
    source_s = tostring(supporting_data.stealer),
    severity_s = tostring(severity),
    status_s = 'active',
    campaign_id_s = '',
    user_id_s = '',
    username_s = '',
    detection_ts_t = todatetime(supporting_data.date_compromised),
    metadata_s = tostring(finding)
"@

# Get current DCR configuration
Write-Host "Getting current DCR configuration..." -ForegroundColor Gray
$dcr = az monitor data-collection rule show `
    --resource-group $resourceGroup `
    --name $dcrName `
    -o json | ConvertFrom-Json

# Update the transform
$dcr.dataFlows[0].transformKql = $newTransformKql

# Save to temp file
$tempFile = "$env:TEMP\dcr-tacitred-fixed.json"
$dcr | ConvertTo-Json -Depth 20 | Out-File $tempFile -Encoding UTF8

Write-Host "Updating DCR with new transform..." -ForegroundColor Yellow
az rest `
    --method PUT `
    --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Insights/dataCollectionRules/$dcrName`?api-version=2024-03-11" `
    --body "@$tempFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ DCR updated successfully!" -ForegroundColor Green
    Write-Host "The Logic App will now extract nested fields correctly on next run." -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "1. Wait for Logic App's next scheduled run, OR" -ForegroundColor Gray
    Write-Host "2. Manually trigger the Logic App for immediate results" -ForegroundColor Gray
} else {
    Write-Host "`n❌ DCR update failed!" -ForegroundColor Red
}

Remove-Item $tempFile -ErrorAction SilentlyContinue

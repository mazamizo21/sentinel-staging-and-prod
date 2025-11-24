# Final DCR Update - Complete approach
$dcrFile = "$env:TEMP\dcr-full.json"
$dcr = Get-Content $dcrFile | ConvertFrom-Json

# Update the transformKql with the correct nested field extraction
$newTransform = "source | extend finding_obj = parse_json(tostring(finding)) | extend supporting_data = finding_obj.supporting_data | extend tg = todatetime(time) | extend TimeGenerated = iif(isnull(tg), now(), tg) | project TimeGenerated, email_s=tostring(supporting_data.credential), domain_s=tostring(supporting_data.domain), findingType_s=tostring(finding_obj.types[0]), confidence_d=toint(toreal(severity) * 100), firstSeen_t=todatetime(supporting_data.date_compromised), lastSeen_t=todatetime(supporting_data.date_compromised), notes_s=tostring(finding_obj.title), source_s=tostring(supporting_data.stealer), severity_s=tostring(severity), status_s='active', campaign_id_s='', user_id_s='', username_s='', detection_ts_t=todatetime(supporting_data.date_compromised), metadata_s=tostring(finding)"

Write-Host "Current transform (truncated):" -ForegroundColor Yellow
Write-Host $dcr.dataFlows[0].transformKql.Substring(0, [Math]::Min(100, $dcr.dataFlows[0].transformKql.Length)) -ForegroundColor Gray

$dcr.dataFlows[0].transformKql = $newTransform

Write-Host "`nNew transform (truncated):" -ForegroundColor Yellow
Write-Host $newTransform.Substring(0, 100) -ForegroundColor Gray

# Create update body (location + properties only)
$updateBody = @{
    location = $dcr.location
    properties = $dcr.PSObject.Properties['properties'].Value
} | ConvertTo-Json -Depth 20 -Compress

# Save to file  
$outputFile = "$env:TEMP\dcr-update-final.json"
$updateBody | Out-File $outputFile -Encoding UTF8 -NoNewline

Write-Host "`nUpdating DCR..." -ForegroundColor Cyan
az rest `
    --method PUT `
    --uri "https://management.azure.com/subscriptions/774bee0e-b281-4f70-8e40-199e35b65117/resourceGroups/SentinelTestStixImport/providers/Microsoft.Insights/dataCollectionRules/dcr-tacitred-findings?api-version=2024-03-11" `
    --body "@$outputFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ DCR UPDATED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "`nThe transform now extracts nested fields from the API response." -ForegroundColor Cyan
    Write-Host "Trigger the Logic App to see results immediately." -ForegroundColor Yellow
} else {
    Write-Host "`n❌ Update failed" -ForegroundColor Red
}

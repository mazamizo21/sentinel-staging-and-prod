$solutionName = "TacitRed-SentinelOne"
$root = "/Users/tazjack/Documents/sentinel-staging-and-prod/sentinel-production"
$solutionRoot = Join-Path $root $solutionName
$packageRoot = Join-Path $solutionRoot "Package"
$playbooksRoot = Join-Path $solutionRoot "Playbooks"
$zipPath = Join-Path $packageRoot "1.0.0.zip"

Write-Host "Zipping Playbooks from $playbooksRoot to $zipPath"

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

# Compress-Archive requires the folder to be inside the zip, usually.
# If we just compress $playbooksRoot, the zip will contain "Playbooks/..."
# Let's verify if that's what's expected. 
# Usually the zip structure should match the relative paths referenced in mainTemplate.
# In mainTemplate, we have "Playbooks/TacitRedToSentinelOne_Playbook.json" (implied by nested deployment).
# Actually, mainTemplate embeds the playbook. The zip is often used for the UI or other assets, or if the playbook is linked.
# In TacitRed-IOC-CrowdStrike/Data/Solution_....json, it references "Playbooks/TacitRedToCrowdStrike_Playbook.json".
# So the zip should probably contain the Playbooks folder.

Compress-Archive -Path $playbooksRoot -DestinationPath $zipPath

Write-Host "Created $zipPath"

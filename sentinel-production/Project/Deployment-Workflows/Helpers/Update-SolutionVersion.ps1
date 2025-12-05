function Update-SolutionVersion {
    param (
        [string]$PackagePath,
        [switch]$DryRun
    )

    $metadataPath = Join-Path $PackagePath "packageMetadata.json"
    $mainTemplatePath = Join-Path $PackagePath "mainTemplate.json"

    if (-not (Test-Path $metadataPath)) {
        throw "packageMetadata.json not found at $metadataPath"
    }

    # 1. Read and Parse packageMetadata.json
    $metadataJson = Get-Content $metadataPath -Raw | ConvertFrom-Json
    $currentVersion = $metadataJson.version

    if ([string]::IsNullOrWhiteSpace($currentVersion)) {
        throw "Version not found in packageMetadata.json"
    }

    # 2. Increment Version (Patch level)
    $versionParts = $currentVersion.Split('.')
    if ($versionParts.Count -ne 3) {
        # Fallback for non-standard versions, just append .1 or handle roughly
        # But standard is X.Y.Z
        throw "Version format '$currentVersion' is not X.Y.Z"
    }

    [int]$major = $versionParts[0]
    [int]$minor = $versionParts[1]
    [int]$patch = $versionParts[2]
    
    $patch++
    $newVersion = "$major.$minor.$patch"

    Write-Host "Incrementing version: $currentVersion -> $newVersion" -ForegroundColor Cyan

    # 3. Update packageMetadata.json
    if ($DryRun) {
        Write-Host "[DRY RUN] Would update packageMetadata.json version to $newVersion" -ForegroundColor DarkGray
    }
    else {
        $metadataJson.version = $newVersion
        $metadataJson | ConvertTo-Json -Depth 10 | Set-Content $metadataPath
    }

    # 4. Update mainTemplate.json
    if (Test-Path $mainTemplatePath) {
        $mainTemplateJson = Get-Content $mainTemplatePath -Raw | ConvertFrom-Json
        
        # Find contentPackages resource
        $contentPackage = $null
        if ($mainTemplateJson.resources) {
            $contentPackage = $mainTemplateJson.resources | Where-Object { $_.type -eq "Microsoft.OperationalInsights/workspaces/providers/contentPackages" }
        }

        if ($contentPackage) {
            if ($DryRun) {
                Write-Host "[DRY RUN] Would update mainTemplate.json version to $newVersion" -ForegroundColor DarkGray
            }
            else {
                Write-Host "Updating version in mainTemplate.json..."
                $contentPackage.properties.version = $newVersion
                $mainTemplateJson | ConvertTo-Json -Depth 100 | Set-Content $mainTemplatePath
            }
        }
        else {
            Write-Warning "ContentPackage resource not found in mainTemplate.json. Skipping update for this file."
        }
    }

    return $newVersion
}

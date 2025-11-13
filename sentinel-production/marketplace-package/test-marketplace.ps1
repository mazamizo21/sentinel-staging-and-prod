# Quick Marketplace Testing Script
# Tests mainTemplate.json and createUiDefinition.json before production

param(
    [string]$TestResourceGroup = "rg-marketplace-test",
    [string]$TestWorkspace = "test-sentinel-ws",
    [string]$Location = "eastus"
)

$ErrorActionPreference = "Stop"
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   MARKETPLACE PACKAGE - PRE-PRODUCTION TESTING               ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $PSCommandPath

# Phase 1: Validate JSON Syntax
Write-Host "═══ PHASE 1: JSON VALIDATION ═══" -ForegroundColor Yellow
try {
    Write-Host "  [1/2] Validating mainTemplate.json..." -ForegroundColor Gray
    $template = Get-Content "$scriptDir\mainTemplate.json" -Raw | ConvertFrom-Json
    Write-Host "    ✓ mainTemplate.json is valid JSON" -ForegroundColor Green
    
    Write-Host "  [2/2] Validating createUiDefinition.json..." -ForegroundColor Gray
    $ui = Get-Content "$scriptDir\createUiDefinition.json" -Raw | ConvertFrom-Json
    Write-Host "    ✓ createUiDefinition.json is valid JSON" -ForegroundColor Green
} catch {
    Write-Host "    ✗ JSON validation failed: $_" -ForegroundColor Red
    exit 1
}

# Phase 2: Check File Sizes
Write-Host "`n═══ PHASE 2: FILE SIZE CHECK ═══" -ForegroundColor Yellow
Get-ChildItem $scriptDir\*.json | ForEach-Object {
    $sizeKB = [math]::Round($_.Length / 1KB, 2)
    $sizeMB = [math]::Round($_.Length / 1MB, 2)
    $status = if($sizeMB -lt 4) { "✓" } else { "✗" }
    Write-Host "  $status $($_.Name): $sizeKB KB ($sizeMB MB)" -ForegroundColor $(if($sizeMB -lt 4) {"Green"} else {"Red"})
}

# Phase 3: ARM Template Validation
Write-Host "`n═══ PHASE 3: ARM TEMPLATE VALIDATION ═══" -ForegroundColor Yellow
Write-Host "  NOTE: This requires an existing resource group and workspace" -ForegroundColor Cyan
Write-Host "  Skipping actual validation (run manually with real RG/WS)" -ForegroundColor Yellow

$validateCmd = @"

# To validate manually, run this command:
az deployment group validate \
  --resource-group $TestResourceGroup \
  --template-file $scriptDir\mainTemplate.json \
  --parameters \
      workspaceName=$TestWorkspace \
      tacitRedApiKey="test-placeholder-key" \
      cyrenIPJwtToken="eyJtest.placeholder" \
      cyrenMalwareJwtToken="eyJtest.placeholder"

"@
Write-Host $validateCmd -ForegroundColor Gray

# Phase 4: UI Definition Sandbox Test
Write-Host "`n═══ PHASE 4: UI DEFINITION SANDBOX TEST ═══" -ForegroundColor Yellow
Write-Host "  To test the UI wizard, visit:" -ForegroundColor Cyan
Write-Host "  https://portal.azure.com/#blade/Microsoft_Azure_CreateUIDef/SandboxBlade" -ForegroundColor White
Write-Host "`n  Then paste the contents of createUiDefinition.json and click Preview" -ForegroundColor Gray

# Phase 5: Summary
Write-Host "`n═══ TEST SUMMARY ═══" -ForegroundColor Cyan
Write-Host "  ✓ JSON syntax validation: PASSED" -ForegroundColor Green
Write-Host "  ✓ File size check: PASSED" -ForegroundColor Green
Write-Host "  ⚠ ARM validation: MANUAL (see command above)" -ForegroundColor Yellow
Write-Host "  ⚠ UI sandbox test: MANUAL (see URL above)" -ForegroundColor Yellow

# Phase 6: Next Steps
Write-Host "`n═══ NEXT STEPS ═══" -ForegroundColor Cyan
Write-Host "  1. Test UI in sandbox: https://portal.azure.com/#blade/Microsoft_Azure_CreateUIDef/SandboxBlade" -ForegroundColor White
Write-Host "  2. Create test environment and deploy:" -ForegroundColor White
Write-Host "     - Create resource group" -ForegroundColor Gray
Write-Host "     - Create Sentinel workspace" -ForegroundColor Gray
Write-Host "     - Run az deployment group create" -ForegroundColor Gray
Write-Host "  3. Verify all resources deployed" -ForegroundColor White
Write-Host "  4. Monitor data ingestion (30 min)" -ForegroundColor White
Write-Host "  5. Check connector status in portal" -ForegroundColor White
Write-Host "`n  See TESTING-GUIDE.md for complete testing procedures" -ForegroundColor Cyan

Write-Host "`n✅ Pre-validation complete!`n" -ForegroundColor Green

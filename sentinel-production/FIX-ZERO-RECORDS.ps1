# FIX-ZERO-RECORDS.ps1
# Emergency fix script to resolve zero records issue

<#
.SYNOPSIS
    Creates missing custom tables and fixes API connectivity issues
.DESCRIPTION
    This script addresses the root causes identified by diagnostic:
    1. Creates missing custom Log Analytics tables
    2. Verifies and tests API key authentication
    3. Validates DCR/DCE configuration
.NOTES
    Based on diagnostic findings from 2025-11-14 15:13 UTC
    Critical issues: All custom tables missing, TacitRed API 401 error
#>

param(
    [switch]$WhatIf,
    [switch]$SkipAPITest
)

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   ZERO RECORDS EMERGENCY FIX SCRIPT" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

# Load config
if(-not (Test-Path ".\client-config-COMPLETE.json")){
    Write-Host "ERROR: client-config-COMPLETE.json not found" -ForegroundColor Red
    exit 1
}

$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$ws = $config.parameters.azure.value.workspaceName

Write-Host "Subscription: $sub" -ForegroundColor Gray
Write-Host "Resource Group: $rg" -ForegroundColor Gray
Write-Host "Workspace: $ws" -ForegroundColor Gray
Write-Host "WhatIf Mode: $WhatIf`n" -ForegroundColor Gray

az account set --subscription $sub | Out-Null

$fixResults = @{
    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    TablesCreated = @()
    APITests = @()
    Issues = @()
    Success = $false
}

# ============================================================================
# SECTION 1: CREATE MISSING CUSTOM TABLES
# ============================================================================
Write-Host "═══ SECTION 1: CREATE MISSING CUSTOM TABLES ═══" -ForegroundColor Cyan

# Define table schemas based on mainTemplate.json
$tables = @{
    'TacitRed_Findings_CL' = @{
        name = "TacitRed_Findings_CL"
        columns = @(
            @{name="TimeGenerated"; type="datetime"},
            @{name="email_s"; type="string"},
            @{name="domain_s"; type="string"},
            @{name="findingType_s"; type="string"},
            @{name="confidence_d"; type="int"},
            @{name="firstSeen_t"; type="datetime"},
            @{name="lastSeen_t"; type="datetime"},
            @{name="notes_s"; type="string"},
            @{name="source_s"; type="string"},
            @{name="severity_s"; type="string"},
            @{name="status_s"; type="string"},
            @{name="campaign_id_s"; type="string"},
            @{name="user_id_s"; type="string"},
            @{name="username_s"; type="string"},
            @{name="detection_ts_t"; type="datetime"},
            @{name="metadata_s"; type="string"}
        )
    }
    'Cyren_IpReputation_CL' = @{
        name = "Cyren_IpReputation_CL"
        columns = @(
            @{name="TimeGenerated"; type="datetime"},
            @{name="ip_s"; type="string"},
            @{name="threat_type_s"; type="string"},
            @{name="risk_d"; type="int"},
            @{name="confidence_d"; type="int"},
            @{name="first_seen_t"; type="datetime"},
            @{name="last_seen_t"; type="datetime"},
            @{name="country_s"; type="string"},
            @{name="asn_s"; type="string"},
            @{name="category_s"; type="string"},
            @{name="tags_s"; type="string"}
        )
    }
    'Cyren_MalwareUrls_CL' = @{
        name = "Cyren_MalwareUrls_CL"
        columns = @(
            @{name="TimeGenerated"; type="datetime"},
            @{name="url_s"; type="string"},
            @{name="domain_s"; type="string"},
            @{name="threat_type_s"; type="string"},
            @{name="risk_d"; type="int"},
            @{name="confidence_d"; type="int"},
            @{name="first_seen_t"; type="datetime"},
            @{name="last_seen_t"; type="datetime"},
            @{name="category_s"; type="string"},
            @{name="tags_s"; type="string"},
            @{name="malware_family_s"; type="string"}
        )
    }
}

foreach($tableName in $tables.Keys | Sort-Object){
    Write-Host "`n[$tableName]" -ForegroundColor Yellow
    
    try {
        # Check if table already exists
        $checkQuery = "$tableName | getschema"
        $existing = az monitor log-analytics query -w $ws --analytics-query $checkQuery 2>$null
        
        if($existing){
            Write-Host "  ⚠ Table already exists, skipping" -ForegroundColor Yellow
            $fixResults.TablesCreated += @{
                Name = $tableName
                Status = "AlreadyExists"
            }
            continue
        }
        
        if($WhatIf){
            Write-Host "  [WhatIf] Would create table with $($tables[$tableName].columns.Count) columns" -ForegroundColor Cyan
            $fixResults.TablesCreated += @{
                Name = $tableName
                Status = "WhatIf"
            }
            continue
        }
        
        # Build table creation payload
        $tablePayload = @{
            properties = @{
                schema = $tables[$tableName]
            }
        } | ConvertTo-Json -Depth 10
        
        Write-Host "  Creating table with $($tables[$tableName].columns.Count) columns..." -ForegroundColor Gray
        
        # Save to temp file for az rest
        $tempFile = "$env:TEMP\table-schema-$tableName.json"
        $tablePayload | Out-File -FilePath $tempFile -Encoding UTF8 -Force
        
        $uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/tables/${tableName}?api-version=2023-09-01"
        
        $result = az rest --method PUT --uri $uri --headers "Content-Type=application/json" --body "@$tempFile" 2>&1
        
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        
        if($LASTEXITCODE -eq 0){
            Write-Host "  ✓ Table created successfully" -ForegroundColor Green
            $fixResults.TablesCreated += @{
                Name = $tableName
                Status = "Created"
                Columns = $tables[$tableName].columns.Count
            }
            
            # Wait a bit for table to propagate
            Start-Sleep -Seconds 5
        }else{
            Write-Host "  ✗ Failed to create table" -ForegroundColor Red
            Write-Host "    Error: $result" -ForegroundColor Red
            $fixResults.TablesCreated += @{
                Name = $tableName
                Status = "Failed"
                Error = $result
            }
        }
        
    } catch {
        Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
        $fixResults.TablesCreated += @{
            Name = $tableName
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# SECTION 2: VERIFY AND TEST API KEYS
# ============================================================================
Write-Host "`n═══ SECTION 2: VERIFY AND TEST API KEYS ═══" -ForegroundColor Cyan

if($SkipAPITest){
    Write-Host "  Skipping API tests (use without -SkipAPITest to test)" -ForegroundColor Gray
}else{
    # Test TacitRed API
    Write-Host "`n[TacitRed API Authentication]" -ForegroundColor Yellow
    try {
        Write-Host "  Retrieving API key from Key Vault..." -ForegroundColor Gray
        $tacitRedKey = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "tacitred-api-key" --query "value" -o tsv 2>$null
        
        if(-not $tacitRedKey){
            Write-Host "  ✗ Could not retrieve API key from Key Vault" -ForegroundColor Red
            $fixResults.APITests += @{
                Service = "TacitRed"
                Status = "KeyVaultError"
                Error = "Could not retrieve secret"
            }
        }else{
            Write-Host "  ✓ API key retrieved (length: $($tacitRedKey.Length))" -ForegroundColor Green
            Write-Host "  First 20 chars: $($tacitRedKey.Substring(0, [Math]::Min(20, $tacitRedKey.Length)))..." -ForegroundColor Gray
            
            # Test with different time ranges
            $testWindows = @(
                @{Name="Last 24 hours"; Hours=24},
                @{Name="Last 7 days"; Hours=168}
            )
            
            foreach($window in $testWindows){
                Write-Host "`n  Testing API: $($window.Name)" -ForegroundColor Gray
                
                $headers = @{
                    'Authorization' = "Bearer $tacitRedKey"
                    'Accept' = 'application/json'
                    'User-Agent' = 'Microsoft-Sentinel-TacitRed/1.0'
                }
                
                $endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                $startTime = (Get-Date).AddHours(-$window.Hours).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                $apiUrl = "https://app.tacitred.com/api/v1/findings?from=$startTime&until=$endTime&page_size=100"
                
                try {
                    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
                    
                    Write-Host "    ✓ HTTP Status: Success" -ForegroundColor Green
                    Write-Host "    ✓ Result Count: $($response.results.Count)" -ForegroundColor $(if($response.results.Count -gt 0){'Green'}else{'Yellow'})
                    
                    if($response.results.Count -gt 0){
                        Write-Host "    ✓ Sample Finding:" -ForegroundColor Green
                        $sample = $response.results[0]
                        Write-Host "      Email: $($sample.email)" -ForegroundColor Gray
                        Write-Host "      Type: $($sample.findingType)" -ForegroundColor Gray
                        Write-Host "      Confidence: $($sample.confidence)" -ForegroundColor Gray
                    }
                    
                    $fixResults.APITests += @{
                        Service = "TacitRed"
                        Window = $window.Name
                        Status = "Success"
                        HTTPStatus = 200
                        ResultCount = $response.results.Count
                        HasData = $response.results.Count -gt 0
                    }
                    
                    # If we got data, no need to test longer windows
                    if($response.results.Count -gt 0){
                        break
                    }
                    
                } catch {
                    $statusCode = $_.Exception.Response.StatusCode.value__
                    Write-Host "    ✗ API Error: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "    ✗ Status Code: $statusCode" -ForegroundColor Red
                    
                    $fixResults.APITests += @{
                        Service = "TacitRed"
                        Window = $window.Name
                        Status = "Error"
                        HTTPStatus = $statusCode
                        Error = $_.Exception.Message
                    }
                }
            }
        }
        
    } catch {
        Write-Host "  ✗ Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
        $fixResults.APITests += @{
            Service = "TacitRed"
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
    
    # Test Cyren APIs
    Write-Host "`n[Cyren API Authentication]" -ForegroundColor Yellow
    
    # IP Reputation
    try {
        Write-Host "  Testing Cyren IP Reputation API..." -ForegroundColor Gray
        $cyrenIPJWT = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "cyren-ip-jwt-token" --query "value" -o tsv 2>$null
        
        if($cyrenIPJWT){
            $headers = @{
                'Authorization' = "Bearer $cyrenIPJWT"
                'Accept' = 'application/json'
            }
            
            $apiUrl = "https://api-feeds.cyren.com/v1/feed/data?feedId=ip_reputation&offset=0&count=10&format=jsonl"
            $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
            
            Write-Host "    ✓ HTTP Status: 200" -ForegroundColor Green
            Write-Host "    ✓ Records: $($response.Count)" -ForegroundColor $(if($response.Count -gt 0){'Green'}else{'Yellow'})
            
            $fixResults.APITests += @{
                Service = "Cyren-IP"
                Status = "Success"
                HTTPStatus = 200
                ResultCount = $response.Count
                HasData = $response.Count -gt 0
            }
        }else{
            Write-Host "    ✗ Could not retrieve JWT from Key Vault" -ForegroundColor Red
        }
    } catch {
        Write-Host "    ✗ API Error: $($_.Exception.Message)" -ForegroundColor Red
        $fixResults.APITests += @{
            Service = "Cyren-IP"
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
    
    # Malware URLs
    try {
        Write-Host "`n  Testing Cyren Malware URLs API..." -ForegroundColor Gray
        $cyrenMalwareJWT = az keyvault secret show --vault-name "kv-tacitred-secure01" --name "cyren-malware-jwt-token" --query "value" -o tsv 2>$null
        
        if($cyrenMalwareJWT){
            $headers = @{
                'Authorization' = "Bearer $cyrenMalwareJWT"
                'Accept' = 'application/json'
            }
            
            $apiUrl = "https://api-feeds.cyren.com/v1/feed/data?feedId=malware_urls&offset=0&count=10&format=jsonl"
            $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
            
            Write-Host "    ✓ HTTP Status: 200" -ForegroundColor Green
            Write-Host "    ✓ Records: $($response.Count)" -ForegroundColor $(if($response.Count -gt 0){'Green'}else{'Yellow'})
            
            $fixResults.APITests += @{
                Service = "Cyren-Malware"
                Status = "Success"
                HTTPStatus = 200
                ResultCount = $response.Count
                HasData = $response.Count -gt 0
            }
        }else{
            Write-Host "    ✗ Could not retrieve JWT from Key Vault" -ForegroundColor Red
        }
    } catch {
        Write-Host "    ✗ API Error: $($_.Exception.Message)" -ForegroundColor Red
        $fixResults.APITests += @{
            Service = "Cyren-Malware"
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# SECTION 3: VERIFY CRITICAL INFRASTRUCTURE
# ============================================================================
Write-Host "`n═══ SECTION 3: VERIFY CRITICAL INFRASTRUCTURE ═══" -ForegroundColor Cyan

Write-Host "`n[TacitRed CCF Connector Configuration]" -ForegroundColor Yellow
try {
    $uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/providers/Microsoft.SecurityInsights/dataConnectors/TacitRedFindings?api-version=2024-09-01"
    $connector = az rest --method GET --uri $uri 2>$null | ConvertFrom-Json
    
    if($connector){
        Write-Host "  ✓ CCF Connector exists" -ForegroundColor Green
        Write-Host "  Data Type: $($connector.properties.dataType)" -ForegroundColor Gray
        Write-Host "  Kind: $($connector.kind)" -ForegroundColor Gray
        
        if($connector.properties.request.queryWindowInMin){
            Write-Host "  Polling Interval: $($connector.properties.request.queryWindowInMin) minutes" -ForegroundColor Gray
            
            if($connector.properties.request.queryWindowInMin -eq 1){
                Write-Host "  ⚠ WARNING: Connector is in TEST MODE (queryWindowInMin=1)" -ForegroundColor Yellow
                Write-Host "  ⚠ This must be changed to 60 before production deployment!" -ForegroundColor Yellow
                $fixResults.Issues += "TacitRed CCF connector is in test mode (queryWindowInMin=1) - must revert to production (60) before packaging"
            }
        }
        
        if($connector.properties.dcrConfig){
            Write-Host "  ✓ DCR Configuration present" -ForegroundColor Green
            Write-Host "    Stream: $($connector.properties.dcrConfig.streamName)" -ForegroundColor Gray
            Write-Host "    DCR ID: $($connector.properties.dcrConfig.dataCollectionRuleImmutableId)" -ForegroundColor Gray
        }else{
            Write-Host "  ✗ DCR Configuration MISSING" -ForegroundColor Red
            $fixResults.Issues += "TacitRed CCF connector missing dcrConfig"
        }
    }else{
        Write-Host "  ✗ CCF Connector not found" -ForegroundColor Red
        $fixResults.Issues += "TacitRed CCF connector does not exist"
    }
} catch {
    Write-Host "  ✗ Error checking connector: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# SUMMARY AND NEXT STEPS
# ============================================================================
Write-Host "`n═══ SUMMARY AND NEXT STEPS ═══" -ForegroundColor Cyan

$tablesCreated = ($fixResults.TablesCreated | Where-Object {$_.Status -eq "Created"}).Count
$tablesExisted = ($fixResults.TablesCreated | Where-Object {$_.Status -eq "AlreadyExists"}).Count
$tablesFailed = ($fixResults.TablesCreated | Where-Object {$_.Status -in @("Failed", "Error")}).Count

$apiSuccess = ($fixResults.APITests | Where-Object {$_.Status -eq "Success"}).Count
$apiWithData = ($fixResults.APITests | Where-Object {$_.HasData -eq $true}).Count
$apiFailed = ($fixResults.APITests | Where-Object {$_.Status -eq "Error"}).Count

Write-Host "`n📊 RESULTS:" -ForegroundColor Cyan
Write-Host "  Tables Created: $tablesCreated" -ForegroundColor $(if($tablesCreated -gt 0){'Green'}else{'Gray'})
Write-Host "  Tables Already Existed: $tablesExisted" -ForegroundColor Gray
Write-Host "  Tables Failed: $tablesFailed" -ForegroundColor $(if($tablesFailed -gt 0){'Red'}else{'Gray'})

if(-not $SkipAPITest){
    Write-Host "  API Tests Successful: $apiSuccess" -ForegroundColor $(if($apiSuccess -gt 0){'Green'}else{'Gray'})
    Write-Host "  APIs with Data: $apiWithData" -ForegroundColor $(if($apiWithData -gt 0){'Green'}else{'Yellow'})
    Write-Host "  API Tests Failed: $apiFailed" -ForegroundColor $(if($apiFailed -gt 0){'Red'}else{'Gray'})
}

if($fixResults.Issues.Count -gt 0){
    Write-Host "`n⚠ ISSUES FOUND:" -ForegroundColor Yellow
    $fixResults.Issues | ForEach-Object {
        Write-Host "  • $_" -ForegroundColor Yellow
    }
}

# Determine overall success
$fixResults.Success = ($tablesFailed -eq 0) -and ($tablesCreated -gt 0 -or $tablesExisted -gt 0)

if($fixResults.Success){
    Write-Host "`n✅ FIX COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "  1. Wait 60-120 minutes for first TacitRed data (CCF polls every 60 min)" -ForegroundColor White
    Write-Host "  2. Verify data ingestion with query:" -ForegroundColor White
    Write-Host "     TacitRed_Findings_CL | summarize count()" -ForegroundColor Gray
    Write-Host "  3. Check Cyren connector deployment status" -ForegroundColor White
    Write-Host "  4. Monitor ingestion with DIAGNOSE-ZERO-RECORDS.ps1" -ForegroundColor White
}else{
    Write-Host "`n❌ FIX ENCOUNTERED ISSUES" -ForegroundColor Red
    Write-Host "Review the errors above and address them before proceeding." -ForegroundColor Red
}

# Save results
$reportFile = ".\docs\fix-zero-records-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$fixResults | ConvertTo-Json -Depth 10 | Out-File $reportFile -Encoding UTF8
Write-Host "`n📄 Fix report saved: $reportFile" -ForegroundColor Gray

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

exit $(if($fixResults.Success){0}else{1})

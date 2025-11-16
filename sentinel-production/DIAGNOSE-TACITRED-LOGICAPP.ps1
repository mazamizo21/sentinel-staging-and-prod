# DIAGNOSE-TACITRED-LOGICAPP.ps1
# Focused diagnostic for TacitRed Logic App

<#
.SYNOPSIS
    Diagnoses TacitRed Logic App configuration and execution
.DESCRIPTION
    Checks Logic App state, recent runs, RBAC assignments, and DCR/DCE configuration
#>

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   TACITRED LOGIC APP DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

# Load config
$config = Get-Content ".\client-config-COMPLETE.json" -Raw | ConvertFrom-Json
$sub = $config.parameters.azure.value.subscriptionId
$rg = $config.parameters.azure.value.resourceGroupName
$ws = $config.parameters.azure.value.workspaceName

Write-Host "Subscription: $sub" -ForegroundColor Gray
Write-Host "Resource Group: $rg" -ForegroundColor Gray
Write-Host "Workspace: $ws`n" -ForegroundColor Gray

az account set --subscription $sub | Out-Null

$laName = "logic-tacitred-ingestion"

# ============================================================================
# SECTION 1: LOGIC APP STATUS
# ============================================================================
Write-Host "═══ SECTION 1: LOGIC APP STATUS ═══" -ForegroundColor Cyan

try {
    $la = az logic workflow show -g $rg -n $laName 2>$null | ConvertFrom-Json
    
    if(-not $la){
        Write-Host "✗ Logic App '$laName' NOT FOUND" -ForegroundColor Red
        Write-Host "`n📋 ACTION REQUIRED:" -ForegroundColor Yellow
        Write-Host "  The Logic App has not been deployed. Run:" -ForegroundColor White
        Write-Host "  .\DEPLOY-COMPLETE.ps1" -ForegroundColor Cyan
        exit 1
    }
    
    Write-Host "✓ Logic App exists" -ForegroundColor Green
    Write-Host "  State: $($la.properties.state)" -ForegroundColor Gray
    Write-Host "  Location: $($la.location)" -ForegroundColor Gray
    Write-Host "  Resource ID: $($la.id)" -ForegroundColor Gray
    
    # Check managed identity
    if($la.identity -and $la.identity.principalId){
        Write-Host "`n✓ Managed Identity configured" -ForegroundColor Green
        Write-Host "  Principal ID: $($la.identity.principalId)" -ForegroundColor Gray
        Write-Host "  Type: $($la.identity.type)" -ForegroundColor Gray
    }else{
        Write-Host "`n✗ NO MANAGED IDENTITY" -ForegroundColor Red
        Write-Host "  Logic App cannot authenticate to DCR/DCE without managed identity" -ForegroundColor Red
    }
    
} catch {
    Write-Host "✗ Error checking Logic App: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================================================
# SECTION 2: RECENT RUNS
# ============================================================================
Write-Host "`n═══ SECTION 2: RECENT RUNS (Last 5) ═══" -ForegroundColor Cyan

try {
    $runsUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/runs?`$top=5&api-version=2019-05-01"
    $runs = az rest --method GET --uri $runsUri 2>$null | ConvertFrom-Json
    
    if(-not $runs.value -or $runs.value.Count -eq 0){
        Write-Host "⚠ NO RUNS FOUND" -ForegroundColor Yellow
        Write-Host "  Logic App has not been triggered yet" -ForegroundColor Yellow
        Write-Host "`n📋 ACTION:" -ForegroundColor Cyan
        Write-Host "  Manually trigger the Logic App:" -ForegroundColor White
        Write-Host "  az logic workflow trigger run -g $rg --name $laName --trigger-name Recurrence" -ForegroundColor Gray
    }else{
        Write-Host "✓ Found $($runs.value.Count) recent runs`n" -ForegroundColor Green
        
        foreach($run in $runs.value){
            $runTime = [DateTime]::Parse($run.properties.startTime).ToString('yyyy-MM-dd HH:mm:ss')
            $runStatus = $run.properties.status
            $runDuration = if($run.properties.endTime){
                $start = [DateTime]::Parse($run.properties.startTime)
                $end = [DateTime]::Parse($run.properties.endTime)
                ($end - $start).TotalSeconds
            }else{"Running"}
            
            $color = if($runStatus -eq 'Succeeded'){'Green'}elseif($runStatus -match 'Running'){'Yellow'}else{'Red'}
            Write-Host "  Run: $runTime - $runStatus ($runDuration sec)" -ForegroundColor $color
            
            # Get detailed action status for failed/running runs
            if($runStatus -ne 'Succeeded'){
                $actionsUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$laName/runs/$($run.name)/actions?api-version=2019-05-01"
                $actions = az rest --method GET --uri $actionsUri 2>$null | ConvertFrom-Json
                
                if($actions.value){
                    foreach($action in $actions.value | Where-Object {$_.properties.status -ne 'Succeeded'}){
                        Write-Host "    Action: $($action.name) - $($action.properties.status)" -ForegroundColor Yellow
                        
                        if($action.properties.error){
                            Write-Host "      Error Code: $($action.properties.error.code)" -ForegroundColor Red
                            Write-Host "      Error Message: $($action.properties.error.message)" -ForegroundColor Red
                        }
                        
                        # Special handling for Send_to_DCE action
                        if($action.name -eq 'Send_to_DCE' -and $action.properties.outputs){
                            $outputs = $action.properties.outputs
                            if($outputs.statusCode){
                                Write-Host "      HTTP Status: $($outputs.statusCode)" -ForegroundColor $(if($outputs.statusCode -eq 204){'Green'}else{'Red'})
                            }
                            if($outputs.body){
                                Write-Host "      Response: $($outputs.body | ConvertTo-Json -Compress)" -ForegroundColor Gray
                            }
                        }
                    }
                }
            }
        }
    }
    
} catch {
    Write-Host "✗ Error checking runs: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# SECTION 3: DCR/DCE CONFIGURATION
# ============================================================================
Write-Host "`n═══ SECTION 3: DCR/DCE CONFIGURATION ═══" -ForegroundColor Cyan

# Check for TacitRed DCR
Write-Host "`n[TacitRed DCR]" -ForegroundColor Yellow
try {
    $dcrList = az monitor data-collection rule list --resource-group $rg -o json | ConvertFrom-Json
    $tacitredDcr = $dcrList | Where-Object { $_.name -like "*tacitred*" -or $_.name -like "*findings*" } | Select-Object -First 1
    
    if($tacitredDcr){
        Write-Host "✓ DCR found: $($tacitredDcr.name)" -ForegroundColor Green
        Write-Host "  Immutable ID: $($tacitredDcr.immutableId)" -ForegroundColor Gray
        Write-Host "  Location: $($tacitredDcr.location)" -ForegroundColor Gray
        
        # Check stream declarations
        if($tacitredDcr.properties.streamDeclarations){
            $streams = $tacitredDcr.properties.streamDeclarations.PSObject.Properties.Name
            Write-Host "  Streams: $($streams -join ', ')" -ForegroundColor Gray
        }
        
        # Check data flows
        if($tacitredDcr.properties.dataFlows){
            Write-Host "  Data Flows: $($tacitredDcr.properties.dataFlows.Count)" -ForegroundColor Gray
            foreach($flow in $tacitredDcr.properties.dataFlows){
                Write-Host "    Input: $($flow.streams -join ', ')" -ForegroundColor DarkGray
                Write-Host "    Output: $($flow.outputStream)" -ForegroundColor DarkGray
            }
        }
    }else{
        Write-Host "✗ TacitRed DCR NOT FOUND" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Error checking DCR: $($_.Exception.Message)" -ForegroundColor Red
}

# Check for DCE
Write-Host "`n[Data Collection Endpoint]" -ForegroundColor Yellow
try {
    $dceList = az monitor data-collection endpoint list --resource-group $rg -o json | ConvertFrom-Json
    $dce = $dceList | Select-Object -First 1
    
    if($dce){
        Write-Host "✓ DCE found: $($dce.name)" -ForegroundColor Green
        Write-Host "  Endpoint: $($dce.properties.logsIngestion.endpoint)" -ForegroundColor Gray
    }else{
        Write-Host "✗ DCE NOT FOUND" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Error checking DCE: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# SECTION 4: RBAC ASSIGNMENTS
# ============================================================================
Write-Host "`n═══ SECTION 4: RBAC ASSIGNMENTS ═══" -ForegroundColor Cyan

if($la.identity -and $la.identity.principalId){
    $principalId = $la.identity.principalId
    
    Write-Host "`nChecking role assignments for principal: $principalId" -ForegroundColor Gray
    
    # Check DCR RBAC
    if($tacitredDcr){
        Write-Host "`n[DCR RBAC]" -ForegroundColor Yellow
        try {
            $dcrRbac = az role assignment list --scope $tacitredDcr.id --assignee $principalId -o json | ConvertFrom-Json
            
            if($dcrRbac -and $dcrRbac.Count -gt 0){
                Write-Host "✓ Found $($dcrRbac.Count) role assignment(s)" -ForegroundColor Green
                foreach($role in $dcrRbac){
                    Write-Host "  Role: $($role.roleDefinitionName)" -ForegroundColor Gray
                    Write-Host "  Scope: $($role.scope)" -ForegroundColor DarkGray
                }
            }else{
                Write-Host "✗ NO RBAC assignments on DCR" -ForegroundColor Red
                Write-Host "  Logic App cannot write to DCR without 'Monitoring Metrics Publisher' role" -ForegroundColor Red
            }
        } catch {
            Write-Host "✗ Error checking DCR RBAC: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    # Check DCE RBAC
    if($dce){
        Write-Host "`n[DCE RBAC]" -ForegroundColor Yellow
        try {
            $dceRbac = az role assignment list --scope $dce.id --assignee $principalId -o json | ConvertFrom-Json
            
            if($dceRbac -and $dceRbac.Count -gt 0){
                Write-Host "✓ Found $($dceRbac.Count) role assignment(s)" -ForegroundColor Green
                foreach($role in $dceRbac){
                    Write-Host "  Role: $($role.roleDefinitionName)" -ForegroundColor Gray
                    Write-Host "  Scope: $($role.scope)" -ForegroundColor DarkGray
                }
            }else{
                Write-Host "✗ NO RBAC assignments on DCE" -ForegroundColor Red
                Write-Host "  Logic App cannot write to DCE without 'Monitoring Metrics Publisher' role" -ForegroundColor Red
            }
        } catch {
            Write-Host "✗ Error checking DCE RBAC: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ============================================================================
# SECTION 5: TABLE STATUS
# ============================================================================
Write-Host "`n═══ SECTION 5: TABLE STATUS ═══" -ForegroundColor Cyan

Write-Host "`n[TacitRed_Findings_CL]" -ForegroundColor Yellow
try {
    $query = "TacitRed_Findings_CL | summarize Count=count(), Latest=max(TimeGenerated)"
    $result = az monitor log-analytics query -w $ws --analytics-query $query 2>$null | ConvertFrom-Json
    
    if($result.tables -and $result.tables[0].rows.Count -gt 0){
        $count = $result.tables[0].rows[0][0]
        $latest = $result.tables[0].rows[0][1]
        
        if($count -gt 0){
            Write-Host "✓ Table has $count records" -ForegroundColor Green
            Write-Host "  Latest: $latest" -ForegroundColor Gray
        }else{
            Write-Host "⚠ Table exists but has 0 records" -ForegroundColor Yellow
            Write-Host "  Expected behavior if:" -ForegroundColor Gray
            Write-Host "    - Logic App hasn't run yet" -ForegroundColor DarkGray
            Write-Host "    - TacitRed API has no data" -ForegroundColor DarkGray
            Write-Host "    - RBAC is still propagating (wait 30-60 min)" -ForegroundColor DarkGray
        }
    }else{
        Write-Host "✗ Table NOT FOUND or inaccessible" -ForegroundColor Red
        Write-Host "  Run FIX-ZERO-RECORDS.ps1 to create the table" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Table query failed: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n═══ SUMMARY ═══" -ForegroundColor Cyan

Write-Host "`n📋 CHECKLIST:" -ForegroundColor Yellow
Write-Host "  [$(if($la){'✓'}else{'✗'})] Logic App exists" -ForegroundColor $(if($la){'Green'}else{'Red'})
Write-Host "  [$(if($la.identity){'✓'}else{'✗'})] Managed Identity configured" -ForegroundColor $(if($la.identity){'Green'}else{'Red'})
Write-Host "  [$(if($runs.value.Count -gt 0){'✓'}else{'⚠'})] Logic App has run at least once" -ForegroundColor $(if($runs.value.Count -gt 0){'Green'}else{'Yellow'})
Write-Host "  [$(if($tacitredDcr){'✓'}else{'✗'})] TacitRed DCR exists" -ForegroundColor $(if($tacitredDcr){'Green'}else{'Red'})
Write-Host "  [$(if($dce){'✓'}else{'✗'})] DCE exists" -ForegroundColor $(if($dce){'Green'}else{'Red'})
Write-Host "  [$(if($dcrRbac.Count -gt 0){'✓'}else{'✗'})] RBAC on DCR assigned" -ForegroundColor $(if($dcrRbac.Count -gt 0){'Green'}else{'Red'})
Write-Host "  [$(if($dceRbac.Count -gt 0){'✓'}else{'✗'})] RBAC on DCE assigned" -ForegroundColor $(if($dceRbac.Count -gt 0){'Green'}else{'Red'})

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

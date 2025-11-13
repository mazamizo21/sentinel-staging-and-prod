# =============================================================================
# Logic App Deployment Diagnostic Script
# Analyzes failed Logic App deployments and provides detailed error information
# =============================================================================

param(
    [string]$ConfigFile = ".\client-config-COMPLETE.json"
)

# Initialize logging
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = ".\docs\diagnostic-logs"
$logFile = "$logDir\logic-app-diagnostic-$timestamp.log"

# Create log directory if it doesn't exist
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry -ForegroundColor $(
        switch ($Level) {
            "ERROR" { "Red" }
            "WARN" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
    Add-Content -Path $logFile -Value $logEntry
}

try {
    Write-Log "Starting Logic App deployment diagnostic..." "INFO"
    
    # Load configuration
    if (-not (Test-Path $ConfigFile)) {
        throw "Configuration file not found: $ConfigFile"
    }
    
    $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $sub = $cfg.parameters.azure.value.subscriptionId
    $rg = $cfg.parameters.azure.value.resourceGroupName
    
    Write-Log "Using subscription: $sub" "INFO"
    Write-Log "Using resource group: $rg" "INFO"
    
    # Set Azure context
    az account set --subscription "$sub" | Out-Null
    Write-Log "Azure context set successfully" "SUCCESS"
    
    # Get latest Logic App deployments
    Write-Log "Retrieving latest Logic App deployments..." "INFO"
    $deploymentsJson = az deployment group list -g "$rg" --query "[?contains(name,'la-')].{name:name, state:properties.provisioningState, time:properties.timestamp}" -o json
    $deployments = $deploymentsJson | ConvertFrom-Json | Select-Object -First 5
    
    if (-not $deployments -or $deployments.Count -eq 0) {
        Write-Log "No Logic App deployments found" "WARN"
        exit 0
    }
    
    Write-Log "Found $($deployments.Count) Logic App deployments" "INFO"
    
    # Analyze each deployment
    foreach ($deployment in $deployments) {
        Write-Log "`n=== Analyzing Deployment: $($deployment.name) ===" "INFO"
        Write-Log "State: $($deployment.state)" "INFO"
        Write-Log "Time: $($deployment.time)" "INFO"
        
        # Get detailed deployment information
        $detailsJson = az deployment group show -g "$rg" -n "$($deployment.name)" --query "{state:properties.provisioningState, error:properties.error, operations:properties.operations}" -o json
        $details = $detailsJson | ConvertFrom-Json
        
        # Check for errors
        if ($details.error) {
            Write-Log "Deployment Error Detected:" "ERROR"
            Write-Log "Message: $($details.error.message)" "ERROR"
            
            if ($details.error.details) {
                Write-Log "Error Details:" "ERROR"
                foreach ($detail in $details.error.details) {
                    Write-Log "  - $($detail.message)" "ERROR"
                }
            }
        }
        
        # Check failed operations
        if ($details.operations) {
            Write-Log "Checking operations..." "INFO"
            $failedOps = $details.operations | Where-Object { $_.provisioningState -eq "Failed" }
            
            if ($failedOps) {
                Write-Log "Failed Operations Found:" "ERROR"
                foreach ($op in $failedOps) {
                    Write-Log "  Resource: $($op.resourceType)" "ERROR"
                    Write-Log "  Status: $($op.statusMessage)" "ERROR"
                    if ($op.properties.error) {
                        Write-Log "  Error: $($op.properties.error.message)" "ERROR"
                    }
                }
            } else {
                Write-Log "No failed operations found" "SUCCESS"
            }
        }
    }
    
    # Check current Logic App resources
    Write-Log "`n=== Checking Current Logic App Resources ===" "INFO"
    $logicAppsJson = az logic workflow list -g "$rg" --query "[].{name:name, id:id, location:location, state:properties.state}" -o json
    $logicApps = $logicAppsJson | ConvertFrom-Json
    
    if ($logicApps -and $logicApps.Count -gt 0) {
        Write-Log "Found $($logicApps.Count) Logic Apps:" "SUCCESS"
        foreach ($app in $logicApps) {
            Write-Log "  - $($app.name) ($($app.state)) in $($app.location)" "INFO"
        }
    } else {
        Write-Log "No Logic Apps found in resource group" "WARN"
    }
    
    # Check managed identities
    Write-Log "`n=== Checking Managed Identities ===" "INFO"
    foreach ($app in $logicApps) {
        Write-Log "Checking identity for: $($app.name)" "INFO"
        try {
            $identityJson = az logic workflow identity show -g "$rg" -n "$($app.name)" -o json
            $identity = $identityJson | ConvertFrom-Json
            if ($identity.principalId) {
                Write-Log "  Principal ID: $($identity.principalId)" "SUCCESS"
            } else {
                Write-Log "  No principal ID found" "WARN"
            }
        } catch {
            Write-Log "  Failed to get identity information" "ERROR"
        }
    }
    
    Write-Log "`n=== Diagnostic Complete ===" "SUCCESS"
    Write-Log "Log file saved to: $logFile" "INFO"
    
} catch {
    Write-Log "Diagnostic failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
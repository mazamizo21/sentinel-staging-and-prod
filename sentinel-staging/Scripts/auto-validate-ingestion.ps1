param(
  [string]$ConfigFile = ".\client-config-COMPLETE.json",
  [int]$MaxWaitMinutes = 30,
  [int]$PollSeconds = 60
)
$ErrorActionPreference='Stop'
$start=Get-Date
$cfg=(Get-Content $ConfigFile -Raw | ConvertFrom-Json).parameters
$sub=$cfg.azure.value.subscriptionId; $rg=$cfg.azure.value.resourceGroupName; $ws=$cfg.azure.value.workspaceName
$valDir=".\docs\deployment-logs\clean-deploy-20251110-204716\validation"; New-Item -ItemType Directory -Force -Path $valDir | Out-Null
$log="$valDir\\auto-validate-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
function Log($m){ $ts=(Get-Date).ToString('s'); "$ts $m" | Tee-Object -FilePath $log -Append }

Log "═══ AUTO VALIDATE INGESTION START ═══"
az account set --subscription $sub | Out-Null
$wsObj=az monitor log-analytics workspace show -g $rg -n $ws -o json 2>$null | ConvertFrom-Json
$wsGuid=$wsObj.customerId

$apps=@('logic-cyren-ip-reputation','logic-cyren-malware-urls','logic-tacitred-ingestion')

# Trigger all three
foreach($a in $apps){
  $uri="https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$a/triggers/Recurrence/run?api-version=2019-05-01"
  try{ az rest --method POST --uri $uri -o none 2>$null; Log "Triggered: $a" } catch { Log "Trigger failed: $a => $($_.Exception.Message)" }
}

$deadline=(Get-Date).AddMinutes($MaxWaitMinutes)
$success=$false

while((Get-Date) -lt $deadline){
  Start-Sleep -Seconds $PollSeconds
  Log "Polling run status and table counts..."
  $allOk=$true
  foreach($a in $apps){
    try{
      $runs = az rest --method GET --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$a/runs?api-version=2019-05-01&$top=1" -o json 2>$null | ConvertFrom-Json
      $run = $runs.value | Select-Object -First 1
      if($run){ Log ("{0}: {1} @ {2}" -f $a,$run.properties.status,$run.properties.startTime) } else { Log ("{0}: no runs" -f $a) }
    } catch { Log ("{0}: status error {1}" -f $a,$_.Exception.Message) }
  }
  # Query ingestion
  try{
    $q = "union isfuzzy=true TacitRed_Findings_CL, Cyren_Indicators_CL | where TimeGenerated > ago(10m) | summarize Count=count() by TableName=`$table | order by TableName asc"
    $rows = az monitor log-analytics query --workspace $wsGuid --analytics-query $q --timespan PT10M -o tsv 2>$null
    if($rows){ Log "Counts (last 10m):`;n$rows" } else { Log "Counts: 0" }
    if(($rows | Select-String "TacitRed_Findings_CL\t[1-9]") -and ($rows | Select-String "Cyren_Indicators_CL\t[1-9]")){
      $success=$true; break
    }
  } catch { Log "Query error: $($_.Exception.Message)" }
}

if($success){ Log "✅ Ingestion detected for both tables within window"; exit 0 } else { Log "⚠️ Ingestion not detected within $MaxWaitMinutes minutes"; exit 1 }

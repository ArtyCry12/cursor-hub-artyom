param(
    [string]$HubRoot = '',
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
if (-not $HubRoot) { $HubRoot = Split-Path $PSScriptRoot -Parent }
$rolloutPath = Join-Path $HubRoot 'lib/model-router/rollout.json'
$rollout = Get-Content -LiteralPath $rolloutPath -Raw -Encoding UTF8 | ConvertFrom-Json
$reportPath = Join-Path $HubRoot ([string]$rollout.shadowReport)
if (-not (Test-Path -LiteralPath $reportPath)) { throw "Shadow report missing: $reportPath" }
$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json

$failures = New-Object System.Collections.Generic.List[string]
if ([int]$report.cases -lt [int]$rollout.gate.minimumCases) { $failures.Add('insufficient-cases') }
if ([double]$report.accuracy -lt [double]$rollout.gate.minimumAccuracy) { $failures.Add('accuracy') }
if ([int]$report.policyConstraints.violations -gt [int]$rollout.gate.maximumPolicyViolations) { $failures.Add('policy') }
if ([int]$report.budgetViolations -gt [int]$rollout.gate.maximumBudgetViolations) { $failures.Add('budget') }
if ([int]$report.unexplainedExpensiveFallbacks -gt [int]$rollout.gate.maximumUnexplainedExpensiveFallbacks) {
    $failures.Add('expensive-fallback')
}
if (-not [bool]$report.activeReady) { $failures.Add('report-not-ready') }

if ($failures.Count -gt 0) {
    [PSCustomObject]@{
        ok = $false
        mode = [string]$rollout.mode
        failures = [string[]]$failures
    } | ConvertTo-Json -Compress
    exit 3
}
if (-not $CheckOnly) {
    $rollout.mode = 'active'
    $rollout.activatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $temporary = "$rolloutPath.$([Guid]::NewGuid().ToString('N')).tmp"
    $rollout | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $rolloutPath -Force
}
[PSCustomObject]@{
    ok = $true
    mode = if ($CheckOnly) { [string]$rollout.mode } else { 'active' }
    report = [string]$rollout.shadowReport
} | ConvertTo-Json -Compress

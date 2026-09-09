param(
    [switch]$ProbePaid,
    [double]$BudgetUsd = -1,
    [int]$MaxOutputTokens = 16,
    [switch]$RefreshCatalog,
    [switch]$Json,
    [string]$HubRoot = ''
)

$ErrorActionPreference = 'Stop'
if (-not $HubRoot) { $HubRoot = Split-Path $PSScriptRoot -Parent }
Import-Module (Join-Path $HubRoot 'lib/model-router/ModelRouter.psm1') -Force

$catalog = @(Get-OpenRouterCatalog -HubRoot $HubRoot -Refresh:$RefreshCatalog)
$ladder = Get-ModelRouterLadder -HubRoot $HubRoot
$prompt = 'Reply with exactly OK.'
$checks = New-Object System.Collections.Generic.List[object]
$probeQueue = New-Object System.Collections.Generic.List[object]
$aggregateWorst = 0.0

foreach ($rankKey in @('rank1_5', 'rank2')) {
    $rankSpec = Get-ModelRouterRankSpec -Ladder $ladder -RankKey $rankKey
    foreach ($property in $rankSpec.models.PSObject.Properties) {
        $model = [string]$property.Name
        $config = $property.Value
        if (@($config.modality) -notcontains 'text') { continue }
        $record = Get-OpenRouterModelRecord -Catalog $catalog -Model $model
        if (-not $record) {
            Write-ModelRouterHealthEvent -HubRoot $HubRoot -Model $model -Status 'catalog-missing' -Error 'not present in current catalog'
            $checks.Add([PSCustomObject]@{ rank = $rankKey; model = $model; catalog = 'missing'; probed = $false })
            continue
        }
        $requested = if ($config.PSObject.Properties['defaultEffort']) { [string]$config.defaultEffort } else { 'medium' }
        $effort = Resolve-ModelRouterEffort -ModelConfig $config -CatalogRecord $record -Requested $requested
        $estimate = Get-ModelRouterCostEstimate -Prompt $prompt -CatalogRecord $record -Effort $effort.selected -MaxOutputTokens $MaxOutputTokens
        $aggregateWorst += $estimate.worstUsd
        $probeQueue.Add([PSCustomObject]@{
            rank = $rankKey
            model = $model
            role = [string]$config.role
            effort = $effort.selected
            estimate = $estimate
        })
        $checks.Add([PSCustomObject]@{
            rank = $rankKey
            model = $model
            catalog = 'present'
            effort = $effort.selected
            promptPerMillion = $estimate.promptPerMillion
            completionPerMillion = $estimate.completionPerMillion
            worstUsd = $estimate.worstUsd
            probed = $false
        })
    }
}

$autoCap = if ($aggregateWorst -le 0) { 0.0 } else { [Math]::Ceiling($aggregateWorst * 1.2 * 10000) / 10000 }
$effectiveBudget = if ($BudgetUsd -ge 0) { $BudgetUsd } else { $autoCap }
$results = New-Object System.Collections.Generic.List[object]

if ($ProbePaid) {
    if ($aggregateWorst -gt $effectiveBudget) {
        $output = [PSCustomObject]@{
            ok = $false
            code = 'budget_cap'
            error = 'Aggregate worst-case probe estimate exceeds budget; no paid calls were made.'
            estimateUsd = [Math]::Round($aggregateWorst, 8)
            budgetUsd = $effectiveBudget
            checks = [object[]]$checks
        }
        Write-Output ($output | ConvertTo-Json -Compress -Depth 14)
        exit 3
    }
    $sessionId = "health-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))"
    foreach ($probe in $probeQueue) {
        $route = [PSCustomObject]@{
            rank = $probe.rank
            model = $probe.model
            role = $probe.role
            effort = $probe.effort
            effortRequested = $probe.effort
            fallbackModels = @($probe.model)
        }
        $response = Invoke-ModelRouterChat -Prompt $prompt -Route $route -Catalog $catalog `
            -BudgetUsd $effectiveBudget -MaxOutputTokens $MaxOutputTokens -SessionId $sessionId -HubRoot $HubRoot
        $results.Add([PSCustomObject]@{
            rank = $probe.rank
            model = $probe.model
            effort = $probe.effort
            ok = [bool]$response.ok
            actualModel = if ($response.ok) { [string]$response.model } else { $null }
            actualUsd = if ($response.ok -and $response.usage) { $response.usage.cost } else { $null }
            code = if ($response.ok) { $null } else { [string]$response.code }
            errors = if ($response.ok) { @() } else { @($response.errors) }
        })
    }
}

$checkItems = [object[]]$checks
$resultItems = [object[]]$results
$missingCount = 0
foreach ($check in $checkItems) { if ($check.catalog -eq 'missing') { $missingCount++ } }
$failedCount = 0
foreach ($result in $resultItems) { if (-not $result.ok) { $failedCount++ } }

$output = [PSCustomObject]@{
    ok = ($missingCount -eq 0) -and (-not $ProbePaid -or $failedCount -eq 0)
    catalogCheckedAt = [DateTime]::UtcNow.ToString('o')
    probePaid = [bool]$ProbePaid
    modelCount = $checks.Count
    aggregateWorstUsd = [Math]::Round($aggregateWorst, 8)
    budgetUsd = $effectiveBudget
    checks = $checkItems
    results = $resultItems
}

if ($Json -or $ProbePaid) {
    Write-Output ($output | ConvertTo-Json -Compress -Depth 14)
}
else {
    Write-Output "R1.5/R2 metadata: $($checks.Count) models; aggregate probe worst=$($output.aggregateWorstUsd) USD; auto-cap=$effectiveBudget USD"
    $checks | Format-Table rank, model, catalog, effort, promptPerMillion, completionPerMillion
}
if (-not $output.ok) { exit 1 }

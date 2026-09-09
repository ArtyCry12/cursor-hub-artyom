param(
    [switch]$ProbePaid,
    [switch]$ProbeR3,
    [int]$R3MaxCandidates = 5,
    [double]$BudgetUsd = -1,
    [int]$MaxOutputTokens = 16,
    [switch]$RefreshCatalog,
    [switch]$Json,
    [string]$HubRoot = '',
    [string]$StateRoot = ''
)

$ErrorActionPreference = 'Stop'
if (-not $HubRoot) { $HubRoot = Split-Path $PSScriptRoot -Parent }
Import-Module (Join-Path $HubRoot 'lib/model-router/ModelRouter.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue

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
            Write-ModelRouterHealthEvent -HubRoot $HubRoot -Model $model -Status 'catalog-missing' `
                -Category 'catalog-missing' -Error 'not present in current catalog' -StateRoot $StateRoot
            $checks.Add([PSCustomObject]@{
                rank = $rankKey
                model = $model
                catalog = 'missing'
                probed = $false
            })
            continue
        }
        $requested = if ($config.PSObject.Properties['defaultEffort']) { [string]$config.defaultEffort } else { 'medium' }
        $effort = Resolve-ModelRouterEffort -ModelConfig $config -CatalogRecord $record -Requested $requested
        $estimate = Get-ModelRouterCostEstimate -Prompt $prompt -CatalogRecord $record `
            -Effort $effort.selected -MaxOutputTokens $MaxOutputTokens -Model $model `
            -HubRoot $HubRoot -StateRoot $StateRoot
        $aggregateWorst += $estimate.worstUsd
        $probeQueue.Add([PSCustomObject]@{
            rank = $rankKey
            model = $model
            role = [string]$config.role
            effort = $effort.selected
            estimate = $estimate
            r3 = $false
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

if ($ProbeR3) {
    $r3Candidates = @(Get-ModelRouterDynamicR3Candidates -Catalog $catalog | Select-Object -First $R3MaxCandidates)
    foreach ($model in $r3Candidates) {
        $record = Get-OpenRouterModelRecord -Catalog $catalog -Model $model
        $estimate = Get-ModelRouterCostEstimate -Prompt $prompt -CatalogRecord $record -Effort none `
            -MaxOutputTokens $MaxOutputTokens -Model $model -HubRoot $HubRoot -StateRoot $StateRoot
        $probeQueue.Add([PSCustomObject]@{
            rank = 'rank3'
            model = $model
            role = 'general-worker'
            effort = 'none'
            estimate = $estimate
            r3 = $true
        })
        $checks.Add([PSCustomObject]@{
            rank = 'rank3'
            model = $model
            catalog = 'quarantine'
            effort = 'none'
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

if ($ProbePaid -or $ProbeR3) {
    if ($ProbePaid -and $aggregateWorst -gt $effectiveBudget) {
        $output = [PSCustomObject]@{
            ok = $false
            code = 'budget_cap'
            error = 'Aggregate worst-case probe estimate exceeds budget; no paid calls were made.'
            estimateUsd = [Math]::Round($aggregateWorst, 8)
            budgetUsd = $effectiveBudget
            checks = [object[]]$checks
        }
        Write-Output ($output | ConvertTo-Json -Compress -Depth 20)
        exit 3
    }
    $sessionId = "health-$([DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss'))"
    foreach ($probe in $probeQueue) {
        if (-not $ProbePaid -and -not $probe.r3) { continue }
        $profile = Get-ModelRouterAgentProfile -ProfileId 'general-worker' -HubRoot $HubRoot
        $candidate = [PSCustomObject]@{
            rank = $probe.rank
            model = $probe.model
            effortRequested = $probe.effort
        }
        $route = [PSCustomObject]@{
            rank = $probe.rank
            model = $probe.model
            role = $probe.role
            effort = $probe.effort
            effortRequested = $probe.effort
            fallbackModels = @($probe.model)
            fallbackCandidates = @($candidate)
            profile = $profile
        }
        $probeBudget = if ($probe.r3 -and $effectiveBudget -le 0) { 0.0 } else { $effectiveBudget }
        $response = Invoke-ModelRouterChat -Prompt $prompt -Route $route -Catalog $catalog `
            -BudgetUsd $probeBudget -MaxOutputTokens $MaxOutputTokens -SessionId $sessionId `
            -HubRoot $HubRoot -StateRoot $StateRoot
        $qualityPassed = [bool]$response.ok -and ([string]$response.text).Trim() -eq 'OK'
        if ($probe.r3) {
            Set-ModelRouterR3Verification -HubRoot $HubRoot -Model $probe.model -Verified:$qualityPassed `
                -Reason $(if ($qualityPassed) { 'metadata+smoke+exact-output+deny-training' } else { [string]$response.code }) `
                -StateRoot $StateRoot
        }
        $results.Add([PSCustomObject]@{
            rank = $probe.rank
            model = $probe.model
            effort = $probe.effort
            ok = [bool]$response.ok
            qualityPassed = $qualityPassed
            actualModel = if ($response.ok) { [string]$response.model } else { $null }
            actualUsd = if ($response.ok -and $response.usage) { $response.usage.cost } else { $null }
            code = if ($response.ok) { $null } else { [string]$response.code }
            errors = if ($response.ok) { @() } else { @($response.errors) }
        })
    }
}

$checkItems = [object[]]$checks
$resultItems = [object[]]$results
$missingCount = @($checkItems | Where-Object { $_.catalog -eq 'missing' }).Count
$failedCount = @($resultItems | Where-Object { -not $_.ok }).Count
$verifiedR3 = @(Get-ModelRouterVerifiedR3Models -HubRoot $HubRoot -StateRoot $StateRoot)
$output = [PSCustomObject]@{
    ok = ($missingCount -eq 0) -and (-not ($ProbePaid -or $ProbeR3) -or $failedCount -eq 0)
    catalogCheckedAt = [DateTimeOffset]::UtcNow.ToString('o')
    probePaid = [bool]$ProbePaid
    probeR3 = [bool]$ProbeR3
    modelCount = $checks.Count
    aggregateWorstUsd = [Math]::Round($aggregateWorst, 8)
    budgetUsd = $effectiveBudget
    verifiedR3 = [string[]]$verifiedR3
    healthState = Get-ModelRouterHealthPath -HubRoot $HubRoot -StateRoot $StateRoot
    checks = $checkItems
    results = $resultItems
}

if ($Json -or $ProbePaid -or $ProbeR3) {
    Write-Output ($output | ConvertTo-Json -Compress -Depth 20)
}
else {
    Write-Output "R1.5/R2 metadata: $($checks.Count) models; aggregate worst=$($output.aggregateWorstUsd) USD; verified R3=$($verifiedR3.Count)"
    $checks | Format-Table rank, model, catalog, effort, promptPerMillion, completionPerMillion
}
if (-not $output.ok) { exit 1 }

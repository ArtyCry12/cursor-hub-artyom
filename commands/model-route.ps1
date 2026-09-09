param(
    [string]$Prompt = '',
    [string]$PromptFile = '',
    [string]$Rank = '',
    [string]$Model = '',
    [ValidateSet('', 'none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max')]
    [string]$Effort = '',
    [double]$BudgetUsd = -1,
    [int]$MaxOutputTokens = 0,
    [int]$ExpectedStages = 1,
    [int]$ExpectedTasks = 1,
    [string]$SessionId = '',
    [switch]$Sensitive,
    [switch]$RefreshCatalog,
    [switch]$DryRun,
    [switch]$Json,
    [string]$HubRoot = ''
)

$ErrorActionPreference = 'Stop'
if (-not $HubRoot) { $HubRoot = Split-Path $PSScriptRoot -Parent }
if ($PromptFile) {
    if (-not (Test-Path -LiteralPath $PromptFile)) { throw "Prompt file not found: $PromptFile" }
    $Prompt = [IO.File]::ReadAllText($PromptFile, [Text.UTF8Encoding]::new($false))
}
if ([string]::IsNullOrWhiteSpace($Prompt) -and [Console]::IsInputRedirected) {
    $Prompt = [Console]::In.ReadToEnd()
}
if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'Pass -Prompt, -PromptFile, or stdin.' }
if (-not $SessionId) {
    $SessionId = if ($env:MODEL_ROUTER_SESSION_ID) { $env:MODEL_ROUTER_SESSION_ID } else { Get-Date -Format 'yyyyMMdd' }
}
if ($ExpectedStages -lt 1) { $ExpectedStages = 1 }
if ($ExpectedTasks -lt 1) { $ExpectedTasks = 1 }

Import-Module (Join-Path $HubRoot 'lib/model-router/ModelRouter.psm1') -Force

try {
    $catalog = @(Get-OpenRouterCatalog -HubRoot $HubRoot -Refresh:$RefreshCatalog)
    $route = Resolve-ModelRoute -Prompt $Prompt -Rank $Rank -Model $Model -Effort $Effort -HubRoot $HubRoot -Catalog $catalog
    $record = Get-OpenRouterModelRecord -Catalog $catalog -Model $route.model
    $estimate = Get-ModelRouterCostEstimate -Prompt $Prompt -CatalogRecord $record -Effort $route.effort -MaxOutputTokens $MaxOutputTokens
    if (-not $estimate.reliable) {
        $result = [PSCustomObject]@{
            ok = $false
            code = 'budget_required'
            error = 'Current price cannot be estimated. Ask Boss for a budget; no API call was made.'
            route = $route
        }
    }
    else {
        $taskExpected = $estimate.expectedUsd * $ExpectedStages
        $taskWorst = $estimate.worstUsd * $ExpectedStages
        $sessionExpected = $taskExpected * $ExpectedTasks
        $sessionWorst = $taskWorst * $ExpectedTasks
        $session = Get-ModelRouterSession -HubRoot $HubRoot -SessionId $SessionId
        $spentBefore = [double]$session.spentUsd
        $autoCap = if ($sessionWorst -le 0) { $spentBefore } else { $spentBefore + ([Math]::Ceiling($sessionWorst * 1.15 * 10000) / 10000) }
        $effectiveBudget = if ($BudgetUsd -ge 0) { $BudgetUsd } else { $autoCap }
        $receipt = [PSCustomObject]@{
            rank = $route.rank
            preferredModel = $route.preferredModel
            model = $route.model
            selectionAdjusted = $route.selectionAdjusted
            role = $route.role
            effortRequested = $route.effortRequested
            effort = $route.effort
            effortAdjusted = $route.effortAdjusted
            pricePerMillion = [PSCustomObject]@{
                input = $estimate.promptPerMillion
                output = $estimate.completionPerMillion
                reasoning = $estimate.reasoningPerMillion
            }
            estimateUsd = [PSCustomObject]@{
                stageExpected = [Math]::Round($estimate.expectedUsd, 8)
                stageWorst = [Math]::Round($estimate.worstUsd, 8)
                taskExpected = [Math]::Round($taskExpected, 8)
                taskWorst = [Math]::Round($taskWorst, 8)
                sessionExpected = [Math]::Round($sessionExpected, 8)
                sessionWorst = [Math]::Round($sessionWorst, 8)
            }
            budgetUsd = $effectiveBudget
            sessionSpentBeforeUsd = $spentBefore
            sessionRemainingUsd = [Math]::Round(($effectiveBudget - $spentBefore), 8)
            budgetSource = if ($BudgetUsd -ge 0) { 'user' } else { 'auto-cap' }
            inputTokens = $estimate.inputTokens
            inputExact = $estimate.inputExact
            maxOutputTokens = $estimate.maxOutputTokens
            fallbackModels = @($route.fallbackModels)
            sensitive = [bool]$Sensitive
        }
        if ($DryRun) {
            $result = [PSCustomObject]@{ ok = $true; dryRun = $true; receipt = $receipt }
        }
        elseif (($effectiveBudget - $spentBefore) -lt $estimate.worstUsd) {
            $result = [PSCustomObject]@{
                ok = $false
                code = 'budget_cap'
                error = 'Stage worst-case estimate exceeds the budget. No API call was made.'
                receipt = $receipt
            }
        }
        else {
            $response = Invoke-ModelRouterChat -Prompt $Prompt -Route $route -Catalog $catalog `
                -BudgetUsd $effectiveBudget -MaxOutputTokens $MaxOutputTokens -SessionId $SessionId `
                -Sensitive:$Sensitive -HubRoot $HubRoot
            $result = [PSCustomObject]@{ ok = $response.ok; receipt = $receipt; response = $response }
        }
    }
}
catch {
    $result = [PSCustomObject]@{ ok = $false; code = 'router_error'; error = $_.Exception.Message }
}

if ($Json) {
    Write-Output ($result | ConvertTo-Json -Compress -Depth 16)
    if (-not $result.ok) { exit 3 }
}
elseif ($result.ok -and $result.dryRun) {
    $r = $result.receipt
    Write-Output "Route: $($r.rank) -> $($r.model), effort=$($r.effort)"
    Write-Output "Price / 1M: input=$($r.pricePerMillion.input) USD, output=$($r.pricePerMillion.output) USD"
    Write-Output "Estimate: stage=$($r.estimateUsd.stageExpected)..$($r.estimateUsd.stageWorst) USD; task worst=$($r.estimateUsd.taskWorst) USD; session cap=$($r.budgetUsd) USD"
    Write-Output "Dry run: no API call."
}
elseif ($result.ok) {
    Write-Output "Route: $($result.receipt.rank) -> $($result.response.model), effort=$($result.response.effort)"
    Write-Output "Cost: actual=$($result.response.usage.cost) USD; session=$($result.response.sessionSpentUsd)/$($result.receipt.budgetUsd) USD"
    Write-Output ''
    Write-Output $result.response.text
}
else {
    Write-Output ($result | ConvertTo-Json -Compress -Depth 16)
    exit 3
}

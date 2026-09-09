param(
    [string]$Prompt = '',
    [string]$PromptFile = '',
    [string]$Rank = '',
    [string]$Model = '',
    [string]$ProfileId = '',
    [string]$Stage = '',
    [ValidateSet('', 'none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max')]
    [string]$Effort = '',
    [double]$BudgetUsd = -1,
    [int]$MaxOutputTokens = 0,
    [int]$ExpectedStages = 1,
    [int]$ExpectedTasks = 1,
    [string]$SessionId = '',
    [switch]$Sensitive,
    [switch]$StructuredOutput,
    [switch]$Creative,
    [switch]$AllowUnpriced,
    [switch]$PreviewGlobal,
    [switch]$CursorUnavailable,
    [switch]$RequiresCursorTools,
    [switch]$RefreshCatalog,
    [switch]$DryRun,
    [switch]$Json,
    [string]$HubRoot = '',
    [string]$StateRoot = '',
    [string]$CallId = ''
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

Import-Module (Join-Path $HubRoot 'lib/model-router/ModelRouter.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue

try {
    $catalog = @(Get-OpenRouterCatalog -HubRoot $HubRoot -Refresh:$RefreshCatalog)
    if ($PreviewGlobal) {
        $globalRoute = Resolve-GlobalModelRoute -Prompt $Prompt -Rank $Rank -ProfileId $ProfileId -Stage $Stage `
            -Effort $Effort -CursorAvailable:(-not $CursorUnavailable) -RequiresCursorTools:$RequiresCursorTools `
            -HubRoot $HubRoot -Catalog $catalog
        $result = [PSCustomObject]@{
            ok = [bool]$globalRoute.ok
            preview = $true
            route = $globalRoute
        }
        if ($Json) {
            Write-Output ($result | ConvertTo-Json -Compress -Depth 20)
            if (-not $result.ok) { exit 3 }
        }
        else {
            Write-Output ($result | ConvertTo-Json -Depth 20)
            if (-not $result.ok) { exit 3 }
        }
        exit 0
    }
    $route = Resolve-ModelRoute -Prompt $Prompt -Rank $Rank -Model $Model -Effort $Effort `
        -ProfileId $ProfileId -HubRoot $HubRoot -Catalog $catalog
    $record = Get-OpenRouterModelRecord -Catalog $catalog -Model $route.model
    $effectiveInput = if ($route.profile.systemPrompt) { [string]$route.profile.systemPrompt + "`n`n" + $Prompt } else { $Prompt }
    $estimate = Get-ModelRouterCostEstimate -Prompt $effectiveInput -CatalogRecord $record -Effort $route.effort `
        -MaxOutputTokens $MaxOutputTokens -Model $route.model -HubRoot $HubRoot -StateRoot $StateRoot
    if (-not $estimate.reliable -and -not $AllowUnpriced) {
        $result = [PSCustomObject]@{
            ok = $false
            code = 'unpriced_confirmation_required'
            error = 'This model is unpriced. Ask Boss and wait for an explicit yes; no inference call was made.'
            route = $route
        }
    }
    elseif (-not $estimate.reliable -and $BudgetUsd -lt 0) {
        $result = [PSCustomObject]@{
            ok = $false
            code = 'budget_required'
            error = 'AllowUnpriced also requires an explicit BudgetUsd; no inference call was made.'
            route = $route
        }
    }
    else {
        $taskExpected = $estimate.expectedUsd * $ExpectedStages
        $taskWorst = $estimate.worstUsd * $ExpectedStages
        $sessionExpected = $taskExpected * $ExpectedTasks
        $sessionWorst = $taskWorst * $ExpectedTasks
        $session = Get-ModelRouterSession -HubRoot $HubRoot -SessionId $SessionId -StateRoot $StateRoot
        $spentBefore = [double]$session.spentUsd
        $autoCap = if ($sessionWorst -le 0) { $spentBefore } else { $spentBefore + ([Math]::Ceiling($sessionWorst * 1.15 * 10000) / 10000) }
        $effectiveBudget = if ($BudgetUsd -ge 0) { $BudgetUsd } else { $autoCap }
        $receipt = [PSCustomObject]@{
            rank = $route.rank
            allowedRanks = [string[]]$route.allowedRanks
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
            profile = [string]$route.profile.id
            explanation = [string]$route.explanation
            sensitive = [bool]$Sensitive
            structuredOutput = [bool]$StructuredOutput
            creative = [bool]$Creative
            unpricedConfirmed = [bool]$AllowUnpriced
            cursorTools = $false
            executionBoundary = 'text/planning only; Cursor file, shell, browser, and MCP tools remain unavailable in terminal mode'
        }
        if ($DryRun -and ($effectiveBudget - $spentBefore) -lt $estimate.worstUsd) {
            $result = [PSCustomObject]@{
                ok = $false
                dryRun = $true
                code = 'budget_cap'
                error = 'Dry run predicts that the stage worst-case estimate exceeds the budget.'
                receipt = $receipt
            }
        }
        elseif ($DryRun) {
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
                -CallId $CallId -Sensitive:$Sensitive -StructuredOutput:$StructuredOutput -Creative:$Creative `
                -AllowUnpriced:$AllowUnpriced -HubRoot $HubRoot -StateRoot $StateRoot
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

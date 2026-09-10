param(
    [string]$HubRoot = '',
    [string]$OutFile = '',
    [switch]$ForceBaseline
)

$ErrorActionPreference = 'Stop'
if (-not $HubRoot) { $HubRoot = Split-Path $PSScriptRoot -Parent }
$stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')
$defaultRun = Join-Path $HubRoot ("ai-tracking/ecosystem-governance/reports/runs/model-router-shadow-{0}.json" -f $stamp)
$baseline = Join-Path $HubRoot 'ai-tracking/ecosystem-governance/reports/2026-09-09-model-router-shadow.json'
if (-not $OutFile) { $OutFile = $defaultRun }
if ((Resolve-Path -LiteralPath (Split-Path $OutFile -Parent) -ErrorAction SilentlyContinue) -and
    (([IO.Path]::GetFullPath($OutFile)) -eq ([IO.Path]::GetFullPath($baseline))) -and -not $ForceBaseline) {
    throw "Refusing to overwrite baseline shadow report without -ForceBaseline. Use default run path or pass -ForceBaseline."
}

Import-Module (Join-Path $HubRoot 'lib/model-router/ModelRouter.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue

$catalog = @(Get-OpenRouterCatalog -HubRoot $HubRoot -Refresh)
Ensure-ModelRouterR3Allowlist -HubRoot $HubRoot -Catalog $catalog | Out-Null

$cases = @(
    @{ id = 'en-plan-r15'; prompt = 'R1.5 plan the migration'; ranks = 'R1.5'; profile = 'general-worker'; target = 'openrouter-worker'; expectedRanks = @('rank1_5') },
    @{ id = 'en-batch-r2'; prompt = 'R2 fast batch classification'; ranks = 'R2'; profile = 'general-worker'; target = 'openrouter-worker'; expectedRanks = @('rank2') },
    @{ id = 'en-review-mixed'; prompt = 'R1.5, R2 adversarial review'; ranks = 'R1.5,R2'; profile = 'adversarial-hub-auditor'; target = 'openrouter-worker'; expectedRanks = @('rank1_5', 'rank2') },
    @{ id = 'en-r3-draft'; prompt = 'R3 draft a short note'; ranks = 'R3'; profile = 'temporary-worker'; target = 'openrouter-worker'; expectedRanks = @('rank3'); requireR3 = $true },
    @{ id = 'ecosystem-architecture'; prompt = 'Design the hub architecture'; ranks = 'R1.5,R2'; profile = 'ecosystem-architect'; target = 'openrouter-worker'; expectedRanks = @('rank1_5', 'rank2') },
    @{ id = 'dev-os-research'; prompt = 'Research a Dev OS decision'; ranks = 'R1.5,R2'; profile = 'dev-os-research'; target = 'openrouter-worker'; expectedRanks = @('rank1_5', 'rank2') },
    @{ id = 'adversarial-profile'; prompt = 'Audit the router risks'; ranks = 'R1.5,R2'; profile = 'adversarial-hub-auditor'; target = 'openrouter-worker'; expectedRanks = @('rank1_5', 'rank2') },
    @{ id = 'temporary-batch'; prompt = 'Classify these records quickly'; ranks = 'R2'; profile = 'temporary-worker'; target = 'openrouter-worker'; expectedRanks = @('rank2') },
    @{ id = 'tool-apply'; prompt = 'Apply the patch and run tests'; profile = 'general-worker'; target = 'cursor-parent'; tools = $true; expectedRanks = @('cursor') },
    @{ id = 'tool-browser'; prompt = 'Open the browser and verify UI'; profile = 'general-worker'; target = 'cursor-parent'; tools = $true; expectedRanks = @('cursor') },
    @{ id = 'tool-unavailable'; prompt = 'Edit files after Cursor limits'; profile = 'general-worker'; tools = $true; cursor = $false; expectedError = 'cursor_tools_unavailable' },
    @{ id = 'multimodal-r2'; prompt = 'R2 analyze this image multimodal'; ranks = 'R2'; profile = 'general-worker'; target = 'openrouter-worker'; expectedRanks = @('rank2'); model = 'google/gemini-3.8-flash' },
    @{ id = 'critical-r2'; prompt = 'R2 critical maximum analysis'; ranks = 'R2'; profile = 'ecosystem-architect'; target = 'openrouter-worker'; expectedRanks = @('rank2'); model = 'openai/gpt-5.6-luna-pro' },
    @{ id = 'review-r15'; prompt = 'R1.5 adversarial risk review'; ranks = 'R1.5'; profile = 'adversarial-hub-auditor'; target = 'openrouter-worker'; expectedRanks = @('rank1_5'); model = 'x-ai/grok-4.6' },
    @{ id = 'plan-r15'; prompt = 'R1.5 plan the repository'; ranks = 'R1.5'; profile = 'ecosystem-architect'; target = 'openrouter-worker'; expectedRanks = @('rank1_5') },
    @{ id = 'general-r2'; prompt = 'R2 perform general analysis'; ranks = 'R2'; profile = 'general-worker'; target = 'openrouter-worker'; expectedRanks = @('rank2') },
    @{ id = 'ru-architecture'; prompt = 'R1.5, R2 спланируй архитектуру репозитория'; ranks = 'R1.5,R2'; profile = 'ecosystem-architect'; target = 'openrouter-worker'; expectedRanks = @('rank1_5', 'rank2') },
    @{ id = 'ru-batch'; prompt = 'R2 быстро классифицируй записи'; ranks = 'R2'; profile = 'temporary-worker'; target = 'openrouter-worker'; expectedRanks = @('rank2') },
    @{ id = 'ru-r3'; prompt = 'R3 сделай короткий черновик'; ranks = 'R3'; profile = 'temporary-worker'; target = 'openrouter-worker'; expectedRanks = @('rank3'); requireR3 = $true },
    @{ id = 'global-review'; prompt = 'Perform a strategic adversarial review'; profile = 'adversarial-hub-auditor'; target = 'cursor-native'; expectedRanks = @('cursor') }
)

$results = New-Object System.Collections.Generic.List[object]
foreach ($case in $cases) {
    $route = Resolve-GlobalModelRoute -Prompt $case.prompt -Rank ([string]$case.ranks) `
        -ProfileId ([string]$case.profile) -CursorAvailable:$(if ($case.ContainsKey('cursor')) { [bool]$case.cursor } else { $true }) `
        -RequiresCursorTools:([bool]$case.tools) -HubRoot $HubRoot -Catalog $catalog
    $passed = $false
    $reasons = New-Object System.Collections.Generic.List[string]
    if ($case.ContainsKey('expectedError')) {
        $passed = (-not $route.ok) -and $route.code -eq $case.expectedError
        if (-not $passed) { $reasons.Add("expected error $($case.expectedError)") }
    }
    else {
        $passed = [bool]$route.ok
        if (-not $route.ok) {
            $reasons.Add([string]$route.code)
        }
        else {
            if ($route.target -ne $case.target) {
                $passed = $false
                $reasons.Add("target $($route.target) != $($case.target)")
            }
            if (@($case.expectedRanks) -notcontains [string]$route.rank) {
                $passed = $false
                $reasons.Add("rank $($route.rank) outside expected set")
            }
            if ($case.ContainsKey('model') -and $route.model -ne $case.model) {
                $passed = $false
                $reasons.Add("model $($route.model) != $($case.model)")
            }
        }
    }
    $hashBytes = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($case.prompt))
    $hash = ([BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant().Substring(0, 16)
    $results.Add([PSCustomObject]@{
        id = $case.id
        promptHash = $hash
        expectedTarget = $case.target
        expectedRanks = [string[]]@($case.expectedRanks)
        actualTarget = if ($route.ok) { $route.target } else { $null }
        actualRank = if ($route.ok) { $route.rank } else { $null }
        actualModel = if ($route.ok) { $route.model } else { $null }
        code = if ($route.ok) { 'recommendation' } else { $route.code }
        explanation = if ($route.ok) { $route.explanation } else { $null }
        passed = $passed
        requireR3 = [bool]$case.requireR3
        reasons = [string[]]$reasons
    })
}

$passedCount = @($results | Where-Object { $_.passed }).Count
$accuracy = $passedCount / [double]$cases.Count
$policyViolations = @($results | Where-Object {
    $_.actualTarget -eq 'openrouter-worker' -and $_.expectedRanks.Count -gt 0 -and $_.expectedRanks -notcontains $_.actualRank
}).Count
$r3Required = @($results | Where-Object { $_.requireR3 })
$r3Failures = @($r3Required | Where-Object { -not $_.passed }).Count
$activeReady = ($accuracy -ge 0.9 -and $policyViolations -eq 0 -and $r3Failures -eq 0 -and $r3Required.Count -gt 0)
$report = [PSCustomObject]@{
    schemaVersion = 1
    mode = 'shadow'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    catalogModels = $catalog.Count
    cases = $cases.Count
    passed = $passedCount
    accuracy = [Math]::Round($accuracy, 4)
    r3Required = $r3Required.Count
    r3Failures = $r3Failures
    policyConstraints = [PSCustomObject]@{
        total = $cases.Count
        violations = $policyViolations
        passRate = [Math]::Round((($cases.Count - $policyViolations) / [double]$cases.Count), 4)
    }
    budgetViolations = 0
    inferenceCalls = 0
    actualSpendUsd = 0.0
    unexplainedExpensiveFallbacks = 0
    activeReady = $activeReady
    outFile = $OutFile
    results = [object[]]$results
}

$directory = Split-Path -Parent $OutFile
if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
$report | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $OutFile -Encoding UTF8
Write-Output ($report | ConvertTo-Json -Compress -Depth 15)
if (-not $report.activeReady) { exit 1 }

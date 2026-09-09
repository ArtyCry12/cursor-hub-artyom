Set-StrictMode -Version Latest

$script:EffortOrder = @('none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max')

function Get-ModelRouterHubRoot {
    param([string]$HubRoot = '')
    if ($HubRoot) { return (Resolve-Path -LiteralPath $HubRoot).Path }
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-ModelRouterLadder {
    param([string]$HubRoot = '')
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    $path = Join-Path $root 'ai-tracking/model-ladder.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "Model ladder not found: $path" }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Resolve-ModelRouterRankKey {
    param(
        [string]$Rank = '',
        [string]$Prompt = ''
    )
    $value = $Rank.Trim().ToLowerInvariant() -replace ',', '.'
    switch -Regex ($value) {
        '^(r|rank)?\s*1\.5$|^rank1_5$' { return 'rank1_5' }
        '^(r|rank)?\s*2$|^rank2$' { return 'rank2' }
        '^(r|rank)?\s*3$|^rank3$' { return 'rank3' }
    }
    if ($Prompt -match '(?i)(?<![0-9a-zа-я_])r(?:ank)?\s*1[\.,]5(?![0-9a-zа-я_])') { return 'rank1_5' }
    if ($Prompt -match '(?i)(?<![0-9a-zа-я_])r(?:ank)?\s*2(?![0-9a-zа-я_])') { return 'rank2' }
    if ($Prompt -match '(?i)(?<![0-9a-zа-я_])r(?:ank)?\s*3(?![0-9a-zа-я_])') { return 'rank3' }
    return 'rank3'
}

function Get-ModelRouterRankSpec {
    param(
        [Parameter(Mandatory)]$Ladder,
        [Parameter(Mandatory)][string]$RankKey
    )
    $property = $Ladder.PSObject.Properties[$RankKey]
    if (-not $property) { throw "Unknown model rank: $RankKey" }
    return $property.Value
}

function Get-ModelRouterConfig {
    param(
        [Parameter(Mandatory)]$RankSpec,
        [Parameter(Mandatory)][string]$Model
    )
    $property = $RankSpec.models.PSObject.Properties[$Model]
    if (-not $property) { return $null }
    return $property.Value
}

function Get-OpenRouterCatalog {
    param(
        [string]$HubRoot = '',
        [switch]$Refresh,
        [int]$MaxAgeMinutes = 60
    )
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    $cacheDir = Join-Path $root '.cache/model-router'
    $cachePath = Join-Path $cacheDir 'catalog.json'
    if (-not $Refresh -and (Test-Path -LiteralPath $cachePath)) {
        try {
            $cached = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $age = ([DateTime]::UtcNow - [DateTime]::Parse([string]$cached.checkedAt)).TotalMinutes
            if ($age -ge 0 -and $age -lt $MaxAgeMinutes) { return @($cached.data) }
        }
        catch {}
    }
    $response = Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/models' -Method Get -TimeoutSec 60
    if (-not $response.data) { throw 'OpenRouter model catalog returned no data' }
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    [ordered]@{
        checkedAt = [DateTime]::UtcNow.ToString('o')
        data = @($response.data)
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $cachePath -Encoding UTF8
    return @($response.data)
}

function Get-OpenRouterModelRecord {
    param(
        [Parameter(Mandatory)][object[]]$Catalog,
        [Parameter(Mandatory)][string]$Model
    )
    $matches = @($Catalog | Where-Object { [string]$_.id -eq $Model } | Select-Object -First 1)
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Get-RequestedEffort {
    param(
        [string]$Prompt,
        [string]$Requested = ''
    )
    if ($Requested) { return $Requested.ToLowerInvariant() }
    foreach ($effort in @('max', 'xhigh', 'high', 'medium', 'low', 'minimal', 'none')) {
        if ($Prompt -match "(?i)(?<![0-9a-z_])$([Regex]::Escape($effort))(?![0-9a-z_])") { return $effort }
    }
    if ($Prompt -match '(?i)архитект|стратег|критич|сложн|deep|research|аудит') { return 'high' }
    if ($Prompt -match '(?i)быстро|кратко|черновик|классиф|массов|fast|batch|classif') { return 'low' }
    return 'medium'
}

function Resolve-ModelRouterEffort {
    param(
        [Parameter(Mandatory)]$ModelConfig,
        $CatalogRecord,
        [string]$Requested = 'medium'
    )
    if ($ModelConfig.PSObject.Properties['fixedEffort'] -and $ModelConfig.fixedEffort) {
        return [PSCustomObject]@{
            requested = $Requested
            selected = [string]$ModelConfig.fixedEffort
            adjusted = ([string]$ModelConfig.fixedEffort -ne $Requested)
            reason = 'fixed-model-policy'
        }
    }
    $supported = @()
    if ($CatalogRecord -and $CatalogRecord.PSObject.Properties['reasoning'] -and $CatalogRecord.reasoning -and
        $CatalogRecord.reasoning.PSObject.Properties['supported_efforts']) {
        $supported = @($CatalogRecord.reasoning.supported_efforts)
    }
    if ($supported.Count -eq 0 -and $ModelConfig.PSObject.Properties['supportedEfforts']) {
        $supported = @($ModelConfig.supportedEfforts)
    }
    if ($supported.Count -eq 0) {
        return [PSCustomObject]@{ requested = $Requested; selected = 'none'; adjusted = ($Requested -ne 'none'); reason = 'reasoning-unsupported' }
    }
    if ($supported -contains $Requested) {
        return [PSCustomObject]@{ requested = $Requested; selected = $Requested; adjusted = $false; reason = 'exact' }
    }
    $requestedIndex = [Array]::IndexOf($script:EffortOrder, $Requested)
    if ($requestedIndex -lt 0) { $requestedIndex = [Array]::IndexOf($script:EffortOrder, 'medium') }
    $best = $null
    $bestDistance = [int]::MaxValue
    $bestIndex = -1
    foreach ($candidate in $supported) {
        $index = [Array]::IndexOf($script:EffortOrder, [string]$candidate)
        if ($index -lt 0) { continue }
        $distance = [Math]::Abs($index - $requestedIndex)
        if ($distance -lt $bestDistance -or ($distance -eq $bestDistance -and $index -gt $bestIndex)) {
            $best = [string]$candidate
            $bestDistance = $distance
            $bestIndex = $index
        }
    }
    if (-not $best) { $best = [string]$supported[0] }
    return [PSCustomObject]@{ requested = $Requested; selected = $best; adjusted = $true; reason = 'nearest-supported' }
}

function Select-ModelRouterModel {
    param(
        [Parameter(Mandatory)][string]$RankKey,
        [Parameter(Mandatory)]$RankSpec,
        [string]$Prompt = '',
        [string]$Model = ''
    )
    if ($Model) {
        if (-not (Get-ModelRouterConfig -RankSpec $RankSpec -Model $Model)) {
            throw "Model $Model is not registered in $RankKey"
        }
        return $Model
    }
    if ($RankKey -eq 'rank1_5') {
        if ($Prompt -match '(?i)adversarial|review|critic|оспор|риск|аудит') { return 'x-ai/grok-4.6' }
        if ($Prompt -match '(?i)long.context|больш.*контекст|репозитор|код|архитект') { return 'qwen/qwen3.8-max-0902' }
        if ($Prompt -match '(?i)синтез|текст|creative|вариант|обобщ') { return 'meta/muse-spark-1.2' }
        return 'z-ai/glm-5.3'
    }
    if ($RankKey -eq 'rank2') {
        if ($Prompt -match '(?i)критич|best|лучш|max effort|максимальн') { return 'openai/gpt-5.6-luna-pro' }
        if ($Prompt -match '(?i)массов|batch|fast|быстро|классиф') { return 'deepseek/deepseek-v4-flash-0731' }
        if ($Prompt -match '(?i)изображ|image|video|мультимод') { return 'google/gemini-3.8-flash' }
        return 'z-ai/glm-5.2'
    }
    return [string]$RankSpec.textOrder[0]
}

function Get-ModelRouterFallbacks {
    param(
        [Parameter(Mandatory)]$RankSpec,
        [Parameter(Mandatory)][string]$Selected
    )
    $result = New-Object System.Collections.Generic.List[string]
    $result.Add($Selected)
    $order = if ($RankSpec.PSObject.Properties['chatOrder']) { @($RankSpec.chatOrder) } else { @($RankSpec.textOrder) }
    foreach ($status in @('live', 'unknown', 'degraded', 'unavailable', 'catalog-missing')) {
        foreach ($model in $order) {
            if ($result.Contains([string]$model)) { continue }
            $config = Get-ModelRouterConfig -RankSpec $RankSpec -Model ([string]$model)
            if (-not $config -or @('banned', 'dead') -contains [string]$config.status) { continue }
            if ([string]$config.status -eq $status) { $result.Add([string]$model) }
        }
    }
    return [string[]]$result
}

function Measure-ModelRouterInput {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [int]$ExactTokens = 0
    )
    if ($ExactTokens -gt 0) {
        return [PSCustomObject]@{ tokens = $ExactTokens; exact = $true; method = 'provided' }
    }
    $tokens = [Math]::Max(1, [Math]::Ceiling(($Prompt.Length / 3.0) * 1.15))
    return [PSCustomObject]@{ tokens = [int]$tokens; exact = $false; method = 'conservative-char-estimate' }
}

function Get-DefaultOutputCap {
    param([string]$Effort)
    switch ($Effort) {
        'none' { return 1024 }
        'minimal' { return 1024 }
        'low' { return 2048 }
        'medium' { return 4096 }
        'high' { return 8192 }
        default { return 12288 }
    }
}

function ConvertTo-Price {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 0.0 }
    return [double]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture)
}

function Get-ModelRouterPropertyValue {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if (-not $property) { return $null }
    return $property.Value
}

function Get-EffectiveModelPricing {
    param(
        [Parameter(Mandatory)]$CatalogRecord,
        [Parameter(Mandatory)][int]$InputTokens
    )
    $promptRaw = Get-ModelRouterPropertyValue $CatalogRecord.pricing 'prompt'
    $completionRaw = Get-ModelRouterPropertyValue $CatalogRecord.pricing 'completion'
    $result = [ordered]@{
        prompt = ConvertTo-Price $promptRaw
        completion = ConvertTo-Price $completionRaw
        request = ConvertTo-Price (Get-ModelRouterPropertyValue $CatalogRecord.pricing 'request')
        internal_reasoning = ConvertTo-Price (Get-ModelRouterPropertyValue $CatalogRecord.pricing 'internal_reasoning')
        input_cache_read = ConvertTo-Price (Get-ModelRouterPropertyValue $CatalogRecord.pricing 'input_cache_read')
        input_cache_write = ConvertTo-Price (Get-ModelRouterPropertyValue $CatalogRecord.pricing 'input_cache_write')
        known = ($null -ne $promptRaw -and $null -ne $completionRaw)
        overrideApplied = $false
    }
    if ($CatalogRecord.pricing.PSObject.Properties['overrides'] -and $CatalogRecord.pricing.overrides) {
        foreach ($override in @($CatalogRecord.pricing.overrides)) {
            $minimum = 0
            if ($override.PSObject.Properties['min_prompt_tokens']) { $minimum = [int]$override.min_prompt_tokens }
            if ($InputTokens -lt $minimum) { continue }
            foreach ($name in @('prompt', 'completion', 'request', 'internal_reasoning', 'input_cache_read', 'input_cache_write')) {
                if ($override.PSObject.Properties[$name]) { $result[$name] = ConvertTo-Price $override.$name }
            }
            $result.overrideApplied = $true
        }
    }
    return [PSCustomObject]$result
}

function Get-ModelRouterCostEstimate {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)]$CatalogRecord,
        [Parameter(Mandatory)][string]$Effort,
        [int]$MaxOutputTokens = 0,
        [int]$InputTokens = 0
    )
    $input = Measure-ModelRouterInput -Prompt $Prompt -ExactTokens $InputTokens
    if ($MaxOutputTokens -le 0) { $MaxOutputTokens = Get-DefaultOutputCap -Effort $Effort }
    $pricing = Get-EffectiveModelPricing -CatalogRecord $CatalogRecord -InputTokens $input.tokens
    $ratios = @{ none = 0.0; minimal = 0.1; low = 0.2; medium = 0.5; high = 0.8; xhigh = 0.95; max = 0.95 }
    $ratio = if ($ratios.ContainsKey($Effort)) { [double]$ratios[$Effort] } else { 0.5 }
    $expectedOutput = [Math]::Max(1, [Math]::Ceiling($MaxOutputTokens * 0.35))
    $reasoningFloor = if ($ratio -gt 0) { 1024 } else { 0 }
    $expectedReasoning = [Math]::Max($reasoningFloor, [Math]::Ceiling($expectedOutput * $ratio))
    $worstReasoning = [Math]::Max($reasoningFloor, [Math]::Ceiling($MaxOutputTokens * $ratio))
    $reasoningRate = if ($pricing.internal_reasoning -gt 0) { $pricing.internal_reasoning } else { $pricing.completion }
    $expected = ($input.tokens * $pricing.prompt) + ($expectedOutput * $pricing.completion) +
        ($expectedReasoning * $reasoningRate) + $pricing.request
    $worst = ($input.tokens * $pricing.prompt) + ($MaxOutputTokens * $pricing.completion) +
        ($worstReasoning * $reasoningRate) + $pricing.request
    $autoCap = if ($worst -le 0) { 0.0 } else { [Math]::Ceiling($worst * 1.15 * 10000) / 10000 }
    return [PSCustomObject]@{
        inputTokens = $input.tokens
        inputExact = $input.exact
        inputMethod = $input.method
        maxOutputTokens = $MaxOutputTokens
        reasoningTokensExpected = $expectedReasoning
        reasoningTokensWorst = $worstReasoning
        reasoningFloorApplied = ($reasoningFloor -gt 0)
        expectedUsd = [Math]::Round($expected, 8)
        worstUsd = [Math]::Round($worst, 8)
        autoCapUsd = $autoCap
        reliable = [bool]$pricing.known
        overrideApplied = $pricing.overrideApplied
        promptPerMillion = [Math]::Round($pricing.prompt * 1000000, 6)
        completionPerMillion = [Math]::Round($pricing.completion * 1000000, 6)
        reasoningPerMillion = [Math]::Round($pricing.internal_reasoning * 1000000, 6)
    }
}

function Resolve-ModelRoute {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Rank = '',
        [string]$Model = '',
        [string]$Effort = '',
        [string]$HubRoot = '',
        [object[]]$Catalog
    )
    $ladder = Get-ModelRouterLadder -HubRoot $HubRoot
    $rankKey = Resolve-ModelRouterRankKey -Rank $Rank -Prompt $Prompt
    $rankSpec = Get-ModelRouterRankSpec -Ladder $ladder -RankKey $rankKey
    if (-not $Catalog) { $Catalog = Get-OpenRouterCatalog -HubRoot $HubRoot }
    $preferred = Select-ModelRouterModel -RankKey $rankKey -RankSpec $rankSpec -Prompt $Prompt -Model $Model
    $fallbackCandidates = @(Get-ModelRouterFallbacks -RankSpec $rankSpec -Selected $preferred)
    $preferredConfig = Get-ModelRouterConfig -RankSpec $rankSpec -Model $preferred
    if (-not $Model -and $preferredConfig -and @('unavailable', 'catalog-missing') -contains [string]$preferredConfig.status) {
        $healthy = @($fallbackCandidates | Where-Object {
            $candidateConfig = Get-ModelRouterConfig -RankSpec $rankSpec -Model ([string]$_)
            $candidateConfig -and @('unavailable', 'catalog-missing') -notcontains [string]$candidateConfig.status
        })
        $unhealthy = @($fallbackCandidates | Where-Object { $healthy -notcontains [string]$_ })
        $fallbackCandidates = @($healthy + $unhealthy)
    }
    $availableFallbacks = @($fallbackCandidates | Where-Object { Get-OpenRouterModelRecord -Catalog $Catalog -Model ([string]$_) })
    if ($availableFallbacks.Count -eq 0) { throw "No catalog-present models are available in $rankKey" }
    $selected = [string]$availableFallbacks[0]
    $config = Get-ModelRouterConfig -RankSpec $rankSpec -Model $selected
    $record = Get-OpenRouterModelRecord -Catalog $Catalog -Model $selected
    $requestedEffort = Get-RequestedEffort -Prompt $Prompt -Requested $Effort
    $effortResult = Resolve-ModelRouterEffort -ModelConfig $config -CatalogRecord $record -Requested $requestedEffort
    $reasoningMandatory = $false
    if ($config.PSObject.Properties['reasoningMandatory']) { $reasoningMandatory = [bool]$config.reasoningMandatory }
    return [PSCustomObject]@{
        rank = $rankKey
        preferredModel = $preferred
        model = $selected
        selectionAdjusted = ($selected -ne $preferred)
        role = [string]$config.role
        effort = $effortResult.selected
        effortRequested = $effortResult.requested
        effortAdjusted = $effortResult.adjusted
        effortReason = $effortResult.reason
        reasoningMandatory = $reasoningMandatory
        fallbackModels = $availableFallbacks
    }
}

function Get-SafeModelRouterSessionId {
    param([Parameter(Mandatory)][string]$SessionId)
    $safe = $SessionId -replace '[^0-9A-Za-z._-]', '_'
    $safe = $safe.Trim('.', '_')
    if (-not $safe) { $safe = 'default' }
    if ($safe.Length -gt 64) { $safe = $safe.Substring(0, 64) }
    return $safe
}

function Get-ModelRouterSession {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)][string]$SessionId
    )
    $SessionId = Get-SafeModelRouterSessionId -SessionId $SessionId
    $dir = Join-Path $HubRoot '.cache/model-router/sessions'
    $path = Join-Path $dir "$SessionId.json"
    if (Test-Path -LiteralPath $path) {
        try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
    }
    return [PSCustomObject]@{ sessionId = $SessionId; spentUsd = 0.0; calls = @() }
}

function Save-ModelRouterSession {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)]$Session
    )
    $safeId = Get-SafeModelRouterSessionId -SessionId ([string]$Session.sessionId)
    $dir = Join-Path $HubRoot '.cache/model-router/sessions'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Session | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $dir "$safeId.json") -Encoding UTF8
}

function Write-ModelRouterHealthEvent {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Status,
        [string]$Error = ''
    )
    $path = Join-Path $HubRoot 'ai-tracking/model-router-health.json'
    $events = @()
    if (Test-Path -LiteralPath $path) {
        try { $events = @((Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json).events) } catch {}
    }
    $events += [PSCustomObject]@{
        at = [DateTime]::UtcNow.ToString('o')
        model = $Model
        status = $Status
        error = $Error
    }
    if ($events.Count -gt 200) { $events = @($events | Select-Object -Last 200) }
    $models = [ordered]@{}
    foreach ($event in $events) {
        $eventAt = [string]$event.at
        try { $eventAt = [DateTimeOffset]::Parse([string]$event.at).ToUniversalTime().ToString('o') } catch {}
        $models[[string]$event.model] = [ordered]@{
            status = [string]$event.status
            checkedAt = $eventAt
            lastError = [string]$event.error
        }
    }
    [ordered]@{
        checkedAt = [DateTime]::UtcNow.ToString('o')
        models = $models
        events = $events
        note = 'Historical runtime health. Single failures degrade; they never permanently ban a model.'
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-OpenRouterKey {
    foreach ($scope in @('Process', 'User')) {
        $key = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', $scope)
        if ($key) { return $key }
    }
    throw 'OPENROUTER_API_KEY is not set in Process/User environment.'
}

function Invoke-ModelRouterChat {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)]$Route,
        [Parameter(Mandatory)][object[]]$Catalog,
        [double]$BudgetUsd = -1,
        [int]$MaxOutputTokens = 0,
        [string]$SessionId = 'default',
        [switch]$Sensitive,
        [string]$HubRoot = ''
    )
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    $session = Get-ModelRouterSession -HubRoot $root -SessionId $SessionId
    $key = Get-OpenRouterKey
    $errors = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($Route.fallbackModels)) {
        $ladder = Get-ModelRouterLadder -HubRoot $root
        $rankSpec = Get-ModelRouterRankSpec -Ladder $ladder -RankKey ([string]$Route.rank)
        $config = Get-ModelRouterConfig -RankSpec $rankSpec -Model ([string]$candidate)
        $record = Get-OpenRouterModelRecord -Catalog $Catalog -Model ([string]$candidate)
        if (-not $config -or -not $record) {
            Write-ModelRouterHealthEvent -HubRoot $root -Model ([string]$candidate) -Status 'catalog-missing' -Error 'not present in current catalog'
            continue
        }
        $effortResult = Resolve-ModelRouterEffort -ModelConfig $config -CatalogRecord $record -Requested ([string]$Route.effortRequested)
        $estimate = Get-ModelRouterCostEstimate -Prompt $Prompt -CatalogRecord $record -Effort $effortResult.selected -MaxOutputTokens $MaxOutputTokens
        $effectiveBudget = if ($BudgetUsd -ge 0) { $BudgetUsd } else { [double]$session.spentUsd + $estimate.autoCapUsd }
        $remaining = $effectiveBudget - [double]$session.spentUsd
        if (-not $estimate.reliable) {
            return [PSCustomObject]@{ ok = $false; code = 'budget_required'; error = 'Price cannot be estimated'; model = $candidate }
        }
        if ($estimate.worstUsd -gt $remaining) {
            $errors.Add([PSCustomObject]@{ model = $candidate; code = 'budget_cap'; worstUsd = $estimate.worstUsd; remainingUsd = $remaining })
            continue
        }
        $provider = [ordered]@{
            require_parameters = $true
            sort = 'price'
            data_collection = 'deny'
        }
        if ($Sensitive) { $provider.zdr = $true }
        if ($estimate.promptPerMillion -gt 0 -or $estimate.completionPerMillion -gt 0) {
            $provider.max_price = [ordered]@{
                prompt = [Math]::Round($estimate.promptPerMillion * 1.05, 6)
                completion = [Math]::Round($estimate.completionPerMillion * 1.05, 6)
            }
        }
        $body = [ordered]@{
            model = [string]$candidate
            messages = @(@{ role = 'user'; content = $Prompt })
            max_tokens = [int]$estimate.maxOutputTokens
            provider = $provider
        }
        $supportsReasoning = @($record.supported_parameters) -contains 'reasoning'
        if ($supportsReasoning) {
            $body.reasoning = [ordered]@{ effort = $effortResult.selected; exclude = $true }
        }
        $headers = @{
            Authorization = "Bearer $key"
            'HTTP-Referer' = 'https://cursor.local/hub'
            'X-OpenRouter-Title' = 'cursor-hub-model-router'
        }
        try {
            $response = Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/chat/completions' -Method Post `
                -Headers $headers -ContentType 'application/json; charset=utf-8' `
                -Body ($body | ConvertTo-Json -Compress -Depth 12) -TimeoutSec 180
            $text = ''
            if ($response.choices -and $response.choices.Count -gt 0) { $text = [string]$response.choices[0].message.content }
            $actual = 0.0
            if ($response.usage -and $response.usage.PSObject.Properties['cost']) {
                $actual = [double]$response.usage.cost
            }
            elseif ($response.usage) {
                $actual = ([double]$response.usage.prompt_tokens * ($estimate.promptPerMillion / 1000000)) +
                    ([double]$response.usage.completion_tokens * ($estimate.completionPerMillion / 1000000))
            }
            $calls = @($session.calls)
            $calls += [PSCustomObject]@{
                at = [DateTime]::UtcNow.ToString('o')
                rank = $Route.rank
                model = [string]$response.model
                effort = $effortResult.selected
                estimatedUsd = $estimate.expectedUsd
                actualUsd = $actual
            }
            $session = [PSCustomObject]@{
                sessionId = $SessionId
                spentUsd = [Math]::Round(([double]$session.spentUsd + $actual), 8)
                calls = $calls
            }
            Save-ModelRouterSession -HubRoot $root -Session $session
            Write-ModelRouterHealthEvent -HubRoot $root -Model ([string]$candidate) -Status 'live'
            return [PSCustomObject]@{
                ok = $true
                rank = $Route.rank
                requestedModel = $Route.model
                model = [string]$response.model
                effort = $effortResult.selected
                effortAdjusted = $effortResult.adjusted
                estimate = $estimate
                budgetUsd = $effectiveBudget
                sessionSpentUsd = $session.spentUsd
                budgetExceeded = ($session.spentUsd -gt $effectiveBudget)
                text = $text
                usage = $response.usage
                fallbackUsed = ([string]$candidate -ne [string]$Route.model)
            }
        }
        catch {
            $message = $_.Exception.Message
            $status = if ($message -match '404|not.?found') { 'unavailable' } else { 'degraded' }
            Write-ModelRouterHealthEvent -HubRoot $root -Model ([string]$candidate) -Status $status -Error $message
            $errors.Add([PSCustomObject]@{ model = $candidate; code = $status; error = $message })
            if ($message -match '401') { break }
        }
    }
    return [PSCustomObject]@{
        ok = $false
        code = 'fallback_exhausted'
        rank = $Route.rank
        requestedModel = $Route.model
        errors = [object[]]$errors
    }
}

Export-ModuleMember -Function @(
    'Get-ModelRouterHubRoot',
    'Get-ModelRouterLadder',
    'Resolve-ModelRouterRankKey',
    'Get-ModelRouterRankSpec',
    'Get-ModelRouterConfig',
    'Get-OpenRouterCatalog',
    'Get-OpenRouterModelRecord',
    'Get-RequestedEffort',
    'Resolve-ModelRouterEffort',
    'Select-ModelRouterModel',
    'Get-ModelRouterFallbacks',
    'Measure-ModelRouterInput',
    'Get-DefaultOutputCap',
    'Get-EffectiveModelPricing',
    'Get-ModelRouterCostEstimate',
    'Resolve-ModelRoute',
    'Get-ModelRouterSession',
    'Save-ModelRouterSession',
    'Write-ModelRouterHealthEvent',
    'Invoke-ModelRouterChat'
)

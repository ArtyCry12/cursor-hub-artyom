function Get-ModelRouterHubRoot {
    param([string]$HubRoot = '')
    if ($HubRoot) { return (Resolve-Path -LiteralPath $HubRoot).Path }
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
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

function Read-ModelRouterJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        $Default = $null
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $Default }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        if ($null -ne $Default) { return $Default }
        throw
    }
}

function Write-ModelRouterAtomicJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value,
        [int]$Depth = 20
    )
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ModelRouterLadder {
    param([string]$HubRoot = '')
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    $path = Join-Path $root 'ai-tracking/model-ladder.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "Model ladder not found: $path" }
    return (Read-ModelRouterJson -Path $path)
}

function Get-ModelRouterCandidatePolicy {
    param([string]$HubRoot = '')
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    return (Read-ModelRouterJson -Path (Join-Path $root 'lib/model-router/candidate-policy.json'))
}

function Get-ModelRouterAgentRegistry {
    param([string]$HubRoot = '')
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    return (Read-ModelRouterJson -Path (Join-Path $root 'lib/model-router/agent-profiles.json'))
}

function Resolve-ModelRouterRankToken {
    param([Parameter(Mandatory)][string]$Value)
    $normalized = $Value.Trim().ToLowerInvariant() -replace ',', '.'
    switch -Regex ($normalized) {
        '^(r|rank)?\s*1\.5$|^rank1_5$' { return 'rank1_5' }
        '^(r|rank)?\s*2$|^rank2$' { return 'rank2' }
        '^(r|rank)?\s*3$|^rank3$' { return 'rank3' }
    }
    return $null
}

function Resolve-ModelRouterAllowedRanks {
    param(
        [string]$Rank = '',
        [string]$Prompt = ''
    )
    $result = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Rank)) {
        $normalizedRank = [Regex]::Replace($Rank, '(?i)((?:r|rank)?\s*1),5', '$1.5')
        foreach ($part in @($normalizedRank -split '[,;/+\s]+')) {
            $key = Resolve-ModelRouterRankToken -Value $part
            if ($key -and -not $result.Contains($key)) { $result.Add($key) }
        }
    }
    if ($result.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Prompt)) {
        $matches = [Regex]::Matches(
            $Prompt,
            '(?i)(?<![0-9a-zа-я_])(?:r|rank)\s*(1[\.,]5|2|3)(?![0-9a-zа-я_])'
        )
        foreach ($match in $matches) {
            $key = Resolve-ModelRouterRankToken -Value ("R" + [string]$match.Groups[1].Value)
            if ($key -and -not $result.Contains($key)) { $result.Add($key) }
        }
    }
    return [string[]]$result
}

function Resolve-ModelRouterRankKey {
    param(
        [string]$Rank = '',
        [string]$Prompt = ''
    )
    $allowed = @(Resolve-ModelRouterAllowedRanks -Rank $Rank -Prompt $Prompt)
    if ($allowed.Count -gt 0) { return [string]$allowed[0] }
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
    $cachePath = Join-Path $root '.cache/model-router/catalog.json'
    if (-not $Refresh) {
        $cached = Read-ModelRouterJson -Path $cachePath
        if ($cached -and $cached.checkedAt -and $cached.data) {
            try {
                $age = ([DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse([string]$cached.checkedAt)).TotalMinutes
                if ($age -ge 0 -and $age -lt $MaxAgeMinutes) { return [object[]]$cached.data }
            }
            catch {}
        }
    }
    try {
        $response = Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/models' -Method Get -TimeoutSec 60
        if (-not $response.data) { throw 'OpenRouter model catalog returned no data' }
        Write-ModelRouterAtomicJson -Path $cachePath -Value ([ordered]@{
            checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
            data = [object[]]$response.data
        })
        return [object[]]$response.data
    }
    catch {
        $stale = Read-ModelRouterJson -Path $cachePath
        if ($stale -and $stale.data) { return [object[]]$stale.data }
        throw
    }
}

function Get-OpenRouterModelRecord {
    param(
        [Parameter(Mandatory)][object[]]$Catalog,
        [Parameter(Mandatory)][string]$Model
    )
    foreach ($record in $Catalog) {
        if ([string]$record.id -eq $Model) { return $record }
    }
    return $null
}

function Get-ModelRouterIntentPromptText {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Stage = ''
    )
    $normalized = ($Prompt + ' ' + $Stage).ToLowerInvariant()
    # Strip fenced blocks and severity taxonomy so meta-audits do not steer routing.
    $normalized = [Regex]::Replace($normalized, '(?s)```.*?```', ' ')
    $normalized = [Regex]::Replace($normalized, '(?i)severity\s*[:=]\s*(critical|high|medium|low|below-low|info)', ' ')
    $normalized = [Regex]::Replace($normalized, '(?i)\bsev(?:erity)?[-_:]?(critical|high|medium|low)\b', ' ')
    $normalized = [Regex]::Replace($normalized, '(?i)"severity"\s*:\s*"(critical|high|medium|low|below-low|info)"', ' ')
    $normalized = [Regex]::Replace($normalized, '(?i)\bid\s*=\s*[a-z0-9_-]*(critical|high|medium|low)[a-z0-9_-]*', ' ')
    return $normalized
}

function Get-ModelRouterIntent {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Stage = ''
    )
    $normalized = Get-ModelRouterIntentPromptText -Prompt $Prompt -Stage $Stage
    if ($normalized -match '(?<![\p{L}\p{N}_])(critical|maximum|критич[\p{L}]*|максимальн[\p{L}]*)(?![\p{L}\p{N}_])') {
        return 'critical'
    }
    if ($normalized -match '(?<![\p{L}\p{N}_])(adversarial|review|audit|critic|risk|аудит[\p{L}]*|ревью|риск[\p{L}]*|оспор[\p{L}]*)(?![\p{L}\p{N}_])') {
        return 'review'
    }
    if ($normalized -match '(?<![\p{L}\p{N}_])(architecture|architectural|архитектур[\p{L}]*|repository|репозитор[\p{L}]*)(?![\p{L}\p{N}_])') {
        return 'architecture'
    }
    if ($normalized -match '(?<![\p{L}\p{N}_])(batch|classification|classify|fast|массов[\p{L}]*|классификац[\p{L}]*|классифицир[\p{L}]*|быстр[\p{L}]*)(?![\p{L}\p{N}_])') {
        return 'batch'
    }
    if ($normalized -match '(?<![\p{L}\p{N}_])(image|video|multimodal|изображение|видео|мультимодальный)(?![\p{L}\p{N}_])') {
        return 'multimodal'
    }
    if ($normalized -match '(?<![\p{L}\p{N}_])(plan|planning|strategy|research|план[\p{L}]*|стратег[\p{L}]*|исследован[\p{L}]*)(?![\p{L}\p{N}_])') {
        return 'planning'
    }
    return 'general'
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
    $intent = Get-ModelRouterIntent -Prompt $Prompt
    switch ($intent) {
        'critical' { return 'max' }
        'review' { return 'high' }
        'architecture' { return 'high' }
        'planning' { return 'high' }
        'batch' { return 'low' }
        default {
            if ($Prompt -match '(?i)(?<![\p{L}\p{N}_])(critical|критичный|сложный|deep)(?![\p{L}\p{N}_])') {
                return 'high'
            }
            return 'medium'
        }
    }
}

function Get-ModelRouterReasoningMetadata {
    param(
        [Parameter(Mandatory)]$ModelConfig,
        $CatalogRecord
    )
    $reasoning = Get-ModelRouterPropertyValue $CatalogRecord 'reasoning'
    $supported = @()
    $mandatory = $false
    $defaultEnabled = $false
    $defaultEffort = ''
    $supportsMaxTokens = $false
    if ($reasoning) {
        $value = Get-ModelRouterPropertyValue $reasoning 'supported_efforts'
        if ($value) { $supported = @($value) }
        $value = Get-ModelRouterPropertyValue $reasoning 'mandatory'
        if ($null -ne $value) { $mandatory = [bool]$value }
        $value = Get-ModelRouterPropertyValue $reasoning 'default_enabled'
        if ($null -ne $value) { $defaultEnabled = [bool]$value }
        $value = Get-ModelRouterPropertyValue $reasoning 'default_effort'
        if ($value) { $defaultEffort = [string]$value }
        $value = Get-ModelRouterPropertyValue $reasoning 'supports_max_tokens'
        if ($null -ne $value) { $supportsMaxTokens = [bool]$value }
    }
    if ($supported.Count -eq 0) {
        $value = Get-ModelRouterPropertyValue $ModelConfig 'supportedEfforts'
        if ($value) { $supported = @($value) }
    }
    if (-not $reasoning) {
        $value = Get-ModelRouterPropertyValue $ModelConfig 'reasoningMandatory'
        if ($null -ne $value) { $mandatory = [bool]$value }
    }
    if (-not $defaultEffort) {
        $value = Get-ModelRouterPropertyValue $ModelConfig 'defaultEffort'
        if ($value) { $defaultEffort = [string]$value }
    }
    return [PSCustomObject]@{
        supportedEfforts = [string[]]$supported
        mandatory = $mandatory
        defaultEnabled = $defaultEnabled
        defaultEffort = $defaultEffort
        supportsMaxTokens = $supportsMaxTokens
    }
}

function Resolve-ModelRouterEffort {
    param(
        [Parameter(Mandatory)]$ModelConfig,
        $CatalogRecord,
        [string]$Requested = ''
    )
    $metadata = Get-ModelRouterReasoningMetadata -ModelConfig $ModelConfig -CatalogRecord $CatalogRecord
    $fixed = Get-ModelRouterPropertyValue $ModelConfig 'fixedEffort'
    if ($fixed) {
        return [PSCustomObject]@{
            requested = $Requested
            selected = [string]$fixed
            adjusted = ([string]$fixed -ne $Requested)
            reason = 'fixed-model-policy'
            metadata = $metadata
        }
    }
    if (-not $Requested) {
        $Requested = if ($metadata.defaultEffort) { $metadata.defaultEffort } else { 'medium' }
    }
    $supported = @($metadata.supportedEfforts)
    if ($supported.Count -eq 0) {
        $selected = if ($metadata.mandatory) { 'medium' } else { 'none' }
        return [PSCustomObject]@{
            requested = $Requested
            selected = $selected
            adjusted = ($selected -ne $Requested)
            reason = 'reasoning-metadata-missing'
            metadata = $metadata
        }
    }
    if ($metadata.mandatory) { $supported = @($supported | Where-Object { $_ -ne 'none' }) }
    if ($supported -contains $Requested) {
        return [PSCustomObject]@{
            requested = $Requested
            selected = $Requested
            adjusted = $false
            reason = 'exact'
            metadata = $metadata
        }
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
    return [PSCustomObject]@{
        requested = $Requested
        selected = $best
        adjusted = $true
        reason = 'nearest-supported'
        metadata = $metadata
    }
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
    $intent = Get-ModelRouterIntent -Prompt $Prompt
    if ($RankKey -eq 'rank1_5') {
        switch ($intent) {
            'review' { return 'x-ai/grok-4.6' }
            'architecture' { return 'qwen/qwen3.8-max-0902' }
            'planning' { return 'z-ai/glm-5.3' }
            default {
                if ($Prompt -match '(?i)(?<![\p{L}\p{N}_])(creative|synthesis|варианты|синтез|обобщение)(?![\p{L}\p{N}_])') {
                    return 'meta/muse-spark-1.3'
                }
                return 'z-ai/glm-5.3'
            }
        }
    }
    if ($RankKey -eq 'rank2') {
        if ($Prompt -match '(?i)(?<![\p{L}\p{N}_])(critical|best|maximum|критичный|лучший|максимальный)(?![\p{L}\p{N}_])') {
            return 'openai/gpt-5.6-luna-pro'
        }
        switch ($intent) {
            'batch' { return 'deepseek/deepseek-v4-flash-0731' }
            'multimodal' { return 'google/gemini-3.8-flash' }
            'review' { return 'deepseek/deepseek-v4-pro-0813' }
            default { return 'z-ai/glm-5.2' }
        }
    }
    $order = Get-ModelRouterPropertyValue $RankSpec 'textOrder'
    if ($order -and @($order).Count -gt 0) { return [string]@($order)[0] }
    return $null
}

function Get-ModelRouterFallbacks {
    param(
        [Parameter(Mandatory)]$RankSpec,
        [Parameter(Mandatory)][string]$Selected
    )
    $result = New-Object System.Collections.Generic.List[string]
    if ($Selected) { $result.Add($Selected) }
    $orderValue = Get-ModelRouterPropertyValue $RankSpec 'chatOrder'
    if (-not $orderValue) { $orderValue = Get-ModelRouterPropertyValue $RankSpec 'textOrder' }
    foreach ($model in @($orderValue)) {
        if ($result.Contains([string]$model)) { continue }
        $config = Get-ModelRouterConfig -RankSpec $RankSpec -Model ([string]$model)
        if (-not $config -or @('banned', 'dead') -contains [string]$config.status) { continue }
        $result.Add([string]$model)
    }
    return [string[]]$result
}

function Measure-ModelRouterInput {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [int]$ExactTokens = 0,
        [string]$Model = '',
        [string]$HubRoot = '',
        [string]$StateRoot = ''
    )
    if ($ExactTokens -gt 0) {
        return [PSCustomObject]@{
            tokens = $ExactTokens
            baseTokens = $ExactTokens
            exact = $true
            method = 'provided'
            uncertainty = 0.0
            calibrationMultiplier = 1.0
        }
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetByteCount($Prompt)
    $characterEstimate = [Math]::Ceiling($Prompt.Length / 2.5)
    $byteEstimate = [Math]::Ceiling(($bytes / 3.2) * 1.25)
    $baseTokens = [Math]::Max(1, [Math]::Max($characterEstimate, $byteEstimate))
    $multiplier = Get-ModelRouterCalibrationMultiplier -Model $Model -HubRoot $HubRoot -StateRoot $StateRoot
    $tokens = [Math]::Ceiling($baseTokens * $multiplier)
    return [PSCustomObject]@{
        tokens = [int]$tokens
        baseTokens = [int]$baseTokens
        exact = $false
        method = 'utf8-byte-conservative+model-p95'
        uncertainty = 0.25
        calibrationMultiplier = $multiplier
    }
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

function Get-EffectiveModelPricing {
    param(
        [Parameter(Mandatory)]$CatalogRecord,
        [Parameter(Mandatory)][int]$InputTokens,
        [double]$ThresholdSafetyFactor = 1.25
    )
    $pricingRecord = Get-ModelRouterPropertyValue $CatalogRecord 'pricing'
    $promptRaw = Get-ModelRouterPropertyValue $pricingRecord 'prompt'
    $completionRaw = Get-ModelRouterPropertyValue $pricingRecord 'completion'
    $result = [ordered]@{
        prompt = ConvertTo-Price $promptRaw
        completion = ConvertTo-Price $completionRaw
        request = ConvertTo-Price (Get-ModelRouterPropertyValue $pricingRecord 'request')
        internal_reasoning = ConvertTo-Price (Get-ModelRouterPropertyValue $pricingRecord 'internal_reasoning')
        input_cache_read = ConvertTo-Price (Get-ModelRouterPropertyValue $pricingRecord 'input_cache_read')
        input_cache_write = ConvertTo-Price (Get-ModelRouterPropertyValue $pricingRecord 'input_cache_write')
        known = ($null -ne $promptRaw -and $null -ne $completionRaw)
        overrideApplied = $false
    }
    $overrides = Get-ModelRouterPropertyValue $pricingRecord 'overrides'
    foreach ($override in @($overrides)) {
        $minimum = 0
        $value = Get-ModelRouterPropertyValue $override 'min_prompt_tokens'
        if ($value) { $minimum = [int]$value }
        if (($InputTokens * $ThresholdSafetyFactor) -lt $minimum) { continue }
        foreach ($name in @('prompt', 'completion', 'request', 'internal_reasoning', 'input_cache_read', 'input_cache_write')) {
            $value = Get-ModelRouterPropertyValue $override $name
            if ($null -ne $value) { $result[$name] = ConvertTo-Price $value }
        }
        $result.overrideApplied = $true
    }
    return [PSCustomObject]$result
}

function Get-ModelRouterCostEstimate {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)]$CatalogRecord,
        [Parameter(Mandatory)][string]$Effort,
        [int]$MaxOutputTokens = 0,
        [int]$InputTokens = 0,
        [int]$CachedInputTokens = 0,
        [int]$CacheWriteTokens = 0,
        [string]$Model = '',
        [string]$HubRoot = '',
        [string]$StateRoot = ''
    )
    $input = Measure-ModelRouterInput -Prompt $Prompt -ExactTokens $InputTokens -Model $Model `
        -HubRoot $HubRoot -StateRoot $StateRoot
    if ($MaxOutputTokens -le 0) { $MaxOutputTokens = Get-DefaultOutputCap -Effort $Effort }
    $pricing = Get-EffectiveModelPricing -CatalogRecord $CatalogRecord -InputTokens $input.tokens
    $ratios = @{ none = 0.0; minimal = 0.1; low = 0.2; medium = 0.5; high = 0.8; xhigh = 0.95; max = 0.95 }
    $ratio = if ($ratios.ContainsKey($Effort)) { [double]$ratios[$Effort] } else { 0.5 }
    $expectedCompletion = [Math]::Max(1, [Math]::Ceiling($MaxOutputTokens * 0.35))
    $expectedReasoning = [Math]::Ceiling($expectedCompletion * $ratio)
    $worstReasoning = [Math]::Ceiling($MaxOutputTokens * $ratio)
    $expectedVisible = [Math]::Max(0, $expectedCompletion - $expectedReasoning)
    $worstVisible = [Math]::Max(0, $MaxOutputTokens - $worstReasoning)
    $reasoningRate = if ($pricing.internal_reasoning -gt 0) { $pricing.internal_reasoning } else { $pricing.completion }
    $billablePrompt = [Math]::Max(0, $input.tokens - $CachedInputTokens)
    $expected = ($billablePrompt * $pricing.prompt) +
        ($CachedInputTokens * $pricing.input_cache_read) +
        ($CacheWriteTokens * $pricing.input_cache_write) +
        ($expectedVisible * $pricing.completion) +
        ($expectedReasoning * $reasoningRate) +
        $pricing.request
    $worst = ($billablePrompt * $pricing.prompt) +
        ($CachedInputTokens * $pricing.input_cache_read) +
        ($CacheWriteTokens * $pricing.input_cache_write) +
        ($worstVisible * $pricing.completion) +
        ($worstReasoning * $reasoningRate) +
        $pricing.request
    $margin = switch ($Effort) {
        'max' { 2.25 }
        'xhigh' { 2.0 }
        'high' { 1.85 }
        'medium' { 1.5 }
        default { 1.35 }
    }
    $autoCap = if ($worst -le 0) { 0.0 } else { [Math]::Ceiling($worst * $margin * 10000) / 10000 }
    return [PSCustomObject]@{
        inputTokens = $input.tokens
        inputBaseTokens = $input.baseTokens
        inputExact = $input.exact
        inputMethod = $input.method
        inputUncertainty = $input.uncertainty
        calibrationMultiplier = $input.calibrationMultiplier
        cachedInputTokens = $CachedInputTokens
        cacheWriteTokens = $CacheWriteTokens
        maxOutputTokens = $MaxOutputTokens
        reasoningTokensExpected = $expectedReasoning
        reasoningTokensWorst = $worstReasoning
        reasoningFloorApplied = $false
        expectedUsd = [Math]::Round($expected, 8)
        worstUsd = [Math]::Round($worst, 8)
        autoCapUsd = $autoCap
        reliable = [bool]$pricing.known
        overrideApplied = $pricing.overrideApplied
        promptPerMillion = [Math]::Round($pricing.prompt * 1000000, 6)
        completionPerMillion = [Math]::Round($pricing.completion * 1000000, 6)
        reasoningPerMillion = [Math]::Round($reasoningRate * 1000000, 6)
        cacheReadPerMillion = [Math]::Round($pricing.input_cache_read * 1000000, 6)
        cacheWritePerMillion = [Math]::Round($pricing.input_cache_write * 1000000, 6)
    }
}

function Get-ModelRouterAgentProfile {
    param(
        [string]$ProfileId = '',
        [string]$HubRoot = ''
    )
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    $registry = Get-ModelRouterAgentRegistry -HubRoot $root
    if (-not $ProfileId) { $ProfileId = [string]$registry.defaultProfile }
    if ($ProfileId -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw "Invalid model worker profile: $ProfileId" }
    $property = $registry.profiles.PSObject.Properties[$ProfileId]
    if (-not $property) { throw "Unknown model worker profile: $ProfileId" }
    $config = $property.Value
    $parts = New-Object System.Collections.Generic.List[string]
    $system = Get-ModelRouterPropertyValue $config 'system'
    if ($system) { $parts.Add([string]$system) }
    $paths = New-Object System.Collections.Generic.List[string]
    $agentFile = Get-ModelRouterPropertyValue $config 'agentFile'
    if ($agentFile) { $paths.Add([string]$agentFile) }
    foreach ($skill in @((Get-ModelRouterPropertyValue $config 'skills'))) {
        if ($skill) { $paths.Add([string]$skill) }
    }
    $maxChars = [int]$registry.maxContextChars
    foreach ($relativePath in $paths) {
        if ($relativePath -match '(^|[\\/])\.\.([\\/]|$)') { throw "Unsafe profile path: $relativePath" }
        $fullPath = [IO.Path]::GetFullPath((Join-Path $root $relativePath))
        if (-not $fullPath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Profile path escaped hub root: $relativePath"
        }
        if (-not (Test-Path -LiteralPath $fullPath)) { throw "Profile source missing: $relativePath" }
        $text = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
        $currentLength = ($parts -join "`n`n").Length
        $remaining = $maxChars - $currentLength
        if ($remaining -le 0) { break }
        if ($text.Length -gt $remaining) { $text = $text.Substring(0, $remaining) }
        $parts.Add("SOURCE: $relativePath`n$text")
    }
    return [PSCustomObject]@{
        id = $ProfileId
        label = [string]$config.label
        qualityFloor = [double]$config.qualityFloor
        roles = [string[]]@($config.roles)
        systemPrompt = $parts -join "`n`n"
        sources = [string[]]$paths
    }
}

function Get-ModelRouterRoleTargets {
    param(
        [Parameter(Mandatory)][string]$Intent,
        [Parameter(Mandatory)]$Policy
    )
    $property = $Policy.roleAliases.PSObject.Properties[$Intent]
    if ($property) { return [string[]]@($property.Value) }
    return [string[]]@('general-worker', 'mid-strong')
}

function Get-ModelRouterOpenRouterCandidates {
    param(
        [Parameter(Mandatory)][string[]]$AllowedRanks,
        [Parameter(Mandatory)]$Ladder,
        [Parameter(Mandatory)][object[]]$Catalog,
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$RequestedEffort,
        [string]$HubRoot = ''
    )
    $intent = Get-ModelRouterIntent -Prompt $Prompt
    $roleTargets = Get-ModelRouterRoleTargets -Intent $intent -Policy $Policy
    $weights = $Policy.weights
    $candidates = New-Object System.Collections.Generic.List[object]
    $rejected = New-Object System.Collections.Generic.List[object]
    foreach ($rankKey in $AllowedRanks) {
        $rankSpec = Get-ModelRouterRankSpec -Ladder $Ladder -RankKey $rankKey
        $modelNames = @()
        if ($rankKey -eq 'rank3') {
            Ensure-ModelRouterR3Allowlist -HubRoot $HubRoot -Catalog $Catalog | Out-Null
            $modelNames = @(Get-ModelRouterVerifiedR3Models -HubRoot $HubRoot)
        }
        else {
            $modelNames = @($rankSpec.models.PSObject.Properties.Name)
        }
        foreach ($model in $modelNames) {
            $config = Get-ModelRouterConfig -RankSpec $rankSpec -Model ([string]$model)
            if (-not $config -and $rankKey -eq 'rank3') {
                $config = [PSCustomObject]@{
                    role = 'general-worker'
                    modality = @('text')
                    supportedEfforts = @('none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max')
                    defaultEffort = 'medium'
                }
            }
            if (-not $config -or @($config.modality) -notcontains 'text') {
                $rejected.Add([PSCustomObject]@{ target = 'openrouter-worker'; rank = $rankKey; model = [string]$model; reason = 'text-capability' })
                continue
            }
            $record = Get-OpenRouterModelRecord -Catalog $Catalog -Model ([string]$model)
            if (-not $record) {
                $rejected.Add([PSCustomObject]@{ target = 'openrouter-worker'; rank = $rankKey; model = [string]$model; reason = 'catalog-missing' })
                continue
            }
            if ($intent -eq 'batch' -and [string]$model -eq 'openai/gpt-5.6-luna-pro') {
                $rejected.Add([PSCustomObject]@{ target = 'openrouter-worker'; rank = $rankKey; model = [string]$model; reason = 'batch-cost-gate' })
                continue
            }
            if ($intent -eq 'multimodal' -and [string]$config.role -ne 'multimodal-fast') {
                $rejected.Add([PSCustomObject]@{ target = 'openrouter-worker'; rank = $rankKey; model = [string]$model; reason = 'multimodal-capability' })
                continue
            }
            $health = Get-ModelRouterModelHealth -Model ([string]$model) -HubRoot $HubRoot
            if ($health.circuit -eq 'open' -and -not $health.retryEligible) {
                $rejected.Add([PSCustomObject]@{ target = 'openrouter-worker'; rank = $rankKey; model = [string]$model; reason = 'circuit-open' })
                continue
            }
            $modelPolicyProperty = $Policy.openrouter.PSObject.Properties[[string]$model]
            $quality = if ($modelPolicyProperty) { [double]$modelPolicyProperty.Value.quality } else { 0.7 }
            $latency = if ($modelPolicyProperty) { [double]$modelPolicyProperty.Value.latency } else { 0.7 }
            if ($quality -lt [double]$Profile.qualityFloor) {
                $rejected.Add([PSCustomObject]@{ target = 'openrouter-worker'; rank = $rankKey; model = [string]$model; reason = 'quality-floor' })
                continue
            }
            $role = [string]$config.role
            $roleScore = if ($roleTargets -contains $role) {
                1.0
            }
            elseif (@($Profile.roles).Count -gt 0 -and @($Profile.roles) -notcontains $role) {
                0.15
            }
            else {
                0.35
            }
            $healthScore = switch ([string]$health.status) {
                'live' { 1.0 }
                'unknown' { 0.7 }
                'degraded' { 0.35 }
                default { 0.1 }
            }
            if ($health.circuit -eq 'half-open') { $healthScore = [Math]::Min($healthScore, 0.25) }
            $effort = Resolve-ModelRouterEffort -ModelConfig $config -CatalogRecord $record -Requested $RequestedEffort
            $supportedParameters = @((Get-ModelRouterPropertyValue $record 'supported_parameters'))
            if ($effort.metadata.mandatory -and
                $supportedParameters -notcontains 'reasoning' -and
                $supportedParameters -notcontains 'reasoning_effort') {
                $rejected.Add([PSCustomObject]@{ target = 'openrouter-worker'; rank = $rankKey; model = [string]$model; reason = 'mandatory-reasoning-unsupported' })
                continue
            }
            $estimate = Get-ModelRouterCostEstimate -Prompt ($Profile.systemPrompt + "`n" + $Prompt) `
                -CatalogRecord $record -Effort $effort.selected -Model ([string]$model) -HubRoot $HubRoot
            $costScore = if (-not $estimate.reliable) { 0.0 } else { 1.0 / (1.0 + ($estimate.expectedUsd * 200.0)) }
            $score = ($quality * [double]$weights.quality) +
                ($roleScore * [double]$weights.role) +
                ($healthScore * [double]$weights.health) +
                ($latency * [double]$weights.latency) +
                ($costScore * [double]$weights.cost)
            $candidates.Add([PSCustomObject]@{
                target = 'openrouter-worker'
                rank = $rankKey
                model = [string]$model
                role = $role
                quality = $quality
                roleScore = $roleScore
                health = [string]$health.status
                circuit = [string]$health.circuit
                latency = $latency
                effort = $effort.selected
                effortRequested = $effort.requested
                effortAdjusted = $effort.adjusted
                reasoningMetadata = $effort.metadata
                estimate = $estimate
                score = [Math]::Round($score, 6)
            })
        }
    }
    return [PSCustomObject]@{
        eligible = [object[]]$candidates
        rejected = [object[]]$rejected
    }
}

function Get-ModelRouterCursorCandidates {
    param(
        [Parameter(Mandatory)]$Ladder,
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$CursorAvailable = $true
    )
    if (-not $CursorAvailable) { return [object[]]@() }
    $intent = Get-ModelRouterIntent -Prompt $Prompt
    $roleTargets = Get-ModelRouterRoleTargets -Intent $intent -Policy $Policy
    $weights = $Policy.weights
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($property in $Policy.cursor.PSObject.Properties) {
        $model = [string]$property.Name
        $config = $property.Value
        $quality = [double]$config.quality
        if ($quality -lt [double]$Profile.qualityFloor) { continue }
        $roles = @($config.roles)
        $roleScore = if (@($roleTargets | Where-Object { $roles -contains $_ }).Count -gt 0) { 1.0 } else { 0.35 }
        $score = ($quality * [double]$weights.quality) +
            ($roleScore * [double]$weights.role) +
            (1.0 * [double]$weights.health) +
            ([double]$config.latency * [double]$weights.latency) +
            (0.5 * [double]$weights.cost)
        $result.Add([PSCustomObject]@{
            target = 'cursor-native'
            rank = 'cursor'
            model = $model
            role = [string]$roles[0]
            quality = $quality
            roleScore = $roleScore
            health = 'live'
            circuit = 'closed'
            latency = [double]$config.latency
            effort = $null
            effortRequested = $null
            effortAdjusted = $false
            reasoningMetadata = $null
            estimate = $null
            score = [Math]::Round($score, 6)
        })
    }
    return [object[]]$result
}

function Resolve-GlobalModelRoute {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Rank = '',
        [string]$ProfileId = '',
        [string]$Stage = '',
        [string]$Effort = '',
        [bool]$CursorAvailable = $true,
        [bool]$RequiresCursorTools = $false,
        [switch]$OpenRouterOnly,
        [string]$HubRoot = '',
        [object[]]$Catalog
    )
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    $ladder = Get-ModelRouterLadder -HubRoot $root
    $policy = Get-ModelRouterCandidatePolicy -HubRoot $root
    $profile = Get-ModelRouterAgentProfile -ProfileId $ProfileId -HubRoot $root
    if (-not $Catalog) { $Catalog = @(Get-OpenRouterCatalog -HubRoot $root) }
    $explicitRanks = @(Resolve-ModelRouterAllowedRanks -Rank $Rank -Prompt $Prompt)
    [string[]]$allowedRanks = if ($explicitRanks.Count -gt 0) {
        [string[]]$explicitRanks
    }
    else {
        [string[]]@('rank1_5', 'rank2', 'rank3')
    }
    if ($RequiresCursorTools) {
        if (-not $CursorAvailable) {
            return [PSCustomObject]@{
                ok = $false
                code = 'cursor_tools_unavailable'
                allowedRanks = [string[]]$allowedRanks
                explicitRanks = ($explicitRanks.Count -gt 0)
                profile = $profile
                candidates = [object[]]@()
                rejected = [object[]]@()
            }
        }
        return [PSCustomObject]@{
            ok = $true
            target = 'cursor-parent'
            rank = 'cursor'
            model = $null
            role = 'tool-execution'
            effort = $null
            allowedRanks = [string[]]$allowedRanks
            explicitRanks = ($explicitRanks.Count -gt 0)
            profile = $profile
            selected = [PSCustomObject]@{
                target = 'cursor-parent'
                rank = 'cursor'
                model = $null
                role = 'tool-execution'
                score = 100.0
            }
            candidates = [object[]]@()
            rejected = [object[]]@()
            explanation = 'Cursor tools are required; OpenRouter workers may only provide a separate reasoning stage.'
        }
    }
    $requestedEffort = Get-RequestedEffort -Prompt ($Prompt + ' ' + $Stage) -Requested $Effort
    $candidates = New-Object System.Collections.Generic.List[object]
    $rejected = New-Object System.Collections.Generic.List[object]
    $openRouterResult = Get-ModelRouterOpenRouterCandidates -AllowedRanks $allowedRanks -Ladder $ladder -Catalog $Catalog `
        -Policy $policy -Profile $profile -Prompt ($Prompt + ' ' + $Stage) -RequestedEffort $requestedEffort -HubRoot $root
    foreach ($candidate in @($openRouterResult.eligible)) {
        $candidates.Add($candidate)
    }
    foreach ($candidate in @($openRouterResult.rejected)) { $rejected.Add($candidate) }
    if (-not $OpenRouterOnly -and $explicitRanks.Count -eq 0) {
        foreach ($candidate in @(Get-ModelRouterCursorCandidates -Ladder $ladder -Policy $policy -Profile $profile `
            -Prompt ($Prompt + ' ' + $Stage) -CursorAvailable:$CursorAvailable)) {
            $candidates.Add($candidate)
        }
    }
    $ordered = @($candidates | Sort-Object -Property @{ Expression = 'score'; Descending = $true }, @{ Expression = 'quality'; Descending = $true })
    if ($ordered.Count -eq 0) {
        $code = if ($allowedRanks -contains 'rank3' -and $allowedRanks.Count -eq 1) { 'r3_text_unavailable' } else { 'no_eligible_model' }
        return [PSCustomObject]@{
            ok = $false
            code = $code
            allowedRanks = [string[]]$allowedRanks
            explicitRanks = ($explicitRanks.Count -gt 0)
            profile = $profile
            candidates = [object[]]@()
            rejected = [object[]]$rejected
        }
    }
    return [PSCustomObject]@{
        ok = $true
        target = [string]$ordered[0].target
        rank = [string]$ordered[0].rank
        model = [string]$ordered[0].model
        role = [string]$ordered[0].role
        effort = $ordered[0].effort
        allowedRanks = [string[]]$allowedRanks
        explicitRanks = ($explicitRanks.Count -gt 0)
        profile = $profile
        selected = $ordered[0]
        candidates = [object[]]$ordered
        rejected = [object[]]$rejected
        explanation = "quality-floor=$($profile.qualityFloor); intent=$(Get-ModelRouterIntent -Prompt ($Prompt + ' ' + $Stage)); score=$($ordered[0].score)"
    }
}

function Resolve-ModelRoute {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Rank = '',
        [string]$Model = '',
        [string]$Effort = '',
        [string]$ProfileId = '',
        [string]$HubRoot = '',
        [object[]]$Catalog
    )
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    if (-not $Catalog) { $Catalog = @(Get-OpenRouterCatalog -HubRoot $root) }
    if ($Model) {
        $ladder = Get-ModelRouterLadder -HubRoot $root
        $allowed = @(Resolve-ModelRouterAllowedRanks -Rank $Rank -Prompt $Prompt)
        if ($allowed.Count -eq 0) { $allowed = @('rank1_5', 'rank2', 'rank3') }
        $rankKey = $null
        $config = $null
        foreach ($candidateRank in $allowed) {
            $rankSpec = Get-ModelRouterRankSpec -Ladder $ladder -RankKey $candidateRank
            $candidateConfig = Get-ModelRouterConfig -RankSpec $rankSpec -Model $Model
            if ($candidateConfig) {
                $rankKey = $candidateRank
                $config = $candidateConfig
                break
            }
        }
        if (-not $config) { throw "Model $Model is not registered in the allowed ranks" }
        $record = Get-OpenRouterModelRecord -Catalog $Catalog -Model $Model
        if (-not $record) { throw "Model $Model is not present in the OpenRouter catalog" }
        $requested = Get-RequestedEffort -Prompt $Prompt -Requested $Effort
        $effortResult = Resolve-ModelRouterEffort -ModelConfig $config -CatalogRecord $record -Requested $requested
        return [PSCustomObject]@{
            ok = $true
            rank = $rankKey
            allowedRanks = [string[]]$allowed
            preferredModel = $Model
            model = $Model
            selectionAdjusted = $false
            role = [string]$config.role
            effort = $effortResult.selected
            effortRequested = $effortResult.requested
            effortAdjusted = $effortResult.adjusted
            effortReason = $effortResult.reason
            reasoningMandatory = [bool]$effortResult.metadata.mandatory
            reasoningMetadata = $effortResult.metadata
            fallbackModels = [string[]]@($Model)
            fallbackCandidates = [object[]]@()
            profile = Get-ModelRouterAgentProfile -ProfileId $ProfileId -HubRoot $root
        }
    }
    $global = Resolve-GlobalModelRoute -Prompt $Prompt -Rank $Rank -ProfileId $ProfileId -Effort $Effort `
        -OpenRouterOnly -HubRoot $root -Catalog $Catalog
    if (-not $global.ok) { throw $global.code }
    $fallbackCandidates = @($global.candidates | Where-Object { $_.target -eq 'openrouter-worker' })
    $selected = $fallbackCandidates[0]
    return [PSCustomObject]@{
        ok = $true
        rank = [string]$selected.rank
        allowedRanks = [string[]]$global.allowedRanks
        preferredModel = [string]$selected.model
        model = [string]$selected.model
        selectionAdjusted = $false
        role = [string]$selected.role
        effort = [string]$selected.effort
        effortRequested = [string]$selected.effortRequested
        effortAdjusted = [bool]$selected.effortAdjusted
        effortReason = if ($selected.effortAdjusted) { 'nearest-supported' } else { 'exact' }
        reasoningMandatory = [bool]$selected.reasoningMetadata.mandatory
        reasoningMetadata = $selected.reasoningMetadata
        fallbackModels = [string[]]@($fallbackCandidates.model)
        fallbackCandidates = [object[]]$fallbackCandidates
        profile = $global.profile
        explanation = $global.explanation
    }
}

param([string]$HubRoot = '')

$ErrorActionPreference = 'Stop'
if (-not $HubRoot) { $HubRoot = Split-Path $PSScriptRoot -Parent }
$temporaryState = Join-Path ([IO.Path]::GetTempPath()) ("model-router-contract-" + [Guid]::NewGuid().ToString('N'))
$previousStateRoot = $env:MODEL_ROUTER_STATE_ROOT
$env:MODEL_ROUTER_STATE_ROOT = $temporaryState
New-Item -ItemType Directory -Path $temporaryState -Force | Out-Null

Import-Module (Join-Path $HubRoot 'lib/model-router/ModelRouter.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message (actual=$Actual expected=$Expected)" }
}

function Assert-True {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw $Message }
}

function New-CatalogRecord {
    param(
        [string]$Id,
        [string[]]$Efforts,
        [double]$PromptPrice = 0.000001,
        [double]$CompletionPrice = 0.000003,
        [object[]]$Overrides = @(),
        [bool]$Mandatory = $false,
        [bool]$SupportsMaxTokens = $false,
        [string[]]$Parameters = @('reasoning', 'max_tokens', 'response_format', 'structured_outputs', 'temperature')
    )
    return [PSCustomObject]@{
        id = $Id
        supported_parameters = $Parameters
        architecture = [PSCustomObject]@{
            input_modalities = @('text')
            output_modalities = @('text')
        }
        reasoning = [PSCustomObject]@{
            supported_efforts = $Efforts
            mandatory = $Mandatory
            default_enabled = $Mandatory
            default_effort = if ($Efforts.Count -gt 0) { $Efforts[0] } else { $null }
            supports_max_tokens = $SupportsMaxTokens
        }
        pricing = [PSCustomObject]@{
            prompt = [string]$PromptPrice
            completion = [string]$CompletionPrice
            request = '0.00001'
            internal_reasoning = $null
            input_cache_read = '0.0000001'
            input_cache_write = '0.0000012'
            overrides = $Overrides
        }
    }
}

$catalog = @(
    (New-CatalogRecord 'z-ai/glm-5.3' @('max', 'high', 'low') -Mandatory $true),
    (New-CatalogRecord 'x-ai/grok-4.6' @('xhigh', 'high', 'medium', 'low') -Mandatory $true),
    (New-CatalogRecord 'qwen/qwen3.8-max-0902' @('xhigh', 'high', 'medium', 'low', 'minimal') -Mandatory $true),
    (New-CatalogRecord 'meta/muse-spark-1.2' @('xhigh', 'high', 'medium', 'low', 'minimal') -Mandatory $true),
    (New-CatalogRecord 'openai/gpt-5.6-luna-pro' @('max', 'xhigh', 'high', 'medium', 'low', 'none') 0.0000002 0.0000012 @(
        [PSCustomObject]@{ min_prompt_tokens = 272000; prompt = '0.0000004'; completion = '0.0000018' }
    )),
    (New-CatalogRecord 'z-ai/glm-5.2' @('xhigh', 'high')),
    (New-CatalogRecord 'deepseek/deepseek-v4-pro-0813' @('max', 'high', 'low')),
    (New-CatalogRecord 'deepseek/deepseek-v4-flash-0731' @('max', 'high', 'low')),
    (New-CatalogRecord 'z-ai/glm-5.3-flash' @('max', 'high', 'low') -Mandatory $true),
    (New-CatalogRecord 'google/gemini-3.8-flash' @('high', 'medium', 'low') -Mandatory $true),
    (New-CatalogRecord 'test/free:free' @()),
    [PSCustomObject]@{
        id = 'test/unpriced'
        supported_parameters = @()
        architecture = [PSCustomObject]@{ input_modalities = @('text'); output_modalities = @('text') }
        pricing = [PSCustomObject]@{}
    }
)

try {
    Assert-Equal (Resolve-ModelRouterRankKey -Prompt 'используй R1.5 для плана') 'rank1_5' 'R1.5 parsing failed'
    Assert-Equal (Resolve-ModelRouterRankKey -Prompt 'запусти r2') 'rank2' 'R2 parsing failed'
    Assert-Equal (Resolve-ModelRouterRankKey -Prompt 'черновик через R3') 'rank3' 'R3 parsing failed'
    Assert-Equal (@(Resolve-ModelRouterAllowedRanks -Prompt 'R1.5, R2').Count) 2 'Mixed rank count failed'
    Assert-Equal ((Resolve-ModelRouterAllowedRanks -Prompt 'R2, R1.5') -join ',') 'rank2,rank1_5' 'Mixed rank order failed'

    Assert-Equal (Get-ModelRouterIntent -Prompt 'critical path analysis') 'critical' 'critical collided with critic'
    Assert-Equal (Get-ModelRouterIntent -Prompt 'adversarial critic review') 'review' 'Review intent failed'
    Assert-Equal (Get-ModelRouterIntent -Prompt 'спланируй архитектуру репозитория') 'architecture' 'RU architecture intent failed'
    Assert-Equal (Get-ModelRouterIntent -Prompt 'fast batch classification') 'batch' 'Batch intent failed'

    foreach ($record in $catalog | Where-Object { $_.id -notlike 'test/*' }) {
        Write-ModelRouterHealthEvent -HubRoot $HubRoot -Model $record.id -Status 'live' -Category 'success'
    }
    Write-ModelRouterHealthEvent -HubRoot $HubRoot -Model 'qwen/qwen3.8-max-0902' -Status 'unavailable' -Category 'not-found'

    $architecture = Resolve-ModelRoute -Prompt 'R1.5: plan the repository architecture' -Catalog $catalog -HubRoot $HubRoot
    Assert-Equal $architecture.model 'z-ai/glm-5.3' 'Architecture fallback did not use the healthy planning model'
    Assert-Equal $architecture.fallbackModels[0] 'z-ai/glm-5.3' 'Selected candidate must lead fallback order'

    $review = Resolve-ModelRoute -Prompt 'R1.5 adversarial audit risks' -Catalog $catalog -HubRoot $HubRoot
    Assert-Equal $review.model 'x-ai/grok-4.6' 'R1.5 review route failed'

    $general = Resolve-ModelRoute -Prompt 'R2 perform general analysis' -Catalog $catalog -HubRoot $HubRoot
    Assert-Equal $general.model 'deepseek/deepseek-v4-pro-0813' 'R2 quality scorer route failed'
    $glm52 = Resolve-ModelRoute -Prompt 'R2 medium' -Model 'z-ai/glm-5.2' -Catalog $catalog -HubRoot $HubRoot
    Assert-Equal $glm52.effort 'high' 'GLM 5.2 effort normalization failed'

    $fast = Resolve-ModelRoute -Prompt 'R2 fast batch classification' -Catalog $catalog -HubRoot $HubRoot
    Assert-Equal $fast.model 'deepseek/deepseek-v4-flash-0731' 'R2 batch route failed'
    Assert-Equal $fast.effort 'low' 'Batch effort failed'

    $mixed = Resolve-GlobalModelRoute -Prompt 'R1.5, R2 critical architecture review' -ProfileId 'ecosystem-architect' `
        -OpenRouterOnly -Catalog $catalog -HubRoot $HubRoot
    Assert-True $mixed.ok 'Mixed-rank route failed'
    Assert-Equal ($mixed.allowedRanks -join ',') 'rank1_5,rank2' 'Mixed-rank boundaries changed'
    Assert-Equal $mixed.profile.id 'ecosystem-architect' 'Named profile route failed'
    Assert-True ($mixed.candidates.Count -gt 1) 'Global scorer returned no fallback candidates'

    $profileRejected = $false
    try { Get-ModelRouterAgentProfile -ProfileId '../../secret' -HubRoot $HubRoot | Out-Null } catch { $profileRejected = $true }
    Assert-True $profileRejected 'Unsafe profile was not rejected'
    $unknownRejected = $false
    try { Get-ModelRouterAgentProfile -ProfileId 'unknown-worker' -HubRoot $HubRoot | Out-Null } catch { $unknownRejected = $true }
    Assert-True $unknownRejected 'Unknown profile was not rejected'

    $luna = Resolve-ModelRoute -Prompt 'R2 low' -Model 'openai/gpt-5.6-luna-pro' -Effort low -Catalog $catalog -HubRoot $HubRoot
    Assert-Equal $luna.effort 'max' 'Luna fixed max policy failed'
    Assert-True $luna.effortAdjusted 'Luna adjustment receipt missing'

    $glm = Resolve-ModelRoute -Prompt 'R1.5 medium' -Model 'z-ai/glm-5.3' -Effort medium -Catalog $catalog -HubRoot $HubRoot
    Assert-Equal $glm.effort 'high' 'Nearest supported effort must prefer safer higher tie'

    $lunaRecord = Get-OpenRouterModelRecord -Catalog $catalog -Model 'openai/gpt-5.6-luna-pro'
    $basePrice = Get-EffectiveModelPricing -CatalogRecord $lunaRecord -InputTokens 1000
    $nearThresholdPrice = Get-EffectiveModelPricing -CatalogRecord $lunaRecord -InputTokens 220000
    Assert-Equal $basePrice.overrideApplied $false 'Base pricing incorrectly marked overridden'
    Assert-Equal $nearThresholdPrice.overrideApplied $true 'Threshold safety margin was not applied'

    $estimate = Get-ModelRouterCostEstimate -Prompt ('x' * 3000) -CatalogRecord $lunaRecord -Effort max `
        -MaxOutputTokens 1000 -CachedInputTokens 100 -CacheWriteTokens 50
    Assert-True ($estimate.expectedUsd -gt 0) 'Expected cost missing'
    Assert-True ($estimate.worstUsd -ge $estimate.expectedUsd) 'Worst cost below expected'
    Assert-True ($estimate.autoCapUsd -ge $estimate.worstUsd) 'Auto cap below worst estimate'
    Assert-Equal $estimate.reasoningFloorApplied $false 'Unsupported global reasoning floor returned'
    Assert-True ($estimate.cacheReadPerMillion -gt 0) 'Cache read pricing missing'
    Assert-True ($estimate.cacheWritePerMillion -gt 0) 'Cache write pricing missing'

    $beforeCalibration = Measure-ModelRouterInput -Prompt ('я' * 100) -Model 'test/calibration' -HubRoot $HubRoot
    Update-ModelRouterCalibration -HubRoot $HubRoot -Model 'test/calibration' `
        -EstimatedBaseTokens $beforeCalibration.baseTokens -ActualPromptTokens ($beforeCalibration.baseTokens * 2)
    $afterCalibration = Measure-ModelRouterInput -Prompt ('я' * 100) -Model 'test/calibration' -HubRoot $HubRoot
    Assert-True ($afterCalibration.tokens -gt $beforeCalibration.tokens) 'Usage calibration did not increase an undercounted estimate'
    Assert-True ($afterCalibration.calibrationMultiplier -gt 1) 'Calibration multiplier was not persisted'

    $unpriced = Get-OpenRouterModelRecord -Catalog $catalog -Model 'test/unpriced'
    $unpricedEstimate = Get-ModelRouterCostEstimate -Prompt 'test' -CatalogRecord $unpriced -Effort none -MaxOutputTokens 10
    Assert-Equal $unpricedEstimate.reliable $false 'Missing price must require confirmation'

    $safeSession = Get-ModelRouterSession -HubRoot $HubRoot -SessionId '..\..\outside'
    Assert-True (-not $safeSession.sessionId.Contains('..')) 'Session id traversal was not sanitized'

    $reservation = Reserve-ModelRouterBudget -HubRoot $HubRoot -SessionId 'atomic' -CallId 'one' `
        -AmountUsd 0.06 -BudgetUsd 0.1 -Model 'test'
    Assert-True $reservation.ok 'Initial budget reservation failed'
    $duplicate = Reserve-ModelRouterBudget -HubRoot $HubRoot -SessionId 'atomic' -CallId 'one' `
        -AmountUsd 0.06 -BudgetUsd 0.1 -Model 'test'
    Assert-True ($duplicate.ok -and $duplicate.idempotent) 'Reservation idempotency failed'
    $blocked = Reserve-ModelRouterBudget -HubRoot $HubRoot -SessionId 'atomic' -CallId 'two' `
        -AmountUsd 0.06 -BudgetUsd 0.1 -Model 'test'
    Assert-Equal $blocked.code 'budget_cap' 'Reserved balance was double-spent'
    Undo-ModelRouterBudgetReservation -HubRoot $HubRoot -SessionId 'atomic' -CallId 'one' | Out-Null

    $reasoningRecord = New-CatalogRecord 'test/reasoning' @('high') -Mandatory $true -SupportsMaxTokens $true
    $reasoningConfig = [PSCustomObject]@{
        role = 'general-worker'
        supportedEfforts = @('high')
        reasoningMandatory = $true
        defaultEffort = 'high'
    }
    $reasoningMetadata = Get-ModelRouterReasoningMetadata -ModelConfig $reasoningConfig -CatalogRecord $reasoningRecord
    $reasoningEstimate = Get-ModelRouterCostEstimate -Prompt 'test' -CatalogRecord $reasoningRecord -Effort high -MaxOutputTokens 100
    $body = New-ModelRouterRequestBody -Prompt 'test' -SystemPrompt '' -Model 'test/reasoning' -Effort high `
        -ReasoningMetadata $reasoningMetadata -CatalogRecord $reasoningRecord -Estimate $reasoningEstimate -StructuredOutput
    Assert-True ($body.reasoning.max_tokens -lt $body.max_tokens) 'Reasoning max_tokens exceeded global output cap'
    Assert-Equal $body.response_format.type 'json_object' 'Structured output was not enabled'
    Assert-True (-not $body.Contains('temperature')) 'Temperature leaked into non-creative profile'

    Assert-Equal (Get-ModelRouterErrorCategory -StatusCode 401) 'key-auth' '401 error domain failed'
    Assert-Equal (Get-ModelRouterErrorCategory -StatusCode 429) 'rate-limited' '429 error domain failed'
    Assert-Equal (Get-ModelRouterErrorCategory -StatusCode 503) 'provider-error' '5xx error domain failed'

    $clock = [DateTimeOffset]::Parse('2026-09-09T12:00:00Z')
    Write-ModelRouterHealthEvent -HubRoot $HubRoot -Model 'test/circuit' -Status 'degraded' `
        -Category 'provider-error' -Now $clock
    Assert-Equal (Get-ModelRouterModelHealth -HubRoot $HubRoot -Model 'test/circuit' -Now $clock).circuit `
        'closed' 'Circuit opened after a single provider failure'
    Write-ModelRouterHealthEvent -HubRoot $HubRoot -Model 'test/circuit' -Status 'degraded' `
        -Category 'provider-error' -Now $clock.AddSeconds(1)
    $openHealth = Get-ModelRouterModelHealth -HubRoot $HubRoot -Model 'test/circuit' -Now $clock.AddSeconds(2)
    Assert-Equal $openHealth.circuit 'open' 'Circuit did not open after repeated provider failures'
    Assert-Equal $openHealth.retryEligible $false 'Open circuit allowed an early retry'
    $halfOpenAt = $clock.AddMinutes(3)
    Assert-Equal (Get-ModelRouterModelHealth -HubRoot $HubRoot -Model 'test/circuit' -Now $halfOpenAt).circuit `
        'half-open' 'Expired circuit did not become half-open'
    Assert-True (Enter-ModelRouterCircuit -HubRoot $HubRoot -Model 'test/circuit' -Now $halfOpenAt) `
        'Half-open probe was not admitted'
    Assert-Equal (Enter-ModelRouterCircuit -HubRoot $HubRoot -Model 'test/circuit' -Now $halfOpenAt) $false `
        'Second half-open probe was admitted'
    Write-ModelRouterHealthEvent -HubRoot $HubRoot -Model 'test/circuit' -Status 'live' `
        -Category 'success' -Now $halfOpenAt.AddSeconds(1)
    Assert-Equal (Get-ModelRouterModelHealth -HubRoot $HubRoot -Model 'test/circuit').circuit `
        'closed' 'Success did not close the circuit'

    $fallbackProfile = Get-ModelRouterAgentProfile -ProfileId 'general-worker' -HubRoot $HubRoot
    $fallbackRoute = [PSCustomObject]@{
        rank = 'rank2'
        model = 'deepseek/deepseek-v4-pro-0813'
        effort = 'low'
        effortRequested = 'low'
        profile = $fallbackProfile
        fallbackModels = @('deepseek/deepseek-v4-pro-0813', 'deepseek/deepseek-v4-flash-0731')
        fallbackCandidates = @(
            [PSCustomObject]@{ rank = 'rank2'; model = 'deepseek/deepseek-v4-pro-0813'; effortRequested = 'low' },
            [PSCustomObject]@{ rank = 'rank2'; model = 'deepseek/deepseek-v4-flash-0731'; effortRequested = 'low' }
        )
    }
    $transportCalls = New-Object System.Collections.Generic.List[string]
    $fallbackTransport = {
        param($request)
        $transportCalls.Add([string]$request.model)
        if ($request.model -eq 'deepseek/deepseek-v4-pro-0813') {
            $failure = [Exception]::new('provider failed')
            $failure.Data['StatusCode'] = 503
            throw $failure
        }
        return [PSCustomObject]@{
            model = $request.model
            choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = 'OK' } })
            usage = [PSCustomObject]@{
                cost = 0.000001
                prompt_tokens = 10
                completion_tokens = 1
                completion_tokens_details = [PSCustomObject]@{ reasoning_tokens = 0 }
                prompt_tokens_details = [PSCustomObject]@{ cached_tokens = 0; cache_write_tokens = 0 }
            }
        }
    }
    $fallbackResponse = Invoke-ModelRouterChat -Prompt 'test fallback' -Route $fallbackRoute -Catalog $catalog `
        -BudgetUsd 0.01 -MaxOutputTokens 8 -SessionId 'fallback' -CallId 'fallback' `
        -KeyInfo ([PSCustomObject]@{ limitRemaining = 10.0 }) -Transport $fallbackTransport -HubRoot $HubRoot
    Assert-True $fallbackResponse.ok 'Runtime fallback did not recover'
    Assert-Equal $fallbackResponse.model 'deepseek/deepseek-v4-flash-0731' 'Wrong runtime fallback model'
    Assert-True $fallbackResponse.fallbackUsed 'Fallback receipt was false'
    Assert-Equal ($transportCalls -join ',') 'deepseek/deepseek-v4-pro-0813,deepseek/deepseek-v4-flash-0731' `
        'Runtime fallback order diverged from scorer'

    $unpricedCatalog = @($catalog | ForEach-Object {
        if ($_.id -eq 'z-ai/glm-5.2') {
            [PSCustomObject]@{
                id = $_.id
                supported_parameters = $_.supported_parameters
                architecture = $_.architecture
                reasoning = $_.reasoning
                pricing = [PSCustomObject]@{}
            }
        }
        else { $_ }
    })
    $unpricedRoute = Resolve-ModelRoute -Prompt 'R2 test' -Model 'z-ai/glm-5.2' -Catalog $unpricedCatalog -HubRoot $HubRoot
    $unpricedCalls = 0
    $unpricedTransport = { param($request) $unpricedCalls++; throw 'must not run' }
    $unpricedResponse = Invoke-ModelRouterChat -Prompt 'test' -Route $unpricedRoute -Catalog $unpricedCatalog `
        -BudgetUsd 0.01 -SessionId 'unpriced' -CallId 'unpriced' -Transport $unpricedTransport -HubRoot $HubRoot
    Assert-Equal $unpricedResponse.code 'unpriced_confirmation_required' 'Unpriced state machine failed'
    Assert-Equal $unpricedCalls 0 'Unpriced model performed HTTP before confirmation'
    $confirmedCalls = New-Object System.Collections.Generic.List[string]
    $confirmedTransport = {
        param($request)
        $confirmedCalls.Add([string]$request.model)
        return [PSCustomObject]@{
            model = $request.model
            choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = 'confirmed' } })
            usage = [PSCustomObject]@{
                cost = 0.000001
                prompt_tokens = 2
                completion_tokens = 1
                completion_tokens_details = [PSCustomObject]@{ reasoning_tokens = 0 }
                prompt_tokens_details = [PSCustomObject]@{ cached_tokens = 0; cache_write_tokens = 0 }
            }
        }
    }
    $confirmedResponse = Invoke-ModelRouterChat -Prompt 'test' -Route $unpricedRoute -Catalog $unpricedCatalog `
        -BudgetUsd 0.01 -SessionId 'unpriced-confirmed' -CallId 'unpriced-confirmed' `
        -AllowUnpriced -Transport $confirmedTransport -HubRoot $HubRoot
    Assert-True $confirmedResponse.ok 'Confirmed unpriced model did not run'
    Assert-Equal $confirmedCalls.Count 1 'Confirmed unpriced model did not run exactly once'

    $keyRoute = Resolve-ModelRoute -Prompt 'R2 low' -Model 'z-ai/glm-5.2' -Catalog $catalog -HubRoot $HubRoot
    $modelHealthBefore401 = Get-ModelRouterModelHealth -HubRoot $HubRoot -Model 'z-ai/glm-5.2'
    $authTransport = {
        param($request)
        $failure = [Exception]::new('bad key')
        $failure.Data['StatusCode'] = 401
        throw $failure
    }
    $authResponse = Invoke-ModelRouterChat -Prompt 'test auth' -Route $keyRoute -Catalog $catalog `
        -BudgetUsd 0.01 -MaxOutputTokens 8 -SessionId 'auth' -CallId 'auth' `
        -KeyInfo ([PSCustomObject]@{ limitRemaining = 10.0 }) -Transport $authTransport -HubRoot $HubRoot
    Assert-Equal $authResponse.code 'key-auth' '401 did not stop as key health'
    $modelHealthAfter401 = Get-ModelRouterModelHealth -HubRoot $HubRoot -Model 'z-ai/glm-5.2'
    Assert-Equal $modelHealthAfter401.failures $modelHealthBefore401.failures '401 corrupted model health'

    $callsBeforeKeyLimit = $transportCalls.Count
    $exhaustedKeyResponse = Invoke-ModelRouterChat -Prompt 'test exhausted key' -Route $keyRoute -Catalog $catalog `
        -BudgetUsd 0.01 -MaxOutputTokens 8 -SessionId 'key-exhausted' -CallId 'key-exhausted' `
        -KeyInfo ([PSCustomObject]@{ limitRemaining = 0.0 }) -Transport $fallbackTransport -HubRoot $HubRoot
    Assert-Equal $exhaustedKeyResponse.code 'fallback_exhausted' 'Exhausted shared-key remainder was not blocked'
    Assert-Equal $transportCalls.Count $callsBeforeKeyLimit 'Exhausted shared-key remainder still called transport'

    $nullKeyResponse = Invoke-ModelRouterChat -Prompt 'test unlimited key' -Route $keyRoute -Catalog $catalog `
        -BudgetUsd 0.01 -MaxOutputTokens 8 -SessionId 'key-null' -CallId 'key-null' `
        -KeyInfo ([PSCustomObject]@{ limitRemaining = $null }) -Transport $fallbackTransport -HubRoot $HubRoot
    Assert-True $nullKeyResponse.ok 'Null key limit should defer to the local hard cap'

    $overrunTransport = {
        param($request)
        return [PSCustomObject]@{
            model = $request.model
            choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = 'too expensive' } })
            usage = [PSCustomObject]@{
                cost = 0.5
                prompt_tokens = 10
                completion_tokens = 1
                completion_tokens_details = [PSCustomObject]@{ reasoning_tokens = 0 }
                prompt_tokens_details = [PSCustomObject]@{ cached_tokens = 0; cache_write_tokens = 0 }
            }
        }
    }
    $overrunResponse = Invoke-ModelRouterChat -Prompt 'test overrun' -Route $keyRoute -Catalog $catalog `
        -BudgetUsd 1.0 -MaxOutputTokens 8 -SessionId 'overrun' -CallId 'overrun' `
        -KeyInfo ([PSCustomObject]@{ limitRemaining = 10.0 }) -Transport $overrunTransport -HubRoot $HubRoot
    Assert-Equal $overrunResponse.code 'budget_overrun' 'Actual overrun returned ok'
    Assert-Equal $overrunResponse.ok $false 'Actual overrun must not be ok'

    $r3 = Resolve-GlobalModelRoute -Prompt 'R3 draft text' -OpenRouterOnly -Catalog $catalog -HubRoot $HubRoot
    Assert-Equal $r3.code 'r3_text_unavailable' 'Empty R3 allowlist did not fail honestly'

    Write-Output 'model-router contracts: ok'
}
finally {
    Remove-Item -LiteralPath $temporaryState -Recurse -Force -ErrorAction SilentlyContinue
    $env:MODEL_ROUTER_STATE_ROOT = $previousStateRoot
}

function Get-OpenRouterKey {
    foreach ($scope in @('Process', 'User')) {
        $key = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', $scope)
        if ($key) { return $key }
    }
    throw 'OPENROUTER_API_KEY is not set in Process/User environment.'
}

function Get-OpenRouterKeyInfo {
    param([string]$Key = '')
    if (-not $Key) { $Key = Get-OpenRouterKey }
    $headers = @{ Authorization = "Bearer $Key" }
    $response = Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/key' -Method Get -Headers $headers -TimeoutSec 30
    if (-not $response.data) { throw 'OpenRouter key endpoint returned no data' }
    return [PSCustomObject]@{
        limit = Get-ModelRouterPropertyValue $response.data 'limit'
        limitRemaining = Get-ModelRouterPropertyValue $response.data 'limit_remaining'
        limitReset = Get-ModelRouterPropertyValue $response.data 'limit_reset'
        usage = Get-ModelRouterPropertyValue $response.data 'usage'
        usageDaily = Get-ModelRouterPropertyValue $response.data 'usage_daily'
        usageMonthly = Get-ModelRouterPropertyValue $response.data 'usage_monthly'
        isFreeTier = [bool](Get-ModelRouterPropertyValue $response.data 'is_free_tier')
    }
}

function Get-ModelRouterHttpStatusCode {
    param([Parameter(Mandatory)]$ErrorRecord)
    try {
        $dataStatus = $ErrorRecord.Exception.Data['StatusCode']
        if ($dataStatus) { return [int]$dataStatus }
    }
    catch {}
    try {
        $response = $ErrorRecord.Exception.Response
        if ($response -and $response.StatusCode) { return [int]$response.StatusCode }
    }
    catch {}
    $message = [string]$ErrorRecord.Exception.Message
    foreach ($code in @(401, 402, 403, 404, 408, 409, 429, 500, 502, 503, 504)) {
        if ($message -match "(?<!\d)$code(?!\d)") { return $code }
    }
    return 0
}

function Get-ModelRouterErrorCategory {
    param(
        [int]$StatusCode,
        [string]$Message = ''
    )
    switch ($StatusCode) {
        401 { return 'key-auth' }
        402 { return 'key-credit' }
        403 { return 'forbidden' }
        404 { return 'not-found' }
        429 { return 'rate-limited' }
        { $_ -ge 500 } { return 'provider-error' }
    }
    if ($Message -match '(?i)timeout|timed out') { return 'provider-error' }
    return 'protocol-error'
}

function Get-ModelRouterUsageDetails {
    param($Usage)
    if (-not $Usage) {
        return [PSCustomObject]@{
            cost = 0.0
            promptTokens = 0
            completionTokens = 0
            reasoningTokens = 0
            cachedTokens = 0
            cacheWriteTokens = 0
        }
    }
    $completionDetails = Get-ModelRouterPropertyValue $Usage 'completion_tokens_details'
    $promptDetails = Get-ModelRouterPropertyValue $Usage 'prompt_tokens_details'
    return [PSCustomObject]@{
        cost = [double](Get-ModelRouterPropertyValue $Usage 'cost')
        promptTokens = [int](Get-ModelRouterPropertyValue $Usage 'prompt_tokens')
        completionTokens = [int](Get-ModelRouterPropertyValue $Usage 'completion_tokens')
        reasoningTokens = [int](Get-ModelRouterPropertyValue $completionDetails 'reasoning_tokens')
        cachedTokens = [int](Get-ModelRouterPropertyValue $promptDetails 'cached_tokens')
        cacheWriteTokens = [int](Get-ModelRouterPropertyValue $promptDetails 'cache_write_tokens')
    }
}

function Get-ModelRouterReasoningRatio {
    param([string]$Effort)
    switch ($Effort) {
        'none' { return 0.0 }
        'minimal' { return 0.1 }
        'low' { return 0.2 }
        'medium' { return 0.5 }
        'high' { return 0.8 }
        default { return 0.95 }
    }
}

function New-ModelRouterRequestBody {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [AllowEmptyString()][string]$SystemPrompt = '',
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Effort,
        [Parameter(Mandatory)]$ReasoningMetadata,
        [Parameter(Mandatory)]$CatalogRecord,
        [Parameter(Mandatory)]$Estimate,
        [switch]$Sensitive,
        [switch]$StructuredOutput,
        [switch]$Creative
    )
    $messages = New-Object System.Collections.Generic.List[object]
    if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
        $messages.Add([PSCustomObject]@{ role = 'system'; content = $SystemPrompt })
    }
    $messages.Add([PSCustomObject]@{ role = 'user'; content = $Prompt })
    $provider = [ordered]@{
        allow_fallbacks = $true
        require_parameters = $true
        sort = 'price'
        data_collection = 'deny'
    }
    if ($Sensitive) { $provider.zdr = $true }
    if ($Estimate.promptPerMillion -gt 0 -or $Estimate.completionPerMillion -gt 0) {
        $provider.max_price = [ordered]@{
            prompt = [Math]::Round($Estimate.promptPerMillion * 1.05, 6)
            completion = [Math]::Round($Estimate.completionPerMillion * 1.05, 6)
        }
    }
    $body = [ordered]@{
        model = $Model
        messages = [object[]]$messages
        max_tokens = [int]$Estimate.maxOutputTokens
        provider = $provider
    }
    $supported = @((Get-ModelRouterPropertyValue $CatalogRecord 'supported_parameters'))
    if ($supported -contains 'reasoning' -or $supported -contains 'reasoning_effort') {
        $reasoning = [ordered]@{ effort = $Effort; exclude = $true }
        if ([bool]$ReasoningMetadata.supportsMaxTokens -and $Effort -ne 'none' -and $Estimate.maxOutputTokens -gt 1) {
            $budget = [Math]::Floor($Estimate.maxOutputTokens * (Get-ModelRouterReasoningRatio -Effort $Effort))
            $budget = [Math]::Max(1, [Math]::Min($Estimate.maxOutputTokens - 1, $budget))
            $reasoning = [ordered]@{ max_tokens = [int]$budget; exclude = $true }
        }
        $body.reasoning = $reasoning
    }
    if ($StructuredOutput) {
        if ($supported -contains 'response_format') { $body.response_format = [ordered]@{ type = 'json_object' } }
        if ($supported -contains 'structured_outputs') { $body.structured_outputs = $true }
    }
    if ($Creative -and $supported -contains 'temperature') { $body.temperature = 0.9 }
    return $body
}

function Get-ModelRouterActualCost {
    param(
        $Usage,
        [Parameter(Mandatory)]$Estimate
    )
    $cost = Get-ModelRouterPropertyValue $Usage 'cost'
    if ($null -ne $cost) { return [double]$cost }
    if (-not $Usage) { return 0.0 }
    return ([double]$Usage.prompt_tokens * ($Estimate.promptPerMillion / 1000000)) +
        ([double]$Usage.completion_tokens * ($Estimate.completionPerMillion / 1000000))
}

function Get-ModelRouterDynamicR3Candidates {
    param([Parameter(Mandatory)][object[]]$Catalog)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($record in $Catalog) {
        $id = [string]$record.id
        if (-not $id.EndsWith(':free', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $architecture = Get-ModelRouterPropertyValue $record 'architecture'
        $outputs = @((Get-ModelRouterPropertyValue $architecture 'output_modalities'))
        if ($outputs.Count -gt 0 -and $outputs -notcontains 'text') { continue }
        $inputs = @((Get-ModelRouterPropertyValue $architecture 'input_modalities'))
        if ($inputs.Count -gt 0 -and $inputs -notcontains 'text') { continue }
        $result.Add($id)
    }
    return [string[]]$result
}

function Invoke-ModelRouterChat {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)]$Route,
        [Parameter(Mandatory)][object[]]$Catalog,
        [double]$BudgetUsd = -1,
        [int]$MaxOutputTokens = 0,
        [string]$SessionId = 'default',
        [string]$CallId = '',
        [switch]$Sensitive,
        [switch]$StructuredOutput,
        [switch]$Creative,
        [switch]$AllowUnpriced,
        $KeyInfo = $null,
        [ScriptBlock]$Transport = $null,
        [string]$HubRoot = '',
        [string]$StateRoot = ''
    )
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    if (-not $CallId) { $CallId = [Guid]::NewGuid().ToString('N') }
    $key = if ($Transport) { 'injected-transport' } else { Get-OpenRouterKey }
    $routeProfile = Get-ModelRouterPropertyValue $Route 'profile'
    $profile = if ($routeProfile) { $routeProfile } else { Get-ModelRouterAgentProfile -HubRoot $root }
    $systemPrompt = [string]$profile.systemPrompt
    $effectiveInput = if ($systemPrompt) { $systemPrompt + "`n`n" + $Prompt } else { $Prompt }
    $candidateItems = @()
    $routeFallbackCandidates = Get-ModelRouterPropertyValue $Route 'fallbackCandidates'
    if ($routeFallbackCandidates -and @($routeFallbackCandidates).Count -gt 0) {
        $candidateItems = @($routeFallbackCandidates)
    }
    else {
        foreach ($model in @((Get-ModelRouterPropertyValue $Route 'fallbackModels'))) {
            $candidateItems += [PSCustomObject]@{
                rank = [string]$Route.rank
                model = [string]$model
                effortRequested = [string]$Route.effortRequested
            }
        }
    }
    $errors = New-Object System.Collections.Generic.List[object]
    $unpriced = New-Object System.Collections.Generic.List[string]
    foreach ($candidateItem in $candidateItems) {
        $candidate = [string]$candidateItem.model
        $itemRank = Get-ModelRouterPropertyValue $candidateItem 'rank'
        $candidateRank = if ($itemRank) { [string]$itemRank } else { [string]$Route.rank }
        $ladder = Get-ModelRouterLadder -HubRoot $root
        $rankSpec = Get-ModelRouterRankSpec -Ladder $ladder -RankKey $candidateRank
        $config = Get-ModelRouterConfig -RankSpec $rankSpec -Model $candidate
        if (-not $config -and $candidateRank -eq 'rank3') {
            $config = [PSCustomObject]@{
                role = 'general-worker'
                modality = @('text')
                supportedEfforts = @('none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max')
                defaultEffort = 'medium'
            }
        }
        $record = Get-OpenRouterModelRecord -Catalog $Catalog -Model $candidate
        if (-not $config -or -not $record) {
            Write-ModelRouterHealthEvent -HubRoot $root -Model $candidate -Status 'catalog-missing' `
                -Category 'catalog-missing' -Error 'not present in current catalog' -StateRoot $StateRoot
            $errors.Add([PSCustomObject]@{ model = $candidate; code = 'catalog-missing' })
            continue
        }
        $itemEffort = Get-ModelRouterPropertyValue $candidateItem 'effortRequested'
        $routeRequestedEffort = Get-ModelRouterPropertyValue $Route 'effortRequested'
        $requestedEffort = if ($itemEffort) {
            [string]$itemEffort
        }
        elseif ($routeRequestedEffort) {
            [string]$routeRequestedEffort
        }
        else {
            [string]$Route.effort
        }
        $effortResult = Resolve-ModelRouterEffort -ModelConfig $config -CatalogRecord $record -Requested $requestedEffort
        $estimate = Get-ModelRouterCostEstimate -Prompt $effectiveInput -CatalogRecord $record `
            -Effort $effortResult.selected -MaxOutputTokens $MaxOutputTokens -Model $candidate `
            -HubRoot $root -StateRoot $StateRoot
        if (-not $estimate.reliable) {
            $unpriced.Add($candidate)
            if (-not $AllowUnpriced) { continue }
            if ($BudgetUsd -lt 0) {
                return [PSCustomObject]@{
                    ok = $false
                    code = 'unpriced_confirmation_required'
                    model = $candidate
                    error = 'Explicit confirmation and BudgetUsd are required for an unpriced model.'
                }
            }
        }
        if (-not $KeyInfo -and -not $Transport) {
            try {
                $KeyInfo = Get-OpenRouterKeyInfo -Key $key
                Write-ModelRouterKeyHealthEvent -HubRoot $root -Status 'live' -StateRoot $StateRoot
            }
            catch {
                $statusCode = Get-ModelRouterHttpStatusCode -ErrorRecord $_
                if ($statusCode -eq 401) {
                    Write-ModelRouterKeyHealthEvent -HubRoot $root -Status 'unauthorized' `
                        -Error $_.Exception.Message -StateRoot $StateRoot
                    return [PSCustomObject]@{ ok = $false; code = 'key_auth'; error = $_.Exception.Message }
                }
                $errors.Add([PSCustomObject]@{
                    model = $null
                    code = 'key_info_unavailable'
                    error = $_.Exception.Message
                })
                if ([double]$estimate.worstUsd -gt 0) {
                    return [PSCustomObject]@{
                        ok = $false
                        code = 'key_info_unavailable'
                        error = 'Paid call blocked because shared-key remainder could not be read.'
                        errors = [object[]]$errors
                    }
                }
            }
        }
        $session = Get-ModelRouterSession -HubRoot $root -SessionId $SessionId -StateRoot $StateRoot
        $effectiveBudget = if ($BudgetUsd -ge 0) {
            $BudgetUsd
        }
        else {
            [double]$session.spentUsd + [double]$session.reservedUsd + [double]$estimate.autoCapUsd
        }
        $reserveAmount = if ($estimate.reliable) {
            [double]$estimate.autoCapUsd
        }
        else {
            [Math]::Max(0.0, $effectiveBudget - [double]$session.spentUsd - [double]$session.reservedUsd)
        }
        if ($KeyInfo -and $null -ne $KeyInfo.limitRemaining) {
            if ($reserveAmount -gt [double]$KeyInfo.limitRemaining) {
                $errors.Add([PSCustomObject]@{
                    model = $candidate
                    code = 'shared_key_limit'
                    requestedUsd = $reserveAmount
                    limitRemainingUsd = [double]$KeyInfo.limitRemaining
                })
                continue
            }
        }
        $candidateCallId = "$CallId-$candidate"
        $reservation = Reserve-ModelRouterBudget -HubRoot $root -SessionId $SessionId -CallId $candidateCallId `
            -AmountUsd $reserveAmount -BudgetUsd $effectiveBudget -Model $candidate -StateRoot $StateRoot
        if (-not $reservation.ok) {
            $errors.Add([PSCustomObject]@{
                model = $candidate
                code = [string]$reservation.code
                requestedUsd = $reservation.requestedUsd
                availableUsd = $reservation.availableUsd
            })
            continue
        }
        if ($reservation.idempotent) {
            return [PSCustomObject]@{
                ok = $false
                code = 'duplicate_inflight_call'
                model = $candidate
                callId = $candidateCallId
            }
        }
        if (-not (Enter-ModelRouterCircuit -HubRoot $root -Model $candidate -StateRoot $StateRoot)) {
            Undo-ModelRouterBudgetReservation -HubRoot $root -SessionId $SessionId `
                -CallId $candidateCallId -StateRoot $StateRoot | Out-Null
            $errors.Add([PSCustomObject]@{ model = $candidate; code = 'circuit-open' })
            continue
        }
        $body = New-ModelRouterRequestBody -Prompt $Prompt -SystemPrompt $systemPrompt -Model $candidate `
            -Effort $effortResult.selected -ReasoningMetadata $effortResult.metadata -CatalogRecord $record `
            -Estimate $estimate -Sensitive:$Sensitive -StructuredOutput:$StructuredOutput -Creative:$Creative
        $headers = @{
            Authorization = "Bearer $key"
            'HTTP-Referer' = 'https://cursor.local/hub'
            'X-OpenRouter-Title' = 'cursor-hub-model-router'
        }
        $started = [Diagnostics.Stopwatch]::StartNew()
        try {
            $response = if ($Transport) {
                & $Transport ([PSCustomObject]@{
                    uri = 'https://openrouter.ai/api/v1/chat/completions'
                    method = 'POST'
                    headers = $headers
                    body = $body
                    model = $candidate
                })
            }
            else {
                Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/chat/completions' -Method Post `
                    -Headers $headers -ContentType 'application/json; charset=utf-8' `
                    -Body ($body | ConvertTo-Json -Compress -Depth 20) -TimeoutSec 180
            }
            $started.Stop()
            $text = ''
            if ($response.choices -and $response.choices.Count -gt 0) { $text = [string]$response.choices[0].message.content }
            $actual = Get-ModelRouterActualCost -Usage $response.usage -Estimate $estimate
            $usage = Get-ModelRouterUsageDetails -Usage $response.usage
            Update-ModelRouterCalibration -HubRoot $root -Model $candidate `
                -EstimatedBaseTokens ([int]$estimate.inputBaseTokens) -ActualPromptTokens $usage.promptTokens `
                -StateRoot $StateRoot
            $callRecord = [PSCustomObject]@{
                at = [DateTimeOffset]::UtcNow.ToString('o')
                callId = $candidateCallId
                profile = [string]$profile.id
                rank = $candidateRank
                model = [string]$response.model
                requestedModel = $candidate
                effort = $effortResult.selected
                estimatedUsd = $estimate.expectedUsd
                reservedUsd = $reserveAmount
                actualUsd = $actual
                promptTokens = $usage.promptTokens
                completionTokens = $usage.completionTokens
                reasoningTokens = $usage.reasoningTokens
                cachedTokens = $usage.cachedTokens
                cacheWriteTokens = $usage.cacheWriteTokens
                latencyMs = [Math]::Round($started.Elapsed.TotalMilliseconds, 3)
            }
            $settlement = Complete-ModelRouterBudgetReservation -HubRoot $root -SessionId $SessionId `
                -CallId $candidateCallId -ActualUsd $actual -Call $callRecord -BudgetUsd $effectiveBudget -StateRoot $StateRoot
            Write-ModelRouterHealthEvent -HubRoot $root -Model $candidate -Status 'live' -Category 'success' `
                -LatencyMs $started.Elapsed.TotalMilliseconds -StateRoot $StateRoot
            if (-not $settlement.ok) {
                return [PSCustomObject]@{
                    ok = $false
                    code = 'budget_overrun'
                    rank = $candidateRank
                    requestedModel = [string]$Route.model
                    model = [string]$response.model
                    effort = $effortResult.selected
                    estimate = $estimate
                    actualUsd = $actual
                    reservedUsd = $reserveAmount
                    sessionSpentUsd = $settlement.session.spentUsd
                    text = $text
                    usage = $response.usage
                    fallbackUsed = ($candidate -ne [string]$Route.model)
                }
            }
            return [PSCustomObject]@{
                ok = $true
                code = 'completed'
                rank = $candidateRank
                requestedModel = [string]$Route.model
                model = [string]$response.model
                effort = $effortResult.selected
                effortAdjusted = $effortResult.adjusted
                estimate = $estimate
                budgetUsd = $effectiveBudget
                sharedKeyRemainingUsd = if ($KeyInfo) { $KeyInfo.limitRemaining } else { $null }
                sessionSpentUsd = $settlement.session.spentUsd
                sessionReservedUsd = $settlement.session.reservedUsd
                budgetExceeded = $false
                text = $text
                usage = $response.usage
                usageDetails = $usage
                fallbackUsed = ($candidate -ne [string]$Route.model)
                profile = [string]$profile.id
            }
        }
        catch {
            $started.Stop()
            Undo-ModelRouterBudgetReservation -HubRoot $root -SessionId $SessionId -CallId $candidateCallId -StateRoot $StateRoot | Out-Null
            $message = $_.Exception.Message
            $statusCode = Get-ModelRouterHttpStatusCode -ErrorRecord $_
            $category = Get-ModelRouterErrorCategory -StatusCode $statusCode -Message $message
            if ($category -eq 'key-auth' -or $category -eq 'key-credit') {
                Exit-ModelRouterCircuitProbe -HubRoot $root -Model $candidate -StateRoot $StateRoot
                Write-ModelRouterKeyHealthEvent -HubRoot $root -Status $category -Error $message -StateRoot $StateRoot
                return [PSCustomObject]@{
                    ok = $false
                    code = $category
                    error = $message
                    errors = [object[]]$errors
                }
            }
            $status = if ($category -eq 'not-found') { 'unavailable' } else { 'degraded' }
            Write-ModelRouterHealthEvent -HubRoot $root -Model $candidate -Status $status -Category $category `
                -Error $message -LatencyMs $started.Elapsed.TotalMilliseconds -StateRoot $StateRoot
            $errors.Add([PSCustomObject]@{
                model = $candidate
                code = $category
                httpStatus = $statusCode
                error = $message
            })
        }
    }
    if ($unpriced.Count -gt 0 -and -not $AllowUnpriced) {
        return [PSCustomObject]@{
            ok = $false
            code = 'unpriced_confirmation_required'
            models = [string[]]$unpriced
            error = 'A selected unpriced model requires a separate Boss confirmation before any HTTP inference call.'
            errors = [object[]]$errors
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

param([string]$HubRoot = '')

$ErrorActionPreference = 'Stop'
if (-not $HubRoot) { $HubRoot = Split-Path $PSScriptRoot -Parent }
Import-Module (Join-Path $HubRoot 'lib/model-router/ModelRouter.psm1') -Force

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
        [double]$Prompt = 0.000001,
        [double]$Completion = 0.000003,
        [object[]]$Overrides = @()
    )
    return [PSCustomObject]@{
        id = $Id
        supported_parameters = @('reasoning', 'max_tokens', 'tools')
        reasoning = [PSCustomObject]@{ supported_efforts = $Efforts }
        pricing = [PSCustomObject]@{
            prompt = [string]$Prompt
            completion = [string]$Completion
            request = $null
            internal_reasoning = $null
            input_cache_read = $null
            input_cache_write = $null
            overrides = $Overrides
        }
    }
}

$catalog = @(
    (New-CatalogRecord 'z-ai/glm-5.3' @('max', 'high', 'low')),
    (New-CatalogRecord 'x-ai/grok-4.6' @('xhigh', 'high', 'medium', 'low')),
    (New-CatalogRecord 'qwen/qwen3.8-max-0902' @('xhigh', 'high', 'medium', 'low', 'minimal')),
    (New-CatalogRecord 'meta/muse-spark-1.2' @('xhigh', 'high', 'medium', 'low', 'minimal')),
    (New-CatalogRecord 'openai/gpt-5.6-luna-pro' @('max', 'xhigh', 'high', 'medium', 'low', 'none') 0.0000002 0.0000012 @(
        [PSCustomObject]@{ min_prompt_tokens = 272000; prompt = '0.0000004'; completion = '0.0000018' }
    )),
    (New-CatalogRecord 'z-ai/glm-5.2' @('xhigh', 'high')),
    (New-CatalogRecord 'deepseek/deepseek-v4-pro-0813' @('max', 'high', 'low')),
    (New-CatalogRecord 'deepseek/deepseek-v4-flash-0731' @('max', 'high', 'low')),
    (New-CatalogRecord 'z-ai/glm-5.3-flash' @('max', 'high', 'low')),
    (New-CatalogRecord 'google/gemini-3.8-flash' @('high', 'medium', 'low')),
    (New-CatalogRecord 'z-ai/glm-5.2:free' @()),
    (New-CatalogRecord 'minimax/minimax-m3:free' @()),
    (New-CatalogRecord 'thinkingmachines/inkling:free' @())
)

Assert-Equal (Resolve-ModelRouterRankKey -Prompt 'используй R1.5 для плана') 'rank1_5' 'R1.5 parsing failed'
Assert-Equal (Resolve-ModelRouterRankKey -Prompt 'запусти r2') 'rank2' 'R2 parsing failed'
Assert-Equal (Resolve-ModelRouterRankKey -Prompt 'черновик через R3') 'rank3' 'R3 parsing failed'

$architecture = Resolve-ModelRoute -Prompt 'R1.5: спланируй архитектуру репозитория' -Catalog $catalog -HubRoot $HubRoot
Assert-Equal $architecture.preferredModel 'qwen/qwen3.8-max-0902' 'R1.5 architecture preference failed'
Assert-Equal $architecture.model 'z-ai/glm-5.3' 'Unavailable architecture model was not health-routed'
Assert-True $architecture.selectionAdjusted 'Health-aware route adjustment missing'

$review = Resolve-ModelRoute -Prompt 'R1.5 adversarial audit рисков' -Catalog $catalog -HubRoot $HubRoot
Assert-Equal $review.model 'x-ai/grok-4.6' 'R1.5 review route failed'

$general = Resolve-ModelRoute -Prompt 'R2 выполни обычный анализ' -Catalog $catalog -HubRoot $HubRoot
Assert-Equal $general.model 'z-ai/glm-5.2' 'R2 default route failed'
Assert-Equal $general.effort 'high' 'GLM 5.2 effort normalization failed'

$fast = Resolve-ModelRoute -Prompt 'R2 fast batch classification' -Catalog $catalog -HubRoot $HubRoot
Assert-Equal $fast.model 'deepseek/deepseek-v4-flash-0731' 'R2 fast route failed'
Assert-Equal $fast.effort 'low' 'Fast task effort failed'

$luna = Resolve-ModelRoute -Prompt 'R2 low' -Model 'openai/gpt-5.6-luna-pro' -Effort low -Catalog $catalog -HubRoot $HubRoot
Assert-Equal $luna.effort 'max' 'Luna fixed max policy failed'
Assert-True $luna.effortAdjusted 'Luna adjustment receipt missing'

$glm = Resolve-ModelRoute -Prompt 'R1.5 medium' -Model 'z-ai/glm-5.3' -Effort medium -Catalog $catalog -HubRoot $HubRoot
Assert-Equal $glm.effort 'high' 'Nearest supported effort must prefer safer higher tie'

$lunaRecord = Get-OpenRouterModelRecord -Catalog $catalog -Model 'openai/gpt-5.6-luna-pro'
$basePrice = Get-EffectiveModelPricing -CatalogRecord $lunaRecord -InputTokens 1000
$longPrice = Get-EffectiveModelPricing -CatalogRecord $lunaRecord -InputTokens 300000
Assert-Equal $basePrice.overrideApplied $false 'Base pricing incorrectly marked overridden'
Assert-Equal $longPrice.overrideApplied $true 'Long-context override was not applied'
Assert-True ($longPrice.prompt -gt $basePrice.prompt) 'Long-context prompt price did not increase'

$estimate = Get-ModelRouterCostEstimate -Prompt ('x' * 3000) -CatalogRecord $lunaRecord -Effort max -MaxOutputTokens 1000
Assert-True ($estimate.expectedUsd -gt 0) 'Expected cost missing'
Assert-True ($estimate.worstUsd -ge $estimate.expectedUsd) 'Worst cost below expected'
Assert-True ($estimate.autoCapUsd -ge $estimate.worstUsd) 'Auto cap below worst estimate'

$unpriced = [PSCustomObject]@{
    id = 'test/unpriced'
    supported_parameters = @()
    pricing = [PSCustomObject]@{}
}
$unpricedEstimate = Get-ModelRouterCostEstimate -Prompt 'test' -CatalogRecord $unpriced -Effort none -MaxOutputTokens 10
Assert-Equal $unpricedEstimate.reliable $false 'Missing price must require a budget decision'

$safeSession = Get-ModelRouterSession -HubRoot $HubRoot -SessionId '..\..\outside'
Assert-True (-not $safeSession.sessionId.Contains('..')) 'Session id traversal was not sanitized'

Assert-Equal $general.fallbackModels[0] 'z-ai/glm-5.2' 'Selected model is not first fallback'
Assert-True ($general.fallbackModels -contains 'deepseek/deepseek-v4-flash-0731') 'R2 fallback chain incomplete'

Write-Output 'model-router contracts: ok'

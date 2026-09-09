# Task Router hook — UserPromptSubmit → [TASK ROUTE] + optional advisor flag
# Fail-open: any error exits 0 without blocking the chat.

$ErrorActionPreference = 'Stop'

try {
    [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $inputRaw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($inputRaw)) { exit 0 }

    try {
        $data = $inputRaw | ConvertFrom-Json
    }
    catch { exit 0 }

    $prompt = ''
    if ($data.prompt) { $prompt = [string]$data.prompt }
    elseif ($data.user_message) { $prompt = [string]$data.user_message }
    elseif ($data.message) { $prompt = [string]$data.message }

    if ([string]::IsNullOrWhiteSpace($prompt)) { exit 0 }

    $hubRoot = Split-Path $PSScriptRoot -Parent
    $resolver = Join-Path $hubRoot 'lib/task-router/Resolve-TaskRoute.ps1'
    if (-not (Test-Path -LiteralPath $resolver)) { exit 0 }

    . $resolver
    Import-Module (Join-Path $hubRoot 'lib/model-router/ModelRouter.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue
    $rankRequests = @(Resolve-ModelRouterAllowedRanks -Prompt $prompt)
    $extra = Get-TaskRouterPlanExtraText -Prompt $prompt -HubRoot $hubRoot
    $result = if ($rankRequests.Count -gt 0) {
        Resolve-TaskRoute -Prompt $prompt -ExtraText $extra -HubRoot $hubRoot -Source 'user' -NoLog
    }
    else {
        Resolve-TaskRoute -Prompt $prompt -ExtraText $extra -HubRoot $hubRoot -Source 'user'
    }

    if ($rankRequests.Count -gt 0) {
        $result.Advisor = $false
        $result.RequiredActions = @($result.RequiredActions | Where-Object { $_ -ne 'route_advisor' })
        $result.Inject = $true
        $routeIds = @($result.Matches | ForEach-Object { $_.Id })
        $stage = if ($result.PSObject.Properties['Stage']) { [string]$result.Stage } else { '' }
        $confidence = if ($result.PSObject.Properties['Confidence']) { [double]$result.Confidence } else { 0.0 }
        $latencyMs = if ($result.PSObject.Properties['LatencyMs']) { [double]$result.LatencyMs } else { 0.0 }
        $semantic = if ($result.PSObject.Properties['Semantic']) { [bool]$result.Semantic } else { $false }
        Write-TaskRouterLog -HubRoot $hubRoot -Source 'user' -Fingerprint ([string]$result.Fingerprint) `
            -Matched:($routeIds.Count -gt 0) -RouteIds $routeIds -Score ([int]$result.TopScore) `
            -Advisor:$false -PromptLen $prompt.Length -Skipped $null `
            -Stage $stage -Confidence $confidence -RequiredActions @($result.RequiredActions) `
            -LatencyMs $latencyMs -Semantic:$semantic
    }
    $block = Format-TaskRouteContext -ResolveResult $result

    $modelBlock = ''
    if ($rankRequests.Count -gt 0) {
        $rankLabel = ($rankRequests -replace '^rank1_5$', 'R1.5' -replace '^rank2$', 'R2' -replace '^rank3$', 'R3') -join ','
        $rolloutPath = Join-Path $hubRoot 'lib/model-router/rollout.json'
        $rolloutMode = 'shadow'
        if (Test-Path -LiteralPath $rolloutPath) {
            $rolloutMode = [string](Get-Content -LiteralPath $rolloutPath -Raw -Encoding UTF8 | ConvertFrom-Json).mode
        }
        $modelAction = if ($rolloutMode -eq 'active') {
            'keep Cursor as the tool parent; use model-worker MCP route_preview/delegate for intellectual stages.'
        }
        else {
            'shadow only: call model-worker route_preview and log the recommendation; do not auto-delegate.'
        }
        $modelBlock = @"
[MODEL ROUTE]
AllowedRanks: $rankLabel
Rollout: $rolloutMode
Action: $modelAction
Selection: quality floor, role, runtime health, live price, and latency; the listed ranks are a pool, not a first-match choice.
Budget: reserve atomically, check the shared-key remainder, and ask for a separate yes before an unpriced model.
Fallback: use the scored provider/model circuit-breaker chain. Terminal model-route.ps1 remains the post-limit text fallback.
"@
    }

    $contextParts = @($block, $modelBlock) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($contextParts.Count -eq 0) { exit 0 }
    $combinedBlock = $contextParts -join "`n`n"

    $out = @{
        hookSpecificOutput = @{
            hookEventName     = 'UserPromptSubmit'
            additionalContext = $combinedBlock
        }
    } | ConvertTo-Json -Compress -Depth 6

    Write-Output $out
    exit 0
}
catch {
    exit 0
}

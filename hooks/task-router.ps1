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
    $extra = Get-TaskRouterPlanExtraText -Prompt $prompt -HubRoot $hubRoot
    $result = Resolve-TaskRoute -Prompt $prompt -ExtraText $extra -HubRoot $hubRoot -Source 'user'

    $rankRequest = $null
    if ($prompt -match '(?i)(?<![0-9a-z_])r(?:ank)?\s*1[\.,]5(?![0-9a-z_])') { $rankRequest = 'R1.5' }
    elseif ($prompt -match '(?i)(?<![0-9a-z_])r(?:ank)?\s*2(?![0-9a-z_])') { $rankRequest = 'R2' }
    elseif ($prompt -match '(?i)(?<![0-9a-z_])r(?:ank)?\s*3(?![0-9a-z_])') { $rankRequest = 'R3' }

    if ($rankRequest) {
        $result.Advisor = $false
        $result.RequiredActions = @($result.RequiredActions | Where-Object { $_ -ne 'route_advisor' })
        $result.Inject = $true
    }
    $block = Format-TaskRouteContext -ResolveResult $result

    $modelBlock = ''
    if ($rankRequest) {
        $modelBlock = @"
[MODEL ROUTE]
Requested: $rankRequest
Action: use commands/model-route.ps1 with the original prompt for text/planning work.
Budget: refresh live OpenRouter prices, calculate an automatic hard cap, and ask only when price cannot be calculated.
Fallback: use the rank-local health-aware chain; never substitute a Cursor Task model.
Post-limit: the terminal command remains available, but this hook cannot replace Cursor file/command tools.
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

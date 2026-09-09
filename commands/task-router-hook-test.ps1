param([string]$HubRoot = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = "Stop"
$previousOutputEncoding = $OutputEncoding
$OutputEncoding = [Text.UTF8Encoding]::new($false)

function Invoke-TaskRouterHook {
    param([string]$HookPath, [hashtable]$Payload)
    $json = $Payload | ConvertTo-Json -Compress -Depth 10
    $raw = $json | & powershell -NoProfile -ExecutionPolicy Bypass -File $HookPath
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

try {
    $userHook = Join-Path $HubRoot "hooks/task-router.ps1"
    $taskHook = Join-Path $HubRoot "hooks/task-router-task.ps1"
    $nonce = Get-Random
    $architecturePrompt = "design how all system parts should connect probe-$nonce"

    $architecture = Invoke-TaskRouterHook -HookPath $userHook -Payload @{
        prompt = $architecturePrompt
    }
    $context = [string]$architecture.hookSpecificOutput.additionalContext
    if ($context -notmatch '\[TASK PREFLIGHT\]' -or
        $context -notmatch 'architecture_plan' -or
        $context -notmatch 'wbs' -or
        $context -notmatch 'fp=') {
        throw "User hook missed systemic preflight contract"
    }

    $ambiguous = Invoke-TaskRouterHook -HookPath $userHook -Payload @{
        prompt = "Help me make this thing better without technical words probe-$nonce"
    }
    $ambiguousContext = [string]$ambiguous.hookSpecificOutput.additionalContext
    if ($ambiguousContext -notmatch 'TASK ROUTE - advisor' -or
        $ambiguousContext -notmatch 'Parent MUST spawn route-advisor') {
        throw "User hook did not enforce advisor"
    }

    $social = Invoke-TaskRouterHook -HookPath $userHook -Payload @{ prompt = "hi" }
    if ($social) { throw "Social prompt should not inject route context" }

    $ranked = Invoke-TaskRouterHook -HookPath $userHook -Payload @{
        prompt = "R2, R1.5 make this thing better probe-$nonce"
    }
    $rankedContext = [string]$ranked.hookSpecificOutput.additionalContext
    if ($rankedContext -notmatch '\[MODEL ROUTE\]' -or
        $rankedContext -notmatch 'AllowedRanks: R2,R1.5' -or
        $rankedContext -match 'TASK ROUTE - advisor') {
        throw "Mixed-rank hook binding failed"
    }
    $fingerprintMatch = [Regex]::Match($rankedContext, 'fp=([0-9a-f]+)')
    if (-not $fingerprintMatch.Success) { throw "Mixed-rank context missed fingerprint" }
    $rankedLog = Get-Content (Join-Path $HubRoot 'ai-tracking/task-router-log.jsonl') -Encoding UTF8 |
        ForEach-Object { $_ | ConvertFrom-Json } |
        Where-Object { $_.fp -eq $fingerprintMatch.Groups[1].Value } |
        Select-Object -Last 1
    if (-not $rankedLog -or $rankedLog.advisor -or $rankedLog.routeIds -notcontains 'openrouter-free') {
        throw "Final rank override diverged from Task Router telemetry"
    }
    $parsedTimestamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$rankedLog.ts, [ref]$parsedTimestamp) -or
        $parsedTimestamp.Offset -ne [TimeSpan]::Zero) {
        throw "Task Router telemetry timestamp is not UTC ISO"
    }

    $subagent = Invoke-TaskRouterHook -HookPath $taskHook -Payload @{
        tool_name = "Subagent"
        tool_input = @{
            description = "CI investigation"
            prompt = "why is CI failing on github probe-$nonce"
            subagent_type = "ci-investigator"
        }
    }
    $updatedPrompt = [string]$subagent.updated_input.prompt
    if ($updatedPrompt -notmatch 'P:ci-debug' -or
        $updatedPrompt -notmatch 'EPHEMERAL AGENT CONTRACT' -or
        $updatedPrompt -notmatch 'GOAL, EVIDENCE, DECISION') {
        throw "Subagent hook missed routed report contract"
    }

    $ambiguousSubagent = Invoke-TaskRouterHook -HookPath $taskHook -Payload @{
        tool_name = "Subagent"
        tool_input = @{
            description = "Ambiguous work"
            prompt = "make this thing better somehow probe-$nonce"
            subagent_type = "generalPurpose"
        }
    }
    $ambiguousSubagentPrompt = [string]$ambiguousSubagent.updated_input.prompt
    if ($ambiguousSubagentPrompt -match 'TASK ROUTE - advisor' -or
        $ambiguousSubagentPrompt -match 'route_advisor') {
        throw "Subagent hook must not create an advisor loop"
    }
    if ($ambiguousSubagentPrompt -notmatch 'return a blocker') {
        throw "Ambiguous subagent prompt missed fail-safe contract"
    }

    $budgetSession = "hook-budget-$nonce"
    foreach ($number in 1..3) {
        $allowed = Invoke-TaskRouterHook -HookPath $taskHook -Payload @{
            tool_name = "Subagent"
            conversation_id = $budgetSession
            tool_input = @{
                description = "Parallel probe $number"
                prompt = "why is CI failing probe-$nonce-$number"
                subagent_type = "ci-investigator"
                run_in_background = $true
            }
        }
        if ($allowed.permission -ne "allow") {
            throw "Background agent $number should fit the max-3 budget"
        }
    }
    $denied = Invoke-TaskRouterHook -HookPath $taskHook -Payload @{
        tool_name = "Subagent"
        conversation_id = $budgetSession
        tool_input = @{
            description = "Parallel probe 4"
            prompt = "why is CI failing probe-$nonce-4"
            subagent_type = "ci-investigator"
            run_in_background = $true
        }
    }
    if ($denied.permission -ne "deny" -or $denied.message -notmatch "maximum three") {
        throw "Fourth background agent was not blocked"
    }

    $env:TASK_ROUTER_BUDGET_FALLBACK_SESSION = "hook-fallback-$nonce"
    try {
        foreach ($number in 1..4) {
            $fallback = Invoke-TaskRouterHook -HookPath $taskHook -Payload @{
                tool_name = "Subagent"
                tool_input = @{
                    description = "Fallback budget probe $number"
                    prompt = "why is CI failing fallback-$nonce-$number"
                    subagent_type = "ci-investigator"
                    run_in_background = $true
                }
            }
            if ($number -le 3 -and $fallback.permission -eq "deny") {
                throw "Fallback budget blocked background agent $number too early"
            }
            if ($number -eq 4 -and $fallback.permission -ne "deny") {
                throw "Missing session id bypassed the max-3 budget"
            }
        }
    }
    finally {
        Remove-Item Env:TASK_ROUTER_BUDGET_FALLBACK_SESSION -ErrorAction SilentlyContinue
    }

    $alreadyRouted = Invoke-TaskRouterHook -HookPath $taskHook -Payload @{
        tool_name = "Task"
        tool_input = @{ prompt = "[TASK ROUTE]`nalready routed" }
    }
    if ($alreadyRouted) { throw "Already-routed Task should be skipped" }

    python (Join-Path $HubRoot "commands/task-router-hook-utf8-check.py")
    if ($LASTEXITCODE -ne 0) { throw "Raw UTF-8 hook probe failed" }

    $ruPassword = -join @(
        [char]0x043F, [char]0x0430, [char]0x0440,
        [char]0x043E, [char]0x043B, [char]0x044C
    )
    $receiptCommand = Join-Path $HubRoot "commands/task-router-receipt.ps1"
    & $receiptCommand -TaskFp "privacy-$nonce" -System "privacy_test" `
        -Why "${ruPassword}: hidden-value-$nonce" `
        -Evidence "OPENROUTER_API_KEY=hidden-key-$nonce" -HubRoot $HubRoot | Out-Null
    $receipt = Get-Content (Join-Path $HubRoot ".cache/task-router/receipts.jsonl") `
        -Tail 1 -Encoding UTF8 | ConvertFrom-Json
    if ($receipt.why -match "hidden-value" -or
        $receipt.evidence -match "hidden-key" -or
        $receipt.why -match '\$1') {
        throw "Receipt privacy redaction failed"
    }

    Write-Output "task-router hooks: ok"
}
finally {
    $OutputEncoding = $previousOutputEncoding
}

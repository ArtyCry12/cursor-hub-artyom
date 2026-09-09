param([string]$HubRoot = '')

$ErrorActionPreference = 'Stop'
if (-not $HubRoot) { $HubRoot = Split-Path $PSScriptRoot -Parent }
$wrapper = Join-Path $HubRoot 'skills/openrouter-free/scripts/openrouter.ps1'

$raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapper `
    -Action chat -Tier mid -BossYes -Model 'openai/gpt-5.6-luna-pro' `
    -Prompt 'legacy contract' -MaxOutputTokens 16 -BudgetUsd 0.1 -DryRun
if ($LASTEXITCODE -ne 0) { throw "Legacy Luna dry run failed: $raw" }
$result = $raw | ConvertFrom-Json
if (-not $result.ok -or -not $result.dryRun) { throw 'Legacy chat did not delegate to router dry run' }
if ($result.model -ne 'openai/gpt-5.6-luna-pro') { throw 'Legacy model selection changed' }
if ($result.effort -ne 'max') { throw 'Legacy Luna did not enforce max effort' }
if (-not $result.estimate.reliable -or $result.estimate.worstUsd -le 0) {
    throw 'Legacy paid route bypassed pricing'
}
if ($result.budgetUsd -lt $result.estimate.worstUsd) { throw 'Legacy paid route bypassed budget preflight' }

$source = Get-Content -LiteralPath $wrapper -Raw -Encoding UTF8
$chatStart = $source.IndexOf("if (`$Action -eq 'chat') {", [StringComparison]::Ordinal)
$ttsStart = $source.IndexOf('# tts', $chatStart + 1, [StringComparison]::Ordinal)
if ($chatStart -lt 0 -or $ttsStart -lt 0) { throw 'Legacy chat branch was not found' }
$chatBranch = $source.Substring($chatStart, $ttsStart - $chatStart)
if ($chatBranch -match 'Invoke-JsonPost') {
    throw 'Legacy chat still contains a direct OpenRouter POST bypass'
}

Write-Output 'model-router legacy contracts: ok'

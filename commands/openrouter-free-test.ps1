# OpenRouter health check. Never prints the API key. TTS uses -NoPlay.
param(
  [string]$HubRoot = "",
  [switch]$ProbeMid,
  [string]$SttAudioPath = "",
  [switch]$BossYes
)

$ErrorActionPreference = 'Stop'
if (-not $HubRoot) { $HubRoot = Split-Path $PSScriptRoot -Parent }

$script = Join-Path $HubRoot 'skills/openrouter-free/scripts/openrouter.ps1'
$outPath = Join-Path $HubRoot 'ai-tracking/openrouter-free-health.json'
$stamp = (Get-Date).ToUniversalTime().ToString('o')

function Write-Health($obj) {
  $dir = Split-Path $outPath -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  ($obj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $outPath -Encoding UTF8
}

function Key-Status {
  $map = @{}
  foreach ($s in @('Process', 'User', 'Machine')) {
    $v = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', $s)
    $map[$s] = [bool]$v
  }
  return $map
}

function ConvertFrom-WrapperOutput($raw) {
  $chunk = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_.Trim().StartsWith('{') })
  if ($chunk.Count -eq 0) { throw 'wrapper printed no JSON object' }
  return ($chunk[-1] | ConvertFrom-Json)
}

function Get-SafePingLabel($label) {
  $s = [string]$label
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  if ($s -match 'sk-or-') { return 'set' }
  return $s
}

function Set-ModelStatus([hashtable]$Models, [string]$Slug, [string]$Status, [string]$Err) {
  $Models[$Slug] = @{ status = $Status; lastError = $Err }
}

$keyMap = Key-Status
$keyOk = $keyMap.User -or $keyMap.Process -or $keyMap.Machine
$keyStatus = if ($keyOk) { 'unknown' } else { 'missing' }
$ping = $null
$chat = $null
$tts = $null
$stt = $null
$sttSkipped = $true
$lastAction = 'none'
$models = @{}
$errors = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $script)) {
  $errors.Add('wrapper_missing')
}

if (-not $keyOk) {
  $errors.Add('OPENROUTER_API_KEY missing in Process/User/Machine')
}

if ($keyOk) {
  try {
    $pingRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Action ping
    $ping = ConvertFrom-WrapperOutput $pingRaw
    $lastAction = 'ping'
    if (-not $ping.ok) {
      $perr = $(if ($ping.error) { "ping: $($ping.error)" } else { 'ping_not_ok' })
      $errors.Add($perr)
      if ($perr -match '401') { $keyStatus = 'dead' }
    }
    else {
      $keyStatus = 'ok'
    }
  }
  catch {
    $errors.Add("ping: $($_.Exception.Message)")
    $lastAction = 'ping'
  }

  try {
    $chatRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Action chat -Prompt 'Reply with exactly OK' 2>&1
    $chat = ConvertFrom-WrapperOutput $chatRaw
    $lastAction = 'chat'
    if (-not $chat.ok) {
      $err = $(if ($chat.error) { [string]$chat.error } else { 'chat_not_ok' })
      $errors.Add($err)
      if ($err -match '401') {
        $keyStatus = 'dead'
        Set-ModelStatus $models 'z-ai/glm-5.2:free' 'unknown' 'skipped - key 401 (not model delist)'
      }
      else {
        $failSlug = 'z-ai/glm-5.2:free'
        if ($err -match '^([^:\s]+/[^:\s]+(?::free)?)\s*:') { $failSlug = $Matches[1] }
        # 429 = rate; 403 = provider forbid on fallback — not model delist / not dead key
        $st = if ($err -match '404|delist|not.?found') { 'unavailable' } else { 'degraded' }
        Set-ModelStatus $models $failSlug $st $err
      }
    }
    else {
      Set-ModelStatus $models ([string]$chat.model) 'ok' $null
      if ([string]$chat.text -notmatch 'OK') { $errors.Add('chat_unexpected_text') }
    }
  }
  catch {
    $errors.Add("chat: $($_.Exception.Message)")
    $lastAction = 'chat'
  }

  # TTS smoke with -NoPlay (do not open player). Skip hard-fail if free TTS rate-limits.
  try {
    $ttsRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Action tts -Prompt 'OK' -NoPlay 2>&1
    $tts = ConvertFrom-WrapperOutput $ttsRaw
    $lastAction = 'tts'
    if ($tts.ok) {
      Set-ModelStatus $models ([string]$tts.model) 'ok' $null
    }
    else {
      $terr = $(if ($tts.error) { [string]$tts.error } else { 'tts_not_ok' })
      if ($terr -match '401') {
        $keyStatus = 'dead'
        Set-ModelStatus $models 'fish-audio/s2.1-pro-free:free' 'unknown' 'skipped - key 401 (not model delist)'
        $errors.Add("tts: $terr")
      }
      else {
        Set-ModelStatus $models 'fish-audio/s2.1-pro-free:free' $(if ($terr -match '404|delist|not.?found') { 'unavailable' } else { 'degraded' }) $terr
        if ($terr -notmatch '429|403') { $errors.Add("tts: $terr") }
      }
    }
  }
  catch {
    $errors.Add("tts: $($_.Exception.Message)")
  }

  if ($ProbeMid) {
    if (-not $BossYes) {
      $errors.Add('mid: BossYes required (-BossYes) for -ProbeMid')
    }
    else {
      try {
        $midRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Action chat -Tier mid -BossYes -Prompt 'Reply with exactly OK' 2>&1
        $mid = ConvertFrom-WrapperOutput $midRaw
        $lastAction = 'chat'
        if ($mid.ok) {
          Set-ModelStatus $models ([string]$mid.model) 'ok' $null
        }
        else {
          $merr = $(if ($mid.error) { [string]$mid.error } else { 'mid_not_ok' })
          $errors.Add("mid: $merr")
        }
      }
      catch {
        $errors.Add("mid: $($_.Exception.Message)")
      }
    }
  }

  if ($SttAudioPath) {
    $sttSkipped = $false
    if (-not $BossYes) {
      $errors.Add('stt: BossYes required (-BossYes) for -SttAudioPath')
    }
    else {
      try {
        $sttRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Action stt -BossYes -AudioPath $SttAudioPath 2>&1
        $stt = ConvertFrom-WrapperOutput $sttRaw
        $lastAction = 'stt'
        if ($stt.ok) {
          Set-ModelStatus $models ([string]$stt.model) 'ok' $null
        }
        elseif ($stt.skipped) {
          $serr = $(if ($stt.error) { [string]$stt.error } else { 'stt_skipped' })
          Set-ModelStatus $models 'microsoft/mai-transcribe-2' 'unknown' "skipped: $serr"
          # honest skip — not architecture ERROR, not model dead
        }
        else {
          $serr = $(if ($stt.error) { [string]$stt.error } else { 'stt_not_ok' })
          if ($serr -match '401') {
            $keyStatus = 'dead'
            Set-ModelStatus $models 'microsoft/mai-transcribe-2' 'unknown' 'skipped - key 401 (not model delist)'
            $errors.Add("stt: key 401 (not model delist)")
          }
          else {
            # Runtime errors are historical; never permanently ban a model after one probe.
            $st = if ($serr -match '404|delist|not.?found') { 'unavailable' } else { 'degraded' }
            Set-ModelStatus $models 'microsoft/mai-transcribe-2' $st $serr
            $errors.Add("stt: $serr")
          }
        }
      }
      catch {
        $errors.Add("stt: $($_.Exception.Message)")
      }
    }
  }
  else {
    $sttSkipped = $true
  }
}

$errList = @($errors)
$is429 = ($errList -join ' ') -match '429'
$health = [ordered]@{
  checkedAt   = $stamp
  ok          = ($errors.Count -eq 0)
  keyPresent  = $keyOk
  keyScopes   = $keyMap
  pingOk      = [bool]($ping -and $ping.ok)
  pingLabel   = if ($ping) { Get-SafePingLabel $ping.label } else { $null }
  chatOk      = [bool]($chat -and $chat.ok)
  chatModel   = if ($chat) { [string]$chat.model } else { $null }
  chatError   = if ($chat -and $chat.error) { [string]$chat.error } else { $null }
  ttsOk       = [bool]($tts -and $tts.ok)
  lastAction  = $lastAction
  sttSkipped  = $sttSkipped
  keyStatus   = $keyStatus
  models      = $models
  errors      = $errList
  repeating   = $is429
  notes       = 'Legacy free/TTS/STT health. Key never stored. Runtime failures degrade/unavailable; they never permanently ban a model. Ranked R1.5/R2 health lives in model-router-health.json. ProbeMid/STT retain -BossYes.'
}

Write-Health $health
Write-Output ($health | ConvertTo-Json -Compress -Depth 8)
if (-not $health.ok) { exit 1 }
exit 0

# OpenRouter wrapper (free + mid). Never prints the API key.
param(
  [Parameter(Mandatory)]
  [ValidateSet('chat', 'tts', 'stt', 'ping')]
  [string]$Action,
  [string]$Prompt,
  [string]$PromptFile,
  [string]$OutFile,
  [string]$AudioPath,
  [ValidateSet('free', 'mid')]
  [string]$Tier = 'free',
  [string]$Model,
  [switch]$NoPlay,
  [switch]$BossYes
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$HubRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$LadderPath = Join-Path $HubRoot 'ai-tracking\model-ladder.json'

function Get-OpenRouterKey {
  foreach ($scope in @('Process', 'User')) {
    $k = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', $scope)
    if ($k) { return $k }
  }
  throw 'OPENROUTER_API_KEY is not set (Windows user env).'
}

function Get-UserText {
  if ($PromptFile) {
    if (-not (Test-Path -LiteralPath $PromptFile)) { throw "Prompt file not found: $PromptFile" }
    return [IO.File]::ReadAllText($PromptFile, [Text.UTF8Encoding]::new($false))
  }
  if (-not [string]::IsNullOrWhiteSpace($Prompt)) { return $Prompt }
  if ([Console]::IsInputRedirected) { return [Console]::In.ReadToEnd() }
  throw 'Pass -Prompt, -PromptFile, or stdin.'
}

function Get-Headers([string]$Key) {
  return @{
    Authorization        = "Bearer $Key"
    'HTTP-Referer'       = 'https://cursor.local/hub'
    'X-OpenRouter-Title' = 'cursor-hub-openrouter'
  }
}

function Write-Result($obj) {
  $obj | ConvertTo-Json -Compress -Depth 6
}

function Invoke-JsonPost([string]$Url, [hashtable]$Headers, [hashtable]$Body, [int]$TimeoutSec) {
  $json = $Body | ConvertTo-Json -Compress -Depth 8
  return Invoke-RestMethod -Uri $Url -Method POST -Headers $Headers -ContentType 'application/json; charset=utf-8' -Body $json -TimeoutSec $TimeoutSec
}

function Get-LadderModels([string]$RankKey) {
  if (-not (Test-Path -LiteralPath $LadderPath)) { return $null }
  $ladder = Get-Content -LiteralPath $LadderPath -Raw -Encoding UTF8 | ConvertFrom-Json
  return $ladder.$RankKey
}

function Get-FreeTextModels {
  $rank3 = Get-LadderModels 'rank3'
  if ($rank3 -and $rank3.textOrder) {
    $list = @()
    foreach ($slug in @($rank3.textOrder)) {
      $m = $rank3.models.$slug
      if ($m -and $m.status -eq 'banned') { continue }
      if ($m -and $m.status -eq 'dead') { continue }
      $list += $slug
    }
    if ($list.Count -gt 0) { return $list }
  }
  return @('z-ai/glm-5.2:free', 'minimax/minimax-m3:free', 'thinkingmachines/inkling:free')
}

function Get-MidChatModels {
  $rank2 = Get-LadderModels 'rank2'
  if ($rank2 -and $rank2.chatOrder) {
    $list = @()
    foreach ($slug in @($rank2.chatOrder)) {
      $m = $rank2.models.$slug
      if ($m -and $m.status -eq 'banned') { continue }
      if ($m -and $m.status -eq 'dead') { continue }
      $list += $slug
    }
    if ($list.Count -gt 0) { return $list }
  }
  return @(
    'openai/gpt-5.6-luna-pro',
    'z-ai/glm-5.2',
    'deepseek/deepseek-v4-pro-0813',
    'deepseek/deepseek-v4-flash-0731',
    'z-ai/glm-5.3-flash',
    'google/gemini-3.8-flash'
  )
}

function Get-Rank2SlugSet {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($s in @(Get-MidChatModels)) { [void]$set.Add($s) }
  [void]$set.Add('microsoft/mai-transcribe-2')
  $rank2 = Get-LadderModels 'rank2'
  if ($rank2 -and $rank2.models) {
    foreach ($p in $rank2.models.PSObject.Properties) { [void]$set.Add([string]$p.Name) }
  }
  return $set
}

function Test-NeedsBossYes {
  if ($Action -eq 'stt') { return $true }
  if ($Tier -eq 'mid') { return $true }
  if ($Model -and (Get-Rank2SlugSet).Contains($Model)) { return $true }
  return $false
}

function Assert-BossYesOrExit {
  if ($BossYes) { return }
  if (-not (Test-NeedsBossYes)) { return }
  Write-Result @{
    ok      = $false
    action  = $Action
    tier    = $Tier
    model   = $Model
    error   = 'BossYes required for Rank2 mid/STT (or Rank2 -Model). Ask Boss, then re-run with -BossYes.'
    code    = 'boss_yes_required'
  }
  exit 3
}

Assert-BossYesOrExit

$key = Get-OpenRouterKey
$headers = Get-Headers $key

if ($Action -eq 'ping') {
  try {
    $r = Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/key' -Headers $headers -TimeoutSec 30
    $label = $null
    if ($r.data) { $label = [string]$r.data.label }
    if ($label -match 'sk-or-') { $label = 'set' }
    Write-Result @{ ok = $true; action = 'ping'; label = $label }
    exit 0
  }
  catch {
    Write-Result @{ ok = $false; action = 'ping'; error = $_.Exception.Message }
    exit 1
  }
}

if ($Action -eq 'stt') {
  if ([string]::IsNullOrWhiteSpace($AudioPath)) {
    Write-Result @{ ok = $false; action = 'stt'; skipped = $true; error = 'Pass -AudioPath to a wav/mp3/ogg/flac/m4a file' }
    exit 2
  }
  if (-not (Test-Path -LiteralPath $AudioPath)) {
    Write-Result @{ ok = $false; action = 'stt'; skipped = $true; error = "Audio not found: $AudioPath" }
    exit 2
  }
  $sttModel = if ($Model) { $Model } else { 'microsoft/mai-transcribe-2' }
  $ext = [IO.Path]::GetExtension($AudioPath).TrimStart('.').ToLowerInvariant()
  if (-not $ext) { $ext = 'wav' }
  $allowedFmt = @('wav', 'mp3', 'flac', 'm4a', 'ogg', 'webm', 'aac')
  if ($allowedFmt -notcontains $ext) {
    Write-Result @{ ok = $false; action = 'stt'; skipped = $true; model = $sttModel; error = "Unsupported audio format: .$ext (use wav/mp3/ogg or ffmpeg)" }
    exit 2
  }
  # JSON base64 path — OpenRouter primary STT contract; avoids .NET multipart body bugs.
  $fileBytes = [IO.File]::ReadAllBytes($AudioPath)
  $b64 = [Convert]::ToBase64String($fileBytes)
  $headers = Get-Headers $key
  $body = @{
    model       = $sttModel
    input_audio = @{
      data   = $b64
      format = $ext
    }
  }
  try {
    $parsed = Invoke-JsonPost 'https://openrouter.ai/api/v1/audio/transcriptions' $headers $body 120
    $outText = [string]$parsed.text
    Write-Result @{ ok = $true; action = 'stt'; model = $sttModel; text = $outText }
    exit 0
  }
  catch {
    Write-Result @{ ok = $false; action = 'stt'; model = $sttModel; error = $_.Exception.Message }
    exit 1
  }
}

$text = Get-UserText
if ([string]::IsNullOrWhiteSpace($text)) { throw 'Empty prompt.' }

if ($Action -eq 'chat') {
  if ($Model) {
    $tryModels = @($Model)
  }
  elseif ($Tier -eq 'mid') {
    $tryModels = Get-MidChatModels
  }
  else {
    $tryModels = Get-FreeTextModels
  }
  $lastErr = $null
  foreach ($m in $tryModels) {
    $body = @{
      model    = $m
      messages = @(@{ role = 'user'; content = $text })
    }
    try {
      $parsed = Invoke-JsonPost 'https://openrouter.ai/api/v1/chat/completions' $headers $body 120
      $outText = ''
      if ($parsed.choices -and $parsed.choices.Count -gt 0) {
        $outText = [string]$parsed.choices[0].message.content
      }
      Write-Result @{
        ok     = $true
        action = 'chat'
        tier   = $Tier
        model  = [string]$parsed.model
        text   = $outText
      }
      exit 0
    }
    catch {
      $lastErr = "$m : $($_.Exception.Message)"
      # R3 free 429 = brief retry; R2 429 left to caller (stop-ask).
      if ($Tier -eq 'free' -and $lastErr -match '429') { Start-Sleep -Seconds 2 }
    }
  }
  Write-Result @{
    ok     = $false
    action = 'chat'
    tier   = $Tier
    error  = $lastErr
  }
  exit 1
}

# tts
$cache = Join-Path $env:USERPROFILE '.cursor\.cache\openrouter-tts'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
if ([string]::IsNullOrWhiteSpace($OutFile)) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $OutFile = Join-Path $cache "tts-$stamp.mp3"
}

$ttsModel = if ($Model) { $Model } else { 'fish-audio/s2.1-pro-free:free' }
$attempts = @(
  @{ model = $ttsModel; extra = @{} }
)
$lastErr = $null
foreach ($a in $attempts) {
  $body = @{
    model           = $a.model
    input           = $text
    response_format = 'mp3'
  }
  foreach ($k in $a.extra.Keys) { $body[$k] = $a.extra[$k] }
  try {
    $json = $body | ConvertTo-Json -Compress -Depth 6
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $res = Invoke-WebRequest -Uri 'https://openrouter.ai/api/v1/audio/speech' -Method POST -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 120 -OutFile $OutFile -PassThru -UseBasicParsing
    if ($res.StatusCode -ge 200 -and $res.StatusCode -lt 300 -and (Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
      if (-not $NoPlay) { Start-Process -FilePath $OutFile | Out-Null }
      Write-Result @{ ok = $true; action = 'tts'; model = $a.model; file = $OutFile; played = (-not $NoPlay) }
      exit 0
    }
    $lastErr = "HTTP $($res.StatusCode) on $($a.model)"
  }
  catch {
    $lastErr = "$($a.model): $($_.Exception.Message)"
    if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue }
  }
}

Write-Result @{ ok = $false; action = 'tts'; error = $lastErr }
exit 1

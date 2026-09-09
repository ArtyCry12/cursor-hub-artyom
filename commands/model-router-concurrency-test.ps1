param([string]$HubRoot = '')

$ErrorActionPreference = 'Stop'
if (-not $HubRoot) { $HubRoot = Split-Path $PSScriptRoot -Parent }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("model-router-race-" + [Guid]::NewGuid().ToString('N'))
$stateRoot = Join-Path $testRoot 'state'
$workerPath = Join-Path $testRoot 'worker.ps1'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

$worker = @'
param(
    [string]$ModulePath,
    [string]$HubRoot,
    [string]$StateRoot,
    [string]$CallId,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
Import-Module $ModulePath -Force -DisableNameChecking -WarningAction SilentlyContinue
$result = Reserve-ModelRouterBudget -HubRoot $HubRoot -SessionId 'race' -CallId $CallId `
    -AmountUsd 0.03 -BudgetUsd 0.1 -Model 'test/race' -StateRoot $StateRoot
$result | ConvertTo-Json -Compress -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
'@
$worker | Set-Content -LiteralPath $workerPath -Encoding UTF8
$modulePath = Join-Path $HubRoot 'lib/model-router/ModelRouter.psm1'
$processes = New-Object System.Collections.Generic.List[object]

try {
    foreach ($number in 1..8) {
        $outputPath = Join-Path $testRoot "result-$number.json"
        $arguments = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', "`"$workerPath`"",
            '-ModulePath', "`"$modulePath`"",
            '-HubRoot', "`"$HubRoot`"",
            '-StateRoot', "`"$stateRoot`"",
            '-CallId', "call-$number",
            '-OutputPath', "`"$outputPath`""
        ) -join ' '
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru -WindowStyle Hidden
        $processes.Add([PSCustomObject]@{ process = $process; output = $outputPath })
    }
    foreach ($item in $processes) {
        if (-not $item.process.WaitForExit(30000)) {
            $item.process.Kill()
            throw 'A reservation worker timed out'
        }
        if ($item.process.ExitCode -ne 0) { throw "Reservation worker failed: $($item.process.ExitCode)" }
    }
    $results = @($processes | ForEach-Object {
        Get-Content -LiteralPath $_.output -Raw -Encoding UTF8 | ConvertFrom-Json
    })
    $accepted = @($results | Where-Object { $_.ok }).Count
    if ($accepted -gt 3) { throw "Atomic cap failed: $accepted reservations were accepted" }
    $session = Get-Content -LiteralPath (Join-Path $stateRoot 'sessions/race.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([double]$session.reservedUsd -gt 0.10000001) {
        throw "Reserved amount exceeded cap: $($session.reservedUsd)"
    }
    if (@($session.reservations).Count -ne $accepted) {
        throw 'Ledger reservation count diverged from worker results'
    }
    Write-Output "model-router concurrency: ok ($accepted accepted, $($session.reservedUsd) USD reserved)"
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

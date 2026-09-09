function Get-ModelRouterRuntimeRoot {
    param(
        [string]$HubRoot = '',
        [string]$StateRoot = ''
    )
    if ($StateRoot) { return [IO.Path]::GetFullPath($StateRoot) }
    if ($env:MODEL_ROUTER_STATE_ROOT) { return [IO.Path]::GetFullPath($env:MODEL_ROUTER_STATE_ROOT) }
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    return (Join-Path $root '.cache/model-router')
}

function Get-SafeModelRouterSessionId {
    param([Parameter(Mandatory)][string]$SessionId)
    $safe = $SessionId -replace '[^0-9A-Za-z._-]', '_'
    $safe = $safe.Trim('.', '_')
    if (-not $safe) { $safe = 'default' }
    if ($safe.Length -gt 64) { $safe = $safe.Substring(0, 64) }
    return $safe
}

function Open-ModelRouterLock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$TimeoutMs = 10000
    )
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $deadline = [DateTimeOffset]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        try {
            return [IO.File]::Open($Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        catch [IO.IOException] {
            if ([DateTimeOffset]::UtcNow -ge $deadline) { throw "Timed out waiting for model-router lock: $Path" }
            Start-Sleep -Milliseconds 50
        }
    } while ($true)
}

function New-ModelRouterHealthState {
    return [PSCustomObject]@{
        schemaVersion = 2
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        key = [PSCustomObject]@{
            status = 'unknown'
            checkedAt = $null
            lastError = ''
        }
        models = [PSCustomObject]@{}
        events = @()
    }
}

function Get-ModelRouterHealthPath {
    param(
        [string]$HubRoot = '',
        [string]$StateRoot = ''
    )
    return (Join-Path (Get-ModelRouterRuntimeRoot -HubRoot $HubRoot -StateRoot $StateRoot) 'health.json')
}

function Get-ModelRouterHealthState {
    param(
        [string]$HubRoot = '',
        [string]$StateRoot = ''
    )
    $path = Get-ModelRouterHealthPath -HubRoot $HubRoot -StateRoot $StateRoot
    $state = Read-ModelRouterJson -Path $path
    if ($state) { return $state }
    $root = Get-ModelRouterHubRoot -HubRoot $HubRoot
    $legacyPath = Join-Path $root 'ai-tracking/model-router-health.json'
    $legacy = Read-ModelRouterJson -Path $legacyPath
    $state = New-ModelRouterHealthState
    if ($legacy -and $legacy.events) {
        foreach ($event in @($legacy.events)) {
            $status = [string]$event.status
            $category = switch ($status) {
                'live' { 'success' }
                'unavailable' { 'not-found' }
                'catalog-missing' { 'catalog-missing' }
                default { 'provider-error' }
            }
            Set-ModelRouterHealthEventInState -State $state -Model ([string]$event.model) `
                -Status $status -Category $category -Error ([string]$event.error) -At ([string]$event.at)
        }
    }
    return $state
}

function Get-ModelRouterDefaultModelHealth {
    param([Parameter(Mandatory)][string]$Model)
    return [PSCustomObject]@{
        model = $Model
        status = 'unknown'
        circuit = 'closed'
        consecutiveFailures = 0
        successes = 0
        failures = 0
        checkedAt = $null
        openUntil = $null
        halfOpenInFlight = $false
        lastError = ''
        lastCategory = ''
        latencyMs = $null
        retryEligible = $true
    }
}

function Get-ModelRouterModelHealth {
    param(
        [Parameter(Mandatory)][string]$Model,
        [string]$HubRoot = '',
        [string]$StateRoot = '',
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
    )
    $state = Get-ModelRouterHealthState -HubRoot $HubRoot -StateRoot $StateRoot
    $property = $state.models.PSObject.Properties[$Model]
    if (-not $property) { return (Get-ModelRouterDefaultModelHealth -Model $Model) }
    $source = $property.Value
    $circuit = [string]$source.circuit
    $retryEligible = $true
    if ($circuit -eq 'half-open' -and [bool]$source.halfOpenInFlight) {
        $retryEligible = $false
    }
    if ($circuit -eq 'open' -and $source.openUntil) {
        try {
            if ([DateTimeOffset]::Parse([string]$source.openUntil) -gt $Now) {
                $retryEligible = $false
            }
            else {
                $circuit = 'half-open'
                $retryEligible = -not [bool]$source.halfOpenInFlight
            }
        }
        catch {
            $circuit = 'half-open'
        }
    }
    return [PSCustomObject]@{
        model = $Model
        status = [string]$source.status
        circuit = $circuit
        consecutiveFailures = [int]$source.consecutiveFailures
        successes = [int]$source.successes
        failures = [int]$source.failures
        checkedAt = $source.checkedAt
        openUntil = $source.openUntil
        halfOpenInFlight = [bool]$source.halfOpenInFlight
        lastError = [string]$source.lastError
        lastCategory = [string]$source.lastCategory
        latencyMs = $source.latencyMs
        retryEligible = $retryEligible
    }
}

function Get-ModelRouterCircuitDurationSeconds {
    param(
        [Parameter(Mandatory)][string]$Category,
        [int]$ConsecutiveFailures
    )
    switch ($Category) {
        'not-found' { return 21600 }
        'catalog-missing' { return 3600 }
        'forbidden' { return 3600 }
        'rate-limited' { return 300 }
        'protocol-error' { return 600 }
        'provider-error' {
            if ($ConsecutiveFailures -ge 2) { return 120 }
            return 0
        }
        default { return 300 }
    }
}

function Set-ModelRouterHealthEventInState {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Category,
        [string]$Error = '',
        [Nullable[double]]$LatencyMs = $null,
        [string]$At = ''
    )
    if (-not $At) { $At = [DateTimeOffset]::UtcNow.ToString('o') }
    try { $At = [DateTimeOffset]::Parse($At).ToUniversalTime().ToString('o') } catch {}
    $property = $State.models.PSObject.Properties[$Model]
    $current = if ($property) { $property.Value } else { Get-ModelRouterDefaultModelHealth -Model $Model }
    $success = ($Category -eq 'success' -or $Status -eq 'live')
    $consecutive = if ($success) { 0 } else { [int]$current.consecutiveFailures + 1 }
    $duration = if ($success) { 0 } else { Get-ModelRouterCircuitDurationSeconds -Category $Category -ConsecutiveFailures $consecutive }
    $circuit = if ($duration -gt 0) { 'open' } else { 'closed' }
    $openUntil = if ($duration -gt 0) { [DateTimeOffset]::Parse($At).AddSeconds($duration).ToString('o') } else { $null }
    $entry = [PSCustomObject]@{
        status = if ($success) { 'live' } else { $Status }
        circuit = $circuit
        consecutiveFailures = $consecutive
        successes = [int]$current.successes + $(if ($success) { 1 } else { 0 })
        failures = [int]$current.failures + $(if ($success) { 0 } else { 1 })
        checkedAt = $At
        openUntil = $openUntil
        halfOpenInFlight = $false
        lastError = $Error
        lastCategory = $Category
        latencyMs = if ($null -ne $LatencyMs) { [Math]::Round([double]$LatencyMs, 3) } else { $current.latencyMs }
    }
    if ($property) { $property.Value = $entry } else { $State.models | Add-Member -NotePropertyName $Model -NotePropertyValue $entry }
    $events = @($State.events)
    $events += [PSCustomObject]@{
        at = $At
        model = $Model
        status = [string]$entry.status
        category = $Category
        error = $Error
        latencyMs = $entry.latencyMs
    }
    if ($events.Count -gt 300) { $events = @($events | Select-Object -Last 300) }
    $State.events = [object[]]$events
    $State.checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
}

function Write-ModelRouterHealthEvent {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Status,
        [string]$Category = '',
        [string]$Error = '',
        [Nullable[double]]$LatencyMs = $null,
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow,
        [string]$StateRoot = ''
    )
    if (-not $Category) {
        $Category = switch ($Status) {
            'live' { 'success' }
            'unavailable' { 'not-found' }
            'catalog-missing' { 'catalog-missing' }
            default { 'provider-error' }
        }
    }
    $path = Get-ModelRouterHealthPath -HubRoot $HubRoot -StateRoot $StateRoot
    $lock = Open-ModelRouterLock -Path "$path.lock"
    try {
        $state = Get-ModelRouterHealthState -HubRoot $HubRoot -StateRoot $StateRoot
        Set-ModelRouterHealthEventInState -State $state -Model $Model -Status $Status -Category $Category `
            -Error $Error -LatencyMs $LatencyMs -At $Now.ToUniversalTime().ToString('o')
        Write-ModelRouterAtomicJson -Path $path -Value $state
    }
    finally {
        $lock.Dispose()
    }
}

function Write-ModelRouterKeyHealthEvent {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)][string]$Status,
        [string]$Error = '',
        [string]$StateRoot = ''
    )
    $path = Get-ModelRouterHealthPath -HubRoot $HubRoot -StateRoot $StateRoot
    $lock = Open-ModelRouterLock -Path "$path.lock"
    try {
        $state = Get-ModelRouterHealthState -HubRoot $HubRoot -StateRoot $StateRoot
        $state.key = [PSCustomObject]@{
            status = $Status
            checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
            lastError = $Error
        }
        $state.checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        Write-ModelRouterAtomicJson -Path $path -Value $state
    }
    finally {
        $lock.Dispose()
    }
}

function Enter-ModelRouterCircuit {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)][string]$Model,
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow,
        [string]$StateRoot = ''
    )
    $path = Get-ModelRouterHealthPath -HubRoot $HubRoot -StateRoot $StateRoot
    $lock = Open-ModelRouterLock -Path "$path.lock"
    try {
        $state = Get-ModelRouterHealthState -HubRoot $HubRoot -StateRoot $StateRoot
        $property = $state.models.PSObject.Properties[$Model]
        if (-not $property) { return $true }
        $entry = $property.Value
        if ([string]$entry.circuit -eq 'half-open') {
            if ([bool]$entry.halfOpenInFlight) { return $false }
            $entry.halfOpenInFlight = $true
            Write-ModelRouterAtomicJson -Path $path -Value $state
            return $true
        }
        if ([string]$entry.circuit -ne 'open') { return $true }
        if ($entry.openUntil -and [DateTimeOffset]::Parse([string]$entry.openUntil) -gt $Now) { return $false }
        if ([bool]$entry.halfOpenInFlight) { return $false }
        $entry.circuit = 'half-open'
        $entry.halfOpenInFlight = $true
        Write-ModelRouterAtomicJson -Path $path -Value $state
        return $true
    }
    finally {
        $lock.Dispose()
    }
}

function Get-ModelRouterSessionPath {
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$HubRoot = '',
        [string]$StateRoot = ''
    )
    $safe = Get-SafeModelRouterSessionId -SessionId $SessionId
    return (Join-Path (Get-ModelRouterRuntimeRoot -HubRoot $HubRoot -StateRoot $StateRoot) "sessions/$safe.json")
}

function New-ModelRouterSession {
    param([Parameter(Mandatory)][string]$SessionId)
    return [PSCustomObject]@{
        schemaVersion = 2
        sessionId = (Get-SafeModelRouterSessionId -SessionId $SessionId)
        spentUsd = 0.0
        reservedUsd = 0.0
        reservations = @()
        calls = @()
    }
}

function Get-ModelRouterSession {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)][string]$SessionId,
        [string]$StateRoot = ''
    )
    $path = Get-ModelRouterSessionPath -SessionId $SessionId -HubRoot $HubRoot -StateRoot $StateRoot
    $session = Read-ModelRouterJson -Path $path
    if (-not $session) { return (New-ModelRouterSession -SessionId $SessionId) }
    if (-not $session.PSObject.Properties['reservedUsd']) { $session | Add-Member -NotePropertyName reservedUsd -NotePropertyValue 0.0 }
    if (-not $session.PSObject.Properties['reservations']) { $session | Add-Member -NotePropertyName reservations -NotePropertyValue @() }
    return $session
}

function Save-ModelRouterSession {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)]$Session,
        [string]$StateRoot = ''
    )
    $path = Get-ModelRouterSessionPath -SessionId ([string]$Session.sessionId) -HubRoot $HubRoot -StateRoot $StateRoot
    Write-ModelRouterAtomicJson -Path $path -Value $Session
}

function Reserve-ModelRouterBudget {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$CallId,
        [Parameter(Mandatory)][double]$AmountUsd,
        [Parameter(Mandatory)][double]$BudgetUsd,
        [Parameter(Mandatory)][string]$Model,
        [string]$StateRoot = ''
    )
    $path = Get-ModelRouterSessionPath -SessionId $SessionId -HubRoot $HubRoot -StateRoot $StateRoot
    $lock = Open-ModelRouterLock -Path "$path.lock"
    try {
        $session = Get-ModelRouterSession -HubRoot $HubRoot -SessionId $SessionId -StateRoot $StateRoot
        $existing = @($session.reservations | Where-Object { [string]$_.callId -eq $CallId })
        if ($existing.Count -gt 0) {
            return [PSCustomObject]@{ ok = $true; idempotent = $true; session = $session; reservation = $existing[0] }
        }
        $available = $BudgetUsd - [double]$session.spentUsd - [double]$session.reservedUsd
        if ($AmountUsd -gt $available) {
            return [PSCustomObject]@{
                ok = $false
                code = 'budget_cap'
                availableUsd = [Math]::Round($available, 8)
                requestedUsd = $AmountUsd
                session = $session
            }
        }
        $reservation = [PSCustomObject]@{
            callId = $CallId
            model = $Model
            amountUsd = [Math]::Round($AmountUsd, 8)
            at = [DateTimeOffset]::UtcNow.ToString('o')
        }
        $session.reservations = [object[]](@($session.reservations) + $reservation)
        $session.reservedUsd = [Math]::Round(([double]$session.reservedUsd + $AmountUsd), 8)
        Save-ModelRouterSession -HubRoot $HubRoot -Session $session -StateRoot $StateRoot
        return [PSCustomObject]@{ ok = $true; idempotent = $false; session = $session; reservation = $reservation }
    }
    finally {
        $lock.Dispose()
    }
}

function Complete-ModelRouterBudgetReservation {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$CallId,
        [Parameter(Mandatory)][double]$ActualUsd,
        [Parameter(Mandatory)]$Call,
        [double]$BudgetUsd = -1,
        [string]$StateRoot = ''
    )
    $path = Get-ModelRouterSessionPath -SessionId $SessionId -HubRoot $HubRoot -StateRoot $StateRoot
    $lock = Open-ModelRouterLock -Path "$path.lock"
    try {
        $session = Get-ModelRouterSession -HubRoot $HubRoot -SessionId $SessionId -StateRoot $StateRoot
        $reservation = @($session.reservations | Where-Object { [string]$_.callId -eq $CallId } | Select-Object -First 1)
        if ($reservation.Count -eq 0) {
            return [PSCustomObject]@{ ok = $false; code = 'reservation_missing'; session = $session }
        }
        $reserved = [double]$reservation[0].amountUsd
        $session.reservations = [object[]]@($session.reservations | Where-Object { [string]$_.callId -ne $CallId })
        $session.reservedUsd = [Math]::Max(0.0, [Math]::Round(([double]$session.reservedUsd - $reserved), 8))
        $session.spentUsd = [Math]::Round(([double]$session.spentUsd + $ActualUsd), 8)
        $session.calls = [object[]](@($session.calls) + $Call)
        if ($session.calls.Count -gt 500) { $session.calls = [object[]]@($session.calls | Select-Object -Last 500) }
        Save-ModelRouterSession -HubRoot $HubRoot -Session $session -StateRoot $StateRoot
        $overrun = ($ActualUsd -gt ($reserved + 0.00000001))
        if ($BudgetUsd -ge 0 -and [double]$session.spentUsd -gt ($BudgetUsd + 0.00000001)) { $overrun = $true }
        return [PSCustomObject]@{
            ok = (-not $overrun)
            code = if ($overrun) { 'budget_overrun' } else { 'settled' }
            reservedUsd = $reserved
            actualUsd = $ActualUsd
            session = $session
        }
    }
    finally {
        $lock.Dispose()
    }
}

function Undo-ModelRouterBudgetReservation {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$CallId,
        [string]$StateRoot = ''
    )
    $path = Get-ModelRouterSessionPath -SessionId $SessionId -HubRoot $HubRoot -StateRoot $StateRoot
    $lock = Open-ModelRouterLock -Path "$path.lock"
    try {
        $session = Get-ModelRouterSession -HubRoot $HubRoot -SessionId $SessionId -StateRoot $StateRoot
        $reservation = @($session.reservations | Where-Object { [string]$_.callId -eq $CallId } | Select-Object -First 1)
        if ($reservation.Count -eq 0) { return $session }
        $reserved = [double]$reservation[0].amountUsd
        $session.reservations = [object[]]@($session.reservations | Where-Object { [string]$_.callId -ne $CallId })
        $session.reservedUsd = [Math]::Max(0.0, [Math]::Round(([double]$session.reservedUsd - $reserved), 8))
        Save-ModelRouterSession -HubRoot $HubRoot -Session $session -StateRoot $StateRoot
        return $session
    }
    finally {
        $lock.Dispose()
    }
}

function Get-ModelRouterR3AllowlistPath {
    param(
        [string]$HubRoot = '',
        [string]$StateRoot = ''
    )
    return (Join-Path (Get-ModelRouterRuntimeRoot -HubRoot $HubRoot -StateRoot $StateRoot) 'r3-allowlist.json')
}

function Get-ModelRouterVerifiedR3Models {
    param(
        [string]$HubRoot = '',
        [string]$StateRoot = ''
    )
    $state = Read-ModelRouterJson -Path (Get-ModelRouterR3AllowlistPath -HubRoot $HubRoot -StateRoot $StateRoot)
    if (-not $state -or -not $state.models) { return [string[]]@() }
    return [string[]]@($state.models.PSObject.Properties | Where-Object { $_.Value.status -eq 'verified' } | ForEach-Object { $_.Name })
}

function Set-ModelRouterR3Verification {
    param(
        [Parameter(Mandatory)][string]$HubRoot,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][bool]$Verified,
        [string]$Reason = '',
        [string]$StateRoot = ''
    )
    $path = Get-ModelRouterR3AllowlistPath -HubRoot $HubRoot -StateRoot $StateRoot
    $lock = Open-ModelRouterLock -Path "$path.lock"
    try {
        $state = Read-ModelRouterJson -Path $path -Default ([PSCustomObject]@{
            schemaVersion = 1
            checkedAt = $null
            models = [PSCustomObject]@{}
        })
        $entry = [PSCustomObject]@{
            status = if ($Verified) { 'verified' } else { 'quarantined' }
            checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
            reason = $Reason
        }
        $property = $state.models.PSObject.Properties[$Model]
        if ($property) { $property.Value = $entry } else { $state.models | Add-Member -NotePropertyName $Model -NotePropertyValue $entry }
        $state.checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        Write-ModelRouterAtomicJson -Path $path -Value $state
    }
    finally {
        $lock.Dispose()
    }
}

[CmdletBinding()]
param(
    [ValidateRange(60, 1800)]
    [int]$TimeoutSeconds = 300,

    [switch]$KeepResources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BaselineHead = 'c2cc54065cf49410538f4abed850567741dee813'
$RuntimeSensitivePaths = @(
    '.env.example',
    'deploy/compose/backend.compose.yaml',
    'services/api/Dockerfile',
    'services/api/cmd',
    'services/api/db/migrations',
    'services/api/go.mod',
    'services/api/go.sum',
    'services/api/internal/kernel/config',
    'services/api/internal/kernel/health',
    'services/api/internal/platform/database'
)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ComposeFile = Join-Path $RepoRoot 'deploy/compose/backend.compose.yaml'
$EnvFile = Join-Path $RepoRoot '.env.example'
$ProjectSuffix = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$ProjectName = "flowlesshub-s02-accept-$ProjectSuffix"
$StackStarted = $false

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Compose {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & docker compose --env-file $script:EnvFile --project-name $script:ProjectName --file $script:ComposeFile @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Invoke-ComposeCapture {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = @(& docker compose --env-file $script:EnvFile --project-name $script:ProjectName --file $script:ComposeFile @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $detail = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
        throw "docker compose $($Arguments -join ' ') failed with exit code ${exitCode}: $detail"
    }

    return @($output | ForEach-Object { "$_" })
}

function Get-ServiceContainerId {
    param([Parameter(Mandatory)][string]$Service)

    $ids = @(Invoke-ComposeCapture -Arguments @('ps', '-a', '-q', $Service))
    $ids = @($ids | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($ids.Count -ne 1) {
        throw "Expected exactly one container for service '$Service'; found $($ids.Count)."
    }

    return $ids[0].Trim()
}

function Get-ContainerState {
    param([Parameter(Mandatory)][string]$ContainerId)

    $format = '{{.State.Status}}|{{.State.ExitCode}}|{{.RestartCount}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
    $result = & docker inspect --format $format $ContainerId 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "docker inspect failed for container $ContainerId`: $result"
    }

    $parts = ([string]$result).Trim() -split '\|', 4
    if ($parts.Count -ne 4) {
        throw "Unexpected docker inspect state response for container $ContainerId`: $result"
    }

    return [pscustomobject]@{
        Status       = $parts[0]
        ExitCode     = [int]$parts[1]
        RestartCount = [int]$parts[2]
        Health       = $parts[3]
    }
}

function Wait-ForContainerHealth {
    param([Parameter(Mandatory)][string]$Service)

    $containerId = Get-ServiceContainerId -Service $Service
    $deadline = (Get-Date).AddSeconds($script:TimeoutSeconds)
    do {
        $state = Get-ContainerState -ContainerId $containerId
        if ($state.Status -eq 'exited' -or $state.Status -eq 'dead') {
            throw "Service '$Service' stopped before becoming healthy (state=$($state.Status), exit=$($state.ExitCode))."
        }
        if ($state.Status -eq 'running' -and $state.Health -eq 'healthy') {
            Write-Host "$Service is healthy."
            return $state
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for service '$Service' to become healthy."
}

function Wait-ForMigrationExit {
    $containerId = Get-ServiceContainerId -Service 'migrate'
    $deadline = (Get-Date).AddSeconds($script:TimeoutSeconds)
    do {
        $state = Get-ContainerState -ContainerId $containerId
        if ($state.Status -eq 'exited') {
            if ($state.ExitCode -ne 0) {
                throw "Migration container exited with code $($state.ExitCode)."
            }
            Write-Host 'Migration service exited successfully.'
            return $state
        }
        if ($state.Status -eq 'dead') {
            throw 'Migration container entered the dead state.'
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for the migration service to exit."
}

function Wait-ForApiReady {
    $deadline = (Get-Date).AddSeconds($script:TimeoutSeconds)
    do {
        try {
            $response = Invoke-RestMethod -Uri 'http://127.0.0.1:5050/readyz' -TimeoutSec 5
            if ($response.status -eq 'ok') {
                Write-Host 'API readiness is OK.'
                return
            }
        }
        catch {
            # The API may need a short period to accept traffic after its container starts.
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    throw 'Timed out waiting for API /readyz to return status=ok.'
}

function Get-HttpStatusCode {
    param([Parameter(Mandatory)][string]$Uri)

    try {
        $response = Invoke-WebRequest -Uri $Uri -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        return [int]$response.StatusCode
    }
    catch {
        $response = $_.Exception.Response
        if ($null -ne $response) {
            return [int]$response.StatusCode
        }
        throw
    }
}

function Get-ContainerEnvironment {
    param([Parameter(Mandatory)][string]$Service)

    $containerId = Get-ServiceContainerId -Service $Service
    $format = '{{range .Config.Env}}{{println .}}{{end}}'
    $result = & docker inspect --format $format $containerId 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect environment for service '$Service': $result"
    }
    $lines = @($result | ForEach-Object { "$_" })
    return ($lines -join "`n")
}

function Get-ContainerTimestamp {
    param(
        [Parameter(Mandatory)][string]$Service,
        [Parameter(Mandatory)][ValidateSet('StartedAt', 'FinishedAt')][string]$Field
    )

    $containerId = Get-ServiceContainerId -Service $Service
    $format = "{{.State.$Field}}"
    $result = & docker inspect --format $format $containerId 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect $Field timestamp for service '$Service': $result"
    }

    return [DateTimeOffset]::Parse(([string]$result).Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
}

function Assert-ContainerRunning {
    param([Parameter(Mandatory)][string]$Service)

    $state = Get-ContainerState -ContainerId (Get-ServiceContainerId -Service $Service)
    if ($state.Status -ne 'running') {
        throw "Expected '$Service' to be running; state=$($state.Status), exit=$($state.ExitCode)."
    }
    return $state
}

function Test-HostTcpPort {
    param([Parameter(Mandatory)][int]$Port)

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $client.Connect('127.0.0.1', $Port)
        if (-not $client.Connected) {
            throw "Unable to connect to host TCP port $Port."
        }
    }
    finally {
        $client.Dispose()
    }
}

function Assert-PortAvailable {
    param([Parameter(Mandatory)][int]$Port)

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    try {
        $listener.Start()
    }
    catch {
        throw "Local TCP port $Port is already in use. Stop the conflicting service before running this disposable stack."
    }
    finally {
        $listener.Stop()
    }
}

try {
    Write-Step 'Preflight audited baseline and runtime input integrity'
    Set-Location $RepoRoot

    $actualHead = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read Git HEAD.' }

    & git cat-file -e "$BaselineHead^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Audited baseline '$BaselineHead' is unavailable locally. Fetch the repository history before running this harness."
    }

    & git merge-base --is-ancestor $BaselineHead $actualHead
    if ($LASTEXITCODE -ne 0) {
        throw "HEAD '$actualHead' is not a descendant of the audited baseline '$BaselineHead'. Re-audit before running this harness."
    }

    & git diff --quiet $BaselineHead $actualHead -- $RuntimeSensitivePaths
    if ($LASTEXITCODE -ne 0) {
        throw 'Runtime-sensitive repository files changed since the audited baseline. Re-audit the harness before running it.'
    }

    & git diff --quiet HEAD -- $RuntimeSensitivePaths
    if ($LASTEXITCODE -ne 0) {
        throw 'Runtime-sensitive files have local modifications. Commit or revert those paths before runtime acceptance.'
    }

    $untrackedRuntimePaths = @(& git ls-files --others --exclude-standard -- $RuntimeSensitivePaths)
    if ($untrackedRuntimePaths.Count -gt 0) {
        throw "Untracked runtime-sensitive files found: $($untrackedRuntimePaths -join ', ')"
    }

    foreach ($path in @($ComposeFile, $EnvFile)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required file is missing: $path"
        }
    }

    & docker compose version
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose v2 is unavailable.' }
    & docker info --format '{{.ServerVersion}}'
    if ($LASTEXITCODE -ne 0) { throw 'Docker daemon is unavailable; start Docker Desktop and retry.' }

    foreach ($port in @(5432, 6432, 5050)) {
        Assert-PortAvailable -Port $port
    }

    Write-Host "Disposable Compose project: $ProjectName"

    Write-Step 'Validate Compose and build/start from a fresh project volume'
    Invoke-Compose -Arguments @('config', '--quiet')
    # Mark before `up`: Compose may create part of the project before returning an error.
    $script:StackStarted = $true
    Invoke-Compose -Arguments @('up', '-d', '--build')

    Write-Step 'Wait for empty-database migrations, PostgreSQL and PgBouncer'
    $null = Wait-ForContainerHealth -Service 'postgres'
    $null = Wait-ForMigrationExit
    $null = Wait-ForContainerHealth -Service 'pgbouncer'

    $migrationLogs = (Invoke-ComposeCapture -Arguments @('logs', '--no-color', 'migrate')) -join "`n"
    if ($migrationLogs -notmatch 'application SQL migrations are current') {
        throw 'Goose migration completion message was not found in migrate logs.'
    }
    if ($migrationLogs -notmatch 'River schema is current') {
        throw 'River schema completion message was not found in migrate logs.'
    }

    $migrationFinishedAt = Get-ContainerTimestamp -Service 'migrate' -Field 'FinishedAt'
    $apiStartedAt = Get-ContainerTimestamp -Service 'api' -Field 'StartedAt'
    $workerStartedAt = Get-ContainerTimestamp -Service 'worker' -Field 'StartedAt'
    if ($apiStartedAt -lt $migrationFinishedAt) {
        throw 'API started before the migration service finished.'
    }
    if ($workerStartedAt -lt $migrationFinishedAt) {
        throw 'River worker started before the migration service finished.'
    }

    Write-Step 'Verify service routing and API probes'
    $apiEnvironment = Get-ContainerEnvironment -Service 'api'
    $workerEnvironment = Get-ContainerEnvironment -Service 'worker'
    $migrationEnvironment = Get-ContainerEnvironment -Service 'migrate'

    if ($apiEnvironment -notmatch 'DATABASE_URL=.*@pgbouncer:5432/') {
        throw 'API is not configured to use PgBouncer transaction pooling.'
    }
    if ($workerEnvironment -notmatch 'DATABASE_URL=.*@postgres:5432/') {
        throw 'River worker is not configured to connect directly to PostgreSQL.'
    }
    if ($migrationEnvironment -notmatch 'DATABASE_URL=.*@postgres:5432/') {
        throw 'Migration service is not configured to connect directly to PostgreSQL.'
    }

    $apiBefore = Assert-ContainerRunning -Service 'api'
    $workerBefore = Assert-ContainerRunning -Service 'worker'
    if ($apiBefore.RestartCount -ne 0) {
        throw "API restarted during initial startup ($($apiBefore.RestartCount) restart(s))."
    }
    if ($workerBefore.RestartCount -ne 0) {
        throw "River worker restarted during initial startup ($($workerBefore.RestartCount) restart(s))."
    }
    $liveness = Invoke-RestMethod -Uri 'http://127.0.0.1:5050/livez' -TimeoutSec 5
    if ($liveness.status -ne 'ok') { throw "Unexpected /livez response: $($liveness | ConvertTo-Json -Compress)" }
    Wait-ForApiReady

    Write-Step 'Verify PgBouncer host port and authenticated SQL execution'
    Test-HostTcpPort -Port 6432
    $sqlLines = Invoke-ComposeCapture -Arguments @(
        'exec', '-T', 'pgbouncer', 'sh', '-lc',
        'PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -p 5432 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -tAc "SELECT 1"'
    )
    $sqlOutput = ($sqlLines -join "`n").Trim()
    if ($sqlOutput -ne '1') {
        throw "PgBouncer SELECT 1 returned '$sqlOutput'; expected exactly '1'."
    }
    Write-Host 'PgBouncer SELECT 1 returned 1.'

    Write-Step 'Negative readiness test while PgBouncer is unavailable'
    Invoke-Compose -Arguments @('stop', 'pgbouncer')
    Start-Sleep -Seconds 3
    $liveStatus = Get-HttpStatusCode -Uri 'http://127.0.0.1:5050/livez'
    $readyStatus = Get-HttpStatusCode -Uri 'http://127.0.0.1:5050/readyz'
    if ($liveStatus -ne 200) {
        throw "Liveness must remain HTTP 200 during dependency failure; received $liveStatus."
    }
    if ($readyStatus -ne 503) {
        throw "Readiness must return HTTP 503 while PgBouncer is unavailable; received $readyStatus."
    }
    Write-Host 'Liveness stayed 200 while readiness correctly returned 503.'

    Invoke-Compose -Arguments @('start', 'pgbouncer')
    $null = Wait-ForContainerHealth -Service 'pgbouncer'
    Wait-ForApiReady

    Write-Step 'Verify River worker startup and restart stability'
    $workerLogs = (Invoke-ComposeCapture -Arguments @('logs', '--no-color', '--tail=200', 'worker')) -join "`n"
    if ($workerLogs -notmatch 'River worker started') {
        throw 'Expected structured River worker startup record was not found.'
    }
    if ($workerLogs -notmatch '"business_handlers_registered":false') {
        throw 'Expected explicit S0 bootstrap-handler metadata was not found in worker logs.'
    }
    if ($workerLogs -match 'at least one Worker must be added|relation "river_job" does not exist') {
        throw 'Worker logs contain a known River bootstrap/schema failure.'
    }

    Start-Sleep -Seconds 10
    $workerAfter = Assert-ContainerRunning -Service 'worker'
    if ($workerAfter.RestartCount -ne $workerBefore.RestartCount) {
        throw "River worker restarted during the stability window ($($workerBefore.RestartCount) -> $($workerAfter.RestartCount))."
    }

    Write-Step 'Re-run Goose and River migrations against the same volume'
    Invoke-Compose -Arguments @('up', '-d', '--force-recreate', 'migrate')
    $rerunState = Wait-ForMigrationExit
    if ($rerunState.ExitCode -ne 0) { throw 'Migration rerun did not exit successfully.' }

    $rerunLogs = (Invoke-ComposeCapture -Arguments @('logs', '--no-color', 'migrate')) -join "`n"
    if ($rerunLogs -notmatch 'application SQL migrations are current') {
        throw 'Goose did not report a successful idempotent migration rerun.'
    }
    if ($rerunLogs -notmatch 'River schema is current') {
        throw 'River did not report a successful idempotent migration rerun.'
    }

    $workerFinal = Assert-ContainerRunning -Service 'worker'
    if ($workerFinal.RestartCount -ne $workerBefore.RestartCount) {
        throw "River worker restarted during migration rerun ($($workerBefore.RestartCount) -> $($workerFinal.RestartCount))."
    }
    $apiFinal = Assert-ContainerRunning -Service 'api'
    if ($apiFinal.RestartCount -ne $apiBefore.RestartCount) {
        throw "API restarted during the runtime acceptance ($($apiBefore.RestartCount) -> $($apiFinal.RestartCount))."
    }
    Wait-ForApiReady

    Write-Step 'Runtime acceptance passed'
    Write-Host 'PASS: fresh PostgreSQL volume, Goose migrations, River migrations, PgBouncer, API probes, readiness failure behavior, direct worker DB route, migration idempotency, and API/worker stability.' -ForegroundColor Green
}
catch {
    Write-Host "`nRuntime acceptance failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($script:StackStarted) {
        Write-Host '`nCollecting disposable stack diagnostics...' -ForegroundColor Yellow
        try { Invoke-Compose -Arguments @('ps', '-a') } catch { Write-Warning $_ }
        try { Invoke-Compose -Arguments @('logs', '--no-color', '--tail=200') } catch { Write-Warning $_ }
    }
    throw
}
finally {
    if ($script:StackStarted) {
        if ($KeepResources) {
            Write-Host "Disposable stack preserved for inspection: $ProjectName" -ForegroundColor Yellow
        }
        else {
            Write-Step 'Remove only this disposable Compose project and its volume'
            try {
                Invoke-Compose -Arguments @('down', '--volumes', '--remove-orphans')
            }
            catch {
                throw "Disposable project cleanup failed; remove project '$ProjectName' manually. $($_.Exception.Message)"
            }
        }
    }
}

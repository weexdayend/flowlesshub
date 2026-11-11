[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$KubeContext = "docker-desktop"
$Namespace = "flowlesshub"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
Set-Location $repoRoot

$actualContext = (& kubectl config current-context 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($actualContext)) {
    throw "kubectl has no active context. Start Docker Desktop Kubernetes and select '$KubeContext'."
}
if ($actualContext -ne $KubeContext) {
    throw "Refusing to provision local credentials into context '$actualContext'; expected '$KubeContext'."
}

& kubectl cluster-info | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Kubernetes API is not reachable for context '$KubeContext'."
}

$namespaceManifest = Join-Path $repoRoot "deploy\k8s\base\namespace.yaml"
if (-not (Test-Path -LiteralPath $namespaceManifest -PathType Leaf)) {
    throw "Kubernetes namespace manifest not found: $namespaceManifest"
}
& kubectl apply -f $namespaceManifest | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Unable to ensure the FlowlessHub Kubernetes namespace." }

# Remove the completed one-shot host-routing probe created by the previous
# helper version. The replacement runtime uses only in-cluster Service DNS.
& kubectl delete pod flowlesshub-host-network-probe --namespace $Namespace --ignore-not-found=true --wait=true | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Unable to remove the obsolete host-network probe Pod." }

function Get-KubeSecret([string]$Name) {
    $secretLines = @(& kubectl get secret $Name --namespace $Namespace --ignore-not-found -o json 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect Kubernetes Secret '$Name'." }
    $secretJson = ($secretLines -join [Environment]::NewLine).Trim()
    if ([string]::IsNullOrWhiteSpace($secretJson)) { return $null }
    return ($secretJson | ConvertFrom-Json)
}

function ConvertFrom-SecretValue([string]$EncodedValue, [string]$SecretName, [string]$Key) {
    if ([string]::IsNullOrWhiteSpace($EncodedValue)) {
        throw "Kubernetes Secret '$SecretName' is missing required key '$Key'."
    }
    try {
        return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($EncodedValue))
    }
    catch {
        throw "Kubernetes Secret '$SecretName' contains invalid base64 for key '$Key'."
    }
}

function ConvertTo-SecretValue([string]$Value) {
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function Apply-KubeSecret([string]$Name, [System.Collections.IDictionary]$Values) {
    $data = [ordered]@{}
    foreach ($key in $Values.Keys) {
        $data[$key] = ConvertTo-SecretValue ([string]$Values[$key])
    }
    $secretObject = [ordered]@{
        apiVersion = "v1"
        kind = "Secret"
        metadata = [ordered]@{ name = $Name; namespace = $Namespace }
        type = "Opaque"
        data = $data
    }
    $secretJson = ConvertTo-Json -InputObject $secretObject -Depth 12 -Compress
    $secretJson | & kubectl apply -f - | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to create Kubernetes Secret '$Name'. Secret values were not printed or written to disk." }
}

function New-UrlSafePassword {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
    }
    finally {
        $rng.Dispose()
    }
}

# Reuse the existing cluster-local credentials on reruns. A new disposable
# random password is generated only on first provisioning and never printed.
$databaseSecretName = "flowlesshub-local-database-credentials"
$existingDatabaseSecret = Get-KubeSecret $databaseSecretName
if ($null -ne $existingDatabaseSecret) {
    $resolvedDatabaseName = ConvertFrom-SecretValue ([string]$existingDatabaseSecret.data.POSTGRES_DB) $databaseSecretName "POSTGRES_DB"
    $resolvedDatabaseUser = ConvertFrom-SecretValue ([string]$existingDatabaseSecret.data.POSTGRES_USER) $databaseSecretName "POSTGRES_USER"
    $resolvedDatabasePassword = ConvertFrom-SecretValue ([string]$existingDatabaseSecret.data.POSTGRES_PASSWORD) $databaseSecretName "POSTGRES_PASSWORD"
}
else {
    $resolvedDatabaseName = "flowlesshub"
    $resolvedDatabaseUser = "flowlesshub"
    $resolvedDatabasePassword = New-UrlSafePassword
    $databaseValues = [ordered]@{
        POSTGRES_DB = $resolvedDatabaseName
        POSTGRES_USER = $resolvedDatabaseUser
        POSTGRES_PASSWORD = $resolvedDatabasePassword
    }
    Apply-KubeSecret $databaseSecretName $databaseValues
}

Write-Host "Applying the disposable in-cluster PostgreSQL/PgBouncer runtime..." -ForegroundColor Cyan

$runtimeLabels = [ordered]@{
    "app.kubernetes.io/name" = "flowlesshub-local-database"
    "app.kubernetes.io/component" = "local-runtime"
    "app.kubernetes.io/part-of" = "flowlesshub"
}
$selectorLabels = [ordered]@{
    "app.kubernetes.io/name" = "flowlesshub-local-database"
    "app.kubernetes.io/component" = "local-runtime"
}

$serviceObject = [ordered]@{
    apiVersion = "v1"
    kind = "Service"
    metadata = [ordered]@{
        name = "flowlesshub-local-database"
        namespace = $Namespace
        labels = $runtimeLabels
    }
    spec = [ordered]@{
        type = "ClusterIP"
        selector = $selectorLabels
        ports = @(
            [ordered]@{ name = "postgres"; port = 5432; targetPort = 5432; protocol = "TCP" },
            [ordered]@{ name = "pgbouncer"; port = 6432; targetPort = 6432; protocol = "TCP" }
        )
    }
}

$postgresProbe = [ordered]@{
    exec = [ordered]@{ command = @("sh", "-c", 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"') }
    periodSeconds = 5
    timeoutSeconds = 3
    failureThreshold = 3
}
$pgbouncerReadinessProbe = [ordered]@{
    exec = [ordered]@{ command = @("sh", "-c", 'PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -p 6432 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "SELECT 1" >/dev/null') }
    periodSeconds = 5
    timeoutSeconds = 5
    failureThreshold = 12
}

$deploymentObject = [ordered]@{
    apiVersion = "apps/v1"
    kind = "Deployment"
    metadata = [ordered]@{
        name = "flowlesshub-local-database"
        namespace = $Namespace
        labels = $runtimeLabels
    }
    spec = [ordered]@{
        replicas = 1
        revisionHistoryLimit = 2
        strategy = [ordered]@{ type = "Recreate" }
        selector = [ordered]@{ matchLabels = $selectorLabels }
        template = [ordered]@{
            metadata = [ordered]@{ labels = $selectorLabels }
            spec = [ordered]@{
                automountServiceAccountToken = $false
                terminationGracePeriodSeconds = 60
                securityContext = [ordered]@{
                    runAsNonRoot = $true
                    runAsUser = 70
                    runAsGroup = 70
                    fsGroup = 70
                    fsGroupChangePolicy = "OnRootMismatch"
                    seccompProfile = [ordered]@{ type = "RuntimeDefault" }
                }
                containers = @(
                    [ordered]@{
                        name = "postgres"
                        image = "postgres:17.11-alpine"
                        imagePullPolicy = "IfNotPresent"
                        ports = @([ordered]@{ name = "postgres"; containerPort = 5432; protocol = "TCP" })
                        env = @(
                            # Keep PGDATA below the fsGroup-writable emptyDir mount root.
                            # The official image entrypoint can then chmod the child directory
                            # as UID 70 without trying to chmod the volume mount itself.
                            [ordered]@{ name = "PGDATA"; value = "/var/lib/postgresql/data/pgdata" },
                            [ordered]@{ name = "POSTGRES_DB"; valueFrom = [ordered]@{ secretKeyRef = [ordered]@{ name = $databaseSecretName; key = "POSTGRES_DB" } } },
                            [ordered]@{ name = "POSTGRES_USER"; valueFrom = [ordered]@{ secretKeyRef = [ordered]@{ name = $databaseSecretName; key = "POSTGRES_USER" } } },
                            [ordered]@{ name = "POSTGRES_PASSWORD"; valueFrom = [ordered]@{ secretKeyRef = [ordered]@{ name = $databaseSecretName; key = "POSTGRES_PASSWORD" } } }
                        )
                        volumeMounts = @([ordered]@{ name = "postgres-data"; mountPath = "/var/lib/postgresql/data" })
                        startupProbe = [ordered]@{
                            exec = [ordered]@{ command = @("sh", "-c", 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"') }
                            periodSeconds = 5
                            timeoutSeconds = 3
                            failureThreshold = 36
                        }
                        readinessProbe = $postgresProbe
                        livenessProbe = [ordered]@{
                            exec = [ordered]@{ command = @("sh", "-c", 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"') }
                            periodSeconds = 10
                            timeoutSeconds = 3
                            failureThreshold = 6
                        }
                        resources = [ordered]@{
                            requests = [ordered]@{ cpu = "100m"; memory = "256Mi" }
                            limits = [ordered]@{ cpu = "750m"; memory = "768Mi" }
                        }
                        securityContext = [ordered]@{
                            runAsNonRoot = $true
                            runAsUser = 70
                            runAsGroup = 70
                            allowPrivilegeEscalation = $false
                            capabilities = [ordered]@{ drop = @("ALL") }
                        }
                    },
                    [ordered]@{
                        name = "pgbouncer"
                        image = "edoburu/pgbouncer:v1.26.1-p0"
                        imagePullPolicy = "IfNotPresent"
                        ports = @([ordered]@{ name = "pgbouncer"; containerPort = 6432; protocol = "TCP" })
                        env = @(
                            [ordered]@{ name = "DB_USER"; valueFrom = [ordered]@{ secretKeyRef = [ordered]@{ name = $databaseSecretName; key = "POSTGRES_USER" } } },
                            [ordered]@{ name = "DB_PASSWORD"; valueFrom = [ordered]@{ secretKeyRef = [ordered]@{ name = $databaseSecretName; key = "POSTGRES_PASSWORD" } } },
                            [ordered]@{ name = "DB_HOST"; value = "127.0.0.1" },
                            [ordered]@{ name = "DB_PORT"; value = "5432" },
                            [ordered]@{ name = "DB_NAME"; valueFrom = [ordered]@{ secretKeyRef = [ordered]@{ name = $databaseSecretName; key = "POSTGRES_DB" } } },
                            [ordered]@{ name = "AUTH_TYPE"; value = "scram-sha-256" },
                            [ordered]@{ name = "POOL_MODE"; value = "transaction" },
                            [ordered]@{ name = "MAX_CLIENT_CONN"; value = "200" },
                            [ordered]@{ name = "DEFAULT_POOL_SIZE"; value = "20" },
                            [ordered]@{ name = "MAX_PREPARED_STATEMENTS"; value = "200" },
                            [ordered]@{ name = "LISTEN_ADDR"; value = "0.0.0.0" },
                            [ordered]@{ name = "LISTEN_PORT"; value = "6432" }
                        )
                        readinessProbe = $pgbouncerReadinessProbe
                        livenessProbe = [ordered]@{
                            exec = [ordered]@{ command = @("sh", "-c", 'pg_isready -h 127.0.0.1 -p 6432') }
                            periodSeconds = 10
                            timeoutSeconds = 3
                            failureThreshold = 6
                        }
                        resources = [ordered]@{
                            requests = [ordered]@{ cpu = "25m"; memory = "64Mi" }
                            limits = [ordered]@{ cpu = "250m"; memory = "192Mi" }
                        }
                        securityContext = [ordered]@{
                            runAsNonRoot = $true
                            runAsUser = 70
                            runAsGroup = 70
                            allowPrivilegeEscalation = $false
                            capabilities = [ordered]@{ drop = @("ALL") }
                        }
                    }
                )
                volumes = @([ordered]@{
                    name = "postgres-data"
                    emptyDir = [ordered]@{ sizeLimit = "2Gi" }
                })
            }
        }
    }
}

$serviceJson = ConvertTo-Json -InputObject $serviceObject -Depth 30 -Compress
$serviceJson | & kubectl apply -f - | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Unable to apply the local PostgreSQL/PgBouncer ClusterIP Service." }

$deploymentJson = ConvertTo-Json -InputObject $deploymentObject -Depth 40 -Compress
$deploymentJson | & kubectl apply -f - | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Unable to apply the local PostgreSQL/PgBouncer Deployment." }

Write-Host "Waiting for PostgreSQL and PgBouncer readiness inside Kubernetes..." -ForegroundColor Cyan
& kubectl rollout status deployment/flowlesshub-local-database --namespace $Namespace --timeout=240s
if ($LASTEXITCODE -ne 0) {
    & kubectl get pods --namespace $Namespace -l "app.kubernetes.io/name=flowlesshub-local-database" -o wide
    & kubectl describe pods --namespace $Namespace -l "app.kubernetes.io/name=flowlesshub-local-database"
    & kubectl logs deployment/flowlesshub-local-database --namespace $Namespace -c postgres --tail=100
    & kubectl logs deployment/flowlesshub-local-database --namespace $Namespace -c pgbouncer --tail=100
    throw "The in-cluster local database did not become ready. Runtime Secret was not created; inspect the Pod events and container logs above."
}

$endpointLines = @(& kubectl get endpoints flowlesshub-local-database --namespace $Namespace -o json)
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect the local database Service endpoints." }
$endpointObject = (($endpointLines -join [Environment]::NewLine) | ConvertFrom-Json)
$endpointAddresses = @($endpointObject.subsets | ForEach-Object { $_.addresses } | Where-Object { $null -ne $_ })
if ($endpointAddresses.Count -eq 0) {
    throw "The local database Service has no ready endpoints. Runtime Secret was not created."
}

# API -> PgBouncer (transaction pooling); worker and migrations -> direct PostgreSQL.
$userEscaped = [Uri]::EscapeDataString($resolvedDatabaseUser)
$passwordEscaped = [Uri]::EscapeDataString($resolvedDatabasePassword)
$databaseEscaped = [Uri]::EscapeDataString($resolvedDatabaseName)
$serviceHost = "flowlesshub-local-database"
$apiUrl = "postgres://${userEscaped}:${passwordEscaped}@${serviceHost}:6432/${databaseEscaped}?sslmode=disable"
$directUrl = "postgres://${userEscaped}:${passwordEscaped}@${serviceHost}:5432/${databaseEscaped}?sslmode=disable"
$desiredRuntimeData = [ordered]@{
    DATABASE_URL_API = (ConvertTo-SecretValue $apiUrl)
    DATABASE_URL_WORKER = (ConvertTo-SecretValue $directUrl)
    DATABASE_URL_MIGRATE = (ConvertTo-SecretValue $directUrl)
}

$runtimeSecretName = "flowlesshub-runtime-secrets"
$existingRuntimeSecret = Get-KubeSecret $runtimeSecretName
if ($null -ne $existingRuntimeSecret) {
    foreach ($key in @("DATABASE_URL_API", "DATABASE_URL_WORKER", "DATABASE_URL_MIGRATE")) {
        if ([string]$existingRuntimeSecret.data.$key -ne [string]$desiredRuntimeData[$key]) {
            throw "Existing '$runtimeSecretName' differs from the local in-cluster database endpoints. It was not overwritten. Remove the local runtime Secret explicitly before retrying."
        }
    }
    Write-Host "Existing runtime Secret matches the in-cluster database; leaving it unchanged." -ForegroundColor Green
}
else {
    $runtimeSecretObject = [ordered]@{
        apiVersion = "v1"
        kind = "Secret"
        metadata = [ordered]@{ name = $runtimeSecretName; namespace = $Namespace }
        type = "Opaque"
        data = $desiredRuntimeData
    }
    $runtimeSecretJson = ConvertTo-Json -InputObject $runtimeSecretObject -Depth 12 -Compress
    $runtimeSecretJson | & kubectl apply -f - | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create '$runtimeSecretName'. Secret values were not printed or written to disk."
    }
}

& kubectl describe secret $runtimeSecretName --namespace $Namespace
if ($LASTEXITCODE -ne 0) { throw "Runtime Secret was created but could not be verified." }
& kubectl get service flowlesshub-local-database --namespace $Namespace
if ($LASTEXITCODE -ne 0) { throw "Local database Service was created but could not be verified." }

Write-Host "Local FlowlessHub Kubernetes runtime is ready." -ForegroundColor Green
Write-Host "PostgreSQL endpoint: ${serviceHost}:5432" -ForegroundColor Green
Write-Host "PgBouncer endpoint: ${serviceHost}:6432" -ForegroundColor Green
Write-Host "Runtime Secret provisioned with the three required keys; credential values were not displayed." -ForegroundColor Green
Write-Warning "This database uses an emptyDir volume and is disposable. It is only for local S0.7 smoke acceptance; never use it for production or durable development data."

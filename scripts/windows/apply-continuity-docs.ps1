$ErrorActionPreference = 'Stop'

$ExpectedBase = '94536d65317aa513bdc715a39fbce2789dbb8709'
$ExpectedBlobs = @{
    'AGENTS.md' = '46060655a7a6e890fbc3f0b37e2012fc59709de6'
    'CHECKPOINTS.md' = '6d29c7c8197410d21496b55bad6a217528c9edeb'
    'README.md' = '73335469c25dd943bfccf938f8f9148e41d72d4b'
}

$RepoRoot = (git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or -not $RepoRoot) { throw 'Run this script from inside the FlowlessHub Git repository.' }
Set-Location $RepoRoot

$Head = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $Head -ne $ExpectedBase) {
    throw "Unexpected HEAD. Expected $ExpectedBase; found $Head. Re-audit before continuing."
}

foreach ($Path in $ExpectedBlobs.Keys) {
    $Blob = (git rev-parse "HEAD:$Path").Trim()
    if ($LASTEXITCODE -ne 0 -or $Blob -ne $ExpectedBlobs[$Path]) {
        throw "Root entry point changed from the audited source baseline: $Path. Stop and review manually."
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Expected root entry point is missing: $Path"
    }
    $RootItem = Get-Item -LiteralPath $Path -Force
    if (($RootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Root entry point must not be a symbolic link or reparse point: $Path"
    }

    # Compare the actual working copy (including staged and unstaged changes)
    # with the audited HEAD before creating any archive or replacing any root file.
    git diff --quiet HEAD -- $Path
    $DiffExitCode = $LASTEXITCODE
    if ($DiffExitCode -eq 1) {
        throw "Working copy/index differs from the audited baseline; refusing partial archive: $Path"
    }
    if ($DiffExitCode -ne 0) {
        throw "Unable to verify the working copy against HEAD: $Path (git diff exit $DiffExitCode)"
    }
}

$ArchiveDir = Join-Path $RepoRoot 'docs/archive'
if (Test-Path -LiteralPath $ArchiveDir) {
    $ArchiveDirItem = Get-Item -LiteralPath $ArchiveDir -Force
    if (-not $ArchiveDirItem.PSIsContainer -or
        (($ArchiveDirItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Archive destination must be a real directory, not a file/link: $ArchiveDir"
    }
}
$ArchiveMap = @{
    'AGENTS.md' = 'LEGACY-IT-SERVICES-PSA-AGENTS.md'
    'CHECKPOINTS.md' = 'LEGACY-IT-SERVICES-PSA-CHECKPOINTS.md'
    'README.md' = 'LEGACY-ROOT-README.md'
}
$Templates = @{
    'AGENTS.md' = 'docs/project-entrypoints/AGENTS.md'
    'CHECKPOINTS.md' = 'docs/project-entrypoints/CHECKPOINTS.md'
    'README.md' = 'docs/project-entrypoints/README.md'
}

# Preflight every input and destination before the first file is copied.
foreach ($Source in $ArchiveMap.Keys) {
    $ArchivePath = Join-Path $ArchiveDir $ArchiveMap[$Source]
    if (Test-Path -LiteralPath $ArchivePath) {
        throw "Archive destination already exists; refusing to overwrite: $ArchivePath"
    }
    $Template = Join-Path $RepoRoot $Templates[$Source]
    if (-not (Test-Path -LiteralPath $Template -PathType Leaf)) {
        throw "Missing continuity template: $Template"
    }
    $TemplateItem = Get-Item -LiteralPath $Template -Force
    if (($TemplateItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Continuity template must not be a symbolic link or reparse point: $Template"
    }
}
New-Item -ItemType Directory -Force -Path $ArchiveDir | Out-Null

foreach ($Source in $ArchiveMap.Keys) {
    $ArchivePath = Join-Path $ArchiveDir $ArchiveMap[$Source]
    Copy-Item -LiteralPath (Join-Path $RepoRoot $Source) -Destination $ArchivePath
    $ArchivedBlob = (git hash-object -- $ArchivePath).Trim()
    if ($LASTEXITCODE -ne 0 -or $ArchivedBlob -ne $ExpectedBlobs[$Source]) {
        throw "Legacy archive does not match the audited source blob: $Source"
    }
}

foreach ($Target in $Templates.Keys) {
    $Template = Join-Path $RepoRoot $Templates[$Target]
    Copy-Item -LiteralPath $Template -Destination (Join-Path $RepoRoot $Target) -Force
    $SourceHash = (Get-FileHash -LiteralPath $Template -Algorithm SHA256).Hash
    $TargetHash = (Get-FileHash -LiteralPath (Join-Path $RepoRoot $Target) -Algorithm SHA256).Hash
    if ($SourceHash -ne $TargetHash) { throw "Root entry point copy verification failed: $Target" }
}

Write-Host 'FlowlessHub root entry points updated.' -ForegroundColor Green
Write-Host 'Original root files preserved under docs/archive/.' -ForegroundColor Green
Write-Host 'Review root changes and archived snapshots before staging.' -ForegroundColor Yellow

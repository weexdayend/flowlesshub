# FlowlessHub — Windows ↔ VPS Operating Runbook

**Document class:** Mandatory project operating standard / continuity source of truth
**Applies to:** Every FlowlessHub engineering checkpoint, patch, CI run, deployment, runtime inspection, backup, restore, and recovery operation
**Repository:** `weexdayend/flowlesshub`
**Windows checkout:** `E:\workspace\flowlesshub`
**VPS:** Ubuntu 24.04, `/opt/flowlesshub`
**Last synchronized:** 14 November 2026
**Current accepted repository baseline at synchronization:** `c6e31e03204de8035af9ef0bf2e0f0f187f8f297`

> This is a permanent operating rule, not a one-checkpoint note. Every future continuation must read this document before giving commands or changing the repository/runtime. Update this file when an operating rule changes; do not create competing versions of the Windows/VPS rules.

---

## 1. Non-negotiable environment separation

| Mandatory label | Environment | Shell | Working directory | Allowed responsibility |
|---|---|---|---|---|
| **[WINDOWS — POWERSHELL]** | Developer workstation | PowerShell | `E:\workspace\flowlesshub` | Git, patch apply/review, source/docs edits, local tests, commit, push, CI inspection, evidence checksum |
| **[WINDOWS — GIT BASH]** | Developer workstation | Git Bash | `/e/workspace/flowlesshub` | Only commands explicitly requiring Bash on the workstation; still not the VPS |
| **[VPS — UBUNTU BASH]** | Production VPS | Bash over SSH | `/opt/flowlesshub` | Runtime inspection, deployment, backup, restore, recovery, systemd operations when specifically required |
| **[GITHUB — WEB/CI]** | GitHub | GitHub UI / Actions | Repository / exact SHA | Pull requests, branch source, CI gates and immutable workflow evidence |

Every command block must state all of the following before the block:

1. **Environment** — Windows, VPS, or GitHub.
2. **Shell** — PowerShell, Git Bash, Ubuntu Bash, or GitHub Actions shell.
3. **Directory** — exact working directory.
4. **Mode** — read-only or mutating.
5. **Purpose** — what the command proves or changes.
6. **Preconditions and stop conditions** — what must be true, and when to stop.
7. **Expected result** — the evidence that should appear.

Never mix PowerShell and Bash in the same code block. Never make the user infer where a command runs. If a procedure crosses environments, number each hop and explicitly say when SSH starts and ends.

### Recognize the prompt

- `PS E:\workspace\flowlesshub>` means **Windows PowerShell**.
- `user@machine MINGW64 /e/workspace/flowlesshub` means **Windows Git Bash**.
- `ubuntu@<host>:/opt/flowlesshub$` means **VPS Ubuntu Bash**.

Git Bash is still Windows. It is not a VPS shell.

### SSH boundary

**[WINDOWS — POWERSHELL]** — start an SSH session only when a checkpoint requires VPS work. `FLOWLESSHUB_VPS` must be an already configured SSH alias; do not invent the alias, hostname, account, or key path.

```powershell
ssh FLOWLESSHUB_VPS
```

After the prompt changes to Ubuntu, only VPS-labelled commands may run.

**[VPS — UBUNTU BASH]** — return to the workstation:

```bash
exit
```

After the prompt returns to `PS ...>`, commands run on Windows again.

---

## 2. Responsibility split

### Windows is the repository workstation

Do on Windows:

- fetch and inspect `origin/main`, compare exact commit SHAs, and inspect repository history;
- apply `.patch` files only after SHA and clean-tree checks;
- edit source, tests, docs, scripts, and configuration in the working checkout;
- run local quality gates that are available (lint, typecheck, test, build, Bash syntax, ShellCheck, docs/link checks);
- review every changed path, line ending, whitespace change, and executable file mode;
- commit, push, inspect GitHub Actions, and capture the exact successful CI run;
- download non-secret runtime evidence from VPS and independently verify SHA-256.

Do not use the VPS as a development workstation. Do not edit repository files ad hoc on production to bypass the Windows patch/review workflow.

### Linux-specific deployment CI gates belong to GitHub Actions

- The repository CI workflow is the authoritative place for Linux-dependent checks and deployment-configuration gates: Bash syntax, ShellCheck, `systemd-analyze verify`, VPS Docker Compose configuration, Caddy/Nginx configuration, and Kubernetes/edge validation.
- Run and judge those gates in GitHub Actions on the exact pushed candidate SHA. Do not turn Windows setup into a prerequisite by repairing WSL or installing a separate Bash runtime just to imitate the CI runner.
- A disposable Linux container on Windows may be used for troubleshooting, but its result is local diagnostic evidence only. It does not replace GitHub Actions and must not be described as CI acceptance or VPS acceptance.
- The CI `vps-deployment` job validates repository files and configuration. It does not deploy to, inspect, or accept the production VPS.

### VPS is the production runtime

Do on VPS only when the checkpoint requires it:

- read-only host, Docker, Compose, systemd, active-color, health, memory, swap, and disk inspection;
- an explicitly approved release rollout or rollback;
- FlowlessHub-only production backup, verification, isolated restore, or recovery steps;
- installation/activation of systemd units after source, CI, policy, and owner approval;
- runtime evidence collection with exact target and timestamp.

Do not run frontend/backend development builds on the VPS. Do not use the VPS to fix a patch. Do not copy secrets into chat or logs.

### GitHub CI is not runtime acceptance

- CI proves only the gates that actually ran against the exact SHA.
- CI does not prove deployment, live health, backup existence, off-site durability, restore success, or Petshop isolation.
- A green run for another SHA is not evidence for the candidate commit.

---

## 3. Repository and production invariants

- Repository: `weexdayend/flowlesshub`, default branch `main`.
- VPS OS: Ubuntu 24.04.
- VPS source/runtime directory: `/opt/flowlesshub`.
- VPS Compose file: `deploy/compose/vps.compose.yaml`.
- Compose project: `flowlesshub-vps`.
- FlowlessHub networks: `flowlesshub-vps-edge`, `flowlesshub-vps-backend`.
- Persistent PostgreSQL volume: `flowlesshub-vps-postgres-data`.
- Runtime secrets and state: `/opt/flowlesshub/.vps-runtime/` (Git-ignored).
- Production active color at S0.10 acceptance: `blue`.
- PostgreSQL image used by S0.10 validation: `postgres:17.11-alpine`.
- Backup/restore shared lock: `.vps-runtime/backup.lock`.

### Petshop isolation is absolute

The following Petshop containers were observed running after the S0.10 restore drill and must not be modified by FlowlessHub work:

- `petshop-web`
- `erp-petshop-api-1`
- `petshop-adminer`
- `petshop-redis`
- `petshop-postgres`

Never change Petshop containers, databases, volumes, networks, ports, Compose files, or Nginx virtual hosts. Never use Petshop resources to validate FlowlessHub. FlowlessHub must remain in its own Compose project, networks, volumes, and runtime paths.

### Never run broad cleanup

Do not use global `docker system prune`, `docker volume prune`, `docker network prune`, `docker compose down`, or wildcard deletion as an operational shortcut. Do not run `docker compose down -v` for FlowlessHub. Inspect exact labels, project names, and target paths before any allowed mutation.

---

## 4. Standard checkpoint delivery sequence

Every checkpoint follows this sequence, with environment and evidence explicit at each stage:

**Audit → Slice Specification → Patch → Local Review → Commit/Push → Exact-SHA CI → VPS Runtime Validation (only when required) → Acceptance Evidence → Checkpoint Documentation Update → Next Checkpoint.**

A documentation-only checkpoint does not require a VPS login. A shell-script-only operational checkpoint does not require an application image rebuild unless the changed files actually affect an image. Do not add unnecessary production actions to a repo-only task.

### 4.1 Mandatory gate handoff: Windows → GitHub Actions → VPS

1. **Windows pre-push:** finish source review, inspect the complete working-tree diff, and run the applicable native local tests and quality gates. Keep the change set scoped to the active checkpoint.
2. **Commit and push:** stage only reviewed paths, preserve required Git file modes, commit, push, and record the resulting 40-character SHA. Do not start production deployment while CI is pending or failing.
3. **GitHub Actions:** inspect the workflow run for that exact SHA. All applicable required jobs must pass, including the `vps-deployment` configuration job. A run for a parent or earlier SHA is not sufficient.
4. **VPS runtime:** only after exact-SHA CI is green, follow the checkpoint's VPS runbook when runtime validation or deployment is required. Use the separate SSH boundary and explicit owner authorization for production mutations. A documentation-only or configuration-only checkpoint does not automatically require VPS access.
5. **Failure loop:** if CI fails, diagnose and fix the source on Windows, review the diff, create and push a new commit, then inspect CI for the new SHA. Never bypass a failing gate by substituting a local container run.

Do not describe Windows-hosted Docker validation, GitHub Actions configuration validation, or static file checks as production runtime acceptance. Record repository, CI, VPS runtime, and owner-acceptance evidence as separate categories.

### Required evidence categories

1. **Repository evidence:** base SHA, changed paths, final commit SHA, diff summary.
2. **Local validation:** exact Windows command, exit code, and output summary.
3. **CI evidence:** workflow URL/run ID, exact SHA, each relevant job result.
4. **Runtime evidence:** only when required; VPS command, target, UTC timestamp, output, resource state, and postcondition.
5. **Owner acceptance:** explicit acceptance record; never infer it from CI.

`DONE`, `VERIFIED`, `ACCEPTED`, and `CLOSED` are not interchangeable with “patch prepared”. Use them only when all required acceptance evidence exists.

---

## 5. Permanent patch workflow — Windows PowerShell

Patch files and ZIPs belong outside the repository, normally in `$HOME\Downloads`. Never stage patch packages, database dumps, runtime directories, `.env`, credentials, or private keys.

### Step 1 — inspect checkout and current origin

**[WINDOWS — POWERSHELL]**
**Directory:** `E:\workspace\flowlesshub`
**Mode:** Read-only except `git fetch` metadata update
**Purpose:** Confirm the exact base before applying a patch.

```powershell
$ErrorActionPreference = "Stop"
Set-Location 'E:\workspace\flowlesshub'
git status --short --branch
git branch --show-current
git rev-parse HEAD
git remote -v
git fetch origin --prune --tags
if ($LASTEXITCODE -ne 0) { throw "git fetch failed." }
git rev-parse origin/main
```

Stop if there are unreviewed local changes, the wrong branch is checked out, the base SHA differs from the patch's declared SHA, or `origin/main` moved after the patch was produced. Re-audit and regenerate the patch against the new SHA; never force a stale patch.

### Step 2 — verify patch hash and preflight

**[WINDOWS — POWERSHELL]**
**Directory:** repository root
**Mode:** Read-only
**Purpose:** Verify artifact identity and apply compatibility.

```powershell
$PatchPath = Join-Path $HOME 'Downloads\FLOWLESSHUB-CHECKPOINT.patch'
$ExpectedSha256 = 'REPLACE_WITH_SHA256_FROM_HANDOFF'
$ActualSha256 = (Get-FileHash -LiteralPath $PatchPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualSha256 -ne $ExpectedSha256.ToLowerInvariant()) { throw "Patch SHA-256 mismatch." }
git apply --check --whitespace=error-all $PatchPath
if ($LASTEXITCODE -ne 0) { throw "Patch preflight failed." }
```

### Step 3 — apply and review

**[WINDOWS — POWERSHELL]**
**Directory:** repository root
**Mode:** Mutating local working tree only
**Purpose:** Apply the reviewed patch and inspect all changes.

```powershell
git apply --whitespace=error-all $PatchPath
if ($LASTEXITCODE -ne 0) { throw "Patch application failed." }
git status --short
git diff --check
git diff --stat
git diff --name-status
git diff
```

Stop if a file outside the declared allowlist changes. Never proceed based on `git apply` exit code alone; review the diff.

### Step 4 — preserve executable modes for VPS scripts

Windows filesystems may not carry POSIX executable bits. The Git index must still record all `scripts/vps/*.sh` files as `100755`.

**[WINDOWS — POWERSHELL]**
**Directory:** repository root
**Mode:** Mutating Git index only
**Purpose:** Record executable mode after staging the exact intended paths.

```powershell
git add -- <EXACT_REVIEWED_PATHS>
git update-index --chmod=+x -- scripts/vps/<SCRIPT_A>.sh scripts/vps/<SCRIPT_B>.sh
if ($LASTEXITCODE -ne 0) { throw "Unable to set executable mode." }
git ls-files --stage -- scripts/vps/*.sh
git diff --cached --check
git diff --cached --stat
git diff --cached --name-status
```

Check the mode column for each VPS script (`100755`). Do not stage the whole repository blindly. Do not stage `.vps-runtime`, backup artifacts, patch files, temporary fixtures, credentials, or local logs.

### Step 5 — commit and push

**[WINDOWS — POWERSHELL]**
**Directory:** repository root
**Mode:** Mutating Git history and remote branch
**Purpose:** Publish only after the staged inventory and local tests are accepted.

```powershell
git status --short
git diff --cached --check
git diff --cached --name-status
git commit -m "<checkpoint-specific message>"
if ($LASTEXITCODE -ne 0) { throw "Commit failed." }
git push origin main
if ($LASTEXITCODE -ne 0) { throw "Push failed." }
git rev-parse HEAD
```

Record the resulting 40-character SHA. Use that exact SHA for CI evidence.

---

## 6. VPS read-only inspection template

Only enter the VPS when the active checkpoint needs runtime evidence.

**[WINDOWS — POWERSHELL]** — start SSH:

```powershell
ssh FLOWLESSHUB_VPS
```

**[VPS — UBUNTU BASH]**
**Directory:** `/opt/flowlesshub`
**Mode:** Read-only
**Purpose:** Identify host, checkout, active color, services, and resource headroom before a mutation.

```bash
set -Eeuo pipefail
hostname
cd /opt/flowlesshub
pwd
git rev-parse HEAD 2>/dev/null || true
printf '\n== active color ==\n'
if [[ -f .vps-runtime/active-color ]]; then tr -d '\r\n' < .vps-runtime/active-color; printf '\n'; else echo 'MISSING'; fi
printf '\n== FlowlessHub Compose services ==\n'
docker compose --env-file .vps-runtime/.env -f deploy/compose/vps.compose.yaml ps
printf '\n== resources ==\n'
free -h
df -h / /opt/flowlesshub
```

If the host, path, Compose project, `.env` permission, active color, or service state differs from expected, stop before a mutating operation. Do not print `.vps-runtime/.env` or any credential.

**[VPS — UBUNTU BASH]** — return to Windows:

```bash
exit
```

---

## 7. Runtime mutation gate

A production command may run only when the checkpoint runbook specifies:

- exact FlowlessHub target resource and immutable source SHA;
- preconditions and resource guards;
- exact command and expected result;
- impact boundary (what must not change);
- rollback or safe stop behavior;
- postcondition checks;
- non-secret evidence to record.

For releases, preserve the VPS detached-HEAD model and existing Blue/Green behavior. Do not switch the production checkout to a moving `main` branch. Deployment and rollback procedures must remain scoped to the FlowlessHub Compose project and its own Caddy configuration.

---

## 8. Backup, retention, off-site, and restore rules

- `scripts/vps/backup-db.sh` creates a logical PostgreSQL custom-format archive, checksum, and non-secret manifest under `.vps-runtime/backups`.
- `scripts/vps/verify-backup.sh` checks archive identity, permissions, checksum, manifest, and `pg_restore --list` readability.
- `scripts/vps/restore-drill.sh` restores only to a separate disposable container with `--network none`, no published port, bounded memory/CPU, swap disabled, and an ephemeral data volume.
- Backup, restore, off-site upload, and local retention operations share `.vps-runtime/backup.lock`; they must not overlap.
- Production database restore is prohibited for a drill. A recovery runbook must distinguish isolated validation from real incident recovery and require explicit authorization for a production recovery.
- Retention defaults to dry-run. Deletion requires a protected policy file, explicit `--apply`, a keep floor of at least two newest local backups, a versioned marker, and a matching live off-site snapshot for every local artifact group to be deleted.
- The uploader reads the archive, checksum sidecar, and manifest back from the exact Restic snapshot and compares their SHA-256 values before writing the marker. Retention validates the recorded triplet hashes and performs a fresh read-back of all three files immediately before deleting local copies. This targeted artifact check is not a PostgreSQL restore drill or a full remote-repository integrity audit.
- S3-compatible off-site storage is provider-neutral. No vendor, bucket, region, credentials, encryption password, or retention objective is assumed by repository templates.
- Restic repository initialization is a one-time, explicit owner operation. Automation must never initialize or overwrite a remote repository silently.
- Off-site credentials and the Restic password live only in `.vps-runtime/`, mode `600`; never commit, paste, log, or place them in process arguments. The systemd unit must set Restic's cache to its private writable `/tmp` because `ProtectHome=true` hides the service user's home directory.
- External alerting is not configured by this package. Until an alert destination is approved, inspect systemd service result and journald logs.
- A one-second database restore does not equal end-to-end service RTO. Do not invent RPO/RTO values.
- Do not lower RAM, swap, or disk guards to force a backup or restore operation.

---

## 9. Evidence transfer — VPS to Windows

**[VPS — UBUNTU BASH]** — calculate source checksum only for a verified non-secret artifact:

```bash
sha256sum /opt/flowlesshub/<exact-evidence-file>
```

**[WINDOWS — POWERSHELL]** — copy and independently verify:

```powershell
$EvidenceDir = Join-Path $HOME 'FlowlessHubEvidence'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
scp FLOWLESSHUB_VPS:/opt/flowlesshub/<exact-evidence-file> $EvidenceDir
Get-FileHash (Join-Path $EvidenceDir '<exact-evidence-file>') -Algorithm SHA256
```

Use the exact checksum printed by the source command. Never transfer `.env`, SSH private keys, database credentials, cloud access keys, Restic passwords, or unredacted environment output.

---

## 10. Stop conditions and prohibited shortcuts

Stop immediately on any of these conditions:

- wrong shell, host, directory, repository, branch, or base SHA;
- dirty local tree that has not been reviewed;
- `origin/main` moved after patch creation;
- unexpected changed paths, executable mode drift, or line-ending drift;
- failed CI for the exact SHA;
- missing/incorrect runtime `.env` mode or unignored secrets;
- active color differs from the checkpoint's required color;
- memory, swap, or disk guard fails;
- ambiguous Docker project/resource ownership;
- any risk to Petshop resources or unrelated Nginx configuration;
- incomplete archive triplet, checksum mismatch, malformed manifest, missing off-site marker, or concurrent backup/restore lock;
- off-site repository not initialized, credentials missing, or encryption password file unavailable.

Never respond to a failure by broad cleanup, disabling a guard, retrying a command blindly, using another project's container/database/volume, or changing production state outside the runbook. Preserve the non-secret error output and diagnose the exact failure first.

---

## 11. Fresh-session continuity protocol

At the start of every new FlowlessHub session:

1. Read this runbook first.
2. Read `README.md`, `AGENTS.md`, and `CHECKPOINTS.md`, in that order.
3. Read the current checkpoint slice, runbook, and acceptance record linked by `CHECKPOINTS.md`.
4. Read the latest repository state from `origin/main`; never assume a SHA from memory is still current.
5. Distinguish **prepared**, **applied locally**, **committed**, **pushed**, **CI-passed**, **VPS-deployed**, and **owner-accepted** states.
6. Carry forward only facts with concrete evidence. Do not re-run closed destructive or resource-intensive operations to reconfirm them.
7. Update the checkpoint register and relevant runbooks as part of the checkpoint's deliverable, not as a later memory exercise.
8. End each completed handoff with: current accepted SHA, exact CI run, runtime state (if applicable), owner-accepted checkpoint, remaining follow-ups, next checkpoint, and separate Windows/VPS next commands.

### Canonical files to maintain

- `AGENTS.md` — engineering rules and mandatory read order.
- `CHECKPOINTS.md` — checkpoint register and current sequence.
- `README.md` — repository navigation and quick start.
- `docs/slices/` — scope, design, dependencies, and implementation baselines.
- `docs/runbooks/` — durable operational procedures, including this Windows/VPS standard.
- `docs/acceptance/` — evidence-backed acceptance, status, and boundaries.

Never rely on an old chat as the only copy of a project decision or command sequence. The repository is the durable continuity record. When a decision is unresolved, mark it **OPEN / OWNER DECISION REQUIRED** and keep automation fail-closed.

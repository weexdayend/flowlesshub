# FlowlessHub — Agent Working Agreement

This file is the repository-level engineering contract for FlowlessHub. It is self-contained and must not depend on documents from another project.

## Mandatory read order

1. `docs/runbooks/FLOWLESSHUB-WINDOWS-VPS-OPERATING-RUNBOOK.md` — read this canonical operating contract first.
2. `README.md` — repository entry point and navigation.
3. `AGENTS.md` — this engineering agreement.
4. `CHECKPOINTS.md` — authoritative checkpoint sequence, state, evidence, and open decisions.
5. The current checkpoint's slice, runbook, and acceptance record linked from `CHECKPOINTS.md`.
6. Any applicable nested `AGENTS.md` and relevant versioned framework documentation before changing framework APIs.

Never infer that a checkpoint is accepted because it appears in a plan, a patch exists, or CI is green. Use the evidence in the checkpoint's acceptance record.

## Source-of-truth hierarchy

- The current repository source/configuration defines what is implemented.
- An approved slice specification defines the scope and decisions for the active checkpoint.
- `CHECKPOINTS.md` defines sequence and current checkpoint status; it must link to evidence rather than replace it.
- The canonical Windows/VPS operating runbook defines where and how commands may run.
- Checkpoint runbooks define operational procedure and safety controls.
- Acceptance records define what was actually validated and accepted.
- Explicit owner decisions override proposals. Unresolved decisions remain `OPEN / OWNER DECISION REQUIRED`.

Do not refer to the ServicePilot / IT Services PSA Blueprint or Technical Architecture as FlowlessHub sources of truth. Those are unrelated project artifacts. Do not silently import requirements from them.

## Mandatory environment separation

Every command block in any FlowlessHub response, patch guide, slice, or runbook MUST be labelled with:

1. Environment: Windows, Windows Git Bash, GitHub Actions, or VPS Ubuntu.
2. Shell: PowerShell, Git Bash, GitHub Actions Bash, or Ubuntu Bash.
3. Exact working directory.
4. Mode: read-only or mutating.
5. Purpose and expected evidence.
6. Preconditions and explicit stop conditions.

Never mix PowerShell and Bash in one code block. Never label Git Bash as VPS. When crossing Windows ↔ VPS, show the SSH entry and exit as separate steps. Use separate command blocks for every environment hop.

Canonical locations:

| Environment | Shell | Working directory | Responsibility |
|---|---|---|---|
| Developer workstation | Windows PowerShell | `C:\Projects\saas\flowlesshub` | Source/docs edits, patch apply/review, Git, local tests, commit/push, CI inspection |
| Developer workstation | Windows Git Bash | `/c/Projects/saas/flowlesshub` | Only explicitly Bash-specific workstation tasks; never production runtime |
| Production host | Ubuntu Bash over SSH | `/opt/flowlesshub` | Runtime inspection and explicitly approved operational actions |
| GitHub | UI / Actions | Repository and exact commit SHA | Pull requests, immutable CI evidence, release workflow |

Repository work is performed on Windows. Do not edit repository files ad hoc on the production VPS. VPS access is not required for documentation-only work or local patch review.

## Checkpoint execution discipline

Use this sequence for every checkpoint:

**Audit → Slice Specification → Owner Decisions → Patch → Local Review → Commit/Push → Exact-SHA CI → VPS Runtime Validation (only when required) → Acceptance Evidence → Checkpoint Documentation Update → Next Checkpoint.**

### Environment-specific gate execution (mandatory)

The sequence above is an ordering rule, not a requirement to emulate every environment on the Windows workstation.

- **Windows is the development/repository workstation.** Use it for source and documentation changes, review, native local checks, Git staging/commit/push, and CI inspection. Windows PowerShell, Git Bash, WSL, and Docker Desktop remain workstation tooling; none is the production VPS.
- **GitHub Actions is the authoritative runner for repository CI.** Any gate defined in `.github/workflows/ci.yml` must be judged from that workflow on the exact pushed candidate SHA. This includes Linux-dependent checks and VPS deployment-configuration checks such as Bash syntax, ShellCheck, `systemd-analyze verify`, VPS Compose config, Caddy/Nginx config, and Kubernetes/edge validation.
- Do not make the Windows workflow block on installing or repairing WSL/Git Bash just to reproduce CI's Linux gates. A local Linux container may be used to diagnose a failure, but label it `local diagnostic`; it does not replace or satisfy GitHub Actions evidence.
- **VPS runtime acceptance comes after exact-SHA CI passes.** Only then use the VPS runbook for runtime checks or explicitly approved deployment/migration/operational changes, and only when required by the checkpoint.
- A CI job named `vps-deployment` validates repository configuration in CI; it does not deploy to or accept the production VPS.
- On CI failure, diagnose on Windows, make a reviewed fix, create and push a new commit, then inspect CI for the new exact SHA. A green run on an earlier SHA never validates later changes.
- Never report local container checks, GitHub CI checks, or static configuration validation as VPS runtime acceptance. Keep repository, CI, runtime, and owner-acceptance evidence separate.

- Work on one active checkpoint at a time.
- Preserve historical implementation baselines and accepted evidence.
- Separate proposed scope from implemented code, CI evidence, VPS evidence, and owner acceptance.
- Never mark acceptance boxes without sourceable evidence.
- A CI run must match the exact pushed SHA.
- Runtime validation is a separate gate; CI does not prove production deployment or safety.
- Keep patches narrow. Avoid bundling unrelated feature work into operational checkpoints.
- Do not repeat a closed, costly, or destructive operation merely to reconfirm it. Read its recorded evidence unless a new reason requires a new drill.
- If a command fails, diagnose the actual error before suggesting retries.

## Architecture and implementation rules

- Backend is a Go modular monolith with API, worker, and migration entry points.
- PostgreSQL is the source of truth. Keep migrations and SQL source-controlled; regenerate generated code through repository targets.
- Preserve module boundaries and current architecture unless an approved slice changes them.
- Do not hand-edit generated OpenAPI or sqlc outputs.
- Use tenant-scoped queries and RLS for tenant data; do not use superuser application roles or bypass RLS.
- Use PostgreSQL `NUMERIC` / decimal arithmetic for money; floats are forbidden for money.
- Use expand/migrate/switch/contract for database compatibility changes.
- Keep API contract and generated Go/TypeScript output synchronized.
- Keep CI quality gates green; do not skip, weaken, or silently redefine them to make a patch pass.

## Production and infrastructure safety

- Preserve the dedicated FlowlessHub Compose project `flowlesshub-vps`, its named networks, and its volumes.
- Preserve Blue/Green routing and the VPS detached-HEAD deployment model. Do not switch production to a moving `main` branch.
- The active production color at the S0.10 acceptance record is Blue. Verify the live marker before any future mutating action; do not assume it remains Blue forever.
- Do not change Petshop containers, databases, volumes, networks, ports, Compose files, or Nginx virtual hosts. Do not touch Frictiona infrastructure.
- Never use global Docker cleanup (`docker system prune`, `docker volume prune`, `docker network prune`, image prune) as an operational shortcut.
- Never use `docker compose down -v` on FlowlessHub. Never publish PostgreSQL/PgBouncer ports for convenience.
- Do not expose `.vps-runtime/.env`, database passwords, SSH private keys, cloud keys, Restic passwords, or raw environment output in chat, Git, logs, or artifacts.
- Preserve the existing RAM/swap/disk safety guards. If a guard refuses an operation, stop and reassess; do not lower it to force the action.
- Production restore is not an ordinary deployment rollback. An isolated restore drill must never target the production database.

## Operations-specific Definition of Done

For an operational checkpoint, record all applicable items separately:

- Script syntax and static analysis passed on the exact source revision.
- Git executable modes are correct (`100755` for executable VPS Bash scripts).
- CI passed on the exact commit SHA, including relevant deployment configuration gates.
- Runtime operation was performed only when required and authorized.
- Resource/safety guards passed without weakening.
- Postconditions and isolation boundaries were checked.
- Non-secret logs, hashes, timestamps, and resource evidence were captured.
- Owner acceptance is explicitly recorded.

Do not report `DONE`, `VERIFIED`, `ACCEPTED`, or `CLOSED` when only a patch was prepared or CI passed.

## Continuity requirement

The repository is the durable project memory. At the end of each checkpoint, update `CHECKPOINTS.md`, the relevant slice/runbook/acceptance documents, and the canonical Windows/VPS runbook when an operating rule changes. A fresh session must be able to continue from these files without depending on chat history.

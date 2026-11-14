# FlowlessHub

FlowlessHub is a monorepo application with a Go modular-monolith backend, a Next.js frontend, PostgreSQL, and a VPS-first Docker Compose Blue/Green deployment workflow.

> **Operational rule:** Before running commands or continuing engineering work, read [`docs/runbooks/FLOWLESSHUB-WINDOWS-VPS-OPERATING-RUNBOOK.md`](docs/runbooks/FLOWLESSHUB-WINDOWS-VPS-OPERATING-RUNBOOK.md). Windows PowerShell, Windows Git Bash, GitHub Actions, and VPS Ubuntu Bash are separate execution environments. Never infer where a command should run.

## Repository navigation

| Document | Purpose |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Mandatory engineering agreement, read order, safety rules |
| [`CHECKPOINTS.md`](CHECKPOINTS.md) | Current checkpoint register, state, evidence, and follow-ups |
| [`docs/runbooks/FLOWLESSHUB-WINDOWS-VPS-OPERATING-RUNBOOK.md`](docs/runbooks/FLOWLESSHUB-WINDOWS-VPS-OPERATING-RUNBOOK.md) | Permanent Windows ↔ VPS operating standard and continuity protocol |
| [`docs/slices/`](docs/slices/) | Checkpoint scope, architecture decisions, implementation baselines |
| [`docs/roadmap/S1-MVP-ROADMAP.md`](docs/roadmap/S1-MVP-ROADMAP.md) | Product MVP scope and ordered delivery milestones |
| [`docs/runbooks/`](docs/runbooks/) | Step-by-step local, CI, VPS, deployment, backup, and recovery procedures |
| [`docs/acceptance/`](docs/acceptance/) | Evidence-backed validation and owner acceptance records |
| [`api/openapi.yaml`](api/openapi.yaml) | OpenAPI source contract |
| [`deploy/compose/vps.compose.yaml`](deploy/compose/vps.compose.yaml) | Dedicated production Compose topology |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | Source/configuration quality gates |
| [`.github/workflows/publish-images.yml`](.github/workflows/publish-images.yml) | Commit-addressed GHCR image publication gates |

## Current operational baseline

- Repository: `weexdayend/flowlesshub`, default branch `main`.
- Last synchronized accepted repository baseline: `94536d65317aa513bdc715a39fbce2789dbb8709` (12 November 2026).
- VPS source/runtime directory: `/opt/flowlesshub` on Ubuntu 24.04.
- Production Compose project: `flowlesshub-vps`.
- Production Blue/Green implementation: FlowlessHub-owned Docker networks, volumes, Caddy edge, and host Nginx virtual host.
- S0.10 backup-integrity and isolated-restore drill: `CLOSED` with owner-accepted evidence in [`docs/acceptance/S0.10-backup-restore-drill.md`](docs/acceptance/S0.10-backup-restore-drill.md).
- S0.11 scheduled backup / retention / off-site operations: operational follow-up remains open; daily timer is enabled, and its first scheduled execution is awaiting runtime evidence. This does not block S1 product development.
- S1.1 Identity & Tenant Foundation: slice specification prepared at the current product-delivery lane; implementation has not started. See [`docs/slices/S1.1-identity-tenant-foundation.md`](docs/slices/S1.1-identity-tenant-foundation.md).

The above baseline is a recorded synchronization point, not a claim that `origin/main` will remain unchanged. Always fetch and verify the live SHA before applying a patch.

## Environment responsibilities

- **Windows PowerShell:** source and documentation changes, patch apply/review, Git, local validation, commit/push, CI inspection.
- **Windows Git Bash:** Bash-specific commands on the workstation only.
- **VPS Ubuntu Bash:** production runtime inspection and explicitly approved operational procedures only.
- **GitHub Actions:** CI and image build/publish gates against an exact commit SHA.

Do not develop or build the application on the production VPS. Do not edit production repository files ad hoc. Do not touch Petshop or Frictiona resources.

## Fresh-session continuation

Read the canonical Windows/VPS operating runbook first. Then read `README.md`, `AGENTS.md`, and `CHECKPOINTS.md` in that order. Inspect live `origin/main`, read the active checkpoint's slice/runbook/acceptance record, and continue only from evidence-backed state. Keep proposed, prepared, applied, committed, pushed, CI-passed, runtime-validated, and owner-accepted states distinct.

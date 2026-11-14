# FlowlessHub

FlowlessHub is a production-grade IT Services PSA platform, implemented as a Go modular monolith with a Next.js frontend, PostgreSQL, and a VPS-first Docker Compose Blue/Green deployment workflow.

> **Operational rule:** Before running commands or continuing engineering work, read [`docs/runbooks/FLOWLESSHUB-WINDOWS-VPS-OPERATING-RUNBOOK.md`](docs/runbooks/FLOWLESSHUB-WINDOWS-VPS-OPERATING-RUNBOOK.md). Windows PowerShell, Windows Git Bash, GitHub Actions, and VPS Ubuntu Bash are separate execution environments. Never infer where a command should run.

## Product and architecture source of truth

| Document | Purpose |
|---|---|
| [`docs/product/PRODUCT-STRATEGY.md`](docs/product/PRODUCT-STRATEGY.md) | Product mandate, complete PSA lifecycle, customer operating model, capability map and owner decisions |
| [`docs/architecture/DOMAIN-MODULE-ARCHITECTURE.md`](docs/architecture/DOMAIN-MODULE-ARCHITECTURE.md) | Current implementation facts, target module ownership, invariants, transaction boundaries and tenant isolation |
| [`docs/architecture/PRODUCTION-ENGINEERING-CHARTER.md`](docs/architecture/PRODUCTION-ENGINEERING-CHARTER.md) | Mandatory production-grade security, correctness, reliability, operations and release gates |
| [`docs/roadmap/PRODUCTION-GRADE-PSA-ROADMAP.md`](docs/roadmap/PRODUCTION-GRADE-PSA-ROADMAP.md) | Full lifecycle vertical-slice delivery order and production-grade acceptance contracts |
| [`AGENTS.md`](AGENTS.md) | Mandatory engineering agreement, read order and safety rules |
| [`CHECKPOINTS.md`](CHECKPOINTS.md) | Current checkpoint register, state, evidence and open decisions |
| [`docs/runbooks/FLOWLESSHUB-WINDOWS-VPS-OPERATING-RUNBOOK.md`](docs/runbooks/FLOWLESSHUB-WINDOWS-VPS-OPERATING-RUNBOOK.md) | Permanent Windows ↔ VPS operating standard and continuity protocol |
| [`docs/slices/`](docs/slices/) | Checkpoint scope, architecture decisions and implementation baselines |
| [`docs/runbooks/`](docs/runbooks/) | Step-by-step local, CI, VPS, deployment, backup and recovery procedures |
| [`docs/acceptance/`](docs/acceptance/) | Evidence-backed validation and owner-acceptance records |
| [`api/openapi.yaml`](api/openapi.yaml) | OpenAPI source contract |
| [`deploy/compose/vps.compose.yaml`](deploy/compose/vps.compose.yaml) | Dedicated production Compose topology |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | Source/configuration quality gates |
| [`.github/workflows/publish-images.yml`](.github/workflows/publish-images.yml) | Commit-addressed GHCR image publication gates |

The former [`docs/roadmap/S1-MVP-ROADMAP.md`](docs/roadmap/S1-MVP-ROADMAP.md) is retained as a historical pointer only; it is no longer the active delivery plan.

## Current repository and operational baseline

- Repository: `weexdayend/flowlesshub`, default branch `main`.
- Strategy-rebase patch base: `c6e31e03204de8035af9ef0bf2e0f0f187f8f297` (14 November 2026).
- S1.1 implementation/release baseline: `495383f38ec7c356b97bb66017b66a3380130eaf` (`flowlesshub-v0.1.1`); S1.1 is owner-accepted for backend/API scope only.
- VPS source/runtime directory: `/opt/flowlesshub` on Ubuntu 24.04.
- Production Compose project: `flowlesshub-vps`.
- Production Blue/Green implementation: FlowlessHub-owned Docker networks, volumes, Caddy edge and host Nginx virtual host.
- S0.10 backup-integrity and isolated-restore drill: `CLOSED` with owner-accepted evidence in [`docs/acceptance/S0.10-backup-restore-drill.md`](docs/acceptance/S0.10-backup-restore-drill.md).
- S0.11 scheduled backup / retention / off-site operations: first natural scheduled run, archive validation, Restic/R2 targeted read-back, Discord success and guarded local retention apply are verified. External disposable restore, measured 24-hour RPO/RTO and explicit owner acceptance remain open. This operational checkpoint does not block local product engineering.
- S1.1 Identity & Tenant Foundation: backend/API implementation, exact-SHA CI, release publication and production API acceptance are verified. Browser sign-in/session UX and protected web routes were explicitly deferred to S1.2. See [`docs/acceptance/S1.1-identity-tenant-foundation.md`](docs/acceptance/S1.1-identity-tenant-foundation.md).
- Next product checkpoint: S1.2 authenticated web entry and session UX; S1.3 tenant authorization, membership lifecycle and PostgreSQL/PgBouncer isolation; S1.4 customer/contact master data. See the [production-grade roadmap](docs/roadmap/PRODUCTION-GRADE-PSA-ROADMAP.md).

The baseline above is a recorded patch reference, not a claim that `origin/main` will remain unchanged. Always fetch and verify the live SHA before applying a patch.

## Environment responsibilities

- **Windows PowerShell:** source and documentation changes, patch apply/review, Git, local validation, commit/push and CI inspection.
- **Windows Git Bash:** Bash-specific commands on the workstation only.
- **VPS Ubuntu Bash:** production runtime inspection and explicitly approved operational procedures only.
- **GitHub Actions:** CI and image build/publish gates against an exact commit SHA.

Do not develop or build the application on the production VPS. Do not edit production repository files ad hoc. Do not touch Petshop or Frictiona resources.

## Fresh-session continuation

Read the canonical Windows/VPS operating runbook first. Then read `README.md`, `AGENTS.md` and `CHECKPOINTS.md` in that order, followed by the product strategy, domain architecture, production engineering charter and production-grade roadmap. Inspect live `origin/main`, read the active checkpoint's slice/runbook/acceptance record, and continue only from evidence-backed state. Keep proposed, prepared, applied, committed, pushed, CI-passed, runtime-validated and owner-accepted states distinct.

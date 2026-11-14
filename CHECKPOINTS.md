# FlowlessHub — Checkpoint Register

**Repository:** `weexdayend/flowlesshub`
**Default branch:** `main`
**Last synchronized repository baseline:** `92aec75c6387d6f57a1dc0d71c5ab7431f5831cd`
**Synchronization date:** 14 November 2026
**Current active product checkpoint:** S1.2 — Passwordless Identity, First-Party SSO and Authenticated Web Entry (owner-approved scope; ADR-0001 accepted; implementation not started)
**Open operational follow-up:** S0.11 — Scheduled Backup Operations, Retention & Off-Site Recovery (not a product-development blocker)

> This register describes FlowlessHub only. It supersedes the unrelated IT Services PSA/ServicePilot roadmap that previously occupied this file. Do not use external project blueprints as FlowlessHub source-of-truth documents.

## 1. How to use this register

1. Read the canonical [`Windows ↔ VPS Operating Runbook`](docs/runbooks/FLOWLESSHUB-WINDOWS-VPS-OPERATING-RUNBOOK.md) first, then `README.md`, `AGENTS.md`, and this register.
2. Work only on the current active checkpoint after inspecting live `origin/main`.
3. Read the product strategy, domain architecture, production engineering charter, and production-grade roadmap before changing lifecycle scope or module boundaries.
4. Read the linked slice, runbook, and acceptance record before implementation or runtime commands.
5. Preserve historical baselines. Do not rewrite historical implementation SHAs to the current HEAD.
6. Tick acceptance only when the matching evidence exists. A prepared patch or green CI alone is not production acceptance.
7. Keep owner decisions separate from implementation details. Do not invent provider selection, retention period, backup cadence, alert destination, RPO, or RTO.

## 2. State vocabulary

| State | Meaning |
|---|---|
| `HISTORICAL / OPEN` | Historical implementation record exists; the umbrella S0 exit gate is not claimed complete. |
| `PREPARED` | Specification or patch package exists, but owner application/validation is pending. |
| `IMPLEMENTED` | Source is present at a recorded commit; CI/runtime/owner acceptance may still be pending. |
| `CI VERIFIED` | Relevant CI jobs passed on the exact recorded SHA. This is not runtime acceptance. |
| `RUNTIME VERIFIED` | Required operations were observed on the actual target environment. |
| `CLOSED` | Owner explicitly accepted the checkpoint and its acceptance record contains evidence. |
| `OPEN / OWNER DECISION REQUIRED` | Progress is blocked on an explicit policy or product decision. |

## 3. Checkpoint matrix

| ID | Scope | Current status | Implementation baseline / SHA | CI evidence | Runtime acceptance | Evidence and remaining follow-ups |
|---|---|---|---|---|---|---|
| S0.1 | Repository foundation bootstrap | `HISTORICAL / OPEN` | Historical baseline recorded in slice/runbook | Not reasserted by this synchronization | Initial production deployment is not claimed by this sub-slice | [Slice](docs/slices/S0.1-foundation-bootstrap.md), [Runbook](docs/runbooks/S0.1-ci-repair.md). S0 umbrella exit gate remains open. |
| S0.2 | Database pooling, River worker, disposable runtime harness | `HISTORICAL / OPEN` | Multiple follow-up baselines recorded in the three S0.2 slices | Historical CI state varies by follow-up; see exact records | Owner runtime validation was pending in the latest slice records | [Database slice](docs/slices/S0.2-database-runtime-pooling.md), [Worker slice](docs/slices/S0.2-river-worker-bootstrap.md), [Runtime harness slice](docs/slices/S0.2-runtime-acceptance-harness.md), [Runbooks](docs/runbooks/). Reconcile older pending records only with evidence. |
| S0.3 | Go module-boundary lint | `HISTORICAL / OPEN` | Historical baseline in slice/runbook | Owner validation and green CI pending in recorded slice | No production runtime acceptance applicable | [Slice](docs/slices/S0.3-module-boundary-lint.md), [Runbook](docs/runbooks/S0.3-module-boundary-lint.md). |
| S0.4 | PostgreSQL migration lint and sqlc generation | `HISTORICAL / OPEN` | `c281d0ce4ffae945ae4f4aa6ec9450237f26c94b` patch baseline | Owner validation/remote CI pending in recorded slice | Tooling slice; production migration acceptance not claimed | [Slice](docs/slices/S0.4-postgres-migration-lint-sqlc.md), [Runbook](docs/runbooks/S0.4-postgres-migration-lint-sqlc.md). |
| S0.5 | Hybrid PQ TLS handshake verification | `ACCEPTED SUB-SLICE` | `d0fe4eb1b9c01ea8e24167c0663658f396818c88` | Run #13 passed on exact implementation SHA | In-process TLS handshake test passed; not production edge validation | [Slice](docs/slices/S0.5-pq-tls-handshake.md), [Runbook](docs/runbooks/S0.5-pq-tls-handshake.md). S0 remains open. |
| S0.6 | OpenAPI Go strict-server generation | `HISTORICAL / OPEN` | Historical baseline in slice | Exact-HEAD owner generation/CI acceptance pending in recorded slice | Not a production runtime acceptance item | [Slice](docs/slices/S0.6-openapi-go-server-generation.md), [Runbook](docs/runbooks/S0.6-openapi-go-server-generation.md). |
| S0.7 | Kubernetes deployment foundation and image gates | `IMPLEMENTED / LOCAL ACCEPTANCE RECORDED` | Accepted implementation `97c772b03d5d5cbe4b044412e5d3ec53b2e46d3f` | Run #22 passed on exact SHA | Local Kubernetes smoke acceptance passed; production acceptance and legacy Compose-project cleanup are not claimed | [Slice](docs/slices/S0.7-kubernetes-foundation.md), [Acceptance](docs/acceptance/S0.7-kubernetes-foundation.md), [Runbook](docs/runbooks/S0.7-kubernetes-foundation.md). |
| S0.8 | Caddy edge and Blue/Green deployment foundation / edge validation repair | `CLOSED — OWNER ACCEPTED (13 Nov 2026)` | Edge repair commit `e8f33bb7c0e92d4c49724dadde55d2378cbfddce`; earlier repair base `f949f896514cb871d1cbaeb2c01aac3195d6e546` | CI Run #26 / `43147198165` passed on exact `e8f33...` (Frontend and Backend quality gates) | Owner confirmed manual S0.8 acceptance on 13 Nov 2026; the acceptance record documents the owner attestation without inventing unarchived terminal output | [Slice](docs/slices/S0.8-caddy-edge-blue-green.md), [Acceptance](docs/acceptance/S0.8-edge-validation-repair.md), [Runbook](docs/runbooks/S0.8-caddy-edge-blue-green.md). S0.8 slice is closed; the broader S0 exit gate remains separate. |
| S0.9 | VPS-first Compose Blue/Green delivery hardening | `CLOSED — OWNER ACCEPTED (13 Nov 2026)` | Foundation `e8f33...`; hardening commit `20558818bca599782c822e9e3851e64cb979c369`; executable-mode fix `2bfdc36106df4a65dad410e8c71e91cd580de21d` | CI Run #27 / `43172335762` passed on `205588...`; CI Run #28 / `43179520063` passed on `2bfdc...`; release workflow #1 / `43172457693` passed all four GHCR image jobs | Owner confirmed manual S0.9 VPS acceptance on 13 Nov 2026; the acceptance record captures that attestation separately from exact-SHA CI evidence | [Slice](docs/slices/S0.9-vps-first-hardening.md), [Acceptance](docs/acceptance/S0.9-vps-first-hardening.md), [Runbook](docs/runbooks/S0.9-vps-blue-green-deployment.md). S0.9 slice is closed; the broader S0 exit gate remains separate. |
| S0.10 | Backup integrity and isolated restore drill | `CLOSED` | Implementation accepted at `94536d65317aa513bdc715a39fbce2789dbb8709`; scripts first hardened at `2bfdc36106df4a65dad410e8c71e91cd580de21d` | Run #29 / `43189431464` passed on exact accepted SHA | Owner accepted actual backup, off-host workstation checksum, isolated restore, production post-checks, and Petshop isolation on 12 Nov 2026 | [Slice](docs/slices/S0.10-backup-restore-drill.md), [Acceptance](docs/acceptance/S0.10-backup-restore-drill.md), [Runbook](docs/runbooks/S0.10-backup-restore-drill.md). Do not repeat the S0.10 drill merely to reconfirm it. |
| S0.11 | Scheduled backup operations, retention, off-site recovery, and Discord alerts | `RUNTIME VERIFIED — NATURAL SCHEDULED RUN + R2 READ-BACK + DISCORD SUCCESS; LOCAL RETENTION APPLY VERIFIED; REMOTE PRUNE NOT APPLIED; EXTERNAL RESTORE / MEASURED RPO-RTO / OWNER ACCEPTANCE PENDING` | Production-readiness commit `151c8931cb9b00974c90406001590763d6050cf3`; latest runtime evidence 14 Nov 2026 | Run #40 / `43407844129` passed all three required jobs on exact implementation SHA `151c8931cb9b00974c90406001590763d6050cf3` | First natural timer-originated run observed 14 Nov 03:07:19 WIB; service success, archive verification, R2 snapshot/read-back and Discord OnSuccess HTTP 200 verified; local keep-newest-2 apply deleted one eligible artifact group only after remote read-back; no remote `forget`/`prune` | [Current runtime addendum](docs/acceptance/S0.11-current-runtime-status-2026-11-14.md), [Slice](docs/slices/S0.11-scheduled-backup-operations.md), [Acceptance](docs/acceptance/S0.11-scheduled-backup-operations.md), [Runbook](docs/runbooks/S0.11-scheduled-backup-operations.md). External disposable restore, measured 24-hour RPO/RTO, remote retention application when a real candidate exists, and owner acceptance remain open. |
| S1.1 | Backend Identity & Tenant Foundation (API) | `CLOSED — OWNER ACCEPTED 14 NOV 2026 (BACKEND/API SCOPE; WEB SIGN-IN/SESSION UX DEFERRED TO S1.2)` | Implementation/release SHA `495383f38ec7c356b97bb66017b66a3380130eaf`; release tag `flowlesshub-v0.1.1` | CI Run #43 / `43563224712` passed all 3 jobs; release workflow #2 / `43564539435` passed all 5 jobs | Production Green deployment, migration v2, one-time owner bootstrap, `/readyz`, trusted/untrusted Origin, login, cookie attributes, authenticated identity/org listing, logout and revoked-session replay checks passed; Blue S0.9 API/Web retained for rollback | [Roadmap](docs/roadmap/PRODUCTION-GRADE-PSA-ROADMAP.md), [Slice](docs/slices/S1.1-identity-tenant-foundation.md), [Runbook](docs/runbooks/S1.1-identity-tenant-foundation.md), [Acceptance](docs/acceptance/S1.1-identity-tenant-foundation.md). Web login/session UI and protected application routing are explicitly excluded from S1.1 and assigned as the first S1.2 work; the owner formally accepted S1.1 against the backend/API-only scope on 14 November 2026. |
| S1.2 | Passwordless Identity, First-Party OIDC SSO and Authenticated Web Entry | `OWNER-APPROVED SCOPE — ADR-0001 ACCEPTED / SLICE UPDATED; IMPLEMENTATION NOT STARTED` | Depends on accepted S1.1 API/release SHA `495383f38ec7c356b97bb66017b66a3380130eaf`; strategy baseline `92aec75c6387d6f57a1dc0d71c5ab7431f5831cd` | Not run for S1.2 | No S1.2 runtime work started or authorized | [Slice](docs/slices/S1.2-authenticated-web-entry-session-ux.md), [ADR-0001](docs/architecture/ADR-0001-passwordless-identity-and-first-party-oidc.md), [Roadmap](docs/roadmap/PRODUCTION-GRADE-PSA-ROADMAP.md). Passkey/WebAuthn, internal OIDC SSO, same-origin BFF, SMTP transactional email/outbox, recovery and staged S1.1 credential migration are included. External enterprise IdP federation remains separate. S1.3 authorization/RLS/PgBouncer gates remain mandatory before tenant business data. |
| S1.3 | Tenant authorization, membership lifecycle and PostgreSQL/PgBouncer isolation | `PLANNED — DEPENDENT ON S1.2; SPECIFICATION AND IMPLEMENTATION NOT STARTED` | Depends on S1.2 and accepted S1.1 identity foundation | Not run | No S1.3 runtime work started or authorized | [Domain architecture](docs/architecture/DOMAIN-MODULE-ARCHITECTURE.md), [Roadmap](docs/roadmap/PRODUCTION-GRADE-PSA-ROADMAP.md). Runtime non-owner DB role, RLS/FORCE RLS, transaction-local tenant context and PgBouncer connection-reuse leakage proof are hard gates before any tenant-owned business relation. |
| S1.4 | Customer and contact master data | `PLANNED — BLOCKED UNTIL S1.3 TENANT ISOLATION GATE IS ACCEPTED` | Depends on accepted S1.3 | Not run | No S1.4 runtime work started or authorized | [Domain architecture](docs/architecture/DOMAIN-MODULE-ARCHITECTURE.md), [Roadmap](docs/roadmap/PRODUCTION-GRADE-PSA-ROADMAP.md). No customer/contact table or endpoint may precede S1.3's runtime-role, RLS and PgBouncer proof. |

### Status reconciliation notes

- This register preserves the historical pending states for S0.1–S0.4 and S0.6. S0.8 and S0.9 were subsequently owner-accepted on 13 November 2026; see their acceptance records and Section 7.1 below.
- S0.5 is an accepted test-only sub-slice; it does not close S0.
- S0.7's acceptance scope is local Kubernetes smoke + CI only, not production Kubernetes deployment.
- S0.8 and S0.9 are closed at their respective slice scopes based on the owner's explicit manual-acceptance confirmation; this does not claim that the entire S0 umbrella is complete.
- S0.10 remains explicitly owner-accepted and closed; do not repeat its restore drill merely to reconfirm it.

## 4. S0.10 accepted evidence — immutable summary

- Accepted repository SHA: `94536d65317aa513bdc715a39fbce2789dbb8709`.
- CI run #29: `43189431464`, success on that SHA; backend, frontend, and VPS deployment config gates passed.
- Archive: `flowlesshub-20261112T094448Z.dump`, 16,050 bytes, PostgreSQL `17.11`.
- Archive SHA-256: `eb9223274cbccbbca2fb54ad0fa82834040244b262479c5f39326f81993ca21c`.
- Archive catalog verification passed; manifest recorded 2 user schemas and 9 user relations.
- The archive, checksum sidecar, and manifest were copied to the Windows workstation; independently calculated workstation checksum matched the VPS checksum. This was an off-host workstation copy, not geographic/cloud off-site storage.
- Isolated restore into `flowlesshub_restore` passed with 2/2 schemas, 9/9 relations, `platform` present, restored size `8,115,891` bytes, and actual `pg_restore --exit-on-error --single-transaction` success. Reported restore duration was one second; this is not service RTO.
- Restore container used `--network none`, no published ports, 256 MiB memory, swap disabled, 0.50 CPU, an ephemeral anonymous data volume, and `--rm`. A later exact-name inspection confirmed auto-removal after a cleanup warning race.
- Post-drill production checks showed Blue active, FlowlessHub services healthy, API `/readyz` OK, Web HTTP 200, and all five Petshop containers still running. No Petshop resource or Nginx configuration was changed.
- S0.10 did not implement schedule, retention policy, geographic off-site storage, recurring restore schedule, or formal RPO/RTO objectives. Those are separate follow-ups and are not included in S0.10 acceptance.

## 5. S0.11 operational follow-up — not a product-development blocker

S0.11 remains open for explicit owner acceptance, but it no longer blocks local product development. The [14 November operational addendum](docs/acceptance/S0.11-current-runtime-status-2026-11-14.md) is the current state record and supersedes the 13 November snapshot below. The first natural timer-originated backup is now verified; do not continue to describe it as pending. Do not close S0.11 until the external restore, RPO/RTO measurement, and owner-acceptance gates are evidenced.

The following 13 November state is retained as a historical snapshot only. It is not the current runtime status; use the 14 November addendum and the S0.11 matrix row above for current status.

Current state at 13 November 2026 22:32 WIB:

- The daily `20:00 UTC` systemd timer is enabled and active. The next trigger is 14 November 2026 03:07:13 WIB; `LastTriggerUSec` is empty because the first natural scheduled invocation is still pending. The successful one-shot at 22:03 WIB preceded timer activation at 22:05:58 WIB and is not timer-trigger evidence.
- Mandatory Cloudflare R2 off-site upload is enabled. The latest one-shot created `flowlesshub-20261113T150329Z.dump`, SHA-256 `affddd4aa43b23c4a319064e1adae42d60cad5557dd196fed268f24f5bb0e2d3`, Restic snapshot `a8f6a98b60569be8e472425092490a5fe1e675971d739da0abb63d90c3e2bf91`; remote archive-triplet read-back matched and Discord success delivery returned HTTP 200.
- Owner-authorized local retention apply completed after final remote byte read-back. Only the eligible `20261113T001334Z` local artifact group was deleted. The 13 November 10:52 UTC and 15:03 UTC artifacts remain; the unmarked 12 November artifact remains protected.
- Approved remote policy is `--group-by host --tag flowlesshub --keep-last 2 --keep-daily 14 --keep-weekly 8 --keep-monthly 12`. The latest inventory had three matching snapshots; dry-run kept all three and found no removal candidate. No `forget`/`prune` was run after that dry-run.
- `FLOWLESSHUB_BACKUP_RETENTION_AUTO_PRUNE=1` controls local `backup-retention.sh --apply`; despite the name, it does not run remote Restic pruning.
- Monthly restore cadence and 24-hour RPO / 24-hour RTO targets are approved. The reminder is active, but there is no external disposable recovery environment; no external restore drill has been completed and RPO/RTO are not measured.
- Blue was active and all six FlowlessHub containers were `Up` at the latest observation. No production deployment, color switch, or Petshop/Frictiona mutation was part of this work.

### Historical owner decisions before activation

The earlier decision table is retained as a historical record. Use the current runtime addendum linked above for the activated timer, local retention, remote policy, alerting, restore, and RPO/RTO state.

## 6. Follow-up queue

1. Provision a dedicated external disposable recovery environment isolated from production and Petshop.
2. Complete the monthly restore drill in that environment and preserve verifiable restore evidence.
3. Measure actual recovery-point age and service recovery duration independently against the approved 24-hour RPO/RTO targets.
4. Re-run remote retention dry-run as snapshots age. Do not invoke remote `forget`/`prune` while there are no eligible removal candidates.
5. Obtain explicit owner acceptance of S0.11 after the remaining evidence is recorded; keep the broader S0 umbrella exit gate separate.

## 7. Checkpoint closure protocol

Before moving to the next checkpoint, update this register with exact implementation SHA, CI run, runtime evidence (if required), acceptance record link, owner status, and remaining follow-ups. Also update the canonical Windows/VPS operating runbook if command ownership or safety rules changed.

## 7.1 S0.8 and S0.9 owner acceptance reconciliation (13 November 2026)

- The repository owner explicitly confirmed in the project continuation conversation that manual acceptance for both S0.8 and S0.9 had been completed and accepted. This owner confirmation is recorded as the acceptance authority for these two slices.
- S0.8 exact-source CI: Run #26 (`43147198165`) on `e8f33bb7c0e92d4c49724dadde55d2378cbfddce`; Frontend and Backend quality gates passed.
- S0.9 exact-source CI: Run #27 (`43172335762`) on `20558818bca599782c822e9e3851e64cb979c369`; Frontend, Backend, and VPS deployment config gates passed. Executable-mode follow-up CI Run #28 (`43179520063`) on `2bfdc36106df4a65dad410e8c71e91cd580de21d` passed the same three jobs.
- S0.9 release workflow #1 (`43172457693`) completed successfully on the `flowlesshub-v0.1.0` release ref; release verification and all four GHCR image publication jobs passed on the successful attempt.
- The owner confirmed manual runtime acceptance. This reconciliation records the attestation and authoritative CI/release metadata; it does not fabricate command transcripts, probe payloads, timestamps, or runtime measurements that were not supplied in the repository record.
- Closure applies only to S0.8 and S0.9. It does not close the broader S0 definition of done, change any other checkpoint status, or authorize changes to production infrastructure.

## 8. S0.11 Discord alert runtime evidence (13 November 2026)

- Final source on the VPS: detached, clean `4166a78c4ae0f1b13691634f11d7081a43a3e9c7`. GitHub Actions Run #37 (`43392329836`) completed successfully on that exact SHA; Frontend quality gates, Backend quality gates, and VPS deployment config gates all passed. The alert implementation and its follow-ups also passed exact-SHA CI on `c4fac60` (Run #35, `43382145752`) and `d8b77a5` (Run #36, `43385936863`).
- The Discord credential file is present at `.vps-runtime/discord-webhook-url`, owned by `ubuntu:ubuntu`, mode `0600`; its value was not printed or committed. The installed systemd template uses `LoadCredential=`. The backup unit's `OnSuccess=` and `OnFailure=` hooks point to the respective `flowlesshub-backup-alert@` instances. Target systemd version was 255.
- Manual embed delivery was visually confirmed in the selected Discord channel on 13 November 2026 at 15:25:47 WIB / 08:25:47 UTC. HTTP 200; message ID `1570716297845538908`.
- Synthetic `OnFailure` fixture exited 1 as expected; its notifier delivered HTTP 200 with message ID `1570716771298713611`. Synthetic `OnSuccess` fixture exited 0; its notifier delivered HTTP 200 with message ID `1570716771353104457`. Both notifications were visually confirmed in Discord at approximately 15:27:41 WIB / 08:27:41 UTC. Both embeds explicitly identify the source unit and state that no backup job was started.
- Final journal scan covered 26 notifier entries: two manual-test successes, one synthetic success, one synthetic failure, and two historical sanitized failure records. The scan found zero Discord webhook URLs, credential assignments, bearer tokens, database URIs, backup archive filenames, 64-character SHA-256 values, or signed-URL parameters. Secret-safety and event-evidence checks passed.
- Runtime policy after tests: `FLOWLESSHUB_OFFSITE_ENABLED=0`; retention enabled with `KEEP_LAST=2`; `ALLOW_DELETE=0`; `AUTO_PRUNE=0`; no `restic forget`/`prune` command in the local retention script. No production backup was run as part of alert testing.
- Blue remained active. All six FlowlessHub containers and all five Petshop containers were running. `flowlesshub-backup.service` was inactive. `flowlesshub-backup.timer` remained disabled/inactive. Working tree was clean.
- Remaining S0.11 evidence/decisions: explicit owner acceptance is pending; timer activation remains a separate owner decision. Remote prune policy, recurring restore-drill cadence, and RPO/RTO remain undecided.

## 9. S0.11 mandatory-offsite production acceptance evidence (13 November 2026)

- Production source: detached, clean VPS checkout `151c8931cb9b00974c90406001590763d6050cf3`. GitHub Actions Run #40 (`43407844129`) passed Frontend quality gates, Backend quality gates, and VPS deployment config gates on that exact SHA.
- The installed `/etc/systemd/system/flowlesshub-backup.service` matched the committed unit and contained `FLOWLESSHUB_OFFSITE_REQUIRED=1`, `OnSuccess=flowlesshub-backup-alert@success.service`, and `OnFailure=flowlesshub-backup-alert@failure.service`. The timer unit matched source and remained disabled/inactive.
- One authorized production one-shot created `flowlesshub-20261113T105219Z.dump` (16,055 bytes; PostgreSQL 17.11; two user schemas; nine user relations). systemd reported `Result=success`, `ExecMainStatus=0`. Archive SHA-256: `9fceb92c098b1150e2b2495cb5b019f4053a70bbb3949d5616801d79745d0978`.
- Exact Restic snapshot: `feec38548a968365885708921812b84f145ede3bff0e5af032a5efaf697a7849`. Snapshot listing identified one `flowlesshub` artifact snapshot for this backup.
- Independent remote byte read-back from that exact snapshot matched all local files: archive `9fceb92c098b1150e2b2495cb5b019f4053a70bbb3949d5616801d79745d0978`; checksum sidecar `70b0038e380419fbd88606d4490adde2a2b6d53e8c20537f38b4b5075e3b7403`; manifest `caed8af89a20e504dd24ca558138bc6ed7b08742313642ccdf31520d8622cc8a`. Local archive, sidecar, manifest, and versioned upload marker were regular files, owner `ubuntu:ubuntu`, mode `0600`.
- The real systemd `OnSuccess` notifier delivered Discord HTTP 200; message ID `1570753254546087997`. This is a real production backup-success event, not a synthetic hook.
- Retention dry-run kept the 10:52 UTC artifact and the existing 00:13 UTC artifact; the 12 November artifact lacked an off-site marker and was retained. Eligible groups: zero. No local file was deleted and no remote snapshot was pruned.
- Final safety state: `FLOWLESSHUB_OFFSITE_ENABLED=0`; `FLOWLESSHUB_BACKUP_RETENTION_ALLOW_DELETE=0`; `FLOWLESSHUB_BACKUP_RETENTION_AUTO_PRUNE=0`; active color `blue`; backup timer `disabled/inactive`; backup service inactive after completion. No application restart, Blue/Green switch, or Petshop mutation was performed as part of this acceptance.
- The independent read-back proves the three backup artifacts are readable and byte-matched in R2. It is not a new PostgreSQL restore drill or a full Restic repository integrity audit. Explicit owner acceptance of S0.11 and separate timer activation approval remain outstanding.

## 10. Product strategy and roadmap realignment (14 November 2026)

- The owner-approved product direction is a complete production-grade IT Services PSA platform. MVP-first, pilot-first and demo-first scope boundaries are retired.
- The authoritative strategy and architecture documents are now [`PRODUCT-STRATEGY.md`](docs/product/PRODUCT-STRATEGY.md), [`DOMAIN-MODULE-ARCHITECTURE.md`](docs/architecture/DOMAIN-MODULE-ARCHITECTURE.md), [`PRODUCTION-ENGINEERING-CHARTER.md`](docs/architecture/PRODUCTION-ENGINEERING-CHARTER.md), and [`PRODUCTION-GRADE-PSA-ROADMAP.md`](docs/roadmap/PRODUCTION-GRADE-PSA-ROADMAP.md).
- The product strategy, domain architecture, roadmap and S1.2 scope reflect the owner's approved direction as of 14 November 2026; ADR-0001 is accepted. This records target direction and scope only, not implementation, CI, deployment, runtime acceptance or authorization to change production.
- S1.1 remains `CLOSED — OWNER ACCEPTED` against its backend/API-only scope and immutable implementation SHA `495383f38ec7c356b97bb66017b66a3380130eaf`. Its acceptance and release evidence are not rewritten.
- The first implementation workstream is S1.2 passwordless identity, first-party OIDC SSO, and authenticated web entry. Complete and review the S1.2-A implementation contract, threat analysis, exact origin/client configuration and browser-proven BFF/OIDC handoff before feature code begins. S1.3 must establish tenant authorization, membership lifecycle, separate runtime DB role, RLS and PgBouncer transaction-context isolation before S1.4 creates customer/contact or any other tenant-owned business data.
- S0.11 remains a separate open operational checkpoint with external restore, measured 24-hour RPO/RTO and owner-acceptance gates outstanding. Product roadmap progress does not close it.

## 11. S1.2 passwordless identity and first-party SSO scope decision (14 November 2026)

- The owner approved the S1.2 scope expansion to an internally managed Identity authority, WebAuthn/FIDO2 passkeys as the primary passwordless method, evidence-based MFA assurance, first-party OIDC SSO, same-origin Next.js BFF, SMTP transactional email, recovery and staged compatibility with S1.1 accounts.
- `docs/architecture/ADR-0001-passwordless-identity-and-first-party-oidc.md` is the accepted decision record; `docs/slices/S1.2-authenticated-web-entry-session-ux.md` and `docs/roadmap/PRODUCTION-GRADE-PSA-ROADMAP.md` define the implementation phases and acceptance gates.
- The decision changes documentation/scope only. S1.1 remains closed at `495383f38ec7c356b97bb66017b66a3380130eaf`; no authentication code, migration, secret, SMTP connectivity, DNS record or production runtime has changed.
- Exact SMTP connection settings and sender identity must be verified using owner-provided configuration. No credentials are to be committed or pasted into chat. Email OTP/magic-link authentication is prohibited; email is a transactional notification/address-confirmation channel only.
- S1.2 implementation has not started. Its first work item is S1.2-A: verify exact issuer/RP/login origins, OIDC client registry, BFF session binding, supported authenticator assurance, recovery/threat model and SMTP deliverability before selecting libraries or writing migrations.
- S1.3 continues to own organization membership/role policy, assurance requirements by privilege, external customer/vendor delegated authorization, runtime DB role, RLS and PgBouncer transaction-local isolation. S1.4 remains blocked until S1.3 is accepted.

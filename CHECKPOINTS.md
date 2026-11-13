# FlowlessHub — Checkpoint Register

**Repository:** `weexdayend/flowlesshub`
**Default branch:** `main`
**Last synchronized accepted repository baseline:** `94536d65317aa513bdc715a39fbce2789dbb8709`
**Synchronization date:** 13 November 2026
**Current active operational checkpoint:** S0.11 — Scheduled Backup Operations, Retention & Off-Site Recovery

> This register describes FlowlessHub only. It supersedes the unrelated IT Services PSA/ServicePilot roadmap that previously occupied this file. Do not use external project blueprints as FlowlessHub source-of-truth documents.

## 1. How to use this register

1. Read the canonical [`Windows ↔ VPS Operating Runbook`](docs/runbooks/FLOWLESSHUB-WINDOWS-VPS-OPERATING-RUNBOOK.md) first, then `README.md`, `AGENTS.md`, and this register.
2. Work only on the current active checkpoint after inspecting live `origin/main`.
3. Read the linked slice, runbook, and acceptance record before implementation or runtime commands.
4. Preserve historical baselines. Do not rewrite historical implementation SHAs to the current HEAD.
5. Tick acceptance only when the matching evidence exists. A prepared patch or green CI alone is not production acceptance.
6. Keep owner decisions separate from implementation details. Do not invent provider selection, retention period, backup cadence, alert destination, RPO, or RTO.

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
| S0.8 | Caddy edge and Blue/Green deployment foundation / edge validation repair | `IMPLEMENTED; ACCEPTANCE RECORD NEEDS RECONCILIATION` | Edge repair commit `e8f33bb7c0e92d4c49724dadde55d2378cbfddce`; repair history also documents earlier base `f949f896514cb871d1cbaeb2c01aac3195d6e546` | Run #26 on `e8f33...` passed per the S0.9 VPS runbook; the S0.8 repair acceptance file says it does not claim acceptance | Do not infer production acceptance from CI | [Slice](docs/slices/S0.8-caddy-edge-blue-green.md), [Acceptance](docs/acceptance/S0.8-edge-validation-repair.md), [Runbook](docs/runbooks/S0.8-caddy-edge-blue-green.md). Reconcile the acceptance record from evidence; preserve historical facts. |
| S0.9 | VPS-first Compose Blue/Green delivery hardening | `IMPLEMENTED; RUNTIME ACCEPTANCE PENDING IN CURRENT RECORD` | Foundation `e8f33...`; hardening commit `20558818bca599782c822e9e3851e64cb979c369`; executable-mode fix `2bfdc36106df4a65dad410e8c71e91cd580de21d` | Baseline CI run #26 passed; later exact-SHA evidence must be read from GitHub | Current S0.9 acceptance document still marks VPS runtime acceptance pending; do not silently change it | [New slice](docs/slices/S0.9-vps-first-hardening.md), [Acceptance](docs/acceptance/S0.9-vps-first-hardening.md), [Runbook](docs/runbooks/S0.9-vps-blue-green-deployment.md). Owner/runtime evidence reconciliation remains a follow-up. |
| S0.10 | Backup integrity and isolated restore drill | `CLOSED` | Implementation accepted at `94536d65317aa513bdc715a39fbce2789dbb8709`; scripts first hardened at `2bfdc36106df4a65dad410e8c71e91cd580de21d` | Run #29 / `43189431464` passed on exact accepted SHA | Owner accepted actual backup, off-host workstation checksum, isolated restore, production post-checks, and Petshop isolation on 12 Nov 2026 | [Slice](docs/slices/S0.10-backup-restore-drill.md), [Acceptance](docs/acceptance/S0.10-backup-restore-drill.md), [Runbook](docs/runbooks/S0.10-backup-restore-drill.md). Do not repeat the S0.10 drill merely to reconfirm it. |
| S0.11 | Scheduled backup operations, retention, and off-site recovery | `RUNTIME VERIFIED — BACKUP / OFF-SITE / RETENTION; ALERT & OWNER ACCEPTANCE PENDING` | Initial package against `94536d65317aa513bdc715a39fbce2789dbb8709`; current source `ad42e16bff5adc2b5c5a467d655066dd2586be50` | Run #32 / `43274241744` passed on `0bb29c1`; Run #33 / `43334005808` passed on `ad42e16`; all three CI jobs in each run passed | Manual systemd backup succeeded; local checksum, R2 archive-triplet read-back, Restic check + full data read (2/2 packs), retention dry-run, resource guards and Petshop isolation verified on 13 Nov 2026; timer disabled/inactive | [Slice](docs/slices/S0.11-scheduled-backup-operations.md), [Acceptance](docs/acceptance/S0.11-scheduled-backup-operations.md), [Runbook](docs/runbooks/S0.11-scheduled-backup-operations.md). Discord Incoming Webhook selected; source patch, VPS credential provisioning, actual delivery test, and explicit owner acceptance remain pending; timer activation, local deletion and remote prune are not authorized. |

### Status reconciliation notes

- This register intentionally preserves the source records' pending states for S0.1–S0.4, S0.6, S0.8, and S0.9 where current acceptance evidence is incomplete or internally inconsistent.
- S0.5 is an accepted test-only sub-slice; it does not close S0.
- S0.7's acceptance scope is local Kubernetes smoke + CI only, not production Kubernetes deployment.
- S0.8's runbook reports successful CI on the later edge foundation commit, while its acceptance record says acceptance is not claimed. This is a documentation reconciliation task, not permission to infer acceptance.
- S0.9's latest acceptance document says runtime acceptance is pending. The presence of a live VPS deployment elsewhere does not automatically prove every S0.9 checklist item; close it only after mapping exact evidence to its acceptance items.
- S0.10 alone is explicitly owner-accepted and closed in this synchronized register.

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

## 5. Active checkpoint gate — S0.11

S0.11 runtime acceptance is partially verified while the timer remains disabled: exact-SHA CI, manual one-shot service, R2 upload/read-back, full Restic repository data read, retention dry-run, resource guards, and FlowlessHub/Petshop isolation passed on 13 November 2026. External alert delivery and explicit owner acceptance remain open. Timer activation is a separate post-acceptance approval.

The current package defaults are fail-closed:

- systemd timer unit is installed but disabled and inactive; approved schedule is daily `20:00 UTC` with up to 15 minutes random delay;
- Cloudflare R2 is the approved provider; bucket is `flowlesshub`, region `auto`; credentials have been rotated, the Restic password recovery copy is held outside the VPS, and the repository is initialized. Off-site flag is reset to `0` outside a controlled manual run;
- retention dry-run is configured for keep-last 2; local deletion remains disabled (`ALLOW_DELETE=0`) and auto-prune remains disabled (`AUTO_PRUNE=0`);
- Discord Incoming Webhook selected by owner on 13 November 2026; source integration is prepared, while protected VPS credential provisioning and actual delivery test remain pending; RPO/RTO are not agreed;
- no restore is scheduled automatically;
- no production or Petshop service is restarted or modified by the proposed backup workflow.

### Owner decisions required before activation

| Decision | Current state | Required before |
|---|---|---|
| Backup cadence and time | Approved: daily 20:00 UTC (`03:00–03:15 WIB` next day) | Timer remains disabled; activation separately gated |
| Off-site provider / S3 endpoint / bucket / region | Approved and configured: Cloudflare R2; bucket `flowlesshub`; region `auto`; default jurisdiction used; R2 repository initialized | Keep endpoint and target scope unchanged unless a separate decision is made |
| Off-site credentials and Restic encryption password | Old disclosed credential revoked; new bucket-scoped Object Read & Write credentials provisioned; Restic password stored under protected runtime path and recovery copy confirmed outside VPS | Preserve secrets; rotate immediately if exposed |
| Local retention count | Approved: keep two newest; dry-run only | Runtime dry-run validation |
| Local deletion permission | Not approved; disabled | Any future `--apply` requires separate approval |
| Remote Restic retention/prune policy | Not designed | Remote snapshot pruning |
| Alert destination | Discord Incoming Webhook selected; protected VPS credential and end-to-end delivery pending | Timer activation |
| Recurring restore-drill cadence | Not selected; never auto-run by this timer | Restore schedule |
| RPO / RTO | Not agreed | Any formal recovery objective claim |

## 6. Follow-up queue

1. Reconcile S0.8 and S0.9 acceptance documents against exact source/CI/runtime evidence without rewriting historical baselines.
2. After item 4 passes, obtain explicit owner acceptance of S0.11. Keep timer disabled until separately authorized.
3. Design and validate remote Restic retention/prune policy separately; the S0.11 local retention script does not prune remote snapshots.
4. Provision and validate the selected Discord Incoming Webhook; do not activate the timer until manual delivery, synthetic hooks, and required acceptance evidence are recorded.
5. Define and rehearse recurring isolated restore cadence and service-level RPO/RTO after owner approval.
6. Keep broader S0 exit requirements open until the full S0 definition of done is evidenced.

## 7. Checkpoint closure protocol

Before moving to the next checkpoint, update this register with exact implementation SHA, CI run, runtime evidence (if required), acceptance record link, owner status, and remaining follow-ups. Also update the canonical Windows/VPS operating runbook if command ownership or safety rules changed.

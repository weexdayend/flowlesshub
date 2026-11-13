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
| S0.8 | Caddy edge and Blue/Green deployment foundation / edge validation repair | `CLOSED — OWNER ACCEPTED (13 Nov 2026)` | Edge repair commit `e8f33bb7c0e92d4c49724dadde55d2378cbfddce`; earlier repair base `f949f896514cb871d1cbaeb2c01aac3195d6e546` | CI Run #26 / `43147198165` passed on exact `e8f33...` (Frontend and Backend quality gates) | Owner confirmed manual S0.8 acceptance on 13 Nov 2026; the acceptance record documents the owner attestation without inventing unarchived terminal output | [Slice](docs/slices/S0.8-caddy-edge-blue-green.md), [Acceptance](docs/acceptance/S0.8-edge-validation-repair.md), [Runbook](docs/runbooks/S0.8-caddy-edge-blue-green.md). S0.8 slice is closed; the broader S0 exit gate remains separate. |
| S0.9 | VPS-first Compose Blue/Green delivery hardening | `CLOSED — OWNER ACCEPTED (13 Nov 2026)` | Foundation `e8f33...`; hardening commit `20558818bca599782c822e9e3851e64cb979c369`; executable-mode fix `2bfdc36106df4a65dad410e8c71e91cd580de21d` | CI Run #27 / `43172335762` passed on `205588...`; CI Run #28 / `43179520063` passed on `2bfdc...`; release workflow #1 / `43172457693` passed all four GHCR image jobs | Owner confirmed manual S0.9 VPS acceptance on 13 Nov 2026; the acceptance record captures that attestation separately from exact-SHA CI evidence | [Slice](docs/slices/S0.9-vps-first-hardening.md), [Acceptance](docs/acceptance/S0.9-vps-first-hardening.md), [Runbook](docs/runbooks/S0.9-vps-blue-green-deployment.md). S0.9 slice is closed; the broader S0 exit gate remains separate. |
| S0.10 | Backup integrity and isolated restore drill | `CLOSED` | Implementation accepted at `94536d65317aa513bdc715a39fbce2789dbb8709`; scripts first hardened at `2bfdc36106df4a65dad410e8c71e91cd580de21d` | Run #29 / `43189431464` passed on exact accepted SHA | Owner accepted actual backup, off-host workstation checksum, isolated restore, production post-checks, and Petshop isolation on 12 Nov 2026 | [Slice](docs/slices/S0.10-backup-restore-drill.md), [Acceptance](docs/acceptance/S0.10-backup-restore-drill.md), [Runbook](docs/runbooks/S0.10-backup-restore-drill.md). Do not repeat the S0.10 drill merely to reconfirm it. |
| S0.11 | Scheduled backup operations, retention, off-site recovery, and Discord alerts | `RUNTIME VERIFIED — BACKUP / OFF-SITE / RETENTION / DISCORD TEST DELIVERY; OWNER ACCEPTANCE PENDING` | Historical runtime baseline `ad42e16bff5adc2b5c5a467d655066dd2586be50`; alert integration `c4fac60333aef4462e9145988fd7a02298500717`; idempotency fix `d8b77a5a636eae7206bb50512eae46e443f8098c`; current source `4166a78c4ae0f1b13691634f11d7081a43a3e9c7` | Run #35 / `43382145752` on `c4fac60`, Run #36 / `43385936863` on `d8b77a5`, and Run #37 / `43392329836` on `4166a78`; all three jobs passed in each run | Manual Discord embed delivery and synthetic `OnSuccess`/`OnFailure` hooks returned HTTP 200 and were visually confirmed on 13 Nov 2026; journal secret-safety scan passed; Blue and all FlowlessHub/Petshop containers remained running; timer disabled/inactive | [Slice](docs/slices/S0.11-scheduled-backup-operations.md), [Acceptance](docs/acceptance/S0.11-scheduled-backup-operations.md), [Runbook](docs/runbooks/S0.11-scheduled-backup-operations.md), [Discord runbook](docs/runbooks/S0.11-discord-alert-integration.md). A real post-integration production backup-success alert, explicit owner acceptance, timer activation, local deletion, remote prune policy, recurring restore cadence, and RPO/RTO remain open/separately gated. |

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

## 5. Active checkpoint gate — S0.11

S0.11 runtime acceptance is partially verified while the timer remains disabled: exact-SHA CI, manual one-shot service, R2 upload/read-back, full Restic repository data read, retention dry-run, resource guards, FlowlessHub/Petshop isolation, and Discord manual/synthetic test delivery passed on 13 November 2026. The production-readiness patch adds a mandatory-offsite guard to scheduled execution; exact-SHA CI and VPS deployment remain pending. A real post-integration production backup-success alert and explicit S0.11 owner acceptance remain open. The production target is an enabled daily timer after the one-shot evidence and explicit activation approval.

The current package defaults are fail-closed:

- systemd timer unit is installed but disabled and inactive; approved schedule is daily `20:00 UTC` with up to 15 minutes random delay;
- Cloudflare R2 is the approved provider; bucket is `flowlesshub`, region `auto`; credentials have been rotated, the Restic password recovery copy is held outside the VPS, and the repository is initialized. The last recorded runtime flag was reset to `0`; set it to `1` in protected runtime config before the production one-shot and keep it enabled while the timer is enabled;
- retention dry-run is configured for keep-last 2; local deletion remains disabled (`ALLOW_DELETE=0`) and auto-prune remains disabled (`AUTO_PRUNE=0`);
- Discord Incoming Webhook selected by owner on 13 November 2026; protected VPS credential (`ubuntu:ubuntu`, mode `0600`), manual embed delivery, and synthetic success/failure hook deliveries are verified; a real post-integration production backup-success alert and owner acceptance remain pending; RPO/RTO are not agreed;
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
| Alert destination | Discord Incoming Webhook provisioned as a protected systemd credential; manual embed and synthetic success/failure deliveries confirmed | A real production backup-success notification remains pending; timer activation requires separate approval |
| Recurring restore-drill cadence | Not selected; never auto-run by this timer | Restore schedule |
| RPO / RTO | Not agreed | Any formal recovery objective claim |

## 6. Follow-up queue

1. Apply and validate mandatory-offsite scheduled execution on an exact-SHA green CI commit; set protected R2 config enabled, run one authorized post-integration production one-shot, and record its real Discord success alert. Then obtain explicit owner activation approval and enable the daily timer; keep local deletion and remote pruning disabled.
2. Design and validate remote Restic retention/prune policy separately; the S0.11 local retention script does not prune remote snapshots.
3. Define and rehearse recurring isolated restore cadence and service-level RPO/RTO after owner approval.
4. Keep broader S0 exit requirements open until the full S0 definition of done is evidenced.

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
- Remaining S0.11 evidence/decisions: a real post-integration `flowlesshub-backup.service` success alert requires a separately authorized production one-shot; explicit owner acceptance is pending; timer activation remains a separate owner decision. Remote prune policy, recurring restore-drill cadence, and RPO/RTO remain undecided.

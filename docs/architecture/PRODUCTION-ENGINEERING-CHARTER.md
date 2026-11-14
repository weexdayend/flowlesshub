# FlowlessHub — Production Engineering Charter

**Status:** Prepared for owner review; engineering requirements for the complete PSA product.
**Strategic baseline:** `c6e31e03204de8035af9ef0bf2e0f0f187f8f297`
**Applies to:** Every API, web, worker, migration, business module, operational procedure and release.

## 1. Quality objective

FlowlessHub is engineered for real operational use from its foundations. A slice is not complete because it compiles, looks finished, passes a happy-path demo or has been deployed. It is complete when its promised workflow is persisted, secure, correct under concurrency and failure, observable, supportable and accepted against evidence.

The charter does not require a reckless big-bang build. It requires each incremental slice to meet its production boundary before the next dependent slice relies on it.

## 2. Security and tenant isolation

### 2.1 Identity and session security

- Preserve global identity with organization-scoped membership and authorization.
- Keep session credentials opaque, high entropy, revocable and inaccessible to browser JavaScript. Persist only a one-way digest.
- Production cookies are host-only, `HttpOnly`, `Secure`, narrowly scoped and `SameSite`-appropriate. Cookie topology must support authenticated SSR and protected routing without token exposure.
- Mutating cookie-authenticated requests require a tested CSRF/Origin strategy. CORS is not a substitute for CSRF protection.
- Login abuse control must work across active API instances or be paired with enforceable edge controls; the current in-memory limiter is per process and is not a cluster-wide policy.
- Document expiry, logout, account disable, recovery, password change, session inventory and future MFA/passkey semantics. Do not add self-service registration or account recovery without verified identity and abuse controls.

### 2.2 Authorization

- Define organization roles and resource permissions explicitly; enforce them in Go services on every endpoint and background job.
- Deny by default. The selected organization is not trusted until membership and resource permission have been verified.
- Model separation of duties for approvals, money, contracts, ownership and privileged administration.
- Protect the final-active-owner invariant under concurrent membership changes before exposing removal, suspension or demotion workflows.
- Customer, vendor and internal projections are separate API contracts. Authorization tests must assert prohibited fields are absent, not merely hidden in the interface.

### 2.3 PostgreSQL and PgBouncer isolation

Before any tenant-owned business table is merged, require:

- A separate migration/owner role and non-owner application runtime role.
- Runtime role must not be superuser, table owner or `BYPASSRLS`.
- RLS enabled and `FORCE ROW LEVEL SECURITY` where appropriate, with deny-by-default policies.
- Tenant context established from an authenticated membership and permission decision inside each database transaction using transaction-local state.
- All tenant queries executed through the context-bearing transaction; no unscoped pool query for tenant data.
- PgBouncer transaction-pool leakage tests across reused connections, including commit, rollback, cancellation, timeout and query failure.
- Direct-SQL negative tests proving the runtime role cannot cross tenants even without an application filter.
- Migration and privilege tests that fail if a business table is added without isolation coverage.

The current production Compose configuration uses PgBouncer transaction pooling for API traffic, but the current API and migration configuration share the configured DB user and no RLS/non-owner role proof exists. This remains a hard precondition to business-data schema work.

## 3. Data integrity and business correctness

- PostgreSQL is the source of truth for transactional records. Cache, frontend state and integrations are not authoritative.
- Use PostgreSQL `NUMERIC` and decimal arithmetic for every monetary amount, quantity-derived amount and rate where precision matters. Never use `float32`/`float64` as money.
- Specify currency, precision/scale, rounding stage, tax basis/effective date, timezone, date-only versus instant semantics and exchange-rate source/observation date.
- Enforce important invariants with database constraints, foreign keys, unique indexes and transaction boundaries where appropriate—not only service validation.
- Critical workflows are explicit state machines with named actors, allowed transitions, invalid-transition behavior, timeout/expiry and compensating action.
- Retryable commands have idempotency keys or unique source references. Webhooks, worker jobs and invoice/payment operations must tolerate duplicate delivery.
- Use optimistic versioning or row locks for concurrent edits, approvals, sequence allocation, final-owner changes, payment allocation and financial adjustments.
- Preserve issued/approved/signed evidence as immutable snapshots. Correct mistakes with a new version, amendment, credit, reversal or compensating event.
- Design schema changes as expand → migrate/backfill → switch → contract; maintain N-1 compatibility for API, worker and database across Blue/Green rollout.
- Every migration has lock and statement timeouts, reviewed lock impact, forward/rollback strategy, index plan and production-sized rehearsal where risk requires it.
- Domain-generated documents record template version, source record/version, rendered artifact hash, issuer and timestamp.

## 4. Audit, privacy and evidence

- Emit actor-attributed audit events for authentication/security, role and permission changes, approvals, financial actions, contract/quotation issue, baseline changes, document access/export, payment allocation, UAT/BAST and privileged operations.
- Audit evidence is append-only from application workflows; correction is a compensating entry, not rewrite. Protect it from tenant and service-role tampering.
- Business mutations and their audit evidence commit atomically or use a transactionally written outbox with idempotent delivery.
- Record correlation/trace IDs through HTTP, database transactions, worker jobs and outbound integrations. Redact credentials, tokens, private customer data and payment data from logs.
- Classify personal, customer, contract, financial and credential data. Define retention, archival, legal hold, export and erasure policy before the affected data lifecycle is shipped.
- Document downloads and externally shared links require tenant/record authorization, bounded expiry and audit.

## 5. Reliability and operability

### 5.1 Application observability

The current API uses structured JSON logging and request IDs and exposes `/livez` and `/readyz`. The current repository does not yet demonstrate application metrics, distributed traces, service-level dashboards or actionable application alerts. The first product slices must extend this foundation rather than claim observability is complete.

Each production service/workflow must define:

- Structured logs with request, actor, organization, module, job and correlation identifiers where safe.
- Metrics for request rate, error rate, latency, saturation, database pool health, worker queue depth/age/retries, webhook delivery and business-critical workflow failures.
- Trace propagation across HTTP, SQL and worker boundaries where enabled.
- Readiness that reflects dependencies needed to serve traffic, liveness that does not cause restart loops for recoverable dependency faults, and graceful shutdown/drain behavior.
- Actionable alerts with owner, severity, threshold, runbook and suppression/escalation policy.
- Capacity budgets for CPU, memory, database connections, query duration, payload/document size and background work.

### 5.2 SLOs and error budgets

Define service-level indicators and propose SLOs for API availability/latency, critical workflow completion, job processing delay and backup/recovery before committing a production service tier. Record targets, measurement windows, exclusions and error-budget policy in an ADR or operational policy.

No numerical application SLO or achieved error budget is currently evidenced. Do not invent a target and later report it as measured.

### 5.3 Background processing

- Every job declares ownership, input schema/version, idempotency, retryable/permanent error classification, timeout, backoff, concurrency and terminal/manual-repair behavior.
- Workers acknowledge only after durable state transition. Duplicate jobs cannot duplicate invoices, notifications, payment allocation or document versions.
- Outbox dispatch is durable and bounded; failed delivery is visible and replayable.
- Queue health includes oldest-job age, retry counts, dead-letter/manual-repair queue and worker liveness.
- The current River worker contains only a no-op bootstrap handler. The first job-bearing feature must establish these controls; do not treat River installation as production job capability.

### 5.4 Backup and disaster recovery

S0.11 is a separately tracked operational checkpoint and is not a reason to stop local product engineering. The 14 November runtime addendum records a natural systemd timer-triggered backup, successful archive verification, Restic/R2 off-site upload and targeted read-back, Discord OnSuccess delivery, and a local keep-newest-2 retention apply after remote read-back.

S0.11 remains **OPEN** because:

- A dedicated external disposable recovery environment has not been provisioned.
- No external restore drill has been completed.
- Approved 24-hour RPO and 24-hour RTO objectives have not been measured.
- Remote Restic `forget`/`prune` has not been applied.
- Explicit owner acceptance is pending.

Do not label backup upload/read-back as restore proof or infer service RTO from database restore duration. Do not change retention, remote pruning or production restore state without their documented gates and explicit authorization. Keep this status separate from product slice acceptance.

## 6. API and frontend product quality

- OpenAPI is the contract source. Generated Go and TypeScript output must be reproducible and clean in exact-SHA CI.
- Use consistent pagination, filtering, error envelopes, idempotency and concurrency semantics.
- Frontend routes are organization-aware and authenticated, but backend authorization remains authoritative.
- Every consequential action gives the actor a clear outcome and recovery path.
- Every workflow supports loading, empty, error, retry, permission-denied, stale/conflict and expired-session states as applicable.
- Responsive layout, keyboard operation, semantic controls, accessible labels, contrast, focus management and reduced-motion behavior are acceptance requirements.
- Avoid mock fixtures or hard-coded dashboard aggregates in a claimed production workflow.
- Customer/vendor views are permission-filtered at the API boundary and tested against internal-only fields.
- Document upload/download requires content-type/size validation, safe storage, malware/content inspection where appropriate and authorization on every access.

## 7. Supply-chain and release security

- CI runs on the exact proposed SHA. A prior green run does not validate a later commit.
- Keep dependency locks, reproducible generation and migration lint. Do not weaken required gates to obtain a pass.
- Add dependency vulnerability, static-analysis, secret scanning, container scanning, SBOM/provenance and artifact-integrity controls with explicit severity policy and exception expiry.
- Pin GitHub Actions and third-party build dependencies by immutable revision/digest where feasible; version tags alone are mutable references.
- Run containers with least privilege, minimal images, read-only filesystems where compatible, bounded resources and no unnecessary capabilities.
- Protect secrets through the approved secret store/runtime files; never include secret values in logs, command arguments, patches or repository artifacts.
- Publish immutable commit-addressed images. Record image digest and provenance against the source SHA.
- Production deployment uses the accepted dedicated VPS Docker Compose Blue/Green workflow and exact release artifacts. Never deploy a moving `main` ref.
- Database migrations remain backward-compatible with the adjacent Blue/Green application versions.

Current CI verifies frontend/backend quality, generated API outputs, architecture and migration checks, tests/race detector, image builds and VPS configuration. Do not claim vulnerability scanning, SBOM signing or full artifact provenance unless the workflow and evidence actually implement them.

## 8. Production Definition of Done — mandatory for every slice

A slice is not complete until all applicable items below have evidence:

1. **Business outcome:** a real operator can complete the promised workflow using persisted records and the documented roles.
2. **Domain model:** entities, ownership, states, transitions, invariants and exception paths are reviewed.
3. **Database:** additive migration, constraints, indexes, tenant RLS, privilege model, backfill/rollback and expand/contract behavior are verified.
4. **API:** OpenAPI contract, generated Go/TypeScript output, validation, authorization, idempotency and concurrency responses are correct.
5. **Frontend:** authenticated, permission-aware workflow has responsive/accessibility, loading/error/empty/recovery and conflict states.
6. **Isolation/security:** cross-tenant negative tests, role/permission tests, CSRF/session controls, secret/log redaction and relevant threat tests pass.
7. **Correctness:** state-machine, property/table-driven, concurrency, duplicate/retry, failure-injection and financial golden tests pass where applicable.
8. **Audit:** security- and business-critical mutations are traceable to actor, tenant, source version and timestamp.
9. **Observability:** metrics/logs/traces, actionable alerts, dashboards and a support runbook exist for the new failure modes.
10. **Reliability:** worker retry/recovery, graceful shutdown, dependency failure and data-repair behavior are tested.
11. **Operations:** capacity/resource impact, migration compatibility, backup/restore implications, deployment/rollback and incident procedures are reviewed.
12. **Supply chain:** exact-SHA CI, generated-artifact checks, dependency/security policy and immutable image evidence pass.
13. **Acceptance:** manual scenarios, expected outcomes, non-secret evidence, owner approval and checkpoint status are recorded separately.

An item may be marked not applicable only with a written rationale in the slice record. There is no generic later “hardening” phase that excuses missing correctness, tenant security or operability at a slice boundary.

## 9. Release and change-control discipline

- Continue the repository's controlled sequence: audit → slice specification → owner decisions → patch → local review → commit/push → exact-SHA CI → runtime validation only when required → acceptance evidence → checkpoint closeout.
- Distinguish `PREPARED`, `APPLIED`, `COMMITTED`, `PUSHED`, `CI VERIFIED`, `RUNTIME VERIFIED`, `OWNER ACCEPTED` and `CLOSED`.
- A docs-only strategy patch needs local patch review and relevant documentation/path validation; it does not require VPS access, production deployment, migration or runtime testing.
- Production deployment, migration, rollback, restore, retention deletion or remote pruning requires the exact procedure, evidence, resource guards and explicit authorization described in the canonical Windows/VPS runbook.
- Preserve Petshop and Frictiona isolation. Never alter their containers, databases, volumes, networks, ports, Compose files or Nginx virtual hosts. Never run global Docker prune or `docker compose down -v`.
- Preserve historical implementation SHAs and acceptance evidence; do not rewrite S1.1 or operational checkpoint history to make the new strategy look continuous.

## 10. Review triggers

Revisit the charter when workload/tenant volume, data residency, security threat model, legal obligations, SLO commitments, integration consistency, or deployment topology changes materially. Any change to security invariants, transaction boundaries, tenant ownership or production release rules requires an ADR and regression evidence.

# Technical Architecture and Delivery Plan: IT Services PSA Platform

*Companion to the Product Blueprint (https://claude.ai/artifact/FKjqrQQPgBcGxJqnoz8X45). Audience: AI coding agents and the solo developer. Read the Blueprint first for domain rules; this document defines the stack, architecture, security model, zero-downtime strategy, sprint-sliced build plan and agent working rules. Where the two conflict on domain behavior, the Blueprint wins; on technology, this document wins.*

## 1. Delivery Model and Constraints

- **One developer plus code agents.** Optimize for consistency, generated-code safety and low operational load, not for team-scale patterns.
- **No throwaway MVP.** The full product is built module by module in vertical slices. Each slice ships to production behind feature flags and is usable on its own. The founder's company dogfoods from Milestone M1 onward (Section 14).
- **Zero planned downtime**, including database migrations.
- **Strong security posture** including post-quantum (PQ) cryptography where it is real and standardized today (Section 6).
- **Multi-tenant SaaS-ready from sprint 0**; the first tenant is the founder's company.
- Versions below are targets. The agent MUST pin exact versions at scaffold time and re-verify security advisories before each release.

## 2. Technology Stack

### 2.1 Frontend

| Concern | Choice | Notes |
| --- | --- | --- |
| Framework | Next.js (current stable, App Router), React, TypeScript strict | Server Components for data-heavy pages, Client Components for interactive ones |
| Styling | Tailwind CSS plus design tokens (CSS variables) | Light and dark themes from day one |
| Components | shadcn/ui | Copied into repo under `packages/ui`; wrapped, never edited ad hoc |
| Icons | Phosphor Icons (`@phosphor-icons/react`) | One icon wrapper with weight and size tokens |
| Motion (UI) | Framer Motion (`motion`) | Page, list, dialog and layout transitions; respects reduced-motion |
| Motion (advanced) | GSAP | Timeline/Gantt drag interactions, marketing pages, onboarding sequences. Verify the current license terms before commercial use |
| Server state | TanStack Query | Typed against generated API client |
| Tables and lists | TanStack Table and TanStack Virtual | Mandatory virtualization for lists over 200 rows |
| Forms | React Hook Form plus Zod | Zod schemas generated or mirrored from OpenAPI |
| URL state | nuqs | Filters and views are shareable links |
| Rich text | Tiptap | Comments, descriptions, templates |
| i18n | next-intl | Bahasa Indonesia and English; all strings externalized |
| Charts | Recharts or visx | Financial and utilization dashboards |
| Testing | Vitest, Testing Library, Playwright | Playwright covers critical journeys |

### 2.2 Backend

| Concern | Choice | Notes |
| --- | --- | --- |
| Language | Go (latest stable; use the newest patch of the current release, because recent patch releases fixed standard-library vulnerabilities) | Go 1.27 adds `crypto/mldsa`; Go 1.24+ has `crypto/mlkem` and hybrid PQ key exchange in TLS |
| Style | Modular monolith, one deployable binary with `api` and `worker` entry points | Strict module boundaries enforced by lint (`depguard` or `go-arch-lint`) |
| HTTP | `chi` router with OpenAPI-first generation (`oapi-codegen`, strict server) | Spec is the contract; TS client generated from it |
| DB access | PostgreSQL via `pgx` v5 and **sqlc** | Hand-written SQL, generated type-safe Go; no ORM |
| Migrations | `goose` with `squawk` (or equivalent) lint in CI | Expand/contract only (Section 5) |
| Jobs | River (Postgres-backed queue) | Transactional enqueue, retries, schedules; removes need for a separate broker |
| Cache and rate limit | Valkey (Redis-compatible) | Optional at start; never source of truth |
| Object storage | S3-compatible (Cloudflare R2, MinIO, or an Indonesian provider if residency requires) | Presigned URLs, client-side-encrypted payloads |
| Search | PostgreSQL full-text and trigram first; Meilisearch later if needed |  |
| Realtime | Server-Sent Events for notifications and live board updates | WebSocket only if proven necessary |
| Docs rendering | Template engine for DOCX plus Gotenberg (headless) for PDF | Runs as an isolated service |
| Validation | `go-playground/validator` plus domain-level invariants |  |
| Money | `shopspring/decimal` in Go, `NUMERIC(20,4)` in Postgres, ISO currency code per amount | Floats are forbidden for money |
| Logging and tracing | `slog`, OpenTelemetry | Trace ID in every log line and audit entry |
| Config and secrets | Environment plus a secret manager (SOPS/age or cloud KMS) | No secrets in repo |

### 2.3 Data and Infrastructure

- **PostgreSQL** (managed or self-run with streaming replica), `pgBouncer` in transaction mode, PITR backups via `pgBackRest` or provider equivalent, restore drills each quarter.
- **Row-Level Security** on every tenant table; each transaction runs `SET LOCAL app.tenant_id = ...`.
- **Containers:** Docker; start on a small cluster behind Caddy or Traefik with blue/green; graduate to k3s or managed Kubernetes when the second tenant arrives. Keep manifests Kubernetes-compatible from the start.
- **CI/CD:** GitHub Actions: lint, unit, integration (Testcontainers), migration lint, OpenAPI diff check, build, scan (Trivy, govulncheck, npm audit), deploy.
- **Observability:** Grafana stack (Prometheus, Loki, Tempo) or a managed equivalent, plus Sentry for frontend and backend errors.
- **Region:** primary in Indonesia or nearest low-latency region; confirm data-residency requirements per target customer.

## 3. System Architecture

```
Browser (Next.js app: internal app, client portal, vendor portal)
   |  HTTPS, hybrid PQ key exchange at the edge
Edge / Reverse proxy (Caddy or Traefik, WAF, rate limits)
   |
+--------------------- Go modular monolith ---------------------+
|  api (REST/OpenAPI, SSE)        worker (River jobs, schedulers)  |
|  modules: identity, tenancy, rbac, audit, crm, catalog, rab,     |
|  quotation, contract, project, task, timeline, finance, uat,     |
|  bast, vault, template, procurement, vendor, changerequest,      |
|  automation, notification, hrms, itsm, reporting, billing        |
+---------+---------------+--------------+----------+-------------+
          |               |              |          |
     PostgreSQL     Object storage     Valkey    Gotenberg
   (RLS, outbox)   (encrypted blobs)  (cache)   (PDF render)
          |
   External: e-sign provider, email, WhatsApp, accounting export, payment gateway (SaaS billing)
```

### 3.1 Module rules

- Each module owns its tables (prefix per module), its SQL (sqlc package), its service layer and its HTTP handlers.
- Modules talk through **service interfaces and domain events**, never through another module's tables.
- Cross-module reads for reporting go through dedicated read models or views owned by `reporting`.
- Domain events are written to an **outbox table in the same transaction**, then dispatched by workers (automation, notification, audit, search indexing).

### 3.2 Cross-cutting kernel (built in Sprint 0 to 1)

`tenancy`, `authn`, `authz`, `audit`, `statemachine`, `numbering`, `outbox`, `money`, `visibility`, `files`, `errors`, `pagination`, `idempotency`, `featureflags`.

- **State machine kernel:** declarative transitions per entity (RAB, quotation, contract, project, milestone, task, invoice, CR, BAST, ticket). Illegal transitions are rejected server-side; every transition emits an event and an audit entry.
- **Visibility kernel:** every externally-exposable entity has a `visibility` column. Client and vendor endpoints use **separate DTOs and separate SQL queries** that never select cost, margin or vendor pricing columns. A CI test scans client/vendor OpenAPI schemas for forbidden fields.
- **Idempotency:** all mutating endpoints that create money or documents accept an `Idempotency-Key`.

## 4. Data Layer Rules

1. Every business table: `id` (UUIDv7), `tenant_id`, `created_at`, `created_by`, `updated_at`, `row_version` (optimistic concurrency).
2. RLS policy on every tenant table; the application database role is **not** a superuser and cannot bypass RLS. A migration test fails the build if a table with `tenant_id` lacks a policy.
3. Soft delete (`deleted_at`) for business records; hard delete only through a tenant data-erasure job.
4. Money columns use `NUMERIC(20,4)` plus `currency` and, where relevant, tax breakdown columns; rounding rules are centralized in `money`.
5. Immutable records (issued invoices, signed contracts, approved RAB versions, audit entries) are enforced by triggers plus application rules; corrections use credit notes, addenda or new versions.
6. Document metadata lives in Postgres; blobs live in object storage keyed `tenant/{tenant_id}/{project_id}/{doc_id}/{version}`.
7. All SQL lives in `.sql` files under each module; sqlc output is committed; agents never write raw SQL strings inside Go code.
8. Index policy: every foreign key and every `tenant_id`-leading filter path is indexed; new indexes are created `CONCURRENTLY`.

## 5. Zero-Downtime Strategy

### 5.1 Deployment

- **Blue/green (initial) or rolling (Kubernetes)** with readiness and liveness probes; traffic shifts only after readiness passes.
- **Graceful shutdown:** on SIGTERM stop accepting requests, drain in-flight requests and finish or re-queue jobs (River handles retries); SSE clients reconnect automatically.
- **N-1 compatibility:** any two adjacent versions of API, worker and database schema MUST run together. The OpenAPI diff check in CI blocks breaking changes unless the endpoint is versioned.
- **Feature flags** (table-backed, per tenant) decouple deploy from release; every new module ships dark first.

### 5.2 Migrations (expand, migrate, contract)

1. **Expand:** add nullable columns, new tables, new indexes (`CONCURRENTLY`). Never rename or drop in the same release.
2. **Migrate:** dual-write or backfill in batches via a worker job; verify counts.
3. **Switch:** release code that reads the new structure.
4. **Contract:** drop old structures in a later release after one full release cycle.

- Every migration sets `lock_timeout` and `statement_timeout`; adding `NOT NULL` or foreign keys uses the `NOT VALID` then `VALIDATE` pattern.
- Migration lint in CI rejects table rewrites, blocking index builds and unsafe defaults.
- Every migration is rehearsed in CI against a production-sized synthetic dataset before reaching prod.

### 5.3 Data safety

- PITR backups, daily full plus WAL archiving, encrypted, restore tested quarterly with a recorded RTO and RPO.
- Read replica for reporting load once needed; connection pooling through pgBouncer.
- Outbox plus idempotent consumers guarantee at-least-once processing without duplicate side effects.

## 6. Security and Post-Quantum Cryptography

**Threat model emphasis:** tenant isolation, leakage of cost and margin data, document tampering, credential theft, and **harvest-now-decrypt-later** attacks against long-lived contract and financial documents.

### 6.1 What is post-quantum ready today (use it)

| Layer | Control | Detail |
| --- | --- | --- |
| Transport key exchange | Hybrid **X25519MLKEM768** in TLS 1.3 | Supported by Go's `crypto/tls` (default in recent Go releases) and by current major browsers; terminate TLS in Go or in a proxy built on it (Caddy) or a CDN that supports it, and verify with a handshake test in CI |
| Data at rest | **AES-256-GCM** (or XChaCha20-Poly1305) envelope encryption | 256-bit symmetric keys are considered quantum-resistant |
| Key wrapping | **ML-KEM-768** (FIPS 203), preferably hybrid with X25519 | Per-tenant key-encryption key (KEK) wraps per-document data keys (DEK); use Go `crypto/mlkem` or hybrid KEMs in `crypto/hpke` |
| Signatures for integrity | **ML-DSA** (FIPS 204) via `crypto/mldsa` (Go 1.27+) or the `filippo.io/mldsa` compatibility wrapper | Signs audit-log chain checkpoints, document hash attestations, export manifests and outgoing webhooks |
| Hashing | SHA-384 or SHA3-256 | Document fingerprints and audit hash chain |
| Passwords | Argon2id | Plus breached-password checks |

### 6.2 Honest limits (do not over-claim)

- Public CAs do not yet issue broadly trusted PQ certificates; server authentication in TLS remains classical for now. Design for **crypto agility** so certificates and signatures can migrate.
- WebAuthn passkeys and most OIDC providers are classical today; use them, and track PQ updates.
- **ML-DSA signatures are integrity proofs, not legally binding e-signatures.** For contracts and BAST with legal force in Indonesia, integrate a certified e-signature provider (or accept uploaded wet-signed scans) and store its evidence alongside the internal ML-DSA attestation.
- Keep cryptography on standard-library or well-audited implementations; never hand-roll primitives. Use the Go FIPS 140-3 module mode where compliance requires it, noting that module coverage of newer algorithms may lag.

### 6.3 Crypto agility

Every ciphertext, wrapped key and signature carries a **versioned header** (`alg`, `kid`, `version`). Rotation jobs re-wrap DEKs under new KEKs without re-encrypting blobs. A single `cryptokit` package is the only place primitives are called.

### 6.4 Application security

- **AuthN:** httpOnly, Secure, SameSite cookies for sessions; short-lived access plus rotating refresh; passkeys (WebAuthn) and TOTP; optional SSO (OIDC/SAML) for tenants later; device and session management; brute-force protection.
- **AuthZ:** project-scoped RBAC (`resource:action`), evaluated in Go services, plus RLS as the second wall. Authorization tests are table-driven and mandatory for every endpoint.
- **Tenant isolation tests:** an automated suite creates two tenants and attempts cross-tenant reads and writes on every endpoint; the build fails on any leak.
- **Input and output:** strict validation, output encoding, CSP with nonces, CSRF protection for cookie sessions, file-type sniffing, malware scanning (ClamAV) on uploads, size limits.
- **Secrets and keys:** KMS or HSM-backed root keys where available; no plaintext KEKs on disk; break-glass procedure documented.
- **Audit:** append-only, hash-chained entries, checkpoints signed with ML-DSA and exported to separate storage.
- **Supply chain:** pinned dependencies, SBOM, `govulncheck`, Dependabot, signed container images, minimal base images.
- **Privacy:** data classification, field-level encryption for sensitive fields (tax IDs, bank details), UU PDP-aligned retention, export and erasure tooling.
- **Pen test and threat model review** before the first external tenant.

## 7. Frontend Architecture

- **Monorepo** (pnpm and Turborepo): `apps/web` (internal app plus portals as route groups, separable by subdomain), `packages/ui`, `packages/api-client` (generated), `packages/config`.
- **Routing:** `(app)` internal, `(client)` client portal, `(vendor)` vendor portal, `(auth)`, `(marketing)`. Portals use their own layout, navigation and permission guard.
- **Data flow:** Server Components fetch via the generated client with the session cookie forwarded to the Go API; mutations through Server Actions or client mutations calling the same API. No business logic in the frontend beyond presentation and optimistic UX.
- **Design system:** tokens, density modes (comfortable and compact for data-heavy screens), accessible by default (Radix primitives via shadcn), keyboard-first command palette.
- **Motion policy:** Framer Motion for state transitions (under 250 ms, easing consistent); GSAP only for complex timeline or scroll choreography; all animation disabled under `prefers-reduced-motion`.
- **Heavy components:** Gantt/timeline (custom SVG or canvas with virtualization and GSAP-assisted drag), kanban (dnd-kit), RAB grid (editable table with keyboard navigation, formula-safe decimal math through a shared money util), document viewer, approval inbox.
- **Performance budgets:** LCP under 2.5 s on mid-range hardware, route-level code splitting, streaming with Suspense, images through Next Image.
- **Offline-tolerant field mode:** PWA for technicians (checklists, photo evidence, timesheet) with a sync queue; introduced in the Project and HRMS slices.

## 8. API Contract

- OpenAPI 3.1 is the source of truth, stored in `api/openapi.yaml`; Go server stubs and TS client are generated and committed.
- Conventions: REST, plural nouns, cursor pagination, `Idempotency-Key`, RFC 9457 problem details, ETag or `row_version` for concurrency, consistent filtering and sorting parameters.
- Public API and webhooks (signed with ML-DSA, with HMAC fallback for consumers that cannot verify it) are exposed in the SaaS slice but designed in from the start.

## 9. Repository Layout

```
/apps/web                 Next.js app
/packages/ui              shadcn-based design system
/packages/api-client      generated TS client
/services/api             Go: cmd/api, cmd/worker, internal/<module>/{http,service,sql,domain}
/services/api/internal/kernel   cross-cutting kernel
/services/api/db/migrations    goose migrations
/api/openapi.yaml
/deploy                   Docker, compose, k8s manifests, Caddy config
/docs                     blueprint.md, tech.md, ADRs, runbooks
/AGENTS.md                rules for coding agents
/CHECKPOINTS.md           sprint checklists
```

## 10. Working Agreement for Code Agents

1. **Read order:** Blueprint, this document, `AGENTS.md`, then the current sprint block in `CHECKPOINTS.md`.
2. **Spec before code:** for each slice write a short ADR or slice spec (entities, states, endpoints, permissions, events) and get it approved by the developer, then implement.
3. **Vertical slice per task:** migration, SQL, domain, service, handler, OpenAPI, generated client, UI, tests, docs, feature flag.
4. **Definition of Done (every slice):**
   - Tenant isolation and authorization tests pass
   - State machine transitions covered by tests, including illegal ones
   - Audit entries emitted for approvals, money, permissions and documents
   - Client and vendor DTOs verified free of cost and margin
   - Migration is expand/contract and lint-clean
   - Feature flag in place; deployed to staging, then production, with zero downtime
   - i18n strings externalized (ID and EN); accessibility checks pass
   - Docs and checkpoint ticks updated
5. **Test pyramid:** unit (domain and money), integration (Testcontainers Postgres, real RLS), contract (OpenAPI), e2e (Playwright critical journeys), property tests for state machines and financial rollups, load tests before each milestone.
6. **Never:** use floats for money, bypass RLS, query another module's tables, edit generated code by hand, commit secrets, or merge failing checks.
7. **Ambiguity:** list the assumption and ask rather than choosing silently.

## 11. Sprint Plan (Per-Module Slicing)

**Cadence:** two-week sprints. **Assumption:** one developer plus agents sustain roughly one vertical slice per sprint. Recalibrate velocity after Sprint 4 and adjust the whole plan; the order matters more than the dates. Every sprint ends with a production deploy of its slice behind a flag.

| Sprint | Weeks | Module slice | Backend | Frontend | Exit gate |
| --- | --- | --- | --- | --- | --- |
| S0 | 1-2 | Foundation | Monorepo, CI/CD, Docker, Postgres, goose, sqlc, River, OTel, blue/green deploy, PQ TLS handshake test, `cryptokit` skeleton | Next.js shell, Tailwind tokens, shadcn setup, Phosphor wrapper, motion policy, layout and nav | Hello-world deployed to prod with zero-downtime rollout and a rollback rehearsal |
| S1 | 3-4 | Identity, tenancy, RBAC, audit | Tenants, users, sessions, passkeys and TOTP, project-scoped roles, RLS, audit chain, state machine and outbox kernels | Auth screens, org settings, user and role admin, audit viewer | Cross-tenant isolation suite green |
| S2 | 5-6 | Client master and catalog | Clients, contacts, client documents metadata, catalog items and rate cards, numbering sequences, custom fields | Client list and detail, catalog manager, command palette | Client CRUD with permissions and audit |
| S3 | 7-8 | Document vault and template engine | Encrypted object storage, versions, visibility, folder templates, DOCX/PDF render service, variable templates, numbering | Vault browser, uploader, preview, template editor | Generate a numbered PDF from a template with variables |
| S4 | 9-10 | CRM and survey | Leads, pipeline, survey templates per sector, conversion to client and project draft | Pipeline board, survey forms | Lead to project draft in one flow |
| S5 | 11-12 | RAB engine | BoQ lines, cost, margin, selling price, tax, versioning, internal vs client view, import from catalog and spreadsheet | Editable RAB grid with keyboard nav, version diff | RAB totals match golden test cases to the cent |
| S6 | 13-14 | Approvals and quotation | Approval matrix, margin-threshold rules, quotation generation from RAB version, expiry | Approval inbox, quotation preview and send | Low-margin RAB blocked until Director approves |
| S7 | 15-16 | Client portal foundation | Client auth, scoped queries, quotation view, per-line comments, accept with evidence (user, time, IP, version) | Portal shell, quotation review and accept | Client cannot access any internal field (CI scan) |
| S8 | 17-18 | Commercial profile, payment schedule, contract | Duration, contract and payment scheme models, termin generator and validation, retention, contract states, contract generation, e-sign provider adapter and signed-upload path | Commercial profile wizard, termin editor, contract workspace | All payment schemes from the Blueprint generate valid termin tables |
| S9 | 19-20 | Project workspace | Project from sector template, phases, milestones linked to termin, team and roles, invitations for client and vendors, budget baseline lock | Workspace shell, overview, team, template picker | Signed contract auto-creates a baseline-locked project |
| S10 | 21-22 | Tasks and collaboration | Tasks, subtasks, checklists, statuses including `waiting_client`, comments, mentions, notifications over SSE, visibility flags | List and board views, task drawer, activity feed, notification center | Waiting-client time tracked and reportable |
| S11 | 23-24 | Timeline | Dependencies, scheduling, critical path, baseline vs actual, weighted progress calculation | Gantt with drag and zoom, milestone view | 2,000-task project stays responsive |
| S12 | 25-26 | Finance: invoicing | Invoices from termin, configurable taxes, numbering, e-meterai flag, payments, credit notes, invoice PDFs, reminders | Invoice list and detail, payment recording, aging | Termin trigger drafts the correct invoice |
| S13 | 27-28 | UAT, BAST and closing | UAT checklists with client sign-off, BAST generator with preconditions, BAST signature flow, final invoice trigger, project closing, vault archive | UAT sign-off UI, BAST wizard, closing checklist | **Milestone M1:** one real project runs RAB to BAST to invoice |
| S14 | 29-30 | Plan vs actual and P&L | Budget lines vs actuals, expenses, committed vs actual, margin forecast, portfolio rollups, cashflow forecast | Project P&L, budget-vs-actual, portfolio dashboard | Dashboard totals reconcile with invoices and bills |
| S15 | 31-32 | Vendors and vendor portal | Vendor master, scoped access, assigned tasks, deliverable upload and verification | Vendor portal, verification queue | Vendor sees only assigned items |
| S16 | 33-34 | Procurement | PR, RFQ and comparison, PO, goods receipt, vendor bills, payables linked to budget lines | Procurement screens, bid comparison | PO to bill to budget actuals traceable end to end |
| S17 | 35-36 | Change requests and addenda | CR flow, impact estimate, client approval, auto-update of budget, schedule and termin, addendum generation | CR workspace, impact view | Approved CR updates all three consistently |
| S18 | 37-38 | Automation and notifications | Rule engine (trigger, condition, action), reminder schedules, email and WhatsApp providers, expiry watchers | Rule builder, notification preferences | **Milestone M2:** all Blueprint automation examples run |
| S19 | 39-40 | HRMS part 1 | Employees, attendance, leave, holidays, org units | HR screens, leave calendar, mobile attendance | Leave affects capacity data |
| S20 | 41-42 | HRMS part 2 and resourcing | Timesheets, cost rates, capacity planning, utilization, labor cost into P&L | Timesheet UI, resource planner | Labor cost appears in project actuals |
| S21 | 43-44 | ITSM part 1 | Assets and CMDB from handover, warranties, service contracts | Asset registry, contract view | BAST creates asset records |
| S22 | 45-46 | ITSM part 2 | Tickets, SLA timers and escalation, knowledge base, portal ticketing | Service desk, SLA dashboard | SLA breach escalates automatically |
| S23 | 47-48 | Recurring and billing completeness | Recurring invoices, T&M billing, unit-price progress claims, retention release, accounting export (Accurate, Jurnal, Zahir) | Billing runs, export center | **Milestone M3:** all contract and payment types billable |
| S24 | 49-50 | SaaS enablement | Tenant onboarding, plans and limits, subscription billing, public API keys, webhooks, template marketplace stub, tenant data export | Signup, onboarding wizard, billing page, developer settings | Second tenant onboarded without developer help |
| S25 | 51-52 | Hardening | Threat-model review, external pen test, load and chaos tests, DR drill, crypto-agility rotation drill, accessibility audit | Polish, empty states, performance work | Zero critical findings open |
| S26 | 53-54 | Launch and buffer | Migration tooling, support runbooks, status page, contingency for slipped slices | Docs site, in-app help | **Milestone M4:** commercial launch readiness |

**Total:** about 54 weeks including buffer. Treat S0 to S13 (about 28 weeks) as the critical path to internal dogfooding.

## 12. Release Strategy

- **Environments:** local, preview (per pull request), staging (production-like data shape), production.
- **Flags:** every slice is dark until its exit gate passes in staging, then enabled for the founder's tenant, then for all.
- **Versioning:** semantic versions for the API; date-stamped deploys; automatic rollback on failed health checks or error-rate spikes.
- **Dogfooding rule:** from M1, every real project of the company is run inside the platform; defects found are prioritized above new slices.

## 13. Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Scope breadth (PSA, ERP-lite, HRMS, ITSM) for one developer | Strict slice order; HRMS and ITSM after the core lifecycle; defer anything not in a sprint gate |
| Agent-generated code drift | `AGENTS.md`, lint-enforced module boundaries, mandatory tests and isolation suite, small reviewed diffs |
| Cost and margin leakage to client or vendor | Separate DTOs and queries, CI schema scan, RLS, authorization tests |
| Migration causing downtime | Expand/contract, migration lint, rehearsal on production-sized data |
| PQ claims outpacing ecosystem reality | Follow Section 6.2; crypto agility; periodic review of standards and library support |
| Indonesian legal and tax variations | Tax and numbering fully configurable; legal review of templates; certified e-sign provider |
| Gantt and RAB grid complexity | Spike in S5 and S11 with performance tests before full build |
| Solo bus factor | Runbooks, ADRs, infrastructure as code, tested restores |

## 14. Milestones

| Milestone | After | Meaning |
| --- | --- | --- |
| M1 Core lifecycle | S13 | RAB to approval to contract to project to UAT to BAST to invoice works in production; internal dogfooding starts |
| M2 Controlled delivery | S18 | Vendors, procurement, change requests, P&L and automation operate on real projects |
| M3 Full service platform | S23 | HRMS, ITSM and every billing model complete |
| M4 Commercial launch | S26 | Multi-tenant SaaS hardened and ready to sell |

## 15. Open Technical Decisions

1. Hosting provider and region (data residency), managed Postgres versus self-run.
2. E-sign provider and DOCX templating library (evaluate license, fidelity and Indonesian format support).
3. Gantt implementation: custom versus a licensed component.
4. Kubernetes timing (k3s at second tenant versus later).
5. Payment gateway for SaaS subscriptions.
6. Whether the WhatsApp channel uses the official Business API from the start.

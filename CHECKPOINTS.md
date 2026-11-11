# CHECKPOINTS.md: IT Services PSA Platform

> Hand this file to the coding agent together with the two source documents.
> - Product Blueprint (domain rules): https://claude.ai/artifact/FKjqrQQPgBcGxJqnoz8X45
> - Technical Architecture and Delivery Plan (stack, security, sprints): https://claude.ai/artifact/ULoPAYDwtt9QM8Xgm1o2TM
>
> If the two conflict: Blueprint wins on domain behavior, Tech doc wins on technology.

## How the agent must use this file

1. Read Blueprint, then Tech doc, then `AGENTS.md`, then ONLY the current sprint block below.
2. Work one sprint at a time. Do not start a sprint until the previous sprint's **Exit gate** is checked.
3. For each checkbox: write a short slice spec (entities, states, endpoints, permissions, events), get approval, then implement as a vertical slice (migration, SQL, domain, service, handler, OpenAPI, generated client, UI, tests, flag).
4. Tick a box only when the Global Definition of Done (below) is satisfied for that item.
5. If something is ambiguous, write the assumption down and ask. Never choose silently.
6. Never: use floats for money, bypass RLS, query another module's tables, hand-edit generated code, commit secrets, expose cost/margin/vendor pricing to client or vendor.

## Global Definition of Done (applies to every item)

- [ ] Migration is expand/contract, lint-clean, has `lock_timeout` and `statement_timeout`
- [ ] SQL lives in `.sql` files; sqlc output regenerated and committed
- [ ] RLS policy exists on every new tenant table; `tenant_id` in every query, cache key, file path and log
- [ ] Authorization tests (table-driven) cover every new endpoint
- [ ] Cross-tenant isolation suite still green
- [ ] State machine transitions tested, including illegal transitions
- [ ] Audit entries emitted for approvals, money, permissions, documents
- [ ] Client and vendor DTOs contain no cost, margin or vendor pricing (CI schema scan green)
- [ ] OpenAPI updated; breaking-change diff check green; TS client regenerated
- [ ] i18n strings externalized (ID and EN); accessibility checks pass; reduced-motion respected
- [ ] Feature flag in place; deployed to staging then production with zero downtime
- [ ] Docs, ADR and this checklist updated

---

## S0: Foundation (weeks 1-2)

- [ ] Monorepo (pnpm + Turborepo) with `apps/web`, `packages/ui`, `packages/api-client`, `services/api`
- [ ] Go module layout: `cmd/api`, `cmd/worker`, `internal/<module>/{http,service,sql,domain}`, `internal/kernel`
- [ ] Module-boundary lint (`depguard` or `go-arch-lint`) enforced in CI
- [ ] PostgreSQL + pgBouncer + goose + squawk lint + sqlc configured
- [ ] River job queue wired; worker entry point runs
- [ ] OpenAPI-first pipeline (`oapi-codegen` server stubs + generated TS client)
- [ ] Docker images, compose for local, deploy manifests Kubernetes-compatible
- [ ] Reverse proxy (Caddy or Traefik) with blue/green rollout, readiness and liveness probes, graceful shutdown
- [ ] TLS hybrid PQ key exchange (X25519MLKEM768) verified by an automated handshake test
- [ ] `cryptokit` skeleton (versioned envelope header: alg, kid, version)
- [ ] OpenTelemetry + slog + Sentry; trace ID in logs
- [ ] CI: lint, unit, integration (Testcontainers), migration lint, OpenAPI diff, govulncheck, npm audit, Trivy, build, deploy
- [ ] Next.js shell: Tailwind tokens (light/dark), shadcn setup, Phosphor icon wrapper, Framer Motion policy, layout and nav, next-intl (ID/EN)
- [ ] `AGENTS.md` written from Tech doc Section 10
- [ ] **Exit gate:** hello-world deployed to production with zero-downtime rollout AND a rehearsed rollback

## S1: Identity, tenancy, RBAC, audit (weeks 3-4)

- [ ] Tenants, users, memberships; UUIDv7 ids; `row_version` concurrency
- [ ] RLS via `SET LOCAL app.tenant_id`; app DB role is not superuser
- [ ] Migration test fails build if a `tenant_id` table lacks an RLS policy
- [ ] Sessions (httpOnly, Secure, SameSite), rotating refresh, passkeys (WebAuthn), TOTP, brute-force protection
- [ ] Project-scoped RBAC (`resource:action`), role editor, permission checks in services
- [ ] Audit log: append-only, hash-chained, checkpoints signed with ML-DSA (`crypto/mldsa` or `filippo.io/mldsa`)
- [ ] State machine kernel, outbox kernel, idempotency kernel, feature flags kernel
- [ ] UI: auth screens, org settings, user and role admin, audit viewer
- [ ] **Exit gate:** automated two-tenant isolation suite green on all endpoints

## S2: Client master and catalog (weeks 5-6)

- [ ] Clients, contacts, client-level document metadata (NPWP, NIB, deeds, NDA)
- [ ] Catalog items, rate cards, categories (material, labor, license, vendor service, overhead, contingency)
- [ ] Numbering sequences (pattern, roman month, year; never reused)
- [ ] Custom fields per tenant
- [ ] UI: client list/detail, catalog manager, command palette
- [ ] **Exit gate:** client CRUD with permissions and audit

## S3: Document vault and template engine (weeks 7-8)

- [ ] `cryptokit` envelope encryption: AES-256-GCM DEK per document, per-tenant KEK wrapped with ML-KEM-768 (hybrid with X25519 where available)
- [ ] S3-compatible storage, keyed `tenant/{tenant_id}/{project_id}/{doc_id}/{version}`, presigned URLs
- [ ] Versioning, checksum, uploader, per-document visibility, malware scan, file-type sniffing
- [ ] Folder templates (01 Quotation ... 09 Correspondence)
- [ ] Template engine with variables (`{{client.name}}`, `{{contract.value}}`, `{{payment.termin_table}}`); DOCX + PDF via Gotenberg
- [ ] Expiry tracking (60/30/7 day reminders hook)
- [ ] UI: vault browser, uploader, preview, template editor
- [ ] **Exit gate:** numbered PDF generated from a template with variables

## S4: CRM and survey (weeks 9-10)

- [ ] Leads, pipeline stages, source, sector, estimated value
- [ ] Survey templates per sector (CCTV, network, security, software) and survey responses
- [ ] Lead to client + project draft conversion
- [ ] UI: pipeline board, survey forms
- [ ] **Exit gate:** lead to project draft in one flow

## S5: RAB engine (weeks 11-12)

- [ ] RAB, RabVersion (immutable once submitted), RabLine (category, qty, unit, unit cost/HPP, margin or markup, selling price)
- [ ] Tax handling configurable per tenant (no hardcoded rates)
- [ ] Internal view (cost, margin) vs client view (selling price only)
- [ ] Import from catalog and spreadsheet; version diff
- [ ] Money util shared (decimal only; central rounding)
- [ ] UI: editable RAB grid with keyboard navigation, version diff
- [ ] **Exit gate:** totals match golden test cases to the cent

## S6: Approvals and quotation (weeks 13-14)

- [ ] Approval matrix (configurable thresholds, margin floor, value tiers)
- [ ] RAB states: draft, internal_review, internal_approved, sent_to_client, revision_requested, accepted, rejected, expired
- [ ] Quotation generation from an RAB version, numbering, expiry
- [ ] UI: approval inbox, quotation preview and send
- [ ] **Exit gate:** low-margin RAB blocked until Director approves

## S7: Client portal foundation (weeks 15-16)

- [ ] Client auth and scoped queries; separate client DTOs and SQL
- [ ] Quotation view, per-line comments, revision request, accept with evidence (user, time, IP, RAB version)
- [ ] UI: portal shell, quotation review and accept
- [ ] **Exit gate:** CI schema scan proves no internal field reachable by clients

## S8: Commercial profile, payment schedule, contract (weeks 17-18)

- [ ] Commercial profile: duration type (short_term, long_term, recurring), contract type (fixed_price, unit_price, time_and_material, retainer_subscription, hybrid), payment scheme (upfront_full, dp_then_final, dp_milestone_final, progress_based, full_after_bast, periodic_fixed, time_material_periodic, custom)
- [ ] Termin generator with triggers (on_contract_signed, on_milestone_completed, on_progress_percent, on_uat_passed, on_bast_signed, on_date, on_period_end, manual)
- [ ] Validation: termin sum = 100% including retention; milestone references protected; scheme changes after signing only via addendum
- [ ] Retention percentage and release condition
- [ ] Contract states: draft, legal_review, sent, signed, active, completed, terminated, expired
- [ ] Contract generation from RAB + profile; e-sign provider adapter AND signed-scan upload path; internal ML-DSA attestation stored beside legal e-sign evidence
- [ ] UI: commercial profile wizard, termin editor, contract workspace
- [ ] **Exit gate:** every payment scheme in the Blueprint generates a valid termin table

## S9: Project workspace (weeks 19-20)

- [ ] Project from sector template (phases, checklists, folders)
- [ ] Phases and milestones linked to termin
- [ ] Team and project roles; invitations for client PIC and vendors
- [ ] Budget baseline lock from the approved RAB version
- [ ] Project states: planning, active, on_hold, uat, handover, closed, cancelled
- [ ] UI: workspace shell, overview, team, template picker
- [ ] **Exit gate:** signed contract auto-creates a baseline-locked project

## S10: Tasks and collaboration (weeks 21-22)

- [ ] Tasks, subtasks, checklists; statuses todo, in_progress, review, done, blocked, waiting_client
- [ ] Time-in-`waiting_client` tracked separately and reportable
- [ ] Comments, mentions, visibility flags (internal, client, vendor)
- [ ] Notifications via SSE + notification center
- [ ] UI: list and board views, task drawer, activity feed
- [ ] **Exit gate:** waiting-client delay evidence is queryable per project

## S11: Timeline (weeks 23-24)

- [ ] Dependencies (FS/SS/FF/SF), scheduling, critical path
- [ ] Baseline vs actual; weighted progress calculation
- [ ] UI: Gantt (virtualized, drag, zoom; GSAP-assisted drag), milestone view
- [ ] **Exit gate:** 2,000-task project stays responsive

## S12: Finance, invoicing (weeks 25-26)

- [ ] Invoices generated from termin; states draft, issued, partially_paid, paid, overdue, void
- [ ] Configurable taxes (VAT, withholding), tax invoice number, e-meterai flag
- [ ] Payments, credit notes; issued invoices immutable
- [ ] Invoice PDFs; reminder schedule (T+1, T+7, T+14)
- [ ] UI: invoice list/detail, payment recording, aging
- [ ] **Exit gate:** termin trigger drafts the correct invoice

## S13: UAT, BAST, closing (weeks 27-28) => Milestone M1

- [ ] UAT checklists per sector with client item-by-item sign-off
- [ ] BAST generator with preconditions (mandatory tasks done, UAT passed, no critical issues, mandatory docs present)
- [ ] BAST signature flow (provider or upload); `bast_signed` triggers final termin invoice and starts warranty clock
- [ ] Project closing checklist, vault archive, retrospective
- [ ] UI: UAT sign-off, BAST wizard, closing checklist
- [ ] **Exit gate (M1):** one real company project runs RAB to BAST to invoice end to end; start dogfooding

## S14: Plan vs actual and P&L (weeks 29-30)

- [ ] Budget lines vs committed vs actual; expenses
- [ ] Formulas per Blueprint Section 11 (planned/actual margin, cost variance, forecast margin/EAC)
- [ ] Portfolio rollups, cashflow forecast, margin erosion alerts
- [ ] UI: project P&L, budget-vs-actual, portfolio dashboard
- [ ] **Exit gate:** dashboard totals reconcile with invoices and bills

## S15: Vendors and vendor portal (weeks 31-32)

- [ ] Vendor master, scoped access, assigned tasks only
- [ ] Deliverable upload with internal verification (accept/reject)
- [ ] UI: vendor portal, verification queue
- [ ] **Exit gate:** vendor sees only assigned items (tested)

## S16: Procurement (weeks 33-34)

- [ ] PR, RFQ with multi-vendor comparison, approval, PO, goods/service receipt, vendor bills
- [ ] Payables linked to PO and budget line
- [ ] Vendor scorecard
- [ ] UI: procurement screens, bid comparison
- [ ] **Exit gate:** PO to bill to budget actual traceable end to end

## S17: Change requests and addenda (weeks 35-36)

- [ ] CR states: draft, impact_assessed, client_approval, approved, rejected
- [ ] Approved CR updates budget, schedule and payment schedule consistently; generates addendum draft
- [ ] Out-of-scope work blocked from billing without CR
- [ ] UI: CR workspace, impact view
- [ ] **Exit gate:** approved CR updates all three consistently (property tested)

## S18: Automation and notifications (weeks 37-38) => Milestone M2

- [ ] Rule engine (trigger, condition, action) per tenant
- [ ] All Blueprint Section 14 automations implemented
- [ ] Email and WhatsApp providers (pluggable); expiry watchers (60/30/7)
- [ ] UI: rule builder, notification preferences
- [ ] **Exit gate (M2):** every listed automation runs on a real project

## S19: HRMS part 1 (weeks 39-40)

- [ ] Employees, org units, attendance, leave, holidays
- [ ] PWA/mobile attendance
- [ ] **Exit gate:** leave reduces capacity data

## S20: HRMS part 2 and resourcing (weeks 41-42)

- [ ] Timesheets, cost rates, capacity planning, utilization
- [ ] Labor cost flows into project actuals
- [ ] UI: timesheet, resource planner
- [ ] **Exit gate:** labor cost visible in project P&L

## S21: ITSM part 1 (weeks 43-44)

- [ ] Assets/CMDB created from handover; warranties; service contracts
- [ ] **Exit gate:** BAST creates asset records

## S22: ITSM part 2 (weeks 45-46)

- [ ] Tickets, SLA timers, escalation, knowledge base, client portal ticketing
- [ ] **Exit gate:** SLA breach escalates automatically

## S23: Recurring and billing completeness (weeks 47-48) => Milestone M3

- [ ] Recurring invoices, T&M billing from approved timesheets, unit-price progress claims (opname), retention release
- [ ] Accounting export/sync: Accurate, Jurnal, Zahir
- [ ] **Exit gate (M3):** every contract type and payment scheme is billable

## S24: SaaS enablement (weeks 49-50)

- [ ] Tenant onboarding, plans and limits, subscription billing
- [ ] Public API keys, webhooks (ML-DSA signed, HMAC fallback), template marketplace stub, tenant data export and erasure
- [ ] **Exit gate:** second tenant onboarded without developer help

## S25: Hardening (weeks 51-52)

- [ ] Threat-model review, external pen test
- [ ] Load and chaos tests; DR restore drill with recorded RTO/RPO
- [ ] Crypto-agility drill: rotate KEKs and re-wrap DEKs without re-encrypting blobs
- [ ] Accessibility audit, performance budget check (LCP under 2.5 s)
- [ ] **Exit gate:** zero critical findings open

## S26: Launch and buffer (weeks 53-54) => Milestone M4

- [ ] Migration tooling, runbooks, status page, docs site, in-app help
- [ ] Absorb slipped slices
- [ ] **Exit gate (M4):** commercial launch readiness

---

## Recurring checkpoints (every sprint)

- [ ] Sprint start: slice specs approved; velocity compared against plan (recalibrate after S4)
- [ ] Mid-sprint: staging deploy, migration rehearsal on production-sized data
- [ ] Sprint end: production deploy behind flag, exit gate verified, checklist and ADRs updated
- [ ] Dependencies: `govulncheck`, `npm audit`, Dependabot reviewed; Go patch version current
- [ ] After M1: defects found while dogfooding take priority over new slices
- [ ] Quarterly: backup restore test and crypto/standards review (PQ library and TLS support)

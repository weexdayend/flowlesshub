# FlowlessHub — S1 Product MVP Roadmap

**Product lane baseline:** `3def4d8747c12a7a334a448a46509559a2d812fb` (13 November 2026).
**Strategy:** ship a narrow, usable IT-services operating workflow before expanding into the full service lifecycle.

## MVP product outcome

A pilot IT-services organization can securely enter FlowlessHub, maintain its customer records, qualify leads, record a technical survey and cost budget (RAB), prepare and revise a quotation, and produce a customer-ready quotation document. This is the initial commercial-control wedge; it is not a claim that project delivery, accounting, or ITSM is complete.

## Ordered P0 milestones

| Milestone | Capability | User-visible outcome | Depends on |
|---|---|---|---|
| S1.1 | Identity & tenant foundation | First owner can be provisioned; user can sign in/out; API exposes only authorized organization membership | Current S0 platform foundation |
| S1.2 | Tenant authorization, member invitations & customer/contact master data | Team can invite members and create, view, update, and archive customers/contacts within the selected organization | S1.1; RLS/non-owner DB role proof |
| S1.3 | Lead & opportunity management | Team can register a lead, assign an owner, manage pipeline status, and convert/qualify an opportunity | S1.2 |
| S1.4 | Survey & RAB | Team can capture survey findings, scope, line items, quantities, units, cost assumptions, and internal margin controls | S1.3 |
| S1.5 | Quotation & document output | Team can issue a versioned quotation, preview/download a PDF, revise it without destroying history, and track draft/sent/accepted/rejected/expired states | S1.4 |
| S1.6 | MVP integration & pilot hardening | End-to-end acceptance, auditability, tenant-isolation tests, onboarding runbook, observability, backup/recovery checks, and pilot release | S1.1–S1.5 plus operational gates |

Each milestone is one vertical slice: domain rules → migration/queries → OpenAPI contract → backend behavior → frontend workflow → tests → docs/acceptance. Avoid building empty module shells for future stages.

## Explicitly deferred until after the first commercial MVP

- SPK/contract lifecycle and e-signature integrations.
- Project delivery planning, work packages, tasks, milestones, resource scheduling, and progress reporting.
- UAT, BAST, handover, and managed-service transition.
- Invoice, payment collection, tax/accounting integrations, procurement, and project P&L.
- ITSM/service desk, SLA management, asset/configuration management, and recurring service operations.
- Subscription billing/self-service plan management, SSO, MFA, SCIM, public APIs, and mobile applications.

Deferred does not mean abandoned. These capabilities remain in the broader FlowlessHub service lifecycle but do not block the first paid/pilot commercial workflow.

## MVP Definition of Done

1. A real pilot organization can be bootstrapped and at least two authorized team users can work within the same tenant (invitation/member onboarding is a dependency before multi-user pilot).
2. A user cannot read or mutate another organization's customers, leads, survey, RAB, or quotations by changing IDs or request headers.
3. The complete Lead → Survey/RAB → Quotation workflow can be completed using persisted data, not mock fixtures.
4. Quotation revisions preserve an auditable version history; internal cost/margin data is separated from customer-facing output.
5. The API is contract-first and generated Go/TypeScript clients are in sync.
6. Critical business rules, concurrency behavior, authorization, and tenant isolation have automated tests.
7. CI, deployment/rollback, observability, backup, and restore readiness are evidenced for the pilot; no S0 operational gap is hidden by calling MVP complete.
8. Owner explicitly accepts pilot scope and release evidence.

## Delivery guardrails

- Keep the Go modular monolith, PostgreSQL source of truth, Next.js frontend, pnpm/Turborepo workspace, and existing VPS Blue/Green deployment model.
- Prefer a simple, explicit domain model over generic engines and premature service boundaries.
- Model tenant ownership at the database and repository layers, not only in UI navigation.
- Use decimal-safe PostgreSQL `NUMERIC` for money; never use floating point for money.
- Treat audit history, quote versioning, and customer-facing cost/margin redaction as first-class invariants.
- One product slice active at a time. S0.11 backup scheduling/retention/recovery remains a separate operational follow-up and must receive its scheduled-run evidence without blocking local product engineering.

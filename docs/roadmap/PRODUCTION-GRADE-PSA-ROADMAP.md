# FlowlessHub — Production-Grade PSA Delivery Roadmap

**Status:** Owner-approved delivery direction; full PSA and identity platform delivered through production-grade slices.
**Roadmap baseline:** `92aec75c6387d6f57a1dc0d71c5ab7431f5831cd`
**Delivery model:** Incremental production-grade vertical slices; dependency order, not calendar estimates.
**Canonical product strategy:** [`PRODUCT-STRATEGY.md`](../product/PRODUCT-STRATEGY.md)
**Canonical architecture:** [`DOMAIN-MODULE-ARCHITECTURE.md`](../architecture/DOMAIN-MODULE-ARCHITECTURE.md)
**Engineering gates:** [`PRODUCTION-ENGINEERING-CHARTER.md`](../architecture/PRODUCTION-ENGINEERING-CHARTER.md)

## 1. Roadmap mandate

This roadmap targets the complete FlowlessHub IT Services PSA lifecycle:

**Lead → Survey → RAB → Quotation → SPK/Contract → Project Delivery → UAT → BAST → Invoice → Payment → Project P&L → ITSM**

There is no MVP or pilot boundary that removes a core lifecycle stage. Slices are kept incremental so each can be reviewed, tested, deployed and operated safely. Each slice must be production-grade before downstream slices depend on it.

No schedule, sprint duration, delivery date or staffing velocity is asserted. Re-estimate only after observing actual throughput and risk; do not reorder hard security/data dependencies to meet a calendar target.

## 2. Current baseline and sequencing constraints

- `S1.1` is closed and owner-accepted for backend/API identity, session and organization membership endpoints at `495383f38ec7c356b97bb66017b66a3380130eaf`. Do not reopen it or repeat its production migration, bootstrap, release or acceptance.
- The browser sign-in/session UX and protected web routes were explicitly deferred from S1.1 and are the first technical workstream in S1.2.
- The web app currently contains a preview shell only. It has no working sign-in, session restoration, organization context or protected business route.
- The API has S1.1 identity endpoints, but current production API connections use the configured database user through PgBouncer transaction pooling. The current migrations do not create a separate non-owner runtime role or RLS policies, and no transaction-local tenant-context/leakage proof exists.
- **No tenant-owned business table may be introduced until the runtime role, RLS, transaction-local context and PgBouncer isolation gates in S1.3 are proven.** This includes customer/contact tables.
- `S0.11` backup/recovery remains open as a separate operational checkpoint. It does not block local S1 feature engineering, but its remaining gates must not be described as complete or silently absorbed into product acceptance.
- The current product code has no persisted customer, lead, survey, RAB, quotation, contract, project, acceptance, invoice, payment, P&L or ITSM capability.

### 2.1 Two-party and three-party operating paths

The provider organization is the FlowlessHub tenant and prime contractor. The customer is the provider's client and may be the legal/business/asset owner of the underlying project. That project-owner role is explicitly modelled as a customer/business-party relationship; it does not make the customer the owner of the provider's tenant or PSA delivery records. A vendor/subcontractor is a separate supplier engaged by the provider for an explicitly bounded part of a project; it is not a third tenant owner or a customer portal user.

- **Two-party project:** provider ↔ customer. The provider uses its own people/resources and follows the customer quotation/contract, project delivery, UAT/BAST, customer billing/collection and ITSM path. Procurement and vendor workflows are optional and absent when not needed.
- **Three-party project:** provider ↔ customer plus a separate provider ↔ vendor relationship. The customer contract and vendor subcontract/PO have independent parties, scope, price, versions, approvals, evidence and payment direction. A project can have multiple vendor packages and vendors, alongside work delivered by the provider itself.

Keep four commercial artifacts distinct: (1) internal RAB/estimate with costs and margin; (2) customer quotation and any customer-facing BOQ/RAB projection; (3) vendor RFQ response and vendor BOQ revision; (4) accepted vendor subcontract/PO. A customer-facing RAB/BOQ is shared only when required by the deal, and never reuses vendor purchase cost or reveals internal margin by default.

A vendor BOQ agreement is bilateral: the provider's authorized commercial/technical approvers and the vendor's authorized representative must accept the same immutable revision. Capture line scope, quantities, units, rates, totals, currency, tax basis, exclusions, delivery/milestones, acceptance conditions, payment terms, validity, actors, timestamps and evidence hash. Internal RAB approval, customer quotation approval, vendor BOQ acceptance and customer contract execution are four distinct controls.

Presales may obtain non-binding vendor budgetary quotations to inform the internal RAB before the customer quotation is issued. Formal vendor award and subcontract/PO confirmation are controlled in S1.12. If a vendor commitment must be signed before the customer contract, it requires an explicit conditional/pre-award policy and is not inferred from quote acceptance.

## 3. Dependency overview

```text
S1.1 accepted identity API
        |
        v
S1.2 Passwordless identity / first-party SSO / authenticated web entry
        |
        v
S1.3 Tenant authorization + DB isolation + membership lifecycle
        |
        v
S1.4 Customer / contact master
        |
        v
S1.5 Lead / opportunity CRM
        |
        v
S1.6 Survey / solution scope
        |
        v
S1.7 RAB estimation / commercial approval
        |
        v
S1.8 Versioned quotation / customer review
        |
        v
S1.9 SPK / contract / commercial obligations
        |
        v
S1.10 Project initiation / delivery baseline
        |
        v
S1.11 Project execution / resources / time
        |
        +------> S1.12 Procurement / vendor / change control
        |                    |
        +--------------------+
                  |
                  v
S1.13 UAT / BAST / service transition
        |
        +------> S1.14 Invoice / payment / receivables
        |                    |
        |                    v
        |          S1.15 Project cost / financial control / P&L
        |
        +------> S1.16 ITSM / ongoing service operations
```

The dependency graph is directional but does not require all cross-module operations to be asynchronous. Integrations and notification capabilities are introduced when the owning business slice needs them.

## 4. Mandatory slice contract

Every slice specification must complete all of the following before implementation. Its acceptance record must link each item to the source, test or operational evidence that proves it.

| Dimension | Required content |
|---|---|
| Business outcome | Real operator, actor permissions, persisted outcome and failure/recovery path. |
| Domain | Entities, ownership, lifecycle/state machine, invariants, versioning and exceptions. |
| Data | Migration, constraints, indexes, tenant keys/RLS, data classification, retention and expand/contract plan. |
| API | OpenAPI operations/schemas, authorization, idempotency, conflict/concurrency semantics, error behavior and generated artifacts. |
| Frontend | Complete workflow, authenticated route, tenant context, loading/empty/error/denied/expired/conflict states, accessibility and responsive behavior. |
| Security | Threat review, cross-tenant negative tests, role/permission tests, secret/log redaction, CSRF/session and integration verification as applicable. |
| Correctness | State transition, duplicate/retry, concurrency, property/golden, failure-injection and financial reconciliation tests as applicable. |
| Audit and observability | Actor/tenant/source-version audit, structured logs, metrics, trace/correlation propagation, dashboards and alerts. |
| Operations | Capacity impact, worker/retry behavior, migration compatibility, backup/restore implications, deployment/rollback and runbooks. |
| Acceptance | Manual scenarios, expected results, exact-SHA CI, runtime evidence only when required, owner acceptance and checkpoint state. |

A slice may mark an item not applicable only with a written reason. Essential security, financial correctness, data integrity, auditability or operability cannot be deferred into an unspecified later hardening phase.

## 5. Production-grade delivery slices

### S1.2 — Passwordless Identity, First-Party SSO and Authenticated Web Entry

**Business outcome:** Existing S1.1 users can enroll phishing-resistant passkeys, authenticate passwordlessly with a verified user-presence/verification ceremony, use one first-party identity across FlowlessHub applications through OIDC SSO, recover access safely, and use the protected Next.js application through a server-side BFF. S1.1 remains closed and compatible.

- **Authority and compatibility:** Keep the internally managed Go Identity authority and global S1.1 users. Preserve accepted password hashes and opaque sessions as a staged migration bridge. Use additive schema/API changes only; no destructive identity migration or forced mass logout.
- **Passwordless/MFA:** WebAuthn/FIDO2 passkeys are the primary passwordless authenticator. Require `userVerification=required`, exact origin/RP ID validation, one-time expiring challenges, cryptographic signature validation, credential ownership checks, and auditable credential lifecycle. Support multiple passkeys and roaming FIDO2 security keys. Record authenticator/user-verification evidence; do not assume every passkey has equivalent multi-factor assurance or claim a NIST AAL without assessment. S1.3 enforces assurance by role.
- **First-party SSO:** Provide an internal OIDC issuer for first-party clients. Use Authorization Code Flow + PKCE `S256`, exact redirect URI allowlists, transaction-specific `state`/`nonce`, issuer/audience/signature/time validation, short-lived single-use codes, scoped clients and key rotation. Do not use Implicit or Resource Owner Password Credentials grants. External enterprise IdP federation and SCIM remain separate decisions.
- **Browser/session boundary:** Use a same-origin Next.js BFF. Keep the Identity authority's API-host-only session distinct from the app-host-only BFF session. The BFF stores session/token bindings server-side; no access, refresh or opaque session token is exposed to browser JavaScript, local/session storage, URLs, HTML or logs. Logout and revocation invalidate all bound sessions.
- **SMTP foundation:** Integrate the owner's existing SMTP through a server-side adapter for email confirmation, security notifications, recovery notifications and later invitations. Use a durable outbox, asynchronous idempotent delivery, bounded retry/backoff, delivery/bounce state and manual repair. Verify TLS and SPF/DKIM/DMARC alignment. Email OTP and magic-link authentication are prohibited as login/MFA/step-up factors.
- **Recovery and transition:** Enroll passkeys from an already authenticated S1.1 session. Provide one-time hashed recovery codes, a second authenticator route and controlled support recovery; email only notifies. Password fallback remains during migration and is retired only through a separately approved measured rollout.
- **Identity boundary:** A global human identity does not imply tenant membership. Customer contacts and vendor users receive separate delegated relationships and project/package scopes in later slices; they are not automatically members of the provider tenant. S1.2 does not implement customer/vendor portal workflows.
- **Implementation sequence:** S1.2-A accepted-ADR implementation contract/threat model; freeze issuer+RP origins, OIDC client registry and browser-proven BFF handoff; S1.2-B SMTP adapter/outbox and deliverability preflight; S1.2-C WebAuthn credentials/challenges; S1.2-D OIDC issuer/client registry and BFF integration; S1.2-E recovery/assurance/security inventory; S1.2-F migration, Blue/Green compatibility and browser security acceptance.
- **Operational acceptance:** No production deployment or identity migration is authorized by the roadmap entry alone. Exact-SHA frontend/backend CI, browser/WebAuthn interoperability, cross-instance abuse control, credential/session revocation, SMTP failure/retry, OIDC negative tests and rollback evidence are required.
- **Depends on:** S1.1 accepted identity/API baseline. S1.3 consumes the authentication assurance signals and owns tenant authorization/role enforcement.

### S1.3 — Tenant Authorization, Membership Lifecycle and Database Isolation

**Business outcome:** Organization owners/admins can manage authorized membership and organization context, while all tenant business access is secure by construction before tenant business data is introduced.

- **Domain/data:** Membership invitations, acceptance, role/permission assignments and organization lifecycle; final-active-owner invariant; invitation expiry/replay and revocation rules. Exact role catalogue and delegated admin rights require an ADR.
- **API/UI:** Organization selection/context, invitation issue/accept/cancel/resend, membership listing and permitted role changes with explicit confirmation and audit.
- **Security hard gate:** Separate migration/owner and non-owner runtime DB roles; runtime role has no superuser, table ownership or `BYPASSRLS`. Add tenant RLS and `FORCE ROW LEVEL SECURITY` where appropriate. Establish membership-derived tenant context with transaction-local state only.
- **PgBouncer proof:** Test alternating tenant transactions through reused transaction-pool connections; include commit, rollback, error, timeout and cancellation. Prove no cross-tenant reads/writes by application tests and direct SQL under the runtime role. Verify role grants and migration/runtime connection separation.
- **Concurrency/failure:** Concurrent last-owner demotion/suspension/transfer, duplicate invitation, invitation expiry and acceptance replay must be safe and idempotent.
- **Acceptance gate:** This slice must be fully accepted before S1.4 creates the first tenant-owned business table.
- **Depends on:** S1.2 and S1.1.

### S1.4 — Customer and Contact Master Data

**Business outcome:** Authorized organization users can maintain customer accounts and contacts as the durable master records for commercial and service activity.

- **Domain/data:** Customer, contact, addresses and explicit customer-contact relationships; organization-scoped identifiers and uniqueness; archive/merge policy and duplicate resolution must be defined.
- **API/UI:** Create, read, update, archive, search, filter and detail workflows; customer/contact association and activity reference points.
- **Security/correctness:** RLS and repository scoping on every table/query; tests for guessed IDs, cross-tenant joins, duplicate races, concurrent edits and archive restrictions. Do not implement hard delete where records are referenced by issued commercial evidence.
- **Audit/operations:** Actor-attributed changes, searchable activity history, migration/backup impact, paginated queries and data export policy.
- **Depends on:** S1.3 accepted tenant isolation and access foundation.

### S1.5 — Lead and Opportunity Management

**Business outcome:** Sales can register and qualify leads, assign responsibility, manage opportunity progression and convert qualified work without losing its history.

- **Domain/data:** Lead, opportunity, source, owner/assignee, activity, qualification and conversion references. Define duplicate matching, merge, reopen and lost/disqualified semantics.
- **API/UI:** Pipeline list/board, detail, assignment, activity history, search/filter and conversion workflow.
- **Security/correctness:** Tenant/resource authorization, immutable conversion lineage, controlled state transitions, optimistic concurrency and idempotent conversion.
- **Audit/operations:** Stage/owner changes, conversion, closure and exports are audited; dashboards/metrics use source facts rather than client-computed status.
- **Depends on:** S1.4.

### S1.6 — Technical Survey and Solution Scope

**Business outcome:** Presales and technical staff can capture the facts, constraints, assumptions and evidence needed to define a deliverable service solution.

- **Domain/data:** Survey case, versioned templates, questions/findings, site/system details, attachments/evidence references, assumptions, constraints and proposed solution scope. Survey template governance and required evidence are owner decisions.
- **API/UI:** Assign and schedule survey work, capture structured findings, attach protected evidence, review/approve scope and link the result to its opportunity.
- **Security/correctness:** Field-level confidentiality where required, safe file upload/download, idempotent submission, audit and version history. A changed survey must not silently rewrite an estimate already built from an earlier version.
- **Operations:** Attachment scanning/limits, storage outage/retry, large-upload constraints and evidence retention are included.
- **Depends on:** S1.5; Document Management capabilities are introduced at the minimum required boundary.

### S1.7 — RAB / Estimate and Approval Controls

**Business outcome:** Presales can build a reproducible cost estimate and selling-price proposal with controlled margin and approval.

- **Domain/data:** Internal estimate versions, RAB/BoQ work lines, quantity, unit, cost/rate basis, supplier budgetary quote references, tax/currency assumptions, discounts, margin and calculation provenance. A vendor quote/BOQ is a separate vendor-submitted artifact, not an editable section of the internal estimate. Unit catalog/rate cards and external cost sources require explicit scope decisions.
- **API/UI:** Editable internal estimate grid, import/export where approved, formula/golden-case review, version comparison and internal approval inbox. Where vendor pricing is needed before a customer offer, issue scoped budgetary RFQs and retain vendor BOQ/quote revisions as cost evidence; these are not binding awards by default.
- **Correctness:** PostgreSQL `NUMERIC` and decimal calculation only. Define rounding stage, currency scale, tax basis/date and null/zero semantics. Approved internal RAB versions are immutable; corrections create a new revision. Vendor purchase currency and customer sales currency may differ and must not be silently merged.
- **Security:** Separate internal cost/margin/discount/approval DTOs from customer and vendor views. Vendors see only their assigned RFQ package; customers see only the approved customer-facing projection. Approval thresholds and separation of duties require an owner-approved policy; no threshold is invented here.
- **Concurrency/operations:** Prevent approval of stale versions; idempotent submission/approval; record actor, source version, calculations and audit evidence. A budgetary vendor quote is not a purchase commitment or bilateral subcontract approval.
- **Depends on:** S1.6 and S1.4.

### S1.8 — Versioned Quotation and Customer Review

**Business outcome:** An authorized commercial user can issue a customer-ready quotation tied to an approved estimate version; the customer can respond to the exact offer version.

- **Domain/data:** Quotation, immutable issued versions, recipients, validity, line presentation, terms snapshot, rendered document version/hash, send/response/expiry evidence.
- **API/UI:** Draft/revise/preview/approve/issue/send, customer-facing review/accept/reject/comment and an auditable response to a specific version. Portal identity and secure external invitation/link model require an ADR.
- **Security/correctness:** External customer DTO and document must exclude internal cost, supplier purchase rates, margin and internal notes. Customer approval is bound to the issued customer quotation version and never approves a vendor BOQ or subcontract. Expired/superseded version responses are rejected or handled by explicit policy. Issue/send/retry is idempotent.
- **Operations:** Document rendering and outbound delivery use durable jobs/outbox, retry and manual repair. Store template/version and content hashes; protect download links.
- **Depends on:** S1.7, S1.3, and Document Management at production scope.

### S1.9 — SPK / Contract and Commercial Obligations

**Business outcome:** An accepted commercial offer can become an enforceable, versioned contract/SPK with traceable obligations, amendment and payment schedule.

- **Domain/data:** Contract parties, terms, scope reference, dates, obligations, payment schedule, version, amendments, execution evidence and lifecycle. Contract templates and legal semantics require owner/legal review.
- **API/UI:** Contract workspace, generation/preview, review, signing/execution evidence, amendment and obligation schedule.
- **Security/correctness:** Signed/issued versions are immutable; amendments reference the predecessor and affected obligations. Only authorized actors can approve/execute. E-signature provider and wet-signed upload fallback remain open decisions.
- **Operations:** Provider callbacks are verified and deduplicated; signed document artifacts/hash, provider evidence and manual exception handling are retained.
- **Depends on:** S1.8 and approved legal/commercial policies.

### S1.10 — Project Initiation and Delivery Baseline

**Business outcome:** A signed/approved contract obligation can create a delivery project whose scope, budget, phases and milestones have a controlled baseline.

- **Domain/data:** Project, customer/project-owner party reference, contract reference, project team, work breakdown, phases, milestones, budget/schedule baseline, customer participants and initial delivery acceptance criteria.
- **API/UI:** Project initiation wizard, project workspace, overview, team, scope/baseline review and milestone plan.
- **Security/correctness:** Project access is more specific than tenant membership where required. Baseline freeze, amendments, source contract version and duplicate project creation are controlled and idempotent.
- **Operations:** Initial project provisioning is transactional or explicitly orchestrated; partial failures are observable and safely resumable.
- **Depends on:** S1.9 and S1.3.

### S1.11 — Project Execution, Work Management and Delivery Resources

**Business outcome:** The delivery team can plan and execute work against the approved project baseline and provide trustworthy progress/evidence.

- **Domain/data:** Tasks/work packages, dependencies, assignments, statuses, checklists, comments/mentions, work logs/time entries, capacity references, progress and baseline-versus-actual history.
- **API/UI:** Task/list/board and timeline views, assignment, status transitions, time/effort capture, blockers, collaboration and customer-visible progress where authorized.
- **Correctness:** Define progress computation and schedule dependency rules; concurrent task changes use versioning; time entry edits/approval and duplicate submission are controlled.
- **Security/operations:** Assigned-user and project-scope permission tests, notification outbox, worker retries, queue age, audit and performance tests for realistic project sizes.
- **Depends on:** S1.10. Full HR/payroll is not assumed; only delivery-resource capabilities are included unless separately approved.

### S1.12 — Procurement, Vendor Delivery and Change Control

**Business outcome:** Project-related supplier commitments and approved scope changes can be controlled without losing their impact on budget, delivery and commercial obligations.

- **Domain/data:** One project may have zero or many procurement packages mapped to work packages and approved project scope. Own vendor/supplier records, requisitions, RFQs, vendor-submitted quote/BOQ revisions, line-level clarifications, evaluation/comparison, negotiation history, award, subcontract/PO, delivery/receipt evidence, vendor variation requests and supplier cost evidence. Vendor BOQ lines retain descriptions, quantities, units, rates, totals, currency, tax basis, exclusions, delivery/milestone assumptions, acceptance conditions and payment terms.
- **API/UI:** Procurement package workspace; vendor invitation and scoped RFQ portal; vendor quote/BOQ submission and revision; internal technical/commercial review; clarification/negotiation; approval inbox; award and subcontract/PO confirmation; supplier delivery/progress and receipt evidence; vendor variation and change-control workflow.
- **Bilateral approval gate:** Internal provider approvers and the vendor's authorized representative must accept the same immutable vendor BOQ revision. Record parties, actor authority, timestamps, approval evidence/hash and terms snapshot. A revision change invalidates approvals for the prior revision and requires re-approval. No mobilization/order/commitment from draft or unapproved BOQ except an explicitly approved provisional policy.
- **Correctness:** Separate vendor budgetary quotes (which can inform S1.7 RAB) from binding subcontract/PO awards. Support fixed-price/milestone and, where applicable, time-and-material, expense and material lines. Accepted vendor delivery/receipts are matched against the subcontract/PO before vendor invoice approval. Duplicate awards, partial receipts, cancellations, disputed lines and supplier updates are concurrency-safe and auditable.
- **Change control:** Vendor variations revise only the vendor commitment. If they affect customer scope, price, schedule, contract obligations or acceptance, create a linked but separate customer change/variation request and obtain customer approval as required. A vendor approval never substitutes for customer approval, nor vice versa. Approved changes create successor baselines/obligations; they do not mutate signed artifacts.
- **Security/operations:** Vendors see only explicitly assigned RFQs, awarded packages, permitted progress and their own invoice/settlement status; they cannot see customer pricing, internal margin, competing vendor bids or other vendors. Customer portal access remains a separate permission contract. External invitations/uploads are scoped, scanned, rate-limited and revocable. External provider failure cannot erase a committed business decision.
- **Depends on:** S1.7 (vendor budgetary quote inputs where used), S1.9, S1.11 and S1.3. Formal procurement depth is a product capability, not an optional replacement for the customer contract.

### S1.13 — UAT, BAST, Handover and Service Transition

**Business outcome:** A project can demonstrate that its agreed deliverables passed acceptance and transition into support with a traceable handover package.

- **Domain/data:** UAT plans/cases/results, defects/retests, acceptance conditions, BAST versions, signatory/actor evidence, delivered asset/configuration records, warranty/service entitlement and handover checklist.
- **API/UI:** UAT execution/retest, customer sign-off, BAST generation/review/execution, outstanding-obligation handling and service-transition workspace.
- **Correctness/security:** BAST and acceptance snapshots bind to the project/contract version and evidence set; signature method/legal effect requires an owner decision. Customer visibility is constrained to accepted scope.
- **Operations:** Final documents are immutable/versioned; asset/CI creation and ITSM transition are idempotent; missing prerequisites block closure with actionable reasons.
- **Depends on:** S1.11 and S1.12 where applicable; contract acceptance rules from S1.9.

### S1.14 — Customer Billing, Vendor Payables, Payments and Reconciliation

**Business outcome:** Customer billing and collections (Accounts Receivable) and supplier invoicing and settlement (Accounts Payable) are both controlled, traceable and reconciled without conflating money-in with money-out.

- **Domain/data:** Separate customer invoice/credit-note/receipt/allocation/receivable aggregates and vendor invoice/debit-credit adjustment/approval/payment/allocation/payable aggregates. Vendor invoice lines reference the accepted subcontract/PO revision and the corresponding accepted goods, time, expense, material or milestone evidence from S1.12.
- **API/UI:** Customer billing schedule, invoice draft/review/issue/delivery, payment recording/provider reconciliation, allocation, refund/credit and AR aging; plus vendor invoice intake, line matching/dispute, AP approval, due-date scheduling, payment proposal/settlement, remittance evidence and AP aging.
- **Correctness:** Customer invoice issue and vendor payable approval are separately immutable/traceable. Verify vendor invoices against (1) the accepted subcontract/PO and BOQ lines, (2) accepted delivery/receipt/progress evidence, and (3) vendor invoice lines before release for payment. Support partial deliveries, partial invoices, retention/withholding where policy requires, credit/reversal and concurrency-safe partial allocations. Payment callbacks and outbound payment status are verified/idempotent; do not mark a supplier paid from a client-supplied status.
- **Financial policy:** Tax, sales/purchase currency and FX basis, customer/vendor invoice numbering, withholding, e-invoicing, rounding, revenue trigger, payment gateway/bank rail, approval threshold and accounting posting are owner/legal/accounting decisions. Do not hard-code a provider or tax regime.
- **Operations:** Durable invoice generation/delivery, vendor invoice exceptions, payment retries/reconciliation, approval segregation, privacy, audit and evidence retention.
- **Depends on:** S1.9, S1.12, S1.13 where customer billing is acceptance-gated, and the applicable approved AR/AP policies.

### S1.15 — Project Cost, Financial Control and Project P&L

**Business outcome:** Management can explain project revenue, committed cost, actual cost, margin and variance from traceable source records.

- **Domain/data:** Project budget baseline, approved vendor commitments, accepted supplier payable actuals, expenses, labour/time cost, approved adjustments, customer billing/revenue source, cost allocation and P&L snapshot. Preserve the distinction between committed, received/accepted, invoiced, paid and recognized amounts.
- **API/UI:** Budget-vs-actual, committed-vs-actual, forecast, margin bridge, project and portfolio P&L with drill-through to source records.
- **Correctness:** Each number has explicit source, period, currency, allocation and calculation basis. Reconcile project costs to procurement/expense/time sources and billing to invoices/obligations. Revenue recognition/WIP policy is not invented; the view must label cash, invoiced, accrued and recognized concepts distinctly.
- **Security/operations:** Restricted finance permissions, audit for manual journals/adjustments, deterministic rollup tests, large-portfolio performance and reproducible historical snapshots.
- **Depends on:** S1.11, S1.12 where applicable, S1.14, and approved accounting/management-reporting policies.

### S1.16 — ITSM and Ongoing Service Operations

**Business outcome:** A completed delivery can be supported as an ongoing service with contractual entitlements, assets/configuration context, incidents/requests and measurable SLA handling.

- **Domain/data:** Service agreement, service entitlement, asset/configuration item, incident, request, category/priority, SLA policy/calendar, response/resolution clocks, escalation, knowledge and recurring service work.
- **API/UI:** Service desk queues, incident/request intake, assignment, triage, customer portal, SLA dashboards, escalation, knowledge and recurring-service workspace.
- **Correctness:** SLA clock start/pause/stop, business hours, timezone/holidays, severity and breach/escalation policy must be explicitly defined. Handover creates traceable asset/service records; repeated events do not duplicate them.
- **Security/operations:** Customer isolation, support-team/project/service entitlements, attachment handling, notification/retry, alerting, audit, retention and support runbooks.
- **Depends on:** S1.13 service transition and S1.3/S1.4 access/master data.

## 6. Cross-cutting capabilities are not deferred

The following are introduced with the first slice that needs them, not held until a final hardening phase:

- Document metadata/versioning, private file storage, rendering and safe delivery when survey evidence/quotations/contracts/UAT/BAST require it.
- Outbox/inbox and idempotent worker behavior with the first external callback, notification, render or retryable process.
- Audit and actor/tenant/source-version history with the first security- or business-critical mutation.
- Metrics, tracing/correlation, actionable alerts and runbooks as each service workflow appears.
- Customer and vendor portal access control as separate permission/projection contracts with the first external-facing operation; bilateral version-bound vendor BOQ approval with the first vendor commitment.
- Vendor invoice three-way matching (accepted subcontract/PO, accepted delivery evidence, vendor invoice) before AP release; keep AR and AP balances and cash directions separate.
- Financial decimal utilities, golden test cases and currency/tax/rounding policy before the first RAB or invoice calculations.
- Data retention, export, archival and privacy controls before storing the corresponding personal, contract or financial data.
- Performance/load budgets before the first operational scale claim.

## 7. Separate operational lane — S0.11

S0.11 scheduled backup/recovery remains independent of the S1 product sequence. The 14 November record verifies a natural timer-triggered backup, archive validation, Restic/R2 targeted read-back, Discord success notification and a guarded local retention apply. It remains open for an external disposable restore, measured 24-hour RPO/RTO objectives, remote pruning only when a reviewed candidate exists, and explicit owner acceptance.

Do not mark S0.11 complete because a product slice ships. Do not block routine local product engineering solely because S0.11 remains open. Production launch/continuity policy may impose additional release gates based on the actual operating risk.

## 8. Conditional SaaS and ecosystem lane — owner decision required

The PSA lifecycle does not silently settle FlowlessHub's own commercial packaging. Before implementing self-service signup, subscription billing, plan limits, metering, public API keys, webhooks, SSO/SCIM, marketplace or managed-cloud operation, record an owner decision and a separate dependency roadmap. This lane must reuse the same tenant security, audit, finance, operations and release standards; it is not a shortcut around them.

## 9. Roadmap exit and change control

A slice moves to the next status only with exact source evidence:

`SPECIFIED → OWNER DECISIONS RESOLVED → PATCH PREPARED → IMPLEMENTED → EXACT-SHA CI VERIFIED → RUNTIME VERIFIED (when required) → OWNER ACCEPTED → CLOSED`

A patch being prepared is not implementation. CI is not production runtime acceptance. Runtime health is not owner acceptance. Closed historical baselines are not re-run unless a new, documented risk requires it.

Any scope or dependency change updates this roadmap and the relevant slice/ADR before code relies on the changed contract.

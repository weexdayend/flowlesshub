# FlowlessHub — Domain and Module Architecture

**Status:** Owner-approved target architecture; implementation details remain slice/ADR-gated.
**Strategic baseline:** `92aec75c6387d6f57a1dc0d71c5ab7431f5831cd`
**Architectural style:** Go modular monolith, PostgreSQL source of truth, contract-first HTTP API, Next.js web application.

## 1. Architectural intent

FlowlessHub is one product and one business lifecycle implemented as explicit modules inside a modular monolith. The current repository has platform and identity foundations; the business modules below are the target decomposition, not a claim that these packages or tables already exist.

Preserve the current technology direction:

- Go API, worker and migration entry points.
- Next.js, TypeScript and React web application in the pnpm/Turborepo workspace.
- PostgreSQL as the authoritative transactional store.
- PgBouncer for API transaction pooling; worker and migration connection paths retain the session semantics they require.
- OpenAPI as the HTTP contract source, with generated Go and TypeScript outputs.
- Dedicated VPS Docker Compose Blue/Green deployment and GitHub Actions exact-SHA CI.

Do not split modules into microservices by default. Deployment units remain API, worker, migration and web until measured scale, isolation, security or independent operational needs justify another boundary.

## 2. Current implementation inventory

At the audited baseline:

| Area | Implemented repository evidence | Boundary / missing evidence |
|---|---|---|
| Platform | `/livez`, `/readyz`, `pgxpool`, Goose, sqlc, API/worker/migrate entry points | No business-domain services or module-owned business tables. |
| Identity | `identity.users`, `identity.sessions`, `identity.auth_events`; password verification, opaque session lifecycle, owner bootstrap | Browser sign-in UX, account recovery and membership mutation workflows are not present. |
| Tenant foundation | `tenant.organizations`, `tenant.memberships`; active membership listing | No tenant-owned business tables, request tenant context, RLS policies or membership invitation lifecycle. |
| API contract | OpenAPI 3.1 health and S1.1 identity operations; generated Go/TS output | No business operations, client portal contract or public integration API. |
| Frontend | Next.js root layout and static preview shell | No auth routes, protected route group, authenticated API data flow, tenant context or persisted business UX. |
| Worker | River client and one platform no-op handler | No business job handlers, outbox dispatcher or scheduled business workflows. |
| Operations | Docker Compose Blue/Green, Caddy/Nginx edge, CI, backup scripts and systemd timer | Application metrics/traces/alerts and external restore/RPO/RTO proof remain incomplete. |

The only current business-adjacent schemas are identity and tenant access. Do not treat the preview UI's sidebar labels as implemented routes or persisted capabilities.

## 3. Target module boundaries and ownership

The following boundaries are the proposed ownership map. Each module owns its schema/tables, domain rules, write operations, read models and tests. Actual PostgreSQL schemas and Go package paths should be fixed in each slice specification before its first migration.

| Module | Owns | Must not own / must not bypass |
|---|---|---|
| **Identity** | Global human identities, passwordless/WebAuthn credentials, authenticator assurance, server-side sessions, internal OIDC issuer and first-party client registry, account recovery, security events and authentication audit | Organization role decisions, tenant membership and business-record visibility. |
| **Tenant Access** | Organizations, memberships, invitations, organization settings, role/permission assignments, tenant context establishment | Global credential verification or business facts. |
| **CRM** | Customers, contacts, prospects/leads, opportunities, ownership and pipeline history | RAB calculations, contract execution or project delivery state. |
| **Survey & Solution** | Survey cases, technical findings, requirements, constraints, proposed solution/scope and evidence references | Approved selling price or issued quotation snapshots. |
| **Estimation (RAB)** | Provider-owned estimate versions, internal BoQ/cost lines, units/quantities, labor/material/vendor cost inputs, pricing assumptions, margin calculations and internal estimate approval | Customer-facing disclosure of internal cost/margin or ownership of vendor-submitted quote/BOQ revisions. |
| **Commercial & Quotation** | Pricing proposals, approval decisions, quotation versions, issue/expiry/response lifecycle and external quotation projections | Contract legal terms or mutable source estimates after issue. |
| **Document Management** | Document metadata, logical ownership, versions, access classification, render jobs and storage references | Binary storage secrets or arbitrary cross-tenant document access. |
| **Contract & Obligations** | SPK/contract versions, amendments, commercial terms, payment schedules, obligations and execution evidence references | Rewriting signed artifacts or accounting ledger balances. |
| **Project Delivery** | Project creation, approved baselines, phases, milestones, work packages, tasks, assignments, progress and delivery evidence | Contract source-of-truth or finance posting rules. |
| **Resource & Time** | Delivery roles/skills, availability references, assignments, effort/time entries and cost-rate references where approved | Full HR/payroll policy unless separately approved. |
| **Procurement & Vendor** | Supplier records, project procurement packages, RFQs, vendor quote/BOQ submissions and revisions, negotiation history, bilateral approval evidence, subcontract/PO commitments, receipts and supplier cost evidence | Customer quotation/contract ownership, internal sales margin, unrelated general-ledger posting or unrestricted vendor access. |
| **Change Control** | Change requests, impact assessments, approvals and approved baseline/schedule/commercial adjustments | Editing prior signed contract or closed project snapshots. |
| **Acceptance & Transition** | UAT plans/cases/results, defects/retests, BAST, handover package, service-transition evidence and asset-origin events | Service desk ticket state after operational handover. |
| **Finance / AR & AP** | Customer billing/receivables and supplier invoicing/payables as separate aggregates: invoices, credit/debit adjustments, receipts, supplier settlements, allocations, outstanding balances and aging | Conflating customer money-in with vendor money-out, silently changing issued invoices/contracts, or bypassing procurement and delivery verification. |
| **Project Controls** | Budget baseline, committed/actual project costs, revenue/margin projections, variance and project P&L views | Treating management P&L as statutory accounting without approved policy. |
| **ITSM** | Service agreements, service assets/configuration references, incidents, requests, SLA clocks/escalations, recurring service and knowledge | Mutating closed delivery/acceptance records. |
| **Integration & Notifications** | Provider adapters, inbound/outbound webhook records, delivery attempts, retry policy and notification preferences | Domain ownership; adapters call module contracts rather than writing another module's tables. |
| **Audit** | Append-only audit records for privileged, commercial, financial and evidence-changing actions | Replacing domain transaction history or serving as the only source of current state. |

The module list is a logical decomposition, not a requirement to create one Go package per row immediately. Create a module when its first production slice needs it. Keep names, schemas and dependencies explicit in ADRs and `go-arch-lint`.

## 4. Core entity relationships

This is a relationship map, not a finalized ERD. Exact columns, optionality, cardinality, retention and legal semantics belong in each domain model and migration review.

- A **global user** can hold active, invited or suspended **memberships** in one or more **organizations**. Organization membership and role are always evaluated for the current request.
- An **organization** owns its customers, contacts, leads, opportunities, surveys, estimates, quotations, contracts, provider-side project delivery records, work, acceptance records, invoices, payment allocations, cost records and ITSM records. The customer may be the legal/business/asset owner of the underlying project; keep that project-owner/customer party reference explicit and distinct from the provider tenant that owns the PSA delivery record.
- A **customer** has one or more **contacts**. A contact may be associated with sales activity, survey participants, quotation recipients, contract signatories or service users only through explicit scoped relationships.
- A **lead/opportunity** may reference a prospect/customer and contact, assigned owner, activity history and qualification outcome. Conversion must preserve source identity and history rather than copy-and-forget.
- A **survey** belongs to an opportunity or approved service engagement and contains findings, scope assumptions, solution items and evidence/document references.
- An **RAB/estimate** contains ordered, versioned lines for work/items, quantities, units, cost basis, pricing assumptions, taxes/rounding context and approval history. A quotation must reference a specific approved estimate version.
- A **customer quotation** has immutable issued versions and a customer-visible selling-price projection. Customer response/acceptance identifies the exact version, actor, timestamp and evidence. It never exposes internal supplier rates or margin by default.
- A **vendor RFQ response / vendor BOQ** is a separate vendor-owned proposal scoped to an explicitly assigned procurement package. It has immutable revisions and line-level descriptions, quantities, units, rates, totals, currency, tax basis, delivery/milestone assumptions, exclusions, validity and supporting evidence. It links back to the estimate/project work package without becoming the customer quotation.
- A **vendor subcontract / purchase order** references the exact vendor BOQ revision approved by the provider and accepted by the vendor. It records contracting parties, scope, price, currency, commercial terms, delivery/acceptance milestones, payment terms, permitted line types and variation rules. The accepted revision is immutable; changes create a successor proposal/amendment.
- A **contract/SPK** references the customer-accepted quotation or other approved customer commercial source, contains its own versioned terms/obligations and amendments, and defines project/billing obligations. It is distinct from every provider-vendor subcontract/PO.
- A **project** references the signed/approved contract scope and records its own baseline, work breakdown, milestones, tasks, assignments, delivery evidence and change history.
- A **UAT/BAST/handover** package references the project baseline and delivered scope, with checklist results, defect closure, signer/actor, timestamp and immutable evidence references.
- **Billing events** derive from approved contract obligations, milestones, delivery acceptance or agreed recurring/time-and-material rules. An **invoice** references its source obligation and immutable issue version.
- A **payment receipt** has an external/internal reference and is allocated to one or more invoices through explicit allocation records. Reversal/chargeback does not erase the original receipt or allocation history.
- A **project** may contain zero or many **procurement packages** mapped to project work packages/BoQ lines. Each package may invite one or more vendors; the selected vendor award becomes a separate subcontract/PO while alternative bids remain retained as evaluation evidence.
- **Vendor delivery evidence** includes accepted goods/quantity receipts, approved time/expense/material consumption or milestone completion according to the subcontract's billing method. A **vendor invoice** is matched to the approved subcontract/PO lines and corresponding accepted receipt/progress evidence before it becomes payable.
- **Project cost** sources may include procurement commitments, verified/approved supplier invoices, expenses, labour/time records and approved adjustments. Project P&L is a reproducible projection over these records and an explicitly approved revenue/cost policy.
- A **service agreement** and handover package can establish service assets/configuration records, service entitlements, recurring commitments and SLA policies. Incidents/requests reference the applicable customer, service agreement and affected asset/CI where known.

All tenant-owned entities have `organization_id NOT NULL`. Composite foreign keys or equivalent constraints should prevent relationships from connecting records across organizations. Unique natural keys are scoped to the organization unless a true global identifier is intended and documented.

## 5. Two-party and three-party commercial workflow

The provider organization is the tenant and prime contractor in the supported operating pattern. The customer is its client/counterparty; a vendor is a supplier/subcontractor engaged by that provider. The customer does not become the owner of the provider tenant's internal project records, and a vendor does not become a tenant member merely because it is assigned project work. Customer and vendor portals are separate external projections with separate invitation, authorization, audit and revocation rules.

### Two-party path — provider and customer

`Lead → Survey → internal RAB/estimate → customer quotation (and customer BOQ/RAB disclosure if contractually required) → customer approval → customer SPK/contract → project → provider's own delivery → UAT/BAST → customer invoice/receivable → payment/collection → project P&L → ITSM`

No vendor master, RFQ, subcontract or vendor invoice is required for a project delivered entirely with the provider's own resources.

### Three-party path — provider, customer and subcontractor/vendor

The customer-facing path remains the same. A separate procurement lane is attached to the relevant estimate/project work packages:

1. Create a procurement package from approved scope/BoQ lines. It may be used during presales for a non-binding/budgetary vendor quote that informs the internal RAB, or after customer award for a formal RFQ and subcontract award. A budgetary response is not a purchase commitment.
2. Issue only the relevant RFQ package to selected vendors. Vendors submit line-level quote/BOQ revisions; clarification and negotiation preserve every revision and response.
3. Internal technical, delivery and commercial reviewers check quantities, units, scope, exclusions, rates, currency, tax, schedule, dependencies, acceptance evidence and project margin. Internal approval and vendor acceptance must both reference the same exact immutable revision. Capture each approving/accepting identity, authority, timestamp, terms snapshot and document hash.
4. Only after required approvals is the award converted into a confirmed subcontract/PO. No vendor mobilization, order placement or billable commitment occurs from a draft or unapproved BOQ unless a separately approved emergency/provisional policy explicitly allows it.
5. During execution, record receipts and accepted progress/time/material/expense/milestone evidence against subcontract lines. Vendor invoices are checked against the accepted subcontract/PO and accepted delivery evidence (a controlled three-way match) before release to Accounts Payable.
6. Vendor variation requests create a separately versioned change to the vendor commitment. If it affects customer scope, customer price, contract obligation, schedule or acceptance criteria, a separate customer change/variation approval is required. Neither approval substitutes for the other.

A project may use multiple packages and vendors, including a mix of provider-delivered and subcontracted work. Vendor purchase currency may differ from project currency and customer sales currency; persist the currency and effective FX basis used for each estimate/commitment/actual rather than silently merging the values.

## 6. Critical invariants and state ownership

1. **Tenant ownership:** a business record cannot exist without one organization. The authenticated actor must have an active membership and the specific permission before a read or mutation.
2. **Database isolation:** tenant access is enforced by tenant-scoped repositories and PostgreSQL RLS. A client-provided organization ID selects a candidate context; it never proves access.
3. **Final active owner:** membership mutations must not leave an active organization without an active owner. Validate under a database transaction/locking strategy that remains correct under concurrent demotion, suspension, invitation acceptance and transfer.
4. **Version lineage:** approved/issued RABs, customer quotations, vendor BOQs, bilateral vendor approvals, signed customer contracts, vendor subcontracts/POs, baselines, invoices and acceptance evidence refer to immutable versions or append-only revisions. A correction creates an explicit successor or compensating record.
5. **Financial reproducibility:** monetary values use `NUMERIC`/decimal arithmetic; calculations record currency, scale, rounding, tax basis/effective period and source rates as required. Never use binary floating point for money.
6. **Confidentiality:** internal cost, margin, discount authority, supplier cost, private notes and approval rationale are exposed only to authorized internal actors. Customer and vendor projections are separately defined contracts; vendors see only their awarded/invited package, and customers never inherit vendor-private details.
7. **Idempotency:** retryable issuance, conversion, payment/webhook ingestion, invoice generation, notification and background work use stable idempotency keys or source uniqueness constraints.
8. **Concurrency:** state transitions use row locks, version columns/ETags or uniqueness constraints where competing writes can change money, approval, ownership, sequence numbers or deliverable state. Bilateral vendor approval is valid only for the exact revision both parties accepted.
9. **Auditability:** authorization changes, approvals, estimate/quotation/contract/invoice issue, payment allocation, acceptance, export and privileged access emit actor-attributed audit evidence in the same transaction or through a reliable outbox.
10. **Lifecycle traceability:** every downstream record preserves its source references. Reversal, cancellation, expiry and amendment are explicit transitions, not destructive deletion.

Each module defines its own state machine. Illustrative words such as draft, submitted, approved, issued, accepted, rejected, expired, active, suspended, completed or reversed are not adopted status enums until their transition rules and actor permissions are specified.

## 6. Cross-module interaction and transaction boundaries

- A module writes only its owned tables. Another module reads through a documented service/interface or an intentionally designed read model; direct cross-module table mutation is prohibited.
- Keep atomic transactions inside a module/aggregate where the invariant requires one commit: e.g., estimate approval with its immutable approval snapshot, quotation issue with its version and audit entry, or payment receipt with allocation rows and idempotency record.
- A cross-module transition may use an application-level orchestrator in the modular monolith. Use one PostgreSQL transaction for a small, bounded local invariant only when the ownership and lock order are explicit. Do not create an implicit distributed transaction.
- When work crosses a retryable boundary (PDF rendering, email delivery, e-signature, payment callback, external accounting export, scheduled notifications), write an outbox record in the same transaction as the source state change. Workers claim and process it idempotently; inbox/provider-event records deduplicate inbound deliveries.
- A committed domain fact is not rolled back merely because a notification or external adapter is temporarily unavailable. Record retry state, dead-letter/manual-repair state and correlation IDs.
- River is the current worker technology. Its existing handler is a no-op placeholder; business handlers, queue ownership, retry/backoff, timeout, concurrency and dead-letter/manual replay rules must be specified with the first job-bearing slice.
- Avoid a generic workflow engine. Encode important transitions in the owning domain and introduce reusable orchestration only after multiple real workflows demonstrate a common, stable requirement.

## 7. Tenant database execution model — hard gate before business tables

The repository currently uses PgBouncer `POOL_MODE=transaction` for API traffic. The API `DATABASE_URL` uses the configured `FLOWLESSHUB_DB_USER`; the migration and database initialization paths currently use the same configured DB user. No distinct non-owner application role or RLS policy is present in the current migrations.

Before the first tenant-owned business relation is added, the implementation slice must:

1. Separate the migration/owner role from the runtime application role. The runtime role is non-superuser, does not own tenant tables, has no `BYPASSRLS`, and has only required grants.
2. Enable and, where appropriate, `FORCE ROW LEVEL SECURITY` on each tenant-owned table. Define deny-by-default policies for missing, malformed or unauthorized tenant context.
3. Establish tenant context only after authenticated membership and authorization checks, inside the same PostgreSQL transaction that executes tenant queries. Use transaction-local settings (`SET LOCAL` or `set_config(..., true)`); do not use session-level state on a transaction pool.
4. Ensure every repository operation carrying tenant data uses the transaction-bound context. No query on a separate pool connection may accidentally bypass the transaction policy.
5. Prove isolation through PgBouncer transaction-pool reuse: run alternating Tenant A/Tenant B transactions across reused connections and verify no context leakage, including after commit, rollback, errors, timeout and cancellation.
6. Prove that the runtime role cannot read/write another tenant by direct SQL even when the application forgets a filter; prove table owners/migration roles are not used by API runtime.
7. Keep identity/control-plane access distinct from tenant business-data access; use explicit narrowly scoped policies for the organization/membership lookups required to establish context.
8. Include two-tenant negative tests for every tenant-owned repository and endpoint, plus migration/privilege tests.

This is a merge blocker for the first customer/contact or other tenant-owned business table. It is not a future hardening milestone.

## 8. API and frontend contracts

- OpenAPI remains the source of truth for externally consumed HTTP operations. Changes generate and commit the Go server and TypeScript client outputs; generated files are not hand-edited.
- Define separate internal, customer, vendor and public projections. Never reuse an internal response DTO for external clients merely by hiding fields in the UI.
- Mutations that can be retried must define idempotency behavior. Concurrent resource updates define `ETag`/row-version or an explicit conflict response.
- HTTP errors are consistent, machine-readable and avoid leaking internal data. Pagination, sorting, filtering and export limits are explicit.
- The current API cookie is host-only to the API host. The Next.js web host therefore cannot read it during server rendering or middleware execution. S1.2 must resolve the browser-session topology before implementation.
- **Owner-approved S1.2 target:** the Next.js application uses a same-origin backend-for-frontend (BFF) for server-side route protection and API calls. The BFF owns an opaque host-only application-session cookie and a server-side session/token binding; the internal Identity authority owns the revocable identity/SSO session. Keep the two cookies host-only and distinct. OIDC authorization-code exchange occurs server-to-server. No raw token is exposed to browser JavaScript, local/session storage, URL, HTML, or logs. The exact BFF session store, CSRF contract, cookie rotation, revocation propagation, and Blue/Green overlap are fixed in ADR-0001 implementation detail before code.
- Frontend authorization is presentation and navigation only. The API rechecks session, organization membership, resource permission and tenant context on every protected operation.

## 9. Integration boundaries

Use adapter interfaces owned by the relevant domain. Provider selection and business policy remain open until an owner decision is recorded.

| Integration concern | Owning module / boundary | Required controls |
|---|---|---|
| Document binary storage and rendering | Document Management | Private tenant-scoped object keys, authorization before download, version/hash metadata, malware/content checks where applicable, retention and signed-download expiry. |
| Email / WhatsApp / notifications | Integration & Notifications | Existing owner SMTP adapter for transactional email; verified recipient intent, templates, rate limits, durable outbox, deduplication, retry, bounce/failure state and delivery status; never make domain commits depend on synchronous delivery. Email is not an authentication factor. |
| E-signature | Contract & Acceptance adapters | Provider evidence, document hash/version binding, callback signature verification, revocation/correction semantics and legally valid provider selection by owner. |
| Payment gateway | Finance adapter | Verified webhook signatures, idempotent event ingestion, reconciliation, refunds/reversals and no client-supplied payment status. |
| Accounting / tax systems | Finance adapter | Versioned mappings, tax/accounting policy approval, export idempotency, reconciliation reports and exception queues. |
| External REST APIs / webhooks | API platform | Scoped credentials, key rotation, signed webhook delivery, replay protection, rate limits and audit. |
| First-party OIDC SSO | Identity | Internal issuer; Authorization Code + PKCE `S256`; exact redirect URI registration; transaction-bound `state`/`nonce`; issuer/audience/signature/time validation; short-lived single-use codes; scoped clients and server-side BFF token handling. |
| External enterprise identity federation | Identity | Customer-owned OIDC/SAML provider onboarding, verified domains, account linking, JIT/SCIM lifecycle and recovery policy are separate future decisions; no external provider is assumed now. |
| SMTP transactional email | Integration & Notifications, invoked by Identity and owning domains | Existing owner SMTP through a server-side adapter; TLS, sender-domain verification, SPF/DKIM/DMARC alignment, durable outbox, idempotent retries, rate limits, bounce/failure handling and redacted observability. Email OTP/magic links are not authentication factors. |

## 10. Decisions required before affected slices

Create a scoped ADR or product policy for each of the following before its first implementation:

- BFF server-side session binding/storage, CSRF/Origin contract, cookie rotation, OIDC login handoff and Blue/Green session compatibility (S1.2-A).
- Role/permission model, customer/vendor actor identities, tenant context and PostgreSQL roles/policies (S1.3).
- Customer hierarchy, duplicate handling, contact consent and external portal identity (CRM/master-data slices).
- Survey templates, RAB unit/tax/margin semantics, approval thresholds and quotation validity/version policy.
- Contract/SPK legal template, signing method, amendment and obligation semantics.
- Project baselines, progress measurement, resource capacity/time capture and vendor/procurement scope.
- UAT/BAST evidence, required signatures and asset/service transition model.
- Tax, invoice numbering, payment gateway, allocation/reversal and accounting export.
- Revenue recognition, WIP, cost allocation and P&L basis.
- SLA calendar/timezone/holiday, pause conditions, severity, response/resolution definitions and recurring-service contract.
- Data classification, retention, deletion/export, regional hosting, service availability objectives and support model.

Do not block current architectural documentation on making these decisions. Keep them visible and resolve each at the point where it changes the data model, contract or legal/financial behavior.

## 11. Identity platform contract — owner-approved 14 November 2026

### 11.1 Authority and trust boundaries

- Keep the existing Go Identity module and S1.1 global `identity.users` as the internal identity authority. The authority authenticates humans and issues/revokes sessions; it does not decide organization or project permissions.
- Use OpenID Connect as the first-party SSO protocol. Do not invent a custom SSO token format or make a third-party identity provider a runtime dependency for first-party sign-in.
- Existing production origins are `https://app.flowlesshub.com` and `https://api.flowlesshub.com`. The intended issuer origin is the existing API origin; the WebAuthn ceremony is presented only by the approved first-party login surface. Exact issuer metadata, WebAuthn RP ID/origin allowlist, callback URLs and local-development origins must be explicit configuration and frozen in S1.2-A before the first credential is registered. No wildcard origins, parent-domain cookies or inferred subdomain trust.
- First-party applications (initial web app; later customer/vendor applications) register as separate OIDC clients with exact redirect URIs, audiences, scopes, session policies and revocation behavior. Future portals redirect to the central first-party login surface; they do not gain additional WebAuthn origins by default.

### 11.2 Passwordless and authenticator assurance

- WebAuthn/FIDO2 passkeys are the preferred primary passwordless authenticator. Require `userVerification=required` for registration and assertion; do not silently downgrade to `preferred` or `discouraged`.
- The server validates one-time random challenges, expiry and purpose binding, `clientDataJSON` type/challenge/origin, RP ID hash, user-presence/user-verification flags, signature, credential ownership and authenticator data. Challenges are bound to the intended user/session and consumed atomically. Origin allowlists are exact; RP ID is a dedicated, reviewed value.
- Support more than one credential per user, including platform passkeys and external FIDO2 security keys. Store public credential material and required metadata only. Do not store private authenticator keys. Attestation collection is minimized; enterprise/device attestation is not enabled by default without an explicit privacy/security decision.
- Record the evidence needed to classify a ceremony as single-factor cryptographic or multi-factor cryptographic. A successful passkey assertion is phishing-resistant when the WebAuthn verifier-name binding is validated, but do not claim every synced or user-verification-capable credential satisfies the same MFA assurance. If an authorization policy requires MFA, it must demand a credential/event that meets the configured multi-factor assurance requirement.
- Recovery codes are random, single-use lookup secrets; store only a verifier/hash, show them once, rotate/revoke them after use, and audit generation/use. A second enrolled passkey/security key is the preferred recovery route. An email notification is not proof of identity. Manual recovery requires a documented, independently verified process and separation of duties.
- S1.1 password hashes and session semantics remain a migration bridge. Enrollment requires an already authenticated S1.1 account; keep the change additive, support rollback, and do not remove password compatibility until enrollment, support recovery, and a separately approved retirement policy are proven.

### 11.3 OIDC and BFF

- Use Authorization Code Flow with PKCE `S256` for all browser first-party clients, including confidential BFF clients. Require transaction-specific state and nonce, exact redirect URI equality, issuer identification/mix-up defense, ID-token issuer/audience/signature/nonce/expiry validation, short-lived single-use authorization codes and audience-/scope-restricted tokens.
- Do not implement Implicit Flow, Resource Owner Password Credentials grant, wildcard callback matching, open redirects, or bearer tokens in browser storage. Client secrets and access/refresh tokens remain server-side. Apply key rotation and publish the appropriate OIDC discovery/JWKS metadata.
- The BFF uses an opaque, host-only, HttpOnly application cookie (`Secure`, `Path=/`, no `Domain`, appropriate `SameSite`) and a server-side record bound to the user, Identity session, OIDC client, expiry and revocation state. The existing S1.1 identity cookie/session remains separately host-only to the API origin. Do not share one broad-domain cookie across app, client and vendor origins.
- Logout/revocation invalidates the central Identity session and all bound BFF application sessions. Reauthentication/step-up events are explicit and auditable; API authorization is rechecked on every protected request.

### 11.4 SMTP delivery

- Use the SMTP service/domain already owned by the product owner; do not invent hostnames, sender addresses, credentials, ports or TLS modes. Record them as deployment configuration after a redacted connectivity/deliverability preflight.
- Use email for address confirmation, later organization/user invitations, security notifications, and recovery notifications. No email OTP/magic-link login, MFA or step-up; no use of mailbox access as an out-of-band authenticator.
- Persist outbound notification intent with the domain/security event through a durable outbox. River workers deliver asynchronously with idempotency, bounded retries/backoff, deduplication, bounce/failure status and manual-repair visibility. SMTP outage must not roll back an already committed login, security or business-domain event.
- SMTP credentials and signing secrets belong only in the protected runtime secret store. Verify SMTP TLS, sender-domain SPF/DKIM/DMARC alignment, abuse/rate controls and redaction before enabling production send. Never place secret values in Git, CLI arguments, chat, process lists or logs.

### 11.5 Relationship and authorization separation

- One global human identity may later participate in multiple relationships, but identity linking does not grant access. Workforce organization membership, customer-contact access and vendor-user access are distinct relationship types.
- Customer and vendor identities receive only explicitly delegated project/package/document permissions through the authorization model; they are not automatically added as members of the service-provider tenant. One person acting for a customer and a vendor must select and prove the corresponding context, and data/approval trails remain separated.
- S1.2 establishes authentication and first-party SSO only. S1.3 owns organization membership, role/permission matrix, assurance requirements by privileged role, customer/vendor delegated authorization, tenant context, runtime DB role, RLS and PgBouncer isolation.

### 11.6 Required implementation order

1. Review ADR-0001, threat model, exact origins/RP ID, client registry, BFF/session topology and recovery policy.
2. Validate SMTP delivery configuration and domain authentication without exposing credentials; implement the adapter/outbox and isolated delivery tests.
3. Add WebAuthn registration/authentication and credential lifecycle with additive migrations and full negative/security tests.
4. Add OIDC issuer/client support and Next.js BFF integration; keep tokens server-side and verify session/revocation behavior across Blue/Green overlap.
5. Add recovery codes, account-security notifications, session/device inventory and controlled migration from S1.1 password sessions.
6. Verify authenticator assurance semantics and expose policy hooks for S1.3; do not bypass role policy or tenant isolation.

No customer/vendor portal, external enterprise IdP federation, SCIM, or tenant-owned business table is implemented by S1.2. These use the established contracts in later slices.

# FlowlessHub — Product Strategy

**Status:** Owner-approved product direction and first-party identity baseline; implementation remains incremental and slice-gated.
**Strategy date:** 14 November 2026
**Repository:** `weexdayend/flowlesshub`
**Strategic baseline:** `92aec75c6387d6f57a1dc0d71c5ab7431f5831cd`

## 1. Product mandate

FlowlessHub is a production-grade Professional Services Automation (PSA) platform for IT services companies. It must connect the full commercial, delivery, financial, and ongoing-service lifecycle in one coherent product.

The product is **not MVP-first, pilot-first, demo-first, or prototype-first**. No essential lifecycle capability is declared out of scope merely to achieve a narrow first sale. Delivery remains incremental: each vertical slice is small enough to design, implement, validate, deploy, and operate safely, but is production-grade at its own boundary and fits the complete target architecture.

The product target is:

**Lead → Survey → RAB → Quotation → SPK/Contract → Project Delivery → UAT → BAST → Invoice → Payment → Project P&L → ITSM**

The arrows represent connected business transitions, not a requirement that every company use every stage in exactly the same way. Configuration may vary by service model, but version history, authorization, financial correctness, evidence, and tenant isolation must not vary by screen or workflow.

## 2. Customer and operating model

### 2.1 Target organizations

The primary customer is an IT services provider that sells, scopes, delivers, accepts, bills, and supports technology services. This includes project-based delivery and ongoing managed-service operations. The product must accommodate organizations with sales/presales, project delivery, finance, technical delivery, and service operations responsibilities without assuming that every customer has the same department structure.

### 2.2 Actors and operating responsibilities

The following are capability personas, not a fixed role catalogue:

- **Organization owner / administrator:** organization configuration, access governance, commercial policy, and privileged approvals.
- **Sales / account team:** customers, contacts, leads, opportunities, quotations, and commercial follow-up.
- **Presales / solution team:** survey evidence, scope, solution design, RAB assumptions, costs, and margin proposals.
- **Project manager / delivery lead:** project initiation, baselines, plans, assignments, progress, changes, and acceptance readiness.
- **Engineer / technician / field team:** assigned work, technical evidence, time or effort capture where enabled, and handover information.
- **Finance:** billing schedules, invoices, payment allocations, receivables, cost capture, and financial reporting.
- **Service desk / service manager:** service agreements, assets/configuration items, requests, incidents, and SLA operations.
- **Customer-side contact:** only the externally approved documents, decisions, submissions, and service interactions for which the contact is authorized.
- **Supplier / partner:** only explicitly delegated procurement, task, or deliverable interactions if the vendor capability is enabled.

Actual roles, role inheritance, separation of duties, and customer/vendor portal permissions remain subject to a dedicated authorization design. The personas above do not grant permissions.

### 2.3 Tenant model

The S1.1 foundation establishes a global human identity and organization-scoped membership. The organization is the initial tenant boundary for business records. Every tenant-owned record must carry a non-null organization identifier and be protected at the application, repository, and PostgreSQL layers.

Do not add a generic workspace layer or nested tenant hierarchy without an approved business requirement. Organization units, departments, multiple legal entities, subsidiaries, and cross-organization shared customers are unresolved product/model decisions rather than assumptions.

### 2.4 Two-party and three-party project operating patterns

FlowlessHub must support both patterns without forcing every project through procurement. The customer may be the legal/business/asset owner of the underlying project; that is a business-party role, not the FlowlessHub tenant owner. The service provider tenant owns its PSA delivery record, work history and operational evidence, and must explicitly link the customer/project-owner party rather than treating the client as the tenant.

- **Two-party delivery:** the FlowlessHub tenant is the IT services provider and prime contractor; its customer is the project client. The provider scopes, prices, contracts, delivers with its own resources, obtains customer acceptance, bills the customer and supports the resulting service. No vendor/subcontractor record is required.
- **Three-party delivery:** the same provider remains the prime contractor to the customer and separately engages one or more vendors/subcontractors for defined portions of the project. The customer-provider contract and each provider-vendor subcontract/purchase commitment are separate commercial relationships. The provider remains accountable to its customer for the contracted outcome unless the customer contract explicitly states otherwise.

A project may therefore have zero, one or many procurement packages and vendors. A vendor is a supplier/subcontracting counterparty to the provider, not a co-owner of the provider tenant or an unrestricted member of its workspace. Vendor users receive only explicitly delegated access to the RFQ, vendor BoQ/quotation, subcontract lines, delivery evidence and invoice actions assigned to their vendor account. Customer users receive a separate projection for customer quotation, customer-approved scope, project progress, UAT/BAST, invoices and service interactions. Customer and vendor identities, permissions, documents and approval routes must not be conflated.

The following are different business records and must never be represented by one shared document or approval flag:

1. **Internal RAB / estimate:** the provider's versioned cost and selling-price calculation, including internal labor/material cost, vendor quote inputs, tax/currency assumptions and margin. Cost and margin remain internal.
2. **Customer quotation / customer-facing RAB or BOQ:** the provider's approved selling offer and scope projection. A detailed customer BOQ/RAB is exposed only when the commercial agreement requires it; it contains customer-authorized selling values, not supplier cost or internal margin.
3. **Vendor RFQ response / vendor BOQ:** a vendor's separate proposal for the scope package it is invited to price, including descriptions, quantities, units, rates, totals, currency, taxes, delivery/milestone assumptions, exclusions and validity. It is linked to the relevant estimate and project work packages but is not the customer quotation.
4. **Vendor subcontract / purchase order:** the binding provider-vendor commitment created from an explicitly approved vendor proposal revision. Both sides' acceptance must identify the same immutable BOQ/quote revision and its supporting terms.

A vendor's approval of its BOQ does not constitute customer approval of the project scope, price or variation. Customer approval does not silently amend a vendor's agreed BOQ or rates. A change affecting both relationships requires two separately authorized, linked decisions and a reconciled impact on project baseline, margin and schedule.

## 3. Lifecycle capability map

| Lifecycle stage | Business capability | Required operational result |
|---|---|---|
| Lead | Lead capture, qualification, ownership, pipeline and conversion | A prospect and its history can be followed into a real opportunity without losing provenance. |
| Survey | Technical and commercial discovery, findings, constraints, solution scope and evidence | Delivery scope and assumptions are explicit, attributable, and reviewable. |
| RAB | Versioned internal work/BoQ estimate, quantities, units, cost assumptions, supplier quote inputs, pricing and margin | Cost, selling price, tax assumptions and margin reconcile deterministically; customer and vendor projections remain separate. |
| Quotation | Approved, versioned offer and customer-facing document | A customer receives a specific immutable offer version and can respond against that version. |
| SPK / Contract | Contract, amendments, obligations, term, payment schedule and evidence | The agreed commercial baseline is traceable and changes do not rewrite signed history. |
| Project Delivery | Project initiation, baselines, planning, work execution, assignment, progress and changes | The delivery team executes against an approved scope, schedule, budget and responsibility model. |
| UAT | Test scenarios, defects, retests and customer acceptance | Acceptance criteria and evidence are complete and attributable. |
| BAST | Formal handover/acceptance record and transition prerequisites | Handover is tied to the exact delivered scope and evidence set. |
| Invoice | Customer billing/receivables and supplier billing/payables, with separate invoice and settlement lifecycles | Customer receivables and vendor payables reconcile to their own contracts, delivery evidence and cash movements. |
| Payment | Receipts, provider references, allocations, reversals and outstanding balances | Payments are idempotent, allocatable, auditable and reconcilable. |
| Project P&L | Budget, commitments, actual costs, revenue and margin reporting | Project profitability reconciles to source operational and financial records and exposes its calculation basis. |
| ITSM | Service transition, service agreements, assets/configuration, incidents, requests, SLA and recurring work | Accepted delivery becomes supportable ongoing service with measurable commitments. |

The stages are a capability target. Detailed state machines, legal meaning, accounting treatment, and exception paths must be specified with their owning domain and approved before implementation.

## 4. Product principles

1. **One connected lifecycle, distinct commercial lanes.** A customer quotation retains its originating opportunity, survey and approved RAB version; a vendor BOQ/subcontract retains its RFQ, vendor, project package and accepted revision; a project retains the customer contract and supplier commitments separately. Acceptance, customer billing, vendor payables and service transition preserve their own source references.
2. **Business records are durable evidence.** Approved RABs, issued customer quotations, vendor BOQ/quote revisions, bilateral vendor approvals, signed customer contracts, vendor subcontracts/POs, invoices, payment allocations and acceptance records are versioned or immutable as appropriate. Corrections use explicit revisions, amendments, credits, reversals or compensating records.
3. **Security is part of the domain.** Organization membership, role, project visibility, cost/margin confidentiality, customer/vendor data boundaries, delegated external access and privileged approvals must be enforced by the backend and database, not just by navigation or disabled controls.
4. **Financial values are exact.** Money uses PostgreSQL `NUMERIC` and decimal arithmetic, explicit currency and rounding rules, and reproducible calculations. Floating point is not a monetary representation.
5. **Internal and external views are separate contracts.** Cost, margin, internal notes, supplier data and approval context never leak into customer/vendor DTOs or documents by accident.
6. **Operational use is the quality bar.** Loading, failure, empty, permission-denied, retry, recovery, audit and support workflows are product behavior, not finishing work.
7. **Modular monolith first.** Modules have explicit ownership and APIs. A separate service, event broker, or generic workflow engine requires measured justification and an ADR.
8. **Incremental delivery, complete architecture.** No slice is a disposable MVP. A slice must preserve the invariants and dependency contracts of the target lifecycle.

## 5. Current product reality

The product target above is not a claim that the lifecycle already exists in code.

At the audited repository baseline:

- The production Go modular-monolith API has platform health/readiness endpoints and S1.1 identity/session/organization APIs.
- PostgreSQL contains the platform schema and S1.1 identity/tenant foundation relations.
- There are no customer, contact, lead, survey, RAB, quotation, contract, project, UAT, BAST, invoice, payment, project P&L, or ITSM business tables yet.
- The OpenAPI contract contains health and identity operations; no PSA business endpoints exist.
- The Next.js app is a preview/foundation shell. It has no sign-in page, authenticated session restoration, organization switcher, protected application route, or persisted business workflow.
- The River worker is present but currently registers only a platform no-op bootstrap handler; business job handlers are not implemented.

S1.1 remains closed and owner-accepted for its backend/API scope. Its web sign-in/session UX is a deferred scope item, not an S1.1 defect.

## 6. Explicitly outside the current commitment / owner decisions

These are not silently decided by this strategy:

- SaaS packaging, subscription tiers, self-service signup, tenant provisioning automation and billing for FlowlessHub itself.
- Multiple legal entities, subsidiaries, organization-unit hierarchy, cross-tenant collaboration, shared customer masters and data residency.
- External enterprise identity federation (customer-owned OIDC/SAML IdPs), cross-tenant identity linking, and the final role-to-authenticator-assurance matrix. First-party passwordless authentication, internal OIDC SSO, transactional SMTP email, and recovery baseline are decided by ADR-0001. Customer and vendor access must remain separate even if one natural person participates in both relationships.
- Industry-specific survey templates, service catalog taxonomy, project templates, customer/vendor approval matrices and document numbering.
- Contract/SPK templates, legally effective execution and certified electronic-signature provider.
- Indonesian tax/e-invoicing requirements, tax calculation/rounding, invoice numbering, withholding, and any regulatory reporting obligations.
- Accounting policy, revenue recognition, cost capitalization, work-in-progress and exchange-rate policy. Project P&L must not be represented as statutory accounting without an approved accounting model.
- Payment gateway/provider, accounting integration, WhatsApp provider, object-storage provider, document-rendering engine and external API/webhook policy. Transactional email uses the owner's existing SMTP baseline; exact connection/sender configuration remains a deployment input in ADR-0001.
- Whether procurement/vendor management is a complete module or a project-cost-control capability.
- Whether FlowlessHub includes full HRMS or only delivery resource, assignment, availability and time-capture capabilities.
- Language/localization policy, retention schedules, archival/deletion policy and data-export/erasure policy.
- Formal product SLO values, capacity targets, service tiers and customer support commitments.

Record each decision in a versioned ADR or product policy with owner, rationale, scope, migration impact and review trigger. Until then, use explicit placeholders/interfaces and do not claim a provider or legal/accounting decision has been made.

## 7. Product acceptance principle

A release is acceptable only when the slice completes the promised user outcome using persisted data and proves its domain invariants, authorization, tenant isolation, concurrency behavior, failure recovery, audit evidence, observability and production-operating procedure. A visually complete screen, a green build, a successful deployment, or a pilot demonstration alone is not product acceptance.

## 8. Identity and authentication baseline — owner-approved 14 November 2026

FlowlessHub will provide an internally managed Identity authority for workforce users and future first-party application clients. Authentication and authorization remain separate: Identity proves the human account and issues an authenticated session; Tenant Access and the owning business modules decide which organization, customer, vendor, project, package, document, and action that identity may access.

The approved target is:

- **Passwordless primary authentication:** WebAuthn/FIDO2 passkeys. Require WebAuthn user verification (`userVerification=required`) for registration and authentication. Support multiple authenticators, including platform passkeys and roaming FIDO2 security keys. Validate challenge freshness and one-time use, ceremony type, RP ID, exact allowed origin, credential ownership, signatures, and authenticator evidence on the server.
- **MFA assurance:** Do not label every passkey or every successful WebAuthn assertion as equivalent MFA. Record whether local user verification/activation was performed and the authenticator properties needed to classify the event. A policy that requires MFA must reject an assertion that can only be classified as single-factor. Role-to-assurance requirements are enforced with the S1.3 authorization model; no NIST AAL or regulatory certification is claimed without a separate conformance assessment.
- **First-party SSO:** The internal Identity authority exposes OpenID Connect. First-party web applications use Authorization Code Flow with PKCE `S256`, exact registered redirect URIs, transaction-specific `state` and `nonce`, issuer/audience validation, short-lived single-use authorization codes, and narrowly scoped clients. The Next.js application uses a same-origin BFF; bearer/access/refresh tokens remain server-side.
- **Session boundary:** Preserve S1.1 global identities and revocable opaque server-side sessions. Keep the Identity authority session and each BFF application's host-only browser session distinct. Cookies use `__Host-` semantics (`Secure`, `HttpOnly`, `Path=/`, no `Domain`) in production. Never put tokens in browser-readable storage, URLs, HTML, client-side state, or logs. Revocation must propagate to application sessions.
- **SMTP and transactional email:** Use the owner's existing domain SMTP through a replaceable server-side adapter for email-address confirmation, security notifications, account recovery notifications, and later invitations. Delivery uses a durable outbox, idempotent retries, bounded timeouts, and observable failure/manual-repair states. SMTP credentials stay in protected runtime secrets, not source control or command output. Verify TLS and sender-domain SPF/DKIM/DMARC alignment before production delivery.
- **Email is not an authenticator:** No email OTP, email magic link, or mailbox possession as primary login, step-up MFA, or recovery proof. Email confirmation codes may establish address control; email may notify a user of a recovery/security event. Recovery uses separately protected one-time recovery codes and/or another enrolled authenticator plus a controlled recovery process.
- **Existing-account transition:** S1.1 password hashes and opaque sessions remain compatible during staged enrollment. Existing provisioned users authenticate through the accepted S1.1 path to enroll a passkey; the migration is additive and must not invalidate accepted production sessions. Password fallback is transitional only and is retired through an explicit measured rollout after enrollment coverage and recovery readiness are proven.
- **External actor separation:** A global human identity may later act as an organization member, customer contact, or vendor user through distinct relationships. Customer/vendor access is delegated and project-scoped; it does not create unrestricted membership in the service-provider tenant. One person participating in multiple business relationships does not merge their permissions or documents.

This is the first-party baseline. Customer-owned enterprise federation (OIDC/SAML), SCIM provisioning, cross-tenant account linking, and final external-role assurance matrices remain separate owner decisions and are not silently included in S1.2.

The normative design references are [W3C WebAuthn Level 3](https://www.w3.org/TR/webauthn-3/), [NIST SP 800-63B-4](https://pages.nist.gov/800-63-4/sp800-63b.html), and [IETF RFC 9700 — OAuth 2.0 Security Best Current Practice](https://www.rfc-editor.org/rfc/rfc9700.html). The detailed decision record is [`ADR-0001`](../architecture/ADR-0001-passwordless-identity-and-first-party-oidc.md).

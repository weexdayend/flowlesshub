# Product Blueprint: IT Services PSA Platform (Working Name: ServicePilot)

*Audience: AI agents, engineers, designers and analysts who will design, build, test or document this product. Written in English. Source of intent: the founder of an Indonesian IT services company (software house / system integrator). Treat this document as the single source of truth for product scope; where it is ambiguous, see Section 20 (Open Questions) and ask before assuming.*

## 1. Purpose of This Document

This document describes **what** the product is, **who** it serves, **how** its core workflows behave, and **in what order** it should be built. It is intended to let any agent (planner, coder, QA, UX, docs, data-modeling) understand the product without further briefing. It is not a final technical design; it defines domain concepts, rules, states and constraints that designs must respect.

Conventions used below:

- **MUST / SHOULD / MAY** follow RFC 2119 meaning.
- `code_style` names are suggested entity or field names, not mandatory.
- Indonesian business terms are kept in parentheses where they matter (RAB, BAST, SPK, termin, retensi), because the target market uses them in real documents.

## 2. Product Vision and Positioning

**One-line vision:** A single workspace where a project-based service company runs the entire commercial and delivery lifecycle: from lead and budget (RAB), through client approval, contract, execution with vendors and internal teams, to handover (BAST), invoicing, profit and loss, and post-delivery IT service management.

**Category:** Professional Services Automation (PSA) with light ERP, plus embedded ITSM and HRMS modules. Comparable products: Kantata, Accelo, Scoro, Zoho One, Odoo Project.

**Differentiation versus ClickUp / Asana / Jira:** those tools are strong at tasks but weak at money and legal flow. This product treats **budget, contract, payment terms, handover documents and profitability** as first-class citizens tied directly to project execution.

**Go-to-market path:**

1. Phase 1: used internally by the founder's company (dogfooding).
2. Phase 2: sold as multi-tenant SaaS to other project-based service companies, first in Indonesia (IT infrastructure, CCTV, network, security, software house, and adjacent trades such as MEP or telecom contractors).

## 3. Business Context

The founding company delivers, among others:

- IT infrastructure build-outs
- CCTV network deployments
- Network and cyber security services
- Structured cabling and networking
- In-house custom software development
- Post-delivery maintenance and support

Typical engagement shape: many clients, projects ranging from small (days) to large (many months or years) with multiple vendors, subcontractors and third parties. Every project follows a document-heavy path: **RAB to approval to contract (SPK) to timetable to progress monitoring to BAST to invoice**.

## 4. Target Users and Actors

### 4.1 Internal actors

| Actor | Primary concerns |
| --- | --- |
| Owner / Director | Approvals, margin, portfolio health, cashflow |
| Project Manager (PM) | Planning, team, vendors, progress, change requests |
| Presales / Estimator | Leads, surveys, RAB, quotations |
| Engineer / Technician | Tasks, field reports, evidence upload, timesheet |
| Finance | Invoices, payments, vendor bills, tax, margin actuals |
| Legal / Admin | Contracts, documents, numbering, e-sign |
| HR | Employees, attendance, leave, capacity |
| Support Agent | Tickets, SLA, assets |

### 4.2 External actors

| Actor | Access model |
| --- | --- |
| Client (PIC, approver, finance contact) | Client Portal: sees only client-visible items of their own projects |
| Vendor / Subcontractor | Vendor Portal: sees only tasks, POs, documents assigned to them |
| Third party (consultant, auditor, inspector) | Time-boxed, scoped guest access |

## 5. Core Design Principles

1. **Money and legal are first-class.** Budget, payment terms, contract and handover are modeled as structured data, not attachments.
2. **Plan versus actual everywhere.** Every budget line, milestone and schedule item has a baseline and an actual.
3. **Visibility is explicit.** Every task, comment, document and budget view carries a visibility level: `internal`, `client`, `vendor`.
4. **Cost and margin are never exposed externally.** RAB has an internal view (cost, margin) and a client view (selling price only).
5. **State machines, not free-form status.** RAB, quotation, contract, project, milestone, invoice and change request each have enforced transitions.
6. **Everything auditable.** Approvals, price changes, document versions and permission changes are logged immutably.
7. **Multi-tenant from day one.** Every business table carries `tenant_id`; no later retrofit.
8. **Template-driven.** Sector templates (CCTV, network, software) generate project structure, checklists and documents.
9. **Integrate, do not replace, accounting.** Export or sync with Accurate, Jurnal, Zahir; do not build a full general ledger.

## 6. Glossary

| Term | Meaning |
| --- | --- |
| RAB (Rencana Anggaran Biaya) | Cost budget and selling-price breakdown (bill of quantities with costs and margin) |
| BoQ | Bill of quantities; line items in the RAB |
| HPP (Harga Pokok Penjualan) | Cost of goods/services sold; internal cost basis |
| SPK / Kontrak | Work order or contract binding scope, value, terms |
| Termin | Payment installment tied to a milestone or percentage |
| DP (Down Payment) | Advance payment, usually a percentage at contract signing |
| BAST (Berita Acara Serah Terima) | Handover certificate signed when work is delivered and accepted |
| UAT | User acceptance testing |
| Retensi | Retention: a percentage of contract value withheld until the warranty or maintenance period ends |
| Addendum | Formal contract amendment, usually from an approved change request |
| CR | Change request |
| PO / PR / RFQ | Purchase order / purchase request / request for quotation |
| SLA | Service level agreement |
| CMDB | Configuration management database of assets |
| P&L | Profit and loss per project |
| Tenant | One customer company of this SaaS |
| Workspace | The project container holding tasks, team, documents, budget and finance |
| Document Vault | The structured document store per client and per project |

## 7. Domain Model (Hierarchy)

```
Tenant
 ├── Client
 │    ├── Client Documents (NPWP, NIB, deeds, NDA, master agreements)
 │    ├── Contacts / Portal Users
 │    └── Project (workspace)
 │         ├── Commercial Profile (project duration type, contract type, payment scheme)
 │         ├── Budget (RAB versions) and Quotation
 │         ├── Contract (SPK) and Addenda
 │         ├── Payment Schedule (termin) and Invoices and Payments
 │         ├── Phases / Milestones
 │         │    └── Tasks > Subtasks > Checklists
 │         ├── Team (internal, vendor, client PIC) and Roles
 │         ├── Procurement (PR, RFQ, PO, goods receipt, vendor bills)
 │         ├── Change Requests, Risks, Issues
 │         ├── Document Vault (numbered folders)
 │         ├── UAT and BAST
 │         ├── Timesheets and Expenses
 │         └── Profitability (P&L)
 ├── Vendor / Subcontractor (master data)
 ├── Employee (HRMS)
 ├── Catalog (items, services, rate cards, templates)
 └── Asset / Service Contract / Ticket (ITSM)
```

## 8. Commercial Profile of a Project (Critical)

Every project MUST be classified at creation (and when the quotation is approved) by three independent dimensions. These drive scheduling, invoicing, reporting and automation.

### 8.1 Duration type

| Value | Definition | Impact |
| --- | --- | --- |
| `short_term` | Single delivery, typically under about 3 months | Simple milestones, usually one to three termin |
| `long_term` | Multi-phase, over about 3 months or multi-year | Phases, baseline reviews, periodic reporting, cashflow forecast, possible yearly addenda |
| `recurring` | Ongoing service (maintenance, managed service, retainer) | Recurring invoices, SLA, renewal reminders |

The threshold between short and long is tenant-configurable.

### 8.2 Contract type

| Value | Description | Billing basis |
| --- | --- | --- |
| `fixed_price` (lump sum) | One agreed price for defined scope | Termin by milestone or percentage |
| `unit_price` | Price per unit (per camera, per meter, per license) | Measured quantity delivered |
| `time_and_material` | Hours/days at rate card | Approved timesheets per period |
| `retainer_subscription` | Fixed fee per period for service | Recurring invoice |
| `hybrid` | Combination (for example fixed build plus monthly maintenance) | Multiple billing streams on one contract |

### 8.3 Payment scheme

The payment scheme generates the **payment schedule (termin)** automatically and links each termin to a trigger.

| Scheme code | Description | Example |
| --- | --- | --- |
| `upfront_full` | 100 percent paid at or before start | 100 percent on contract signing |
| `dp_then_final` | DP plus final payment after BAST | 50 percent DP, 50 percent after BAST |
| `dp_milestone_final` | DP, intermediate milestone payments, final after BAST | 30 / 40 / 30 |
| `progress_based` | Percentage of measured progress per period | Monthly progress claim (opname) |
| `full_after_bast` | Entire value paid after handover | 100 percent after BAST |
| `periodic_fixed` | Equal installments on dates | Monthly or quarterly |
| `time_material_periodic` | Invoice approved hours each period | Monthly timesheet billing |
| `custom` | Free-form termin table | Any mix |

**Termin triggers** (each termin has exactly one): `on_contract_signed`, `on_milestone_completed(milestone_id)`, `on_progress_percent(x)`, `on_uat_passed`, `on_bast_signed`, `on_date(date)`, `on_period_end`, `manual`.

**Additional payment parameters:** currency, payment due days (net 14/30/45), retention percentage and release condition (after warranty end or maintenance period), late-payment reminder rules, whether tax is added on top or included.

**Validation rules:**

- Sum of termin percentages MUST equal 100 percent of contract value (retention counted as a withheld termin).
- A termin tied to a milestone MUST reference an existing milestone; deleting the milestone is blocked.
- Changing the payment scheme after contract signing MUST go through an addendum.

## 9. Roles, Permissions and Visibility

- **RBAC with project-scoped roles.** A user can be PM on one project and viewer on another. Permissions are `resource:action` (for example `budget:view_cost`, `invoice:issue`).
- **Visibility flag** on tasks, comments, documents, milestones and budget views: `internal`, `client`, `vendor`, or a specific list of parties.
- **Hard rules:**
  - Cost (HPP), margin and vendor pricing MUST NOT be returned by any client or vendor API/view, even if the field is requested.
  - Vendors see only entities assigned to them.
  - Clients see only their own client's projects and only `client`-visible items.
  - Guest/third-party access MUST expire.
- **Approval authority matrix** is configurable per tenant (for example margin below threshold requires Director; value above threshold requires two approvers).

## 10. End-to-End Workflow

Each stage lists steps, system behavior and state transitions.

### Stage A: Lead to Budget (RAB)

1. **Lead** captured in CRM (source, sector, need, contact, estimated value).
2. **Survey / requirement capture** using a sector-specific form template (CCTV: camera points, cable distances, mounting; network: devices, racks, bandwidth; software: features, integrations, users).
3. **RAB creation**: line items from catalog or ad hoc; each line has category (material, labor, license, vendor service, travel, overhead, contingency), quantity, unit, **unit cost (HPP)**, **margin or markup**, and **selling price**. Totals, tax and margin computed automatically.
4. **Versioning**: each edit after submission creates a new version (v1, v2, ...). Prior versions are immutable.
5. **Internal approval** via approval matrix.
6. **Quotation generation**: client-facing document from template (selling prices only), with auto-numbering.

**RAB states:** `draft > internal_review > internal_approved > sent_to_client > revision_requested | accepted | rejected | expired`.

### Stage B: Client Approval to Contract

7. Client opens quotation in the **Client Portal**, comments per line item, requests revision or accepts.
8. **Acceptance** is recorded with user, timestamp, IP and RAB version (this becomes evidence).
9. **Commercial profile finalized**: duration type, contract type, payment scheme, termin table, retention, warranty.
10. **Contract / SPK generation** from template, pulling scope, value, termin, duration, warranty, penalties. NDA and other legal docs generated as needed.
11. **Signature**: e-sign integration or upload of signed scan. On signature the project becomes active and the **approved RAB version becomes the budget baseline**.

**Contract states:** `draft > legal_review > sent > signed > active > completed | terminated | expired`.

### Stage C: Planning

12. **Project creation from sector template** (phases such as Survey, Procurement, Installation, Configuration, Testing, UAT, BAST).
13. **WBS and schedule**: tasks, dependencies (FS/SS/FF/SF), durations, Gantt, milestones. Milestones link to termin and deliverables.
14. **Team assignment** with capacity check against HRMS (leave, allocation).
15. **Invite** client PIC and vendors with scoped roles.
16. **Baseline lock** of schedule and budget; later changes are tracked as variance.

**Project states:** `planning > active > on_hold > uat > handover > closed | cancelled`.

### Stage D: Execution

- **Tasks:** `todo > in_progress > review > done`, plus `blocked` and `waiting_client`. Time in `waiting_client` is tracked separately so client-caused delay is evidenced and does not count against the team.
- **Procurement:** budget line to PR, RFQ to multiple vendors, comparison, approval, PO, goods/service receipt, vendor bill, payment. Every PO and vendor bill is linked to a budget line and project.
- **Vendor execution:** vendor updates progress and uploads evidence (photos, reports); internal verifier accepts or rejects.
- **Change Requests:** `draft > impact_assessed > client_approval > approved | rejected`. An approved CR updates budget, schedule and payment terms and produces an addendum document. Work outside approved scope MUST NOT be billable without a CR.
- **Progress measurement:** percent complete derived from weighted milestones and tasks; client sees client-visible progress only.
- **Reports:** weekly or monthly progress report auto-generated as PDF.
- **Risks and issues** log with owner, severity, mitigation.
- **Timesheets and expenses** feed actual cost.

### Stage E: Closing and Handover

17. **UAT / commissioning checklist** (sector template); client signs off item by item.
18. **BAST generation** from contract, delivered items and UAT results.

- Preconditions: all mandatory tasks done, UAT passed, no open critical issues, mandatory documents present.

19. **BAST signature** (e-sign or upload). State `bast_signed` triggers termin with trigger `on_bast_signed`.
20. **Final invoice** auto-drafted; retention held if configured.
21. **Closing:** lock project, compute final P&L, run retrospective, archive vault, register assets into ITSM.

### Stage F: After Project (ITSM and Recurring)

22. Installed items become **assets** (serial, location, warranty end, owner client).
23. **Warranty and maintenance contracts** run with SLA; client creates tickets in portal; escalation by SLA timers.
24. **Recurring invoices** for maintenance or subscription; **retention release** invoice when warranty ends.

## 11. Financial Model, Plan vs Actual and P&L

### 11.1 Concepts

- **Planned (baseline):** from the approved RAB version: planned revenue, planned cost by category, planned margin.
- **Committed:** open POs and approved vendor commitments.
- **Actual:** posted vendor bills, expenses, labor cost from timesheets (hours times cost rate), plus invoiced and paid revenue.
- **Forecast (EAC):** actual plus remaining estimate.

### 11.2 Formulas

- `planned_gross_margin = planned_revenue - planned_cost`
- `planned_margin_pct = planned_gross_margin / planned_revenue`
- `actual_cost = vendor_bills + expenses + labor_cost + other_direct_costs`
- `actual_revenue = sum(invoiced, net of tax)` (also report `collected = sum(payments)`)
- `actual_gross_margin = actual_revenue - actual_cost`
- `cost_variance(line) = planned_cost(line) - actual_cost(line)` (negative means over budget)
- `forecast_margin = contract_value (incl. approved addenda) - EAC`
- `utilization = billable_hours / available_hours` (HRMS)

### 11.3 Reports per project and portfolio

Budget vs actual by category and line; P&L per project, client, sector and PM; cashflow forecast from termin and vendor payables; invoice aging; margin erosion alerts; retention balance; utilization.

### 11.4 Invoicing

- Invoices are generated from termin (fixed/progress), from approved timesheets (T&M) or on schedule (recurring).
- Tax handling MUST be **configurable per tenant**: VAT (PPN) rate, withholding (PPh 23 or construction-services final tax as applicable), tax invoice number (faktur pajak), electronic stamp duty (e-meterai) thresholds. Do not hardcode rates.
- Invoice states: `draft > issued > partially_paid > paid | overdue | void`. Issued invoices are immutable; corrections via credit note.
- Vendor bills (payables) link to PO and project cost.
- Accounting: export or sync to Accurate, Jurnal, Zahir. No full general ledger in scope.

## 12. Module Specifications

| Module | Key capabilities |
| --- | --- |
| CRM / Presales | Leads, pipeline, survey templates, quotation tracking |
| Estimator (RAB) | Catalog, BoQ, cost and margin, versioning, internal vs client view, approval |
| Project Management | WBS, tasks, subtasks, Gantt, board, dependencies, milestones, baseline, templates |
| Collaboration | Comments, mentions, notifications, activity feed, per-item visibility |
| Procurement and Vendor | PR, RFQ, comparison, PO, receipt, vendor bills, vendor scorecard |
| Document and Contract | Vault, versioning, templates with variables, numbering, e-sign, expiry reminders |
| Finance | Payment schedule, invoices, payments, taxes, payables, P&L |
| Client Portal | Progress, approvals, documents, invoices, tickets, UAT sign-off |
| Vendor Portal | Assigned tasks, PO, deliverable upload, bill status |
| HRMS | Employees, attendance, leave, timesheet, skills, cost rate, capacity planning |
| ITSM | Tickets, SLA, assets/CMDB, maintenance contracts, knowledge base |
| Reporting | Dashboards, exports, scheduled reports |
| Admin | Tenants, roles, templates, custom fields, integrations, audit log |

## 13. Document Management Requirements

- **Client-level documents** (NPWP, NIB, deeds, NDA, master agreements) stored once at client level and referenced by all projects.
- **Project vault** auto-created with numbered folders: `01 Quotation, 02 Contract, 03 Technical, 04 Reports, 05 UAT, 06 BAST, 07 Invoices, 08 Vendor Docs, 09 Correspondence`. Folder set is template-driven.
- **Versioning**, checksum, uploader, timestamp, and per-document visibility.
- **Template engine** with variables such as `{{client.name}}`, `{{contract.value}}`, `{{payment.termin_table}}`, output to DOCX and PDF.
- **Auto-numbering** with configurable pattern, for example `{seq}/SPK/{roman_month}/{year}`; numbers are unique per tenant and never reused.
- **Expiry tracking:** contracts, warranties, licenses, certificates; reminders at 60/30/7 days.
- **Storage:** object storage (S3-compatible); database stores metadata only.

## 14. Automation Rules (Examples the Engine Must Support)

A rule engine with trigger, condition, action, configurable per tenant.

- Milestone `done` and termin trigger matches: draft invoice and notify Finance.
- `bast_signed`: issue final invoice, start warranty clock, register assets, notify client.
- RAB margin below threshold: require Director approval before sending.
- Task in `waiting_client` over N days: remind client PIC and log delay evidence.
- Invoice overdue: staged reminders (T+1, T+7, T+14) and notify PM.
- Contract, warranty or license expiring: notify at 60/30/7 days.
- Actual cost exceeds 90 percent of budget line: alert PM and Finance.
- BAST generation blocked until UAT checklist complete.
- Change request approved: update budget, schedule, payment schedule, create addendum draft.

## 15. Technical Requirements and Constraints

- **Multi-tenancy:** shared schema with `tenant_id` on every business table plus row-level security, or an equivalent isolation strategy; tenant-scoped storage prefixes and encryption keys where feasible.
- **Architecture:** modular monolith first, with clear module boundaries so modules can be separated later.
- **State machines** implemented centrally; transitions validated server-side and logged.
- **Audit log:** append-only for approvals, price/budget changes, document access and permission changes.
- **API-first:** REST or GraphQL with OpenAPI; webhooks for key events; API keys per tenant.
- **Customization:** custom fields, templates and workflows per tenant without code changes.
- **Notifications:** in-app, email, WhatsApp (important in Indonesia) via pluggable providers.
- **Localization:** Bahasa Indonesia and English; IDR default, multi-currency capable; Asia/Jakarta default timezone; Indonesian document formats.
- **Security:** SSO option, 2FA, encryption at rest and in transit, least-privilege defaults, signed URLs for files, data-export and deletion tools for tenants.
- **Compliance awareness:** Indonesian personal data protection law (UU PDP); legally recognized e-signature providers where required.
- **Offline-tolerant field use:** mobile web or app for technicians (photo evidence, checklists, timesheets) with sync.
- **Performance:** Gantt and board views must stay responsive with thousands of tasks per project.

## 16. Key Entities (Starter Data Model)

`Tenant, User, Role, Permission, Client, Contact, Vendor, Employee, Lead, Survey, CatalogItem, Rab, RabVersion, RabLine, Quotation, Contract, ContractAddendum, CommercialProfile, PaymentSchedule, Termin, Invoice, InvoiceLine, Payment, CreditNote, Project, Phase, Milestone, Task, Checklist, DependencyLink, TeamMember, PurchaseRequest, Rfq, PurchaseOrder, GoodsReceipt, VendorBill, ChangeRequest, Risk, Issue, UatChecklist, UatItem, Bast, Document, DocumentVersion, DocumentTemplate, NumberSequence, Timesheet, Expense, Attendance, LeaveRequest, Asset, ServiceContract, Ticket, SlaPolicy, AutomationRule, ApprovalRequest, ApprovalMatrix, AuditLog, Notification.`

Every entity carries: `id`, `tenant_id`, `created_at`, `created_by`, `updated_at`, `version` (where mutable), and `visibility` (where shown externally).

## 17. Phased Roadmap

| Phase | Scope | Exit criterion |
| --- | --- | --- |
| 1 MVP (internal use) | Clients, projects, commercial profile and payment schemes, RAB with versions, quotation, approval, contract generation, tasks and timeline, document vault, UAT, BAST, invoices from termin, basic client portal, project P&L | One real project runs RAB to BAST to invoice entirely in the system |
| 2 | Vendor portal, procurement (PR/RFQ/PO/bills), change requests and addenda, timesheets, plan-vs-actual reporting, automation rules | Large multi-vendor project managed end to end |
| 3 | HRMS: attendance, leave, capacity, cost rates | Resource planning drives staffing |
| 4 | ITSM: tickets, SLA, assets, maintenance contracts, recurring invoices, retention release | Post-delivery revenue managed |
| 5 | SaaS readiness: tenant onboarding, subscription billing, template marketplace, public API, accounting integrations | First external tenant live |

Phase 1 is the strategic core. HRMS and ITSM are each product-sized; do not build them in parallel with the core.

## 18. Success Metrics

- Time from approved RAB to generated contract.
- Percentage of projects with plan-vs-actual margin visible in real time.
- Days sales outstanding (DSO) reduction.
- Percentage of BAST generated and signed in-system.
- Margin leakage caught by alerts.
- Client portal weekly active usage.

## 19. Out of Scope (Initial)

- Full double-entry accounting and general ledger.
- Payroll calculation and statutory payroll tax (HRMS limited to attendance, leave, timesheet, cost rate).
- Tax filing submission.
- Building a custom e-signature authority (integrate providers instead).
- Hardware monitoring or network management tooling (ITSM covers tickets and assets only).

## 20. Assumptions and Open Questions

**Assumptions made:** ITSM means IT Service Management; first users are the founder's company; Indonesian legal and tax context; web-first delivery.

**Open questions to resolve before detailed design:**

1. Which e-sign provider(s) and which accounting package come first?
2. Preferred tech stack and hosting region (Indonesia data residency needed?).
3. Are government or tender-style projects (with formal retention, guarantees, bank guarantees) in scope early?
4. Should unit-price and progress-claim (opname) billing be in MVP or Phase 2?
5. How are cost rates for internal staff defined (per person, per role)?
6. Is WhatsApp notification required in MVP?
7. Branding, product name and pricing model for the SaaS.

## 21. Instructions for Agents Consuming This Document

1. Treat Sections 8, 9, 10 and 11 as the **non-negotiable domain rules**.
2. When generating code, never expose cost, margin or vendor pricing in any client- or vendor-facing response.
3. Implement every status listed as a validated state machine; reject illegal transitions.
4. Always include `tenant_id` in schema, queries, caches, file paths and logs.
5. Prefer configuration (templates, rules, custom fields) over hardcoded sector or tax logic.
6. When a requirement is ambiguous, list the assumption explicitly and surface it as an open question rather than silently choosing.
7. Keep outputs consistent with the glossary terms in Section 6.

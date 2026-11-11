# FlowlessHub Agent Working Agreement

## Read order

1. `documents/Product Blueprint IT Services PSA Platform (Working Name ServicePilot).md`.
2. `documents/Technical Architecture and Delivery Plan IT Services PSA Platform.md`.
3. This file and the current sprint block in `CHECKPOINTS.md`.
4. For frontend work, also read `apps/web/AGENTS.md` and the relevant versioned Next.js guide under `node_modules/next/dist/docs/` before changing framework APIs or conventions.

## Source-of-truth hierarchy

- Product Blueprint wins on domain behavior, product scope, terminology and business invariants.
- Technical Architecture wins on technology and architecture.
- `CHECKPOINTS.md` controls sprint order and completion state.
- Do not silently reconcile conflicts or open questions. Record the uncertainty in the slice spec and surface it to the owner.

## Delivery rules

- Work only on the current sprint; do not start the next sprint until the prior exit gate is verified.
- Write a concise slice spec before implementation: entities, state transitions, endpoints, permissions, emitted events, migration and tests.
- Deliver vertical slices. A backend-only stub or frontend-only screen is not a completed business capability.
- Never tick a checkpoint until its Global Definition of Done is satisfied and evidence is available.
- Prefer small, reviewable changes. Preserve existing behavior unless the approved slice explicitly changes it.

## Architecture rules

- Backend is a modular monolith with `api` and `worker` entry points.
- A module owns its tables, SQL, domain, service and HTTP handlers. Modules communicate through service interfaces and domain events, never by querying another module's tables.
- OpenAPI 3.1 in `api/openapi.yaml` is the API contract. Generate Go stubs and TypeScript types; never hand-edit generated output.
- PostgreSQL is the source of truth. Every business table must be tenant-scoped and protected by RLS. Never use a superuser application role or bypass RLS.
- Use expand/migrate/switch/contract for schema changes. New indexes must be created concurrently when supported.
- Use decimal arithmetic and PostgreSQL `NUMERIC` for money. Floats are forbidden for money.
- Use the transactional outbox for domain events and idempotency for mutating financial/document endpoints.
- Keep feature flags around incomplete capabilities; deploy dark until the exit gate passes.

## Security and privacy invariants

- Cost (HPP), margin and vendor pricing must never be returned by client or vendor DTOs, queries or endpoints.
- Client and vendor portals require separate DTOs and scoped queries; hiding fields in the UI is insufficient.
- Include `tenant_id` in tenant queries, cache keys, object-storage paths and structured logs.
- Approval, financial changes, permissions and document lifecycle events require append-only audit evidence.
- Do not commit secrets, credentials, private keys or real customer data.
- Do not claim ML-DSA attestations are legally binding electronic signatures. Contract/BAST signing must use an accepted provider or signed-scan evidence path.

## Definition of Done

- Migration is expand/contract and lint-clean, with bounded `lock_timeout` and `statement_timeout`.
- SQL is in `.sql` files and sqlc output is regenerated and committed.
- Every new tenant table has RLS; authorization and cross-tenant isolation tests pass.
- State-machine legal and illegal transitions are tested.
- Audit events are emitted for approvals, money, permissions and documents.
- Client/vendor contracts expose no forbidden cost or margin fields.
- OpenAPI and generated TypeScript client are synchronized; breaking API changes are reviewed.
- Bahasa Indonesia and English strings are externalized; accessibility and reduced-motion requirements pass.
- Feature flag, staging validation, production deployment and zero-downtime compatibility are demonstrated.
- Documentation, ADR/slice spec and checkpoint evidence are updated.

## Never

- Never use floats for money, bypass RLS, query another module's tables, hand-edit generated code, commit secrets, or merge failing checks.
- Never claim a sprint exit gate or production readiness based on local compilation alone.

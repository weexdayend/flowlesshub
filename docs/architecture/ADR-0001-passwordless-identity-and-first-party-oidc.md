# ADR-0001 — Passwordless Identity and First-Party OIDC SSO

**Status:** ACCEPTED — owner-directed architecture baseline, 14 November 2026; implementation not started.
**Decision owner:** FlowlessHub product owner.
**Applies to:** S1.2 identity UX, authentication, first-party SSO, SMTP transactional email and account recovery.
**Repository baseline:** `92aec75c6387d6f57a1dc0d71c5ab7431f5831cd`.
**Related records:** [S1.2 slice](../slices/S1.2-authenticated-web-entry-session-ux.md), [product strategy](../product/PRODUCT-STRATEGY.md), [domain architecture](DOMAIN-MODULE-ARCHITECTURE.md), [production roadmap](../roadmap/PRODUCTION-GRADE-PSA-ROADMAP.md).

## 1. Context

S1.1 delivered and the owner accepted the Go Identity backend/API foundation: global users, Argon2id password hashes, opaque revocable sessions, authentication events, organization memberships and first-owner bootstrap. Browser sign-in/session UX was explicitly deferred. The accepted implementation/release SHA remains `495383f38ec7c356b97bb66017b66a3380130eaf`; this ADR does not reopen or rewrite S1.1.

Before the first browser login, client/vendor application or external access surface is built, FlowlessHub needs one durable authentication model. The owner has an existing SMTP email domain and wants passwordless MFA and single sign-on. The design must avoid creating separate identities/sessions for workforce, customer contacts and vendor users, while ensuring that authentication never grants tenant or project authorization by itself.

## 2. Decision summary

1. **Internally managed Identity authority.** Keep identity ownership, credential verification, session issuance/revocation and the first-party OIDC issuer within FlowlessHub's Go modular monolith. Do not add an external identity SaaS as a required runtime dependency for first-party login.
2. **Passkey-first passwordless authentication.** WebAuthn/FIDO2 passkeys are the primary authentication method. Require user verification for every registration and authentication ceremony. Support multiple credentials per identity, including platform passkeys and roaming FIDO2 security keys.
3. **Evidence-based MFA assurance.** Record whether local user verification/activation occurred and the authenticator properties needed to classify an authentication event. Never assume every passkey has the same assurance. A policy requiring MFA must reject an event classified as single-factor. S1.3 binds assurance requirements to privileged roles and permissions.
4. **First-party OIDC SSO.** Use OpenID Connect Authorization Code Flow with PKCE `S256` for every first-party browser client. Each app/portal gets its own registered client, exact redirect URI, audience, scopes and session policy.
5. **Same-origin Next.js BFF.** The web app uses a BFF for route protection and server-side API calls. Identity-provider sessions and BFF application sessions are distinct, host-only and revocable. Tokens remain server-side.
6. **Owner SMTP for transactional email.** Use the existing SMTP service through a server-side, replaceable adapter and durable outbox. Email confirms an address and carries notifications; email OTP/magic links are not authentication or MFA factors.
7. **Additive migration.** Preserve the S1.1 credential/session contract during rollout. Enroll existing accounts through an authenticated S1.1 session. Do not remove passwords or mass-revoke sessions until migration, recovery, support and rollback criteria are proven and explicitly approved.
8. **Authentication is not authorization.** Global identity, organization membership, customer relationship and vendor relationship remain separate. Customer/vendor privileges are delegated and scoped in later authorization slices.

## 3. Identity and application topology

### 3.1 Authority and clients

- The Go Identity module remains the source of truth for the global human identity and the authentication lifecycle.
- The internal OIDC issuer is hosted by the FlowlessHub API origin. The currently configured API origin is `https://api.flowlesshub.com`; any origin change requires a reviewed config/edge change and cannot silently invalidate existing credentials or tokens.
- The first-party web application is the BFF/OIDC client at `https://app.flowlesshub.com`.
- Later client and vendor applications must register as separate first-party OIDC clients. They redirect to the central sign-in surface and return only to exact registered callback URLs. A person may authenticate once and then be authorized into distinct business contexts, but those contexts do not merge.
- External enterprise federation to customer-owned OIDC/SAML providers, SCIM, JIT provisioning and cross-tenant identity linking are not part of this ADR's first-party implementation scope. They require separate decisions.

### 3.2 WebAuthn ceremony origin and RP ID

- The browser ceremony is performed only by the approved first-party sign-in surface on `https://app.flowlesshub.com`.
- The intended initial WebAuthn RP ID is `app.flowlesshub.com`, not the parent `flowlesshub.com`. Exact production origin and RP ID values must be frozen in validated configuration and acceptance tests before the first passkey is registered.
- Do not wildcard origins or accept sibling subdomains. Future portals use the central sign-in surface; they do not automatically become additional WebAuthn origins.
- Local development uses a distinct, explicit development configuration and test RP ID. Production RP IDs/origins are never inferred from the incoming `Host`, `Origin`, forwarded headers or arbitrary tenant configuration.

### 3.3 Browser and server sessions

- Preserve the existing S1.1 API-host-only Identity session cookie and opaque database-backed revocation model as the identity authority session.
- The Next.js BFF issues a separate opaque application-session handle in a host-only `__Host-` cookie on the app origin. The backing record is server-side and binds user, Identity session, OIDC client, creation/expiry, rotation and revocation state.
- Production cookies are `Secure`, `HttpOnly`, `Path=/`, have no `Domain` attribute, and use an explicitly reviewed `SameSite` value. `__Host-` requirements are mandatory. Development uses a separate cookie name/configuration.
- The BFF stores any access/refresh/session tokens and OIDC client credentials server-side. The browser never receives them in JSON, HTML, URLs, local/session storage, client state or logs.
- The authorization endpoint may be exposed through a same-origin BFF front-channel route while the OIDC issuer remains `https://api.flowlesshub.com`; its exact metadata and proxy/handoff contract must be settled and tested in S1.2-A. Do not expose an API-host-only Identity cookie to the browser merely to make the OIDC redirect work.
- A BFF cookie never substitutes for API authorization. Every API request revalidates the central session, organization membership and resource permission. Logout/revocation invalidates the central Identity session and all bound BFF sessions.
- The browser cannot send the app-host BFF cookie to the API host. Never redirect the browser to an API-host authorization endpoint on the assumption that the API-host Identity cookie is present, and never widen cookie scope to make that work. S1.2-A must define and test a standards-conformant front-channel handoff: the preferred candidate is an app-origin BFF authorization route that binds the browser's app session and OIDC transaction to the central Identity session server-to-server; an alternative is allowed only with an explicit threat analysis and interoperability proof. Discovery metadata, issuer identifier, authorization endpoint, callback origins, and the server-side handoff must agree exactly. The issuer must not trust user, organization, client or redirect claims supplied by the browser.

## 4. Passwordless and MFA design

### 4.1 Passkey registration and authentication

- Use a maintained, security-reviewed WebAuthn server library compatible with the pinned Go toolchain. Do not implement protocol cryptography or authenticator verification from scratch.
- Registration and authentication set `userVerification=required`. Reject authenticator responses that do not demonstrate required user verification.
- The server validates fresh cryptographically random challenges, strict TTL, purpose/user/session binding, atomic single use, ceremony type, exact origin, RP ID hash, credential ID/public-key binding, signature and required authenticator flags. Persist the credential backup eligibility (`BE`) and latest backup state (`BS`) flags from authenticator data: `BE` is fixed at registration, `BS` may change, and the invalid `BE=0, BS=1` combination is rejected. Compare the current `BE` value with the stored registration value on assertions.
- Store credential ID, public key, user binding, creation/last-used/revocation times, display label and only the authenticator metadata needed for security policy. Never store a private key or biometric data. Attestation is minimized; enterprise/device attestation remains disabled unless a privacy/security decision explicitly requires it.
- Support multiple passkeys per human identity and at least one roaming FIDO2 security-key option. Credential removal/revocation requires recent reauthentication and an audit event; users must not be able to remove the final usable authenticator without completing a recovery/enrollment transition.

### 4.2 Assurance semantics

- A passkey provides public-key authentication with verifier-name binding when WebAuthn RP ID and origin validation are correct. This makes it phishing-resistant; phishing resistance and MFA are related but not identical labels.
- Record the WebAuthn user-verification result and authenticator evidence. If the applicable authenticator indicates that its activation factor was not used, classify that event as single-factor. Do not assign an MFA assurance label solely because the UI says “passkey”. The `BE` and `BS` backup flags describe credential backup characteristics; they are not evidence that user verification occurred or that an authentication event is multi-factor.
- The authorization layer must be able to require a named assurance level. S1.3 defines which privileged organization roles/actions require it and verifies that the event actually meets the requirement. No AAL2/AAL3 or regulatory certification is claimed by this ADR.
- Email, SMS, typed email OTP and magic-link possession are not phishing-resistant authenticators and are never accepted as MFA/step-up evidence.

### 4.3 Recovery

- Encourage enrollment of a second independent authenticator (another passkey or hardware security key) before the first is relied upon for privileged administration.
- Generate high-entropy, single-use recovery codes; show once, store only a salted/peppered verifier, rate-limit attempts, atomically consume, audit use and support explicit rotation/revocation.
- Loss-of-all-authenticators recovery requires a controlled process with independent identity verification, delay/risk checks where appropriate, separation of duties for privileged accounts, user notification and audit. Email may notify or confirm address control; mailbox access alone cannot reset a passwordless account or enroll a new authenticator.
- No SMS recovery factor is introduced by this baseline. TOTP fallback is not part of the initial S1.2 target; it requires a separate threat/assurance review if later requested.

## 5. OIDC SSO and token requirements

- Implement OpenID Connect on the OAuth 2.0 Authorization Code Flow with PKCE `S256` for all first-party browser clients, including confidential BFF clients.
- Require exact registered redirect URI matching, transaction-specific high-entropy `state`, `nonce`, issuer identification/mix-up defense, authorization-code single use and short expiry, PKCE verifier binding, and validation of token issuer, audience, signature, key ID, expiry/not-before and nonce.
- For each ID Token, require the exact configured `iss`, a valid signature under the configured asymmetric algorithm allowlist, a non-empty `sub`, and an `aud` containing that client’s registered `client_id`. Reject additional audiences unless each is explicitly trusted by that client. If `azp` is present, require it to equal `client_id`. Keep the normal first-party ID Token audience single-client; any multi-valued `aud` must be explicitly allowlisted and all additional audiences trusted by that client. Validate `exp`, `iat` with bounded clock skew, `nbf` when present, and the transaction’s exact `nonce`; when `max_age` is requested, validate `auth_time` against that request. Validate access tokens independently at each API resource server against its issuer, intended API audience, signature, lifetime and required scopes; an ID Token is not an API authorization credential.
- Publish issuer/discovery/JWKS metadata with reviewed asymmetric signing algorithms and key rotation. Reject unknown algorithms, `none`, incorrect issuer/audience and stale/invalid keys.
- Give each first-party app a distinct client ID, exact redirect URI list, audience, scopes and token/session policy. Do not use wildcard callback patterns or a common all-powerful audience for unrelated apps.
- Do not implement Implicit Flow, Resource Owner Password Credentials grant, password-based OIDC grant, open redirects, token-in-URL or browser-held bearer/refresh tokens.
- Access tokens are short-lived and audience-restricted. Refresh/session renewal is server-side, rotated/revocable and bounded by the central Identity session. API resource authorization remains independent of successful OIDC authentication.
- Use mature, maintained OIDC/OAuth libraries and validate behavior against the current security BCP. Do not build custom JWT signature or OIDC parsing/validation code. Use OpenID Connect Core 1.0 as the normative source for ID Token validation, in addition to OAuth 2.0 Security BCP.

## 6. SMTP and transactional email

- Reuse the SMTP service/domain already owned by the product owner. The host, port, TLS mode, authentication mechanism, sender address, rate limits and credential values are configuration inputs to be verified; this ADR does not invent them.
- Verify TLS certificate validation and sender-domain authentication: SPF, DKIM signing and DMARC alignment for the selected From domain. Review bounce/complaint handling and sending limits before production enablement.
- Use email for address confirmation, security notifications, recovery notifications and later membership/vendor/customer invitations. Delivery is asynchronous through a durable outbox and River worker with deduplication, bounded retries/backoff, delivery status, bounce/error handling and manual repair.
- Persist the event/outbox intent transactionally with the state change. A temporary SMTP outage must not undo a completed authentication, security or business transaction.
- Keep SMTP passwords/API credentials only in protected runtime secret storage with least privilege and rotation. Never commit, echo, expose in process arguments, paste into chat or include in logs/test snapshots.
- Email-address confirmation codes are not authenticators; no email OTP, magic link, inbox polling or email-based step-up is used for login/MFA/recovery proof.

## 7. S1.1 compatibility and migration

- Keep the S1.1 `identity.users`, Argon2id password hashes, `identity.sessions` and authentication-event semantics backward compatible while S1.2 rolls out.
- Passkey enrollment begins from a currently authenticated S1.1 user session or an equivalent independently verified owner bootstrap. Email confirmation alone does not permit attaching a passkey to an existing identity.
- Introduce credential/challenge/recovery/OIDC client/session data additively. Any nullable/constraint change requires expand/migrate/switch/contract, compatibility tests against the accepted release and explicit rollback.
- Existing password authentication remains available as a controlled migration bridge until passkey enrollment coverage, multiple-authenticator/recovery readiness, support runbooks and cutover telemetry are accepted. Its sunset is a separate owner-approved policy; do not silently disable users or force a mass reset.
- Existing S1.1 production session cookies remain accepted during migration. New BFF session cookies are separate and revocable. Session fixation, replay, token leakage and Blue/Green mixed-version behavior are release blockers.

## 8. Tenant, workforce, customer and vendor identity boundary

- `identity.users` is a global human identity, not a tenant membership or business counterparty.
- Workforce users receive organization memberships and permissions from Tenant Access.
- Customer contacts and vendor users are represented through explicit customer/vendor relationships and delegated portal grants in later business/authorization slices. They are not inserted as ordinary members of the service-provider tenant merely to make login work.
- Project/package/document access is explicit, time-bounded where appropriate, auditable, revocable and restricted by business relationship. A person with both customer and vendor roles must have separately selected/verified contexts; one relationship cannot authorize access to the other side's pricing, bids, documents or approvals.
- S1.2 ships no customer/vendor portal business workflow. S1.3 owns the role/permission matrix, external actor relationship model, tenant context, PostgreSQL non-owner role, RLS/FORCE RLS and PgBouncer isolation proof.

## 9. S1.2 implementation sequence and gates

1. **S1.2-A — Security architecture:** verify origin/RP ID/issuer config, OIDC clients/redirects/scopes, BFF session storage and cookie contract, CSRF/Origin controls, authenticator assurance, recovery and S1.1 transition threat model.
2. **S1.2-B — SMTP delivery:** owner supplies configuration out of band; verify TLS and DNS sender authentication; implement adapter, outbox, River delivery, retry/dedup/bounce state and redacted health/metrics.
3. **S1.2-C — WebAuthn:** add credential/challenge storage, passkey registration/authentication/removal, security-key support, `userVerification=required`, challenge replay prevention, cross-instance rate limits and browser interoperability/negative tests.
4. **S1.2-D — OIDC/BFF:** implement internal issuer/client registry, Authorization Code + PKCE, exact callback validation, discovery/JWKS/key rotation, server-side token exchange, BFF sessions, protected Next.js routes and revocation propagation.
5. **S1.2-E — Recovery and policy:** add recovery codes, second authenticator, safe support recovery, security notifications, assurance signals and step-up hooks.
6. **S1.2-F — Transition and acceptance:** preserve S1.1 accounts/sessions, test mixed-version Blue/Green overlap, browser/API negative cases, SMTP outage, abuse controls, rollback, exact-SHA CI and owner acceptance.

No code, database migration, SMTP secret, DNS change, production deploy, or credential enrollment is authorized by the documentation decision alone. Each phase follows the repository checkpoint workflow and its own reviewed patch/ADR where needed.

## 10. Consequences and deferred decisions

### Positive consequences

- One identity authority and one first-party SSO protocol can serve workforce, customer and vendor application clients without conflating their business permissions.
- Passkeys reduce password phishing exposure; explicit assurance tracking prevents weak MFA claims.
- SMTP is reused without turning email inbox control into an authentication factor.
- Additive migration preserves accepted S1.1 sessions and minimizes production identity disruption.

### Costs and constraints

- WebAuthn requires exact origin/RP ID governance; changing these after enrollment is costly and can require re-registration.
- OIDC issuer, BFF, client registry, signing-key rotation, token lifecycle, session revocation and recovery all require ongoing security operations.
- SMTP deliverability, sender-domain DNS and bounce handling are production responsibilities.
- First-party login surface and API origin remain separate trust boundaries and require browser integration tests.

### Explicitly deferred

- Customer-owned enterprise IdP federation (OIDC/SAML), SCIM and cross-tenant identity linking.
- Exact role-to-assurance matrix and vendor/customer delegated permission matrix (S1.3).
- SMTP host/port/sender/credentials and DNS changes until the owner supplies and verifies the existing service configuration.
- OIDC token/session TTL numeric values, signing-key storage provider, SMTP worker concurrency/retention values and final database table names until S1.2-A security/implementation design.
- TOTP, SMS, social login, email OTP/magic-link login, self-service public signup and consumer identity providers.

## 11. Normative references

- W3C, [Web Authentication: An API for accessing Public Key Credentials — Level 3](https://www.w3.org/TR/webauthn-3/), Recommendation, 25 August 2026.
- NIST, [SP 800-63B-4 — Authentication and Authenticator Management](https://pages.nist.gov/800-63-4/sp800-63b.html), July 2025.
- IETF, [RFC 9700 — Best Current Practice for OAuth 2.0 Security](https://www.rfc-editor.org/rfc/rfc9700.html), January 2025.
- OpenID Foundation, [OpenID Connect Core 1.0 incorporating errata set 2](https://openid.net/specs/openid-connect-core-1_0-errata2.html), 15 December 2023.

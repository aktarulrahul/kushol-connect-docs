# Identity & Access — Integration Tasks

**Module:** `03-identity-access` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `04-organization-hierarchy` | we call them | exported Go functions: hierarchy reads (placement validation, picker data) + `hierarchy.OnUserVerified(userID)` via the provisioning job | reads: degraded (cached hierarchy) · `OnUserVerified`: degraded (job retries, approval stays) |
| I-2 | `07-command-center-web`, `05-communication-engine`, `08/10/11+` | they call us | 07: REST via generated client (queue, roster) · api modules: in-process `auth.Authenticate` / `auth.RequireRole` / `auth.RequireVerified` | fatal for them (no route runs unauthenticated); our outages surface as their 401/503 |
| I-3 | api → app/web pushes | we notify | verification approved/rejected + SLA reminders delivered via 06; status changes force client re-auth/refresh | degraded, never fatal |
| I-4 | SMS gateway (external — SAS Bulk SMS) | outbound | HTTP GET (`SMS_GATEWAY_*` env; plain HTTP, 08-gaps G-9) | degraded — OTP queued with retry, `auth.smsDelayed` shown |
| I-5 | Google / GitHub OIDC (external) | outbound | HTTPS OIDC (`golang.org/x/oauth2` / `coreos/go-oidc`) | degraded — SSO button errors, phone OTP unaffected |

## 2. Exported Contract

```text
auth.Authenticate(r *http.Request) (Principal, error)
auth.RequireRole(roles ...Role) func(http.Handler) http.Handler
auth.RequireVerified() func(http.Handler) http.Handler
auth.CurrentUser(ctx context.Context) (Principal, error)
type Principal struct { UserID, Role, SchoolID, Status, Locale, Plan }   // Role incl. partner; SchoolID nil for super_admin/partner
sessions.InvalidateForUser(userID uuid.UUID) error
verification.EnqueueProvisioning(userID uuid.UUID)   // 01 job → hierarchy.OnUserVerified (owned by 04)
verification.PendingCount(ctx, schoolID uuid.UUID) (int, error)
users.GetWithSelection(ctx, userID uuid.UUID) (UserSelection{UserID, Role, Status, SchoolID, SectionID}, error)
users.UpsertRosterUser(ctx, schoolID uuid.UUID, in RosterUserInput{FullName, PhoneE164, Role, StudentCode?}) (RosterUserResult{UserID, Created bool}, error)
users.PlanOf(ctx, userID uuid.UUID) (Plan{Tier: free|pro, ExpiresAt?}, error)
users.SetPlan(ctx, actor Principal, userID uuid.UUID, tier string, expiresAt *time.Time) error
users.CreateVendorLogin(ctx, actor Principal, in VendorLoginInput{FullName, Email}) (userID uuid.UUID, err error)
guardians.LinkedStudents(ctx, guardianID uuid.UUID) ([]StudentRef{UserID, SchoolID, Relation}, error)
guardians.GuardiansOf(ctx, studentID uuid.UUID) ([]uuid.UUID, error)
guardians.IsGuardianOf(ctx, guardianID, studentID uuid.UUID) (bool, error)
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `auth.Authenticate` | every api module's router | `Principal` from access JWT (mobile) or session cookie (web) | `UNAUTHENTICATED` | single entry; no module parses tokens itself |
| `auth.RequireRole` | route builders in 04–14 | wrapped handler | `FORBIDDEN` | order after `Authenticate`; tenant scope read from `schoolId` claim |
| `auth.RequireVerified` | participatory routes (05/08/10/11) | wrapped handler | `NOT_VERIFIED` | DB-authoritative status, Redis 30 s cache (BR-001/BR-007) |
| `auth.CurrentUser` | services needing the actor | `Principal` | `UNAUTHENTICATED` | context-embedded by middleware |
| `sessions.InvalidateForUser` | suspend/reinstate paths here; future admin tooling | nil | — | kills sessions + refresh families + caches |
| `verification.EnqueueProvisioning` | approve flow | job id | `INTERNAL` | idempotent per user; retries `OnUserVerified` |
| `verification.PendingCount` | 07 School Admin dashboard | count of PENDING requests for the school | `FORBIDDEN` (cross-tenant) | tenant-scoped read |
| `users.GetWithSelection` | 04 `OnUserVerified` | status + registration-time `requested_section_id` | `NOT_FOUND` | read-only; 04 never guesses placement |
| `users.UpsertRosterUser` | 14 roster ingestion | user id + created flag | `VALIDATION_FAILED`, `CONFLICT` (phone owned by another school) | match on `phone_e164` within the school; creates PENDING users only — never auto-verifies (BR-001); audited `user.roster_upserted` |
| `users.PlanOf` / `users.SetPlan` | 08 quotas (read) · 07 Super Admin + 12 billing (write) | Kushol Pro tier | `FORBIDDEN` (SetPlan: super_admin or 12's system actor only) | expired `plan_expires_at` ⇒ free; audited `user.plan_changed` |
| `users.CreateVendorLogin` | 07 partner approval | new `partner` user id (email+password invite; password set via reset link) | `CONFLICT` (email exists), `FORBIDDEN` (non super_admin) | the only way a `partner` user is created; 07 stores the id in `vendor_accounts.portal_user_id` |
| `guardians.LinkedStudents` / `GuardiansOf` / `IsGuardianOf` | 12 fee entitlement · 05 guardian reach · 04 guardian enrollment · 14 roster | ACTIVE `guardian_links` only | — | tenant-scoped; never exposes other schools' links |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `hierarchy.GetCities/GetSchools/GetSections` (read; no class entity — class level is a section attribute) | 04 | degraded — 5-min stale cache; registration blocked with `validation.hierarchy.invalid` if placement can't be proven |
| `hierarchy.OnUserVerified(userID)` (write; hand-off target) | 04 (04 orchestrates enrollment, chat group joins, FCM topic subs) | provisioning job retries ×5 with backoff + alert; user stays VERIFIED |
| `hierarchy.CreateSchool` (write; owner 2026-10-02 ADR-2 — recorded in 04 `06` §1 I-8/§2) | school-request approve handler | approval provisions the institution before the POC admin is created; failure surfaces to the Super Admin, request stays PENDING |
| `audit.Append(event)` | 01 | audit write retried inline; approval never blocked by audit failure alone (logged + alerted) |
| `jobs.Enqueue / worker runtime` | 01 | job table is 01-owned; enqueue failure surfaces as `INTERNAL` |
| `notify.SendToUser(userID, payload)` (approved/rejected/reminder) | 06 | skipped + retried next SLA tick; never blocks the decision |

Sequencing note: 03 builds before 04, so all hierarchy calls sit behind a Go interface declared
here with an in-memory fake used by `IDT-IT-*` tests; the 04 spec binds the real implementation.

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| login / logout / logout-all | `auth:me`, `session:{hash}` (delete) |
| approve / reject | `verification:queue:{schoolId}`, `status:{userId}`, `auth:me` |
| suspend / reinstate | `status:{userId}`, `auth:me`, `school:users:{schoolId}` |
| `PATCH /me` (locale) | `auth:me` |

| Read | Tagged with |
| --- | --- |
| `GET /me` | `auth:me` (no-store) |
| `GET /verification-requests` | `verification:queue:{schoolId}` |
| `GET /school/users` | `school:users:{schoolId}` |
| session/status lookups (api-internal) | `session:{hash}` · `status:{userId}` (Redis, explicit invalidation) |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| SMS gateway (SAS Bulk SMS, owner 2026-10-17) | HTTP GET, credentials in the query (08-gaps G-9) | `SMS_GATEWAY_URL/API_KEY/SECRET_KEY/SENDER` env | 5 s | ×5 backoff via outbox job | queue + `auth.smsDelayed` copy; alert at `failed` |
| Google OIDC | HTTPS (discovery + token + userinfo) | `GOOGLE_CLIENT_ID/SECRET` | 5 s | ×2 on 5xx | error state → phone OTP alternative |
| GitHub OIDC | HTTPS | `GITHUB_CLIENT_ID/SECRET` | 5 s | ×2 on 5xx | same |
| Redis (limits + caches) | TCP (go-redis) | `REDIS_URL` | 100 ms | none (fail open to DB) | DB fallback counters (stricter), direct DB lookups |

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| Web `/login` phone OTP | `POST /auth/otp/request` → `POST /auth/otp/verify` | §2 endpoint tables (`03` §2) |
| Web `/login` password | `POST /auth/login/password` | session cookie set by api |
| Web SSO buttons | `GET /auth/google/start` · `/auth/github/start` → return via `/auth/sso/return` | 302 + one-time result code |
| App onboarding | `POST /auth/otp/request|verify`, `POST /auth/register` | tokens → secure store |
| App settings | `PATCH /me`, `POST /auth/logout`, `POST /auth/logout-all` | `auth:me` revalidation |
| App device list (P1) | per-user session/refresh list endpoint | P1 contract, additive |
| 07 queue screen | `GET /verification-requests`, `POST /verification-requests/{id}/approve|reject`, `GET /school/users` | role-gated, tenant-scoped |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change. Auth additions (new provider, device-list
endpoint) are additive; the `Principal` shape and middleware signatures are frozen for modules
04–14 (they compile against this file's §2).

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| SMS gateway | password login, SSO, verification decisions | `auth.smsDelayed` + queued OTP | outbox job drains when partner recovers |
| Google/GitHub OIDC | phone OTP + password paths | SSO button error hint | auto |
| Redis | full auth via DB fallback (slower, stricter limits) | slight latency | auto |
| Neon cold start / slow DB | retries mask brief unavailability | slower first hit | pgx retry + health probe |
| 04 `OnUserVerified` | approve commits; user VERIFIED | groups/notices appear moments later | provisioning job retries + alerts |
| 06 notifications | decisions unaffected | no push (in-app status still correct) | reminder repeats next SLA tick |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `IDT-IT-011` | SMS gateway outage: fake gateway 500s → outbox retries → delivers on recovery; UI copy shown | Integration | I-4 degradation |
| `IDT-IT-012` | Provisioning job: `OnUserVerified` fails twice then succeeds → user VERIFIED throughout, provisioning completed, audit trail clean | Integration | I-1 degraded-not-fatal |
| `IDT-IT-001`–`010` | (defined in `03-backend-tasks.md` §6 — OTP flow, refresh reuse, cross-tenant denial, verified gate, SSO link, register/approve/ambassador/suspend/rate-limits) | Integration | core security invariants |
| `IDT-E2E-001` | Playwright web golden path: `/login` bn → phone OTP → session cookie → `/verification-pending` renders bn; EN toggle re-renders | Playwright | web golden path + bilingual default |
| `IDT-E2E-002` | Maestro app golden path: language → role → hierarchy → phone → OTP → pending screen; tabs blocked with explainer | Maestro | onboarding → pending golden path (`tech-stack.md` app table) |

## 10. Task Checklist

- [x] `IDT-INT-001` `auth` middleware package (`Authenticate`, `RequireRole`, `RequireVerified`, `CurrentUser`, `Principal`) — 2026-10-15
- [x] `IDT-INT-002` OpenAPI `securitySchemes` (bearerJWT mobile / sessionCookie web) + route wiring for all `03` §2 endpoints — 2026-10-15
- [x] `IDT-INT-003` hierarchy client interface + in-memory fake (pre-04 builds/tests) — 2026-10-15
- [x] `IDT-INT-004` `verification.EnqueueProvisioning` job → `hierarchy.OnUserVerified` adapter — 2026-10-15
- [x] `IDT-INT-005` audit events emitted for all BR-010 cases — 2026-10-15
- [x] `IDT-INT-006` jobs registered on the 01 worker (SLA reminder, OTP outbox, provisioning, cleanup) — 2026-10-15
- [x] `IDT-INT-007` SMS gateway client + outbox state machine (`SMS_GATEWAY_*`) — 2026-10-15
- [x] `IDT-INT-008` Google + GitHub OIDC clients (state, PKCE, link-on-verified-email) — 2026-10-15
- [x] `IDT-INT-009` rate-limit middleware, class `auth`, Redis + DB fallback — 2026-10-15
- [x] `IDT-INT-010` 06 notification hand-offs: approved / rejected / SLA-reminder templates requested — 2026-10-15
- [x] `IDT-INT-011` Redis cache keys (`session:{hash}`, `status:{userId}`) with explicit invalidation — 2026-10-15
- [ ] `IDT-INT-012` E2E specs: `IDT-E2E-001` (Playwright) + `IDT-E2E-002` (Maestro) in CI

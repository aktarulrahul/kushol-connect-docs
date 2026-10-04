# Identity & Access — Technical Document

**Module:** `03-identity-access` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> Compresses spec files `01`–`06` in this folder; when it drifts, the specs win.

---

## 1. Overview

### 1.1 Purpose

The trust gateway of Kushol Connect: registers and authenticates every user across the five end-user roles (plus the platform-scoped `vendor` portal login)
(Super Admin, School Admin, Teacher, Student, Guardian) via phone OTP (local SMS gateway),
email+password (staff, argon2id) and Google/GitHub SSO, then runs the `PENDING → VERIFIED`
workflow `prd.md` §5.1 makes mandatory before anyone participates — no post, message, purchase or
AI call exists for an unverified account (`brd.md` §2 Goal 1: 20,000+ users in year 1). Student
Ambassador is **a flag on a verified student** (`users.is_ambassador`), not a sixth role.

### 1.2 Scope

**In:** owned tables `users`, `auth_identities`, `otp_codes`, `sessions`, `refresh_tokens`,
`verification_requests`, `guardian_links` · registration (language → role → hierarchy → contact → OTP → `PENDING`,
incl. guardian link evidence) · login paths (phone OTP, staff argon2id password, Google/GitHub
OIDC; logout / logout-all) · tokens & sessions (15-min JWT + rotating refresh mobile, http-only
session web) · verification workflow API + SLA reminder job · role guards middleware · web
`/login` + `/verification-pending`; app onboarding stack, pending gate, settings; `auth.*` /
`verification.*` / `validation.*` catalog keys.

**Out:** hierarchy data/tenant CRUD and `OnUserVerified` internals (04) · the queue UI
`/school/users` (built in 07 on this module's API) · push delivery infrastructure (06) ·
roster CSV upload (14) · participation features (05/08/10/11).

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 01 foundations · 02 design-system | RFC-7807 envelope, `audit_log`, jobs table + worker, config parsing, test harness · tokens, RN + web primitives, bn/en catalog machinery |
| consumes | 04 organization-hierarchy (read-only) | hierarchy reads + `OnUserVerified`, behind an interface (`06` §3) with in-memory fakes so 03 builds/tests before 04 lands |
| consumed by | 07 command-center-web (REST queue/roster) · 05, 08, 10, 11+ (in-process `auth.Authenticate` / `RequireRole` / `RequireVerified`) | generated client · middleware exports |
| consumed by | 06 notifications | approved/rejected/SLA-reminder send requests (03 requests, 06 delivers) |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| api | Go · chi REST · services · tenant-scoped repositories · sqlc + pgx · slog | custom Go auth decided 2026-09-29 (Clerk rejected — 10k MAU free-tier cap vs ~20k year-1 target; BD phone-first SMS) | middleware package exported to 04–14 |
| api — security | argon2id (`golang.org/x/crypto/argon2`: m=19456 KiB, t=2, p=1) · HS256 JWT (`JWT_SECRET` ≥ 32 B) · `golang.org/x/oauth2` + `coreos/go-oidc` · OpenAPI `securitySchemes` (bearerJWT mobile / sessionCookie web), generated Go + TS code | OWASP floor; rehash-on-login path; `Principal` shape frozen for 04–14 (`IDT-INT-002`) | OTPs stored as HMAC-SHA256 with `OTP_PEPPER`, never argon2id |
| api — infra | PostgreSQL (Neon, testcontainers) · Redis (rate limits + session/status caches) | DB-authoritative status with Redis ≤ 30 s cache, invalidated on change | Redis down → DB fallback counters (stricter) |
| web | Next.js App Router · RHF + zod · generated `openapi-fetch` client, `credentials: include` + `X-CSRF-Token` | web never sees the token; cookie on shared site domain (OQ-4) | `/login`, `/verification-pending`, `/auth/sso/return` |
| app | Expo · expo-router · expo-secure-store (never AsyncStorage) · system-browser SSO (auth-session, PKCE) | tokens survive on 3G via refresh rotation | onboarding stack + pending gate + settings |

---

## 3. Architecture

### 3.1 Component diagram

```text
web /login /verification-pending   app onboarding / settings   07 /school/users
        │ openapi-fetch (cookie+CSRF)   │ tokens → secure store   │ generated client
        ▼                              ▼                         ▼
api chi: /auth/* (public, class auth) · /me · /verification-requests · /school/users
  middleware: Authenticate → role claims → tenant-scope → RequireRole → RequireVerified
        ▼ services: auth.Register · LoginPassword · otp.Issue/Verify · token.Issue/Rotate/DetectReuse
                    session.* · sso.Google/GitHub · verification.List/Approve/Reject · users.Suspend
                    bootstrap.CreateSuperAdmin (CLI)
        │ repositories (sqlc)                          │ externals
        ▼                                              ▼
users · auth_identities · otp_codes · sessions     SMS gateway (HTTPS) · Google/GitHub OIDC
refresh_tokens · verification_requests             Redis (limits, session:{hash}, status:{userId})
        │ behind interfaces
        ▼
01: audit.Record · jobs.Enqueue/worker   04: hierarchy.Get* + OnUserVerified   06: notify.SendToUser
```

### 3.2 Boundary

**Owns (tables / services):** the seven owned tables; the auth middleware chain; token/session
lifecycle; the user status machine; rate-limit counters for the `auth` class.

**Reads (via exported service functions only):** 04 hierarchy reads + `OnUserVerified` via the
provisioning job · 01 `audit_log` append + `jobs` enqueue/worker + error envelope · 06
`notify.SendToUser` (requested by 03's job, delivered by 06). 03 never writes enrollments or
hierarchy rows.

### 3.3 Request / data flows

```text
1. Register      language → role → hierarchy (04 reads, SWR-cached) → phone → POST /auth/otp/request (202
                 always) → OTP SMS → POST /auth/register → one tx: users(PENDING) + identities + request → audit
2. OTP login     request (purpose=login) → verify → tokens (app) or session cookie (web); unknown phone →
                 {status:"unknown_phone"} (deliberate — OTP proves possession)
3. Password      POST /auth/login/password → argon2id (dummy-verify on miss) → session (web) / tokens (app);
                 PENDING still gets a session → pending explainer only
4. Refresh       single-use rotation in family_id; claims re-read from DB; replay of a revoked token ⇒ whole
                 family revoked + audit auth.refresh_reuse
5. Approve       matrix check → tx flips VERIFIED → provisioning job → 04 OnUserVerified (×5) → notify 06 → audit
6. SSO           start (state+PKCE) → callback → link-on-verified-email or create PENDING after hierarchy → 302
7. Status gate   per request: Authenticate → DB status (Redis status:{userId} TTL 30s) → NOT_VERIFIED if PENDING
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| `users` | PENDING · VERIFIED · SUSPENDED | (none) → PENDING (register + OTP verified / SSO + hierarchy; unique phone/email, OTP caps) · PENDING → VERIFIED (School Admin same-school, or Ambassador same-school student/guardian approve-only; verifier VERIFIED) · VERIFIED → SUSPENDED (School Admin own school / Super Admin; revokes sessions + refresh families) · SUSPENDED → VERIFIED (same authority; fresh login required) |
| `verification_requests` | PENDING · APPROVED · REJECTED · CANCELLED | PENDING → APPROVED (BR-005 matrix) · PENDING → REJECTED (School Admin/Super Admin only; reason 10–500 chars required) · resubmit → new PENDING row (≤1 open per user, partial unique) |
| `otp_codes` | active · consumed · dead | active → consumed (atomic consume: ≤3 attempts, ≤5 min TTL, constant-time compare) · active → dead (attempts exhausted / expiry / resend cooldown) |
| `refresh_tokens` family | active · rotated · revoked | active → rotated (single-use; new token same family) · any → revoked (logout / logout-all / status change / reuse detection ⇒ whole family) |

---

## 4. Data Model (summary)

Mirror of `03-backend-tasks.md` §1 — column detail stays there. uuid v7 PKs, app-generated.

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `users` | one row per person: role (incl. platform-scoped `vendor`), status, locale, school scope, phone/email, argon2id hash, ambassador flag, Kushol Pro `plan` | `school_id` direct (NULL = platform scope, super_admin only — BR-011) | unique partial `phone_e164`, unique partial `email` · `(school_id, role, status)` · partial `(status)` on PENDING | CHECK role/status/locale enums; `is_ambassador` ⇒ role='student' |
| `auth_identities` | provider links per user: phone / password / google / github | via owning user's `school_id` | `user_id` · `(provider, provider_account_id)` UNIQUE | FK → users ON DELETE CASCADE |
| `otp_codes` | issued OTPs (hashed), purpose, expiry, attempt counter, consumption | pre-auth — scoped by phone + IP counters instead of tenant | `(phone_e164, created_at DESC)` · partial on unconsumed+unexpired | `code_hmac` = HMAC-SHA256(code, `OTP_PEPPER`); `request_ip` for abuse analysis |
| `sessions` | web http-only sessions (opaque token, SHA-256 stored) | via owning user's `school_id` | `token_hash` UNIQUE · `(user_id, expires_at)` · partial `(expires_at)` for cleanup | 30-day expiry, sliding `last_seen_at`; device metadata for device list (P1) |
| `refresh_tokens` | mobile refresh tokens, rotation families for reuse detection | via owning user's `school_id` | `token_hash` UNIQUE · `family_id` · `(user_id, revoked_at)` | single-use; `revoked_reason` ∈ rotated/reuse_detected/logout/logout_all/status_change |
| `verification_requests` | join-request queue: evidence jsonb, decision, SLA counters | `school_id` direct (denormalized for queue scoping) | `(school_id, status, created_at)` · `(status, created_at)` SLA scan | partial unique `user_id WHERE status='PENDING'`; CHECK reject ⇒ reason NOT NULL |

Migrations `IDT-BE-001…006` (six, reversible). Seed: bootstrap Super Admin from env (one-off CLI
`IDT-BE-032`, refuses if a super_admin exists; `TODO: Confirm` contacts) + dev-only "Demo High
School" accounts, excluded from prod builds.

---

## 5. Contracts

### 5.1 REST endpoints

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | POST `/api/v1/auth/register` | public (+ OTP code; class `auth` 100/h/IP — CGNAT/school Wi-Fi) | create user `PENDING` + verification request in one tx; hierarchy re-validated server-side | `VALIDATION_FAILED` · `CONFLICT` · `RATE_LIMITED` · `INTERNAL` | US-001/002/013 |
| 2 | POST `/api/v1/auth/otp/request` · `/resend` · `/verify` | public; class `auth` | issue/resend/verify 6-digit OTP by SMS (primary) or email (`noreply@`, staff/vendors, SMS-delay fallback); request always `202` (enumeration-safe); verify issues tokens or `{status:"unknown_phone"}` | `VALIDATION_FAILED` (one generic message) · `RATE_LIMITED` (60s cooldown, 5/h/phone, 20/h/IP, 3/code, 10/h verify) | US-001/003 |
| 3 | POST `/api/v1/auth/login/password` | public; class `auth` | staff argon2id login; web gets session cookie, app tokens; PENDING still gets a session | `UNAUTHENTICATED` (generic, enumeration-safe) · `VALIDATION_FAILED` · `RATE_LIMITED` (10/h/account, 30/h/IP) | US-004/013 |
| 3a | POST `/api/v1/auth/password/forgot` · `/password/reset` | public; class `auth` | staff/vendor reset via 6-digit email OTP from `noreply@`; reset revokes all sessions | `VALIDATION_FAILED` · `RATE_LIMITED` | IDT-US-015 |
| 4 | POST `/api/v1/auth/refresh` | public (refresh in body) | single-use rotation, claims re-read from DB | `UNAUTHENTICATED` (reuse ⇒ family revoked + audit) · `VALIDATION_FAILED` | US-003, BR-012 |
| 5 | POST `/api/v1/auth/logout` · `/logout-all` | authenticate | kill current session+token / everything, audited | `UNAUTHENTICATED` | US-012 |
| 6 | GET `/api/v1/auth/google/start` + `/callback` · `/github/*` | public; 20/h/IP per provider | OIDC round-trip (state+PKCE); link-on-verified-email; SSO never verifies | redirect with error param (never raw 5xx) | US-005 |
| 7 | GET · PATCH `/api/v1/me` | authenticate (relaxed 60/min/user) | read/patch own profile; locale switch persists, next JWT carries it | `UNAUTHENTICATED` · `VALIDATION_FAILED` · `FORBIDDEN` (role/status change) | US-011 |
| 8 | GET `/api/v1/verification-requests` · POST `…/{id}/approve` · `…/{id}/reject` | list: school_admin (own), student+`is_ambassador` (same-school student/guardian only), super_admin · approve: per BR-005 (ambassador approve-only, daily-capped) · reject: school_admin/super_admin only | paged queue with evidence; approve flips VERIFIED + enqueues provisioning (+06 notify); reject stores reason | `FORBIDDEN` · `NOT_FOUND` · `CONFLICT` (already decided) · `VALIDATION_FAILED` (reason 10–500) · `NOT_VERIFIED` (unverified verifier) | US-007/008/009 |
| 9 | GET `/api/v1/school/users` | school_admin (own from claim), super_admin (`?schoolId=`) | roster page: names, roles, statuses, masked phones | `TENANT_MISMATCH` (cross-school) · `FORBIDDEN` | US-007 |

Web has no Server Actions touching the DB — screens call these endpoints via the generated client
with `credentials: include` + `X-CSRF-Token` on mutations; middleware reads cookie **presence**
for redirects only.

### 5.2 Realtime / jobs

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| `verification-sla-reminder` (`IDT-BE-029`) | hourly; PENDING older than SLA (48 h) | reminder via 06 to school verifiers; `reminder_count`++, daily repeat | 07 admins, verifiers | send failure → retry next tick (`last_reminder_at` guard) |
| `otp-outbox-retry` (`IDT-BE-030`) | every minute | queued SMS → gateway call | SMS gateway | ×5 backoff → `failed` + metric + alert; UI shows `auth.smsDelayed` |
| `provision-verified-user` (`IDT-BE-031`) | enqueued by approve | `hierarchy.OnUserVerified(userId)` (04) | 04 | ×5 retry → alert; user stays VERIFIED; approval committed |
| `session-refresh-cleanup` | daily | delete expired session/refresh rows | housekeeping | silent |

No WebSocket channels of its own; status changes force client re-auth (06 deep links).

### 5.3 Exported service functions

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `auth.Authenticate(r) (Principal, error)` / `auth.CurrentUser(ctx)` | every api module's router · services needing the actor | `Principal{UserID, Role, SchoolID, Status, Locale}` from JWT (mobile) or session cookie (web) | `UNAUTHENTICATED` |
| `auth.RequireRole(roles ...Role)` | route builders 04–14 | wrapped handler | `FORBIDDEN` |
| `auth.RequireVerified()` | participatory routes (05/08/10/11) | wrapped handler | `NOT_VERIFIED` (DB-authoritative, Redis 30 s) |
| `sessions.InvalidateForUser(userID)` | suspend/reinstate here; future admin tooling | nil | — |
| `verification.EnqueueProvisioning(userID)` | approve flow | job id → 04 `OnUserVerified` | `INTERNAL`; idempotent per user |
| `verification.PendingCount(schoolID)` | 07 | int | `FORBIDDEN` |
| `users.GetWithSelection(userID)` | 04 | `UserSelection{UserID, Role, Status, SchoolID, SectionID}` | `NOT_FOUND` |
| `users.UpsertRosterUser(schoolID, in)` | 14 | `{UserID, Created}` — PENDING only, never auto-verify | `VALIDATION_FAILED`, `CONFLICT` |
| `users.PlanOf(userID)` / `users.SetPlan(actor, userID, tier, expiresAt)` | 08 (read) · 07/12 (write) | Kushol Pro tier | `FORBIDDEN` |
| `users.CreateVendorLogin(actor, in)` | 07 vendor approval | vendor user id | `CONFLICT`, `FORBIDDEN` |
| `guardians.LinkedStudents` / `GuardiansOf` / `IsGuardianOf` | 04 · 05 · 12 · 14 | ACTIVE `guardian_links` | — |

Exports return DTOs; `Principal` and middleware signatures are frozen for 04–14
(`06-integration-tasks.md` §7).

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| `/login` | Login (bn-default): LanguageToggle, LoginTabs (Phone OTP default / Password staff), OTP auto-advance boxes + resend countdown, SsoButtons, PendingNotice; delayed-SMS + rate-limit states | Server shell + client island | Public |
| `/verification-pending` | Pending-verification status: numbered steps bn+en, rejected state (`decision_reason` + fix & resubmit), logout; mid-view verify routes onward | Client Component (`GET /me`, no-store) | Authenticated (`PENDING`) |
| `/auth/sso/return` | SSO return landing: consumes one-time result code → `GET /me` → route per role/status | Client Component | Public |
| `/school/users` | Verification queue UI — **built by 07-command-center-web** on this module's APIs; hand-off note `IDT-FE-010`, no layout duplicated here | — | school_admin / ambassador / super_admin |

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| `/onboarding/language` · `/role` | Language pick (bn preselected regardless of device locale, BR-008) · role pick (admin → web link) | none | local-only steps; draft preserved |
| `/onboarding/hierarchy` | City → School → Class → Section picker (04 interface, TanStack Query SWR 5 min, one search) | none | skeleton/empty/offline states; "school not added yet" hint |
| `/onboarding/contact` · `/otp` | Phone (+ guardian student-ID evidence `OQ-3`) · 6 OTP boxes, 60s resend, `auth.smsDelayed` after 15s | none | OTP refused offline — never silently queued |
| `/onboarding/sso` | Google/GitHub via system browser (state + PKCE, deep link `kushol://auth/sso`) | `kushol://auth/sso` | needs connectivity |
| `/onboarding/pending` + `/(tabs)/_layout` gate | "What happens now" explainer; tabs render this until VERIFIED; rejected shows reason + resubmit | approval push via 06; `kushol://(tabs)/chat` declared | cached `auth:me` + staleness banner; refetch on reconnect/foreground |
| `/settings` | Language switch (`PATCH /me`), logout / logout-all, device list (P1) | none | local logout always works; server revoke retries once |

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| SMS gateway (`TODO: Confirm` vendor — SSLWireless-class, `OQ-2`) | OTP delivery | HTTPS REST | `SMS_GATEWAY_URL` / `SMS_GATEWAY_API_KEY` / `SMS_GATEWAY_SENDER` | 5s; ×5 backoff via outbox job | OTP queued; `auth.smsDelayed` copy; alert at `failed`; password/SSO unaffected |
| Google OIDC | teacher/staff SSO | HTTPS (discovery + token + userinfo) | `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | 5s; ×2 on 5xx | SSO button error → phone OTP alternative |
| GitHub OIDC | SSO | HTTPS | `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` | 5s; ×2 on 5xx | same |
| Redis | rate-limit counters + `session:{hash}` / `status:{userId}` caches | TCP (go-redis) | `REDIS_URL` | 100 ms; fail open to DB | DB fallback counters (stricter), direct lookups |

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| `DATABASE_URL` · `REDIS_URL` | yes | (from 01 config module) | pgx pool · Redis client |
| `JWT_SECRET` · `OTP_PEPPER` | yes | ≥ 32 random bytes · random bytes | HS256 access JWT (`02-solution-approach.md` §6) · HMAC-SHA256 OTP storage |
| `SMS_GATEWAY_URL` / `_API_KEY` / `_SENDER` | yes | SSLWireless-class endpoint (`TODO: Confirm` vendor) | SMS outbox worker (`IDT-INT-007`) |
| `GOOGLE_CLIENT_ID` / `_SECRET` · `GITHUB_CLIENT_ID` / `_SECRET` | yes | OIDC app credentials | `sso.Google` / `sso.GitHub` (`IDT-INT-008`) |
| super-admin bootstrap phone/email/password | yes (one-off) | env-fed CLI, argon2id (`TODO: Confirm` contacts) | `bootstrap.CreateSuperAdmin` (`IDT-BE-032`) |

All env reads go through the 01 config module (BR-002); lifetimes move to Super Admin settings
post-P1.

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| verification SLA hours (default 48) · OTP hourly cap per phone (5) · resend cooldown (60 s) · access-JWT TTL (15 min) · refresh/session lifetime (30 d) · granting/revoking ambassador flags (School Admin, per school) | OTP length 6, 5-min expiry, 3-attempt cap (security invariants) · argon2id parameters · JWT claims shape + signing algorithm · role/status/locale enums · E.164 normalization rules · refresh reuse-detection behaviour · verified-gate semantics |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | `authenticate → load role claims → tenant-scope → RequireRole → RequireVerified` (verified gate only on participatory routes); `/auth/*` public but rate-limited (class `auth`) |
| Role matrix | BR-005: School Admin → everything in own school · Student Ambassador (verified student + flag) → same-school student/guardian requests, approve-only, daily-capped · Super Admin → everything (school_id NULL); reject is admin/super_admin only |
| Tenant scope | `users`/`verification_requests`: direct `school_id` column (super_admin bypass audited) · `sessions`/`refresh_tokens`/`auth_identities`: scoped via owning user · `otp_codes`: pre-auth, phone/IP counters; cross-tenant attempts → `TENANT_MISMATCH`/404, no rows leaked (INV-6) |
| Rate limits | class `auth`: register 10/h/IP · OTP 60s cooldown, 5/h per phone or email, 200/h/IP (CGNAT), 3 attempts/code, 10 verifies/h per target · password 10/h/account, 100/h/IP · password reset 5/h/email · SSO 20/h/IP per provider · `/me` 60/min/user · ambassador approvals capped/day |
| Audit events | BR-010: register, first login per device, approve, reject, suspend, reinstate, logout-all, refresh-reuse detection, SSO link, ambassador flag grant/revoke — via 01 `audit.Record` |
| Privacy / minors | phone numbers masked in logs and API responses; OTPs/tokens/secrets never logged; argon2id staff-only; sessions SHA-256-only, `__Host-kushol_session` (HttpOnly, Secure, SameSite=Lax) + CSRF double-submit; minimal PII at auth (name, phone, school placement — no photos); guardian data never crosses schools; enumeration-safe: OTP request always `202`, password login identical body + timing (dummy verify) |

---

## 10. Error Handling

All errors surface as RFC-7807 `application/problem+json` with localized `message` (bn default);
copy resolves via `auth.*` / `verification.*` / `validation.*` keys in each app's `src/i18n` — bn + en
(e.g. `auth.otp.prompt`, `verification.pending.body`).

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `UNAUTHENTICATED` | no/invalid credentials | protected call without session/token; invalid/expired refresh; generic password-login failure | clear session → login; generic copy only (enumeration-safe) |
| `FORBIDDEN` | authenticated but not allowed | wrong school/role; ambassador reject or teacher/other-school target; attempted role/status change on `/me` | message + contact hint; no data leaked |
| `VALIDATION_FAILED` | field-level rejection | phone/OTP/email/password/name/hierarchy/reject-reason rules (§6 of `01`) | field errors from `errors.fields`; bn-default copy |
| `TENANT_MISMATCH` (404) | cross-tenant attempt | school B requests school A's queue/roster | silent 404 treatment |
| `NOT_FOUND` / `CONFLICT` | missing resource / state clash | unknown request id or route · phone/email taken, hierarchy mismatch, already-decided request | generic copy · user-visible "already exists/decided" copy |
| `NOT_VERIFIED` | PENDING/SUSPENDED on participatory route | valid token, unverified account | pending explainer link; gate opens ≤ 30 s after approval |
| `RATE_LIMITED` | class/sub-cap exceeded | OTP cooldown/hourly caps, password caps, SSO caps | countdown UI (`auth.rateLimited`), resend disabled |
| `INTERNAL` | unexpected failure | dependency down, enqueue failure | retry + request id; never a stack trace |

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | slog with `request_id`; phones masked; OTPs/tokens/secrets redacted (01 chain); failures counted (login), successes audited |
| Metrics / counters | OTP delivery failure + resend ratio (SMS vendor ops input, 01 §8); outbox `failed` count + alert; SLA-breach list per school; pending-vs-verified counts feed 07 dashboards |
| Health contribution | none of its own — `/healthz` `/readyz` are 01's; 03 registers its jobs on the 01 worker and depends on Neon/Redis probes indirectly |
| Jobs & retries | SLA reminder hourly (idempotent, daily repeat) · OTP outbox every minute (×5 backoff → `failed` + alert) · provisioning per approve (×5 retry → alert, user stays VERIFIED) · daily session/refresh cleanup |
| Runbook pointers | degradation matrix in `06-integration-tasks.md` §8 (SMS down, OIDC down, Redis down → DB fallback, Neon cold start, `OnUserVerified` failure, 06 outages); vendor SLA belongs in the SMS contract (`OQ-2`); ADRs (unknown-phone response, custom auth) recorded in `07-progress.md` at build |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | BD phone normalization · OTP HMAC + attempt logic · JWT round-trip/wrong-aud · refresh rotation state machine · enumeration-safe login parity · role/verified guard matrix (5 roles × routes × statuses) · CSRF paths | `IDT-UT-001…007` | `go test` green in CI |
| Integration | OTP flow end-to-end · refresh reuse ⇒ family revoke · cross-tenant denial · verified gate · SSO link-on-verified-email · register golden path · approve→provision→audit · ambassador scope · suspend/reinstate · rate limits · SMS-gateway outage · provisioning-retry | `IDT-IT-001…012` (testcontainers Postgres + fake gateway/OIDC) | required check |
| E2E | web golden path `/login` bn → OTP → session → pending screen (Playwright) · app golden path language→…→pending, tabs blocked (Maestro) | `IDT-E2E-001…002` | CI |
| CI | api gate (fmt/lint/vet/unit/integration) + TS workspaces + EAS/Playwright/Maestro hooks | — | required checks, no skip flags |

Mandatory set covered: unauthenticated denial (UT-006 matrix), validation rejection (UT-001 +
contract validators), cross-tenant denial (IT-003), verified-gate enforcement (IT-004).

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | ~20 k users year 1; peak = school onboarding day (hundreds of registrations + OTP verifies per school, bursty within minutes) |
| Hot paths + indexes | per-request session/status lookup — Redis hash reads ~1 ms with DB fallback; JWT verify microseconds; indexes: `users(phone_e164)`, `users(email)`, `users(school_id, status)`, `verification_requests(school_id, status, created_at)`, `refresh_tokens(family_id)`, `sessions(user_id)`, `otp_codes(phone_e164, created_at DESC)` |
| Latency targets | Redis down degrades to DB lookups (slower, no auth outage); Neon cold start masked by pgx retry |
| Bundle / payload impact | web `/login` adds RHF + zod ≈ 15 kB gzip; app auth screens ride the initial bundle with no new deps beyond 02 primitives; auth payloads < 10 kB |
| Caching | `session:{hash}` TTL 300 s and `status:{userId}` TTL 30 s, invalidated on revoke/status change; every `/auth/*` response `no-store`; no CDN caching |

---

## 14. Risks & Open Questions

Consolidated from `01-user-stories.md` §9 and `02-solution-approach.md` §11; unconfirmed items
keep their `TODO: Confirm` marker.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Student Ambassador criteria / verification SLA | queue trust + speed | Rahul | Open | any verified ambassador of the same school verifies same-school student/guardian requests; SLA 48 h with auto-reminder |
| 2 | SMS gateway vendor (`TODO: Confirm` vendor + contract); nationwide within-seconds delivery | OTP delivery; onboarding churn | Rahul | Open | SSLWireless-class local gateway behind `SMS_GATEWAY_*` env; `auth.smsDelayed` copy, resend, SSO + password alternatives; vendor SLA in contract |
| 3 | Guardian↔student linking proof | guardian trust | Rahul | Open | guardian enters school + class + student ID; admin approves in queue; module 14 enables automatic matching later |
| 4 | Shared registrable domain for web + api (session cookie scope) | web auth redesign if split | Rahul | **Resolved 2026-09-30** | `kusholconnect.com`: web on the apex with same-origin `/api/*` proxy → host-only `__Host-` session cookie; mobile on `api.kusholconnect.com` with JWT + refresh tokens |
| 5 | Ambassadors mass-approving outsiders | trust erosion with schools | Rahul | Mitigated | same-school + student/guardian only, approve-only, daily cap, full audit, instant flag revocation, admin spot-checks |
| 6 | argon2id CPU on shared 2-vCPU VPS · token theft on mobile | login spikes; account takeover | Rahul | Mitigated | staff-only passwords (low volume), OTP avoids argon2id, attempt caps · 15-min access TTL, single-use refresh + reuse detection, device list (P1), logout-all |
| 7 | 04 hierarchy endpoints land after 03 starts building | registration blocked | Rahul | Mitigated | hierarchy consumed behind an interface with fakes (`06` §3); contract agreed before either builds |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| `IDT-BR-001` verified gate server-side · `IDT-BR-002` role/status/locale enums | §5.1 | US-006, US-001…014 | IDT-BE-001/017, IDT-INT-001 | IDT-IT-004, IDT-UT-006 |
| `IDT-BR-003` OTP rules · `IDT-BR-004` E.164 phone identity | §5.1, prompt §9 | US-001/003 | IDT-BE-007…009/022/024, IDT-INT-007/009 | IDT-UT-001/002, IDT-IT-001/010 |
| `IDT-BR-005` verifier matrix · `IDT-BR-011` super_admin platform scope | §5.1; brd §2 | US-007/008 | IDT-BE-016/022/023/027, IDT-FE-010 | IDT-IT-003/008 |
| `IDT-BR-006` SSO never verifies · `IDT-BR-012` refresh rotation + reuse detection | §5.1; prompt §9 | US-005, US-003/012 | IDT-BE-013/015/026, IDT-INT-008, IDT-AP-009 | IDT-IT-002/005, IDT-UT-003/004 |
| `IDT-BR-007` status change revokes sessions · `IDT-BR-010` audit all security events | §5.1; brd §6 | US-007/010/012 | IDT-BE-014/019/020, INT-005/011 | IDT-IT-007/009 |
| `IDT-BR-008` bn default locale · `IDT-BR-009` reject reason + resubmit | prompt §2(6); §5.1 | US-011, US-009 | IDT-BE-011/016/018/027, IDT-FE-001, IDT-AP-002 | IDT-E2E-001/002, IDT-IT-007 |
| — (full set) | §5.1, §5.3; brd §2 Goal 1 | IDT-US-001…015 | IDT-BE-001…035 · FE-001…010 · AP-001…014 · INT-001…012 | IDT-UT-001…007 · IT-001…012 · E2E-001…002 |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Email OTP channel (`otp_codes.channel`/`email`, `reset` purpose) sent from `noreply@kusholconnect.com` via 06; staff/vendor forgot-password endpoints (`IDT-US-015`); per-IP limits raised for CGNAT/school Wi-Fi (per-target caps remain primary) | Claude |
| 2026-09-30 | Cross-module consistency pass: `vendor` role, `plan`/`plan_expires_at`, `verification_requests.requested_section_id`, `guardian_links` table + migration `20261001090030`, FKs to 04 tables deferred to 04's `20261002090007`; `classId` removed from registration; exports added for 04/07/08/12/14 | Claude |
| 2026-10-02 | **Passwordless login (owner decision):** `/auth/login/password` removed from the contract; login is email OTP (6-digit code to the staff email) or phone OTP — `OtpVerifyResult` gains `unknown_email`, `otp.UserFinder` gains `StatusByEmail`, web login defaults to the Email OTP tab, app gains an Email OTP tab. Passwords remain provisioned credentials only (bootstrap super admin, teacher registration, `/auth/password/forgot`+`reset`, 07 vendor first-password set). Super admin seeded 2026-10-02 (`contact.aktarul@gmail.com`). | Kilo |
| 2026-10-02 | **OTP email delivery + letter templates:** `jobs.SetConn(pool)` at api/worker boot so `auth.otp_email` jobs run; bilingual HTML/plain letter via `smsout.RenderOTPEmail` (deep-teal wordmark, digit figures, purpose-specific subjects). Web local `/api/v1` rewrite avoids CORS on the api. App `AuthProvider` + refresh-token restore (no welcome flash). Stage 5 partial: phone OTP / register / `/me` / logout / web SSO on generated client; hierarchy still fixtures. | Kilo |

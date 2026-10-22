# Identity & Access — Solution Approach

**Module:** `03-identity-access` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `users` | One row per person: role, status, locale, school scope, primary phone/email, password hash, ambassador flag | ✅ |
| `auth_identities` | Identity links per user: provider ∈ phone/password/google/github + provider account id | ✅ |
| `otp_codes` | Issued OTPs (hashed), purpose, expiry, attempt counter, consumption state | ✅ |
| `sessions` | Web http-only sessions (opaque token, SHA-256 stored server-side) | ✅ |
| `refresh_tokens` | Mobile refresh tokens with rotation `family_id` for reuse detection | ✅ |
| `verification_requests` | Join-request queue: evidence payload, registration-time section choice (`requested_section_id`), status, verifier decision, SLA reminder counters | ✅ |
| `guardian_links` | Durable guardian ↔ student link written when a guardian request is approved (or by 14 roster); read by 04/05/12 | ✅ |
| `audit_log` | Append-only security/decision trail | No — module 01 |
| `jobs` | In-DB job table (SLA reminders, OTP outbox retry, provisioning) | No — module 01 |
| `cities`, `schools`, `sections` (class level is a section attribute — no `classes` table), `enrollments`, `fcm_topic_bindings` | Hierarchy + post-verification provisioning targets | No — module 04 (read-only here) |

### 1.2 Relationships

```text
users 1 ──── n auth_identities        (phone / password / google / github links)
users 1 ──── n sessions               (web http-only; deleted on logout / status change)
users 1 ──── n refresh_tokens         (mobile; family_id chains rotations)
users 1 ──── n verification_requests  (≤ 1 open request per user)
users n ──── 1 schools                (module 04; super_admin school_id = NULL)
verification_requests n ─── 1 schools (denormalized for queue scoping)
services ───► audit_log / jobs        (module 01)
provisioning job ───► hierarchy.OnUserVerified(userId)   (module 04)
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| `INV-1` | Phone (E.164) is unique among non-null values — one account per number | DB partial unique index on `users.phone_e164` |
| `INV-2` | Email is unique among non-null values | DB partial unique index on `users.email` |
| `INV-3` | ≤ 1 open (`PENDING`) verification request per user | DB partial unique index + service check |
| `INV-4` | Refresh tokens are single-use; presenting a revoked token revokes its whole family | Service (rotation transaction) |
| `INV-5` | Session and refresh token values are stored only as SHA-256 hashes | Repository (no plaintext column) |
| `INV-6` | Every guarded query is scoped by `school_id`; `NULL` school_id = platform scope (super_admin only) | Repository layer |
| `INV-7` | One VERIFIED student identity per school-person: a user belongs to exactly one school; 04's enrollment uniqueness is the final guarantee (03 never writes enrollments) | Service + module 04 |
| `INV-8` | An OTP is consumed at most once, ≤ 3 attempts, ≤ 5 min lifetime | Service (atomic consume) + DB |

## 2. Module Boundary

**Owns (writes):** `users`, `auth_identities`, `otp_codes`, `sessions`, `refresh_tokens`,
`verification_requests`; the auth middleware chain; token/session lifecycle; the user status
machine; rate-limit counters for the `auth` class.

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 04 organization-hierarchy | Hierarchy reads (validate school/class/section at registration, picker data) + `OnUserVerified` (called via provisioning job) | 04 owns the hierarchy model; duplicating placement data would fork the truth |
| 01 foundations | `audit_log` append, `jobs` enqueue/worker, RFC-7807 error envelope | Platform services already exist |
| 06 notifications | Send approved/rejected/reminder messages (requested by 03's job, delivered by 06) | Delivery infra (FCM/email) is 06's |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4.

## 3. Lifecycle

```text
            register (+ OTP verified / SSO + hierarchy chosen)          verify (School Admin / Ambassador)
  (none) ────────────────────────────────────────────────▶ PENDING ────────────────────────────────────▶ VERIFIED
                                                            │ ▲                                             │
                                             reject (reason)│ │resubmit                              suspend│reinstate
                                                            ▼ │                                             ▼
                                          request → REJECTED (user stays PENDING)                        SUSPENDED
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| (none) | register + OTP verified (or SSO) | PENDING | valid hierarchy placement (04), unique phone/email, OTP caps | `verification_requests` row; audit `user.registered` |
| PENDING | approve | VERIFIED | verifier = School Admin (same school) or Ambassador (same school, student/guardian only); verifier VERIFIED | status flip; provisioning job → 04 `OnUserVerified`; status-cache invalidation; notify via 06; audit |
| PENDING | reject(reason) | PENDING | School Admin only; reason 10–500 chars | request `REJECTED`; user notified via 06; resubmit allowed; audit |
| VERIFIED | suspend | SUSPENDED | School Admin (own school) or Super Admin | sessions + refresh families revoked; audit |
| SUSPENDED | reinstate | VERIFIED | same authority as suspend | fresh login required; audit |
| any | logout / logout-all | (no status change) | authenticated | session/refresh revocation (+ audit for logout-all) |

`verification_requests` runs its own mini-machine: `PENDING → APPROVED | REJECTED | CANCELLED`.

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| Web `/login` | Static shell + client island | none (public) | — |
| Web `/verification-pending` | Client component, `GET /me` | no-store | `auth:me` |
| App onboarding + tabs gate | Client; hierarchy lists via TanStack Query | SWR 5 min | `hierarchy:{cityId}` |
| API session lookup | — | Redis, token-hash keyed, TTL 300 s, invalidated on revoke/status change | `session:{hash}` |
| API verified-gate status | — | Redis `status:{userId}`, TTL 30 s, invalidated on verify/suspend | `status:{userId}` |

Every `/auth/*` response sets `Cache-Control: no-store`; no CDN caching anywhere in this module.

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| Verification SLA hours (default 48) · OTP hourly cap per phone (5) · resend cooldown (60 s) · access-JWT TTL (15 min) · refresh/session lifetime (30 d) · granting/revoking ambassador flags (School Admin, per school) | OTP length 6, 5-min expiry, 3-attempt cap (security invariants) · argon2id parameters · JWT claims shape + signing algorithm · role/status/locale enums · E.164 normalization rules · refresh reuse-detection behaviour · verified-gate semantics |

Lifetimes start as env-config (`config` module, module 01) and move to Super Admin settings post-P1.

## 6. Security

**Entry points.** All `/auth/*` routes are public but rate-limited (class `auth`); every other
module's routes sit behind the chain **authenticate → load role claims → tenant-scope →
`RequireRole` → `RequireVerified`** (the verified gate only on participatory routes).

**Passwords (staff only).** argon2id via `golang.org/x/crypto/argon2`: m=19456 KiB, t=2, p=1,
16-byte random salt, 32-byte tag (OWASP floor; rehash-on-login upgrade path). Passwords never
leave the service layer; login failure is enumeration-safe: identical problem document, body and
near-identical latency for unknown-account vs wrong-password (dummy verify on miss).

**OTPs.** 6 digits from `crypto/rand`; stored as `HMAC-SHA256(code, OTP_PEPPER)` (never plaintext,
never argon2id — compare must stay fast, the 10⁶ space is covered by attempt caps); TTL 300 s;
≤3 verify attempts per code (atomic consume); 60 s resend cooldown; 5 codes/hour/phone plus
20/hour/IP; constant-time comparison.

**Tokens.** Access JWT (mobile): HS256, `JWT_SECRET` ≥ 32 bytes, claims `sub, role, schoolId,
status, locale, iat, exp(15m)`, `iss=kushol-auth`, `aud=kushol-api`. Refresh: 256-bit random,
SHA-256 stored, 30-day expiry, single-use rotation inside a `family_id`; replay of a revoked
token ⇒ whole family revoked + audit. `status` claims are advisory; the verified gate reads
authoritative DB status (Redis 30 s, invalidated on change) so a fresh verify never waits 15 min.

**Web sessions.** Opaque 256-bit token in `__Host-kushol_session` (HttpOnly, Secure, SameSite=Lax,
Path=/, scoped to the shared site domain — `OQ-4`); server keeps only the SHA-256 hash + expiry
(30 d) + device metadata. Session fixation: every login mints a brand-new session; pre-auth
sessions are never promoted. CSRF: double-submit (`kushol_csrf` cookie + `X-CSRF-Token` header)
on every web mutation.

**Enumeration stance.** OTP request always answers `202` regardless of account existence; password
login is indistinguishable (above); OTP login with a valid code on an unknown phone answers
`{status:"unknown_phone"}` — deliberate, because OTP proves phone possession and the register flow
shares the code path (ADR in `07-progress.md`).

**Tenant-scope rule per owned table.** `users`/`verification_requests`: direct `school_id` column
(super_admin bypass audited); `sessions`/`refresh_tokens`/`auth_identities`: scoped via the owning
user's `school_id`; `otp_codes`: pre-auth, scoped by phone + IP counters instead of tenant.

**Privacy.** Phone numbers masked in logs; OTPs, tokens and secrets never logged; minors: minimal
PII (name, phone, school placement — no photos at auth); guardian data never crosses schools.

**Audited events.** register, first login per device, approve, reject, suspend, reinstate,
logout-all, refresh-reuse detection, ambassador flag grant/revoke.

## 7. Accessibility & Motion

OTP inputs auto-advance and announce remaining digits to screen readers; all errors are announced
via `aria-live` (web) / accessibility focus (app). The pending screen is a plain heading +
numbered steps in reading order — no motion carries meaning. Every animation (tab cross-fade,
invalid-OTP shake, resend countdown, step slide) has a reduced-motion static variant; details in
`04` §5 and `05` §5.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | SMS gateway down/timeout | Send error / 5 s timeout | OTP not delivered | OTP queued in outbox, retried ×5 with backoff (jobs); user shown `auth.smsDelayed`; auto-recovers with partner |
| 2 | Google/GitHub OIDC unavailable | Token-exchange error | SSO button fails | Error state suggests phone OTP; auto-recovers |
| 3 | Neon cold start / slow DB | Elevated p95, pgx retry | Slower auth | pgx retry + health probe; no data risk |
| 4 | Redis down | Client errors | Rate limits fall back to DB counters (stricter); session/status caches bypassed to DB lookups | Degraded latency, no auth outage |
| 5 | `OnUserVerified` fails after approve | Provisioning job error | Verified user briefly lacks enrollment/groups/FCM topics | Job retries (01 worker) with alert; approval itself stays committed |
| 6 | Double-submitted OTP verify | Unique consume guard | Second call gets invalid-code error | Benign |

## 9. Performance

Year-1 volume ≈ 20 k users; peak load is a school onboarding day (hundreds of registrations and
OTP verifications per school, bursty within minutes). The hot path is session/status lookup per
authenticated request — Redis hash reads (~1 ms) with DB fallback; JWT verify is microseconds.
Indexes carry the rest: `users(phone_e164)`, `users(email)`, `users(school_id, status)`,
`verification_requests(school_id, status, created_at)`, `refresh_tokens(family_id)`,
`sessions(user_id)`, `otp_codes(phone_e164, created_at DESC)`. Web bundle: `/login` adds
react-hook-form + zod ≈ 15 kB gzip; the app auth screens are part of the initial bundle with no
new dependencies beyond module 02 primitives.

## 10. Alternatives Considered

### Option A — Custom Go auth · Option B — Clerk / Firebase Auth

| | A: custom Go auth | B: Clerk / Firebase Auth |
| --- | --- | --- |
| Advantages | Five-role RBAC + tenant/verification claims native; local SMS gateway control (cost + BD routing); no per-MAU fee; one deployable | Fast to stand up; polished hosted UIs; built-in OTP/SSO plumbing |
| Disadvantages | We own hashing, rotation, CSRF, OIDC edge cases (all specified here) | Clerk free tier ends at 10 k MAU vs ~20 k year-1 target (~$25/mo per extra 1 k); BD phone-first SMS beats Clerk SMS on cost/routing; tenancy + verification claims would be custom code anyway |
| Complexity / weight | Moderate, fully testable with fakes | Low upfront, high lock-in, recurring cost |

**Recommendation:** Option A — already decided in `tech-stack.md` (2026-09-29, Clerk explicitly
rejected); this module is the implementation of that decision.

### Option A — Phone-OTP-first for everyone · Option B — password-first

| | A: OTP-first (chosen) | B: password-first |
| --- | --- | --- |
| Advantages | No password to forget on low-end phones; proves phone possession; matches BD phone-first habits; students/guardians never see a password field | No SMS cost; no partner dependency |
| Disadvantages | SMS partner dependency + per-SMS cost | Password reuse/forgetting among students/guardians; weaker identity proof |

**Recommendation:** OTP-first for students/guardians; email+password (argon2id) for staff only —
staff volume is tiny, so SMS cost stays bounded.

### Option A — JWT + refresh on both platforms · Option B — opaque sessions everywhere

| | A: hybrid (chosen) | B: opaque sessions everywhere |
| --- | --- | --- |
| Advantages | Mobile survives flaky 3G (offline-tolerant re-auth); stateless verify on hot paths; web gets instant revocation via server-side sessions | One mechanism; trivially revocable everywhere |
| Disadvantages | Two token systems to maintain (specified here) | Mobile must round-trip the server on every cold start — painful on 3G |

**Recommendation:** hybrid — short access JWT (15 min) + rotating refresh (30 d) for the app;
http-only server-side session for web.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | web + api share one registrable domain so the session cookie scopes to both (`OQ-4`) | Cookie can't be shared → web auth redesign | Confirm domain before build; fallback: SameSite=None + strict CSRF |
| 2 | SMS partner delivers OTP within seconds nationwide | Delayed OTPs → onboarding churn | `auth.smsDelayed` copy, resend, SSO + staff-password alternatives; partner SLA in contract (`OQ-2`) |
| 3 | Ambassadors could mass-approve outsiders | Trust erosion with schools | Same-school + student/guardian only, approve-only, daily cap, full audit, instant flag revocation, School Admin spot-checks |
| 4 | argon2id on the shared 2-vCPU VPS | Login CPU spikes | Passwords are staff-only (low volume); OTP path avoids argon2id; caps on password attempts |
| 5 | Token theft on mobile | Account takeover | 15-min access TTL, single-use refresh with reuse detection, device list (P1), logout-all |
| 6 | 04's hierarchy endpoints land after 03 starts building | Registration blocked | 03 consumes 04 behind an interface with fakes (`06-integration-tasks.md` §3); contract agreed before either builds |

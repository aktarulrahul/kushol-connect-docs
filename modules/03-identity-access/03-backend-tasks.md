# Identity & Access — Backend Tasks & Database Design

**Module:** `03-identity-access`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `contracts/openapi/openapi.yaml` · slog logging
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms · generated `openapi-fetch` client → api
**Last updated:** 2026-09-30

---

## 1. Database Design

### 1.1 Tables

#### `users` (model `User`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `role` | `text` | no | — | CHECK ∈ super_admin/school_admin/teacher/student/guardian/vendor (`vendor` = platform-scoped portal login for 07/11/13, created only by the 07 vendor-approval flow — never self-registered in the app) |
| `status` | `text` | no | `'PENDING'` | CHECK ∈ PENDING/VERIFIED/SUSPENDED |
| `locale` | `text` | no | `'bn'` | CHECK ∈ bn/en |
| `full_name` | `text` | no | — | 2–80 chars, service-trimmed |
| `phone_e164` | `text` | null | — | E.164 `+880…`; required for student/guardian |
| `email` | `citext` | null | — | required for staff; lowercased |
| `password_hash` | `text` | null | — | argon2id encoded; staff only |
| `school_id` | `uuid` | null | — | Loose ref → schools (04). 03 builds before 04, so the FK is added by 04's migration `20261002090007_add_identity_hierarchy_fks`. NULL = platform scope (super_admin, vendor) |
| `is_ambassador` | `boolean` | no | `false` | Student Ambassador flag; valid only for VERIFIED students |
| `plan` | `text` | no | `'free'` | CHECK ∈ free/pro — Kushol Pro flag read by 08 quotas; set by Super Admin/ops until module 12 billing sets it |
| `plan_expires_at` | `timestamptz` | null | — | NULL = no expiry; read-time check (expired ⇒ treated as free) |
| `last_login_at` | `timestamptz` | null | — | device/audit support |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** CHECKs on role/status/locale; partial unique `phone_e164` WHERE NOT NULL;
partial unique `email` WHERE NOT NULL; CHECK `is_ambassador` ⇒ role='student'; CHECK role ∈
(super_admin, vendor) ⇔ `school_id IS NULL`; CHECK `plan` ∈ free/pro.
**Indexes:** `phone_e164` → OTP login lookup; `email` → password/SSO lookup;
`(school_id, role, status)` → roster + queue counts; `(status)` partial on PENDING → SLA job.

#### `auth_identities` (model `AuthIdentity`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `user_id` | `uuid` | no | — | FK → users ON DELETE CASCADE |
| `provider` | `text` | no | — | CHECK ∈ phone/password/google/github |
| `provider_account_id` | `text` | no | — | oauth `sub`; phone E.164; lowercased email for password |
| `created_at` | `timestamptz` | no | `now()` | |

**Constraints:** UNIQUE `(provider, provider_account_id)`.
**Indexes:** `user_id` → list identities per user; `(provider, provider_account_id)` → SSO login.

#### `otp_codes` (model `OtpCode`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `channel` | `text` | no | `'sms'` | CHECK ∈ sms/email — email OTPs are sent by 06's email channel from `noreply@kusholconnect.com` (HestiaCP SMTP) |
| `phone_e164` | `text` | null | — | target number (channel `sms`) |
| `email` | `citext` | null | — | target address (channel `email`) |
| `purpose` | `text` | no | — | CHECK ∈ login/register/link/reset (`reset` = staff/vendor password reset and first-password set) |
| `code_hmac` | `text` | no | — | HMAC-SHA256(code, `OTP_PEPPER`) |
| `attempts` | `int` | no | `0` | max 3 (service) |
| `expires_at` | `timestamptz` | no | `now()+5 min` | |
| `consumed_at` | `timestamptz` | null | — | set atomically on success |
| `request_ip` | `inet` | null | — | abuse analysis |
| `created_at` | `timestamptz` | no | `now()` | |

**Constraints:** CHECK exactly one of `phone_e164`/`email`, matching `channel`.
**Indexes:** `(phone_e164, created_at DESC)` and `(email, created_at DESC)` (partial, non-null) → hourly cap count + latest-code lookup; partial on
`consumed_at IS NULL AND expires_at > now()` → active-code check.

#### `sessions` (model `Session` — web http-only)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `user_id` | `uuid` | no | — | FK → users ON DELETE CASCADE |
| `token_hash` | `text` | no | — | SHA-256 of opaque cookie token; UNIQUE |
| `device_label` | `text` | null | — | UA-derived |
| `ip` | `inet` | null | — | last seen |
| `last_seen_at` | `timestamptz` | no | `now()` | sliding touch |
| `expires_at` | `timestamptz` | no | `now()+30 d` | |
| `created_at` | `timestamptz` | no | `now()` | |

**Indexes:** `token_hash` (unique) → per-request lookup; `(user_id, expires_at)` → device list +
logout-all; `(expires_at)` partial → cleanup job.

#### `refresh_tokens` (model `RefreshToken` — mobile)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `user_id` | `uuid` | no | — | FK → users ON DELETE CASCADE |
| `family_id` | `uuid` | no | — | rotation family (set at login) |
| `token_hash` | `text` | no | — | SHA-256; UNIQUE |
| `rotated_from_id` | `uuid` | null | — | previous token in family |
| `revoked_at` | `timestamptz` | null | — | single-use marker |
| `revoked_reason` | `text` | null | — | rotated/reuse_detected/logout/logout_all/status_change |
| `device_label` | `text` | null | — | app-reported |
| `expires_at` | `timestamptz` | no | `now()+30 d` | |
| `created_at` | `timestamptz` | no | `now()` | |

**Indexes:** `token_hash` (unique) → refresh lookup; `family_id` → revoke-family;
`(user_id, revoked_at)` → device list.

#### `verification_requests` (model `VerificationRequest`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `user_id` | `uuid` | no | — | FK → users; ≤1 open (partial unique) |
| `school_id` | `uuid` | no | — | Loose ref → schools (FK added by 04, see `users.school_id`); denormalized for queue scope |
| `requested_section_id` | `uuid` | null | — | Loose ref → sections (FK added by 04). The registration-time section choice (student/guardian/teacher); read by 04 `OnUserVerified` via `users.GetWithSelection`. Class level is derived from the section — there is no separate class entity |
| `requested_role` | `text` | no | — | snapshot of user role |
| `evidence` | `jsonb` | null | — | e.g. guardian: `{studentCode, relation}` — proof only; the durable link is `guardian_links` |
| `status` | `text` | no | `'PENDING'` | CHECK ∈ PENDING/APPROVED/REJECTED/CANCELLED |
| `decided_by` | `uuid` | null | — | FK → users (verifier) |
| `decision_reason` | `text` | null | — | required on reject |
| `decided_at` | `timestamptz` | null | — | |
| `reminder_count` | `int` | no | `0` | SLA reminders sent |
| `last_reminder_at` | `timestamptz` | null | — | |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** partial unique `user_id` WHERE `status='PENDING'`; CHECK
`status='REJECTED'` ⇒ `decision_reason IS NOT NULL`.
**Indexes:** `(school_id, status, created_at)` → admin/ambassador queue; `(status, created_at)`
→ SLA reminder scan.

#### `guardian_links` (model `GuardianLink`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | tenant scope (loose ref → schools; FK added by 04) |
| `guardian_user_id` | `uuid` | no | — | FK → users (role guardian) |
| `student_user_id` | `uuid` | no | — | FK → users (role student) |
| `relation` | `text` | no | — | CHECK ∈ father/mother/other |
| `status` | `text` | no | `'ACTIVE'` | CHECK ∈ ACTIVE/REVOKED |
| `source` | `text` | no | — | CHECK ∈ VERIFICATION/ROSTER (14) |
| `verified_by` | `uuid` | null | — | FK → users (approver); NULL for ROSTER |
| `created_at` / `revoked_at` | `timestamptz` | no / null | `now()` / — | |

**Constraints:** partial unique `(guardian_user_id, student_user_id)` WHERE `status='ACTIVE'`;
guardian and student must share `school_id` (service-enforced + test).
**Indexes:** `(guardian_user_id, status)` → "my children" (12 fee entitlement); `(student_user_id, status)`
→ guardians of a student (05 guardian reach, 12 notices).
Written in the same tx as a guardian approval: the approver confirms which student the evidence
matched (`studentUserId` on the approve request). A guardian may link to 1..n students.

Tenant scope: `users`, `verification_requests`, `guardian_links` carry `school_id` directly;
`sessions`, `refresh_tokens`, `auth_identities` scope through the owning user; `otp_codes` are
pre-auth (phone/IP scoped). Unscoped queries on tenant-owned tables are a defect.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20261001090000_create_users` | ✅ |
| 2 | `20261001090005_create_auth_identities` | ✅ |
| 3 | `20261001090010_create_otp_codes` | ✅ |
| 4 | `20261001090015_create_sessions` | ✅ |
| 5 | `20261001090020_create_refresh_tokens` | ✅ |
| 6 | `20261001090025_create_verification_requests` (incl. `requested_section_id`) | ✅ |
| 7 | `20261001090030_create_guardian_links` | ✅ |

No FK to 04 tables here: 03 is built and migrated before 04 exists. 04's migration
`20261002090007_add_identity_hierarchy_fks` adds `users.school_id`, `verification_requests.school_id`,
`verification_requests.requested_section_id` and `guardian_links.school_id` FKs.

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| Bootstrap Super Admin (phone/email from env, argon2id password) | `DRAFT` — `TODO: Confirm` contact details with Rahul | `IDT-BE-032` one-off CLI; never a public signup path |
| Dev-only demo accounts for "Demo High School" (fictional, marked as such) | `DRAFT` | `brd.md`/seed conventions; excluded from prod builds |

---

## 2. Server Contracts

### Endpoint `POST /api/v1/auth/register` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | public + OTP code in payload; rate-limit class `auth` |
| **Input** | `{locale, role, fullName, phone, otpCode, schoolId, sectionId, studentCode?, relation?, email?, password?}` (no `classId` — class level comes from the section) — contract validator; hierarchy placement re-validated server-side against 04 reads |
| **Result** | `201 {data:{user, accessToken?, refreshToken?, verificationRequest}}` — tokens only when phone OTP completed |
| **Errors** | `VALIDATION_FAILED` · `CONFLICT` (phone/email taken, hierarchy mismatch) · `RATE_LIMITED` · `INTERNAL` |
| **Rate limit** | `auth`: 10/hour/IP |
| **Audit** | `user.registered` |
| **Stories** | `IDT-US-001` `IDT-US-002` `IDT-US-013` |

### Endpoint `POST /api/v1/auth/otp/request` · `…/otp/resend` · `…/otp/verify`

| | |
| --- | --- |
| **Auth** | public; class `auth` |
| **Input** | request/resend: `{phone | email, purpose: login|register|link}` · verify: `{phone | email, otpCode, purpose}` — `phone` is the primary path for students/guardians; `email` is available to any user with a verified email on file (staff and vendors; students/guardians only as a fallback when SMS is delayed) |
| **Result** | request/resend: `202 {data:{sentAt, cooldownSeconds, channel}}` — identical response whether or not the phone/email is registered; email codes are enqueued to 06 `notify.SendEmail` with priority (no batching) · verify: `200 {data:{accessToken, refreshToken, user}}` (or `{status:"unknown_phone"}` → register; register/link purposes mark the code verified for the follow-up call) |
| **Errors** | `VALIDATION_FAILED` (wrong/expired/attempts-exhausted — one generic message) · `RATE_LIMITED` (60 s cooldown; 5/hour per phone or email; 200/hour/IP — high because Bangladeshi carriers share IPs (CGNAT) and whole schools register from one Wi-Fi, so per-target caps are the primary control; 3 attempts/code; 10 verifies/hour per target) · `INTERNAL` |
| **Rate limit** | `auth` (sub-caps left) |
| **Audit** | `user.login` on token issue (first-of-device flagged); request/resend metrics only |
| **Stories** | `IDT-US-001` `IDT-US-003` |

### Endpoint `POST /api/v1/auth/login/password`

| | |
| --- | --- |
| **Auth** | public; class `auth` |
| **Input** | `{email, password, deviceLabel?}` |
| **Result** | `200 {data:{user, accessToken?, refreshToken?, sessionSet}}` — web gets the http-only session cookie; app gets tokens; `PENDING` users still get a session (pending screen) |
| **Errors** | `UNAUTHENTICATED` (generic, enumeration-safe) · `VALIDATION_FAILED` · `RATE_LIMITED` (10/hour/account, 100/hour/IP) |
| **Rate limit** | `auth` |
| **Audit** | `user.login` (success; failures counted, not audited) |
| **Stories** | `IDT-US-004` `IDT-US-013` |

### Endpoint `POST /api/v1/auth/password/forgot` · `POST /api/v1/auth/password/reset`

| | |
| --- | --- |
| **Auth** | public; class `auth` |
| **Input** | forgot: `{email}` · reset: `{email, otpCode, newPassword}` (argon2id policy: ≥ 10 chars, not in a breached/common list) |
| **Result** | forgot: `202` always (enumeration-safe) — if the email belongs to a staff/vendor account, a 6-digit `reset` OTP is emailed from `noreply@` (bn + en, 5-min TTL) · reset: `204`; password updated, **all sessions + refresh families revoked** (`sessions.InvalidateForUser`) |
| **Errors** | `VALIDATION_FAILED` (bad/expired code, weak password — one generic code message) · `RATE_LIMITED` (5/hour/email, 100/hour/IP) |
| **Rate limit** | `auth` |
| **Audit** | `user.password_reset` |
| **Stories** | `IDT-US-015` (staff forgot password) · vendor first-password set after 07 approval (`users.CreateVendorLogin` triggers a `reset` OTP email) |

### Endpoint `POST /api/v1/auth/refresh`

| | |
| --- | --- |
| **Auth** | public (refresh token in body); class `auth` |
| **Input** | `{refreshToken}` |
| **Result** | `200 {data:{accessToken, refreshToken}}` — old token revoked (`rotated`), new one same family; claims re-read from DB (fresh role/status/locale) |
| **Errors** | `UNAUTHENTICATED` (invalid/expired; reuse ⇒ family revoked + audit `auth.refresh_reuse`) · `VALIDATION_FAILED` |
| **Rate limit** | `auth` |
| **Audit** | reuse detection only |
| **Stories** | `IDT-US-003` `IDT-BR-012` |

### Endpoint `POST /api/v1/auth/logout` · `POST /api/v1/auth/logout-all`

| | |
| --- | --- |
| **Auth** | authenticate; class `auth` |
| **Input** | `{refreshToken?}` (app) / cookie (web) |
| **Result** | `204` — logout kills the current session + refresh token; logout-all kills every session + family of the user |
| **Errors** | `UNAUTHENTICATED` |
| **Rate limit** | `auth` |
| **Audit** | `user.logout_all` |
| **Stories** | `IDT-US-012` |

### Endpoint `GET /api/v1/auth/google/start` + `/api/v1/auth/google/callback` · `GET /api/v1/auth/github/*`

| | |
| --- | --- |
| **Auth** | public; class `auth` |
| **Input** | start: `?intent=login|link` + signed `state` (+ PKCE); callback: provider code+state |
| **Result** | 302 redirect to the calling surface (`web /auth/sso/return` or app deep link) with a one-time result code; link-intent requires an authenticated user; new users without hierarchy are redirected to onboarding and created `PENDING` there |
| **Errors** | state mismatch / provider error → redirect with error param (never a raw 5xx page) |
| **Rate limit** | `auth`: 20/hour/IP per provider |
| **Audit** | `auth.sso_linked`, `user.login` (sso) |
| **Stories** | `IDT-US-005` |

### Endpoint `GET /api/v1/me` · `PATCH /api/v1/me`

| | |
| --- | --- |
| **Auth** | authenticate; class `auth` (relaxed: 60/min/user) |
| **Input** | PATCH: `{locale?, fullName?, avatarUrl?}` — locale switch persists to `users.locale` |
| **Result** | `{data:{user}}` (id, role, status, locale, schoolId, maskedPhone) |
| **Errors** | `UNAUTHENTICATED` · `VALIDATION_FAILED` · `FORBIDDEN` (attempted role/status change) |
| **Rate limit** | `auth` |
| **Audit** | no |
| **Stories** | `IDT-US-011` |

### Endpoints `GET /api/v1/verification-requests` · `POST /api/v1/verification-requests/{id}/approve` · `…/{id}/reject` · `GET /api/v1/school/users`

| | |
| --- | --- |
| **Auth** | authenticate → role claims → tenant-scope; class `auth`. List/approve: school_admin (own school), student+`is_ambassador` (same school, student/guardian requests only, approve-only), super_admin (all). Reject: school_admin/super_admin only (BR-005). Roster: school_admin (own school from claim), super_admin (`?schoolId=`) |
| **Input** | list: `?status=PENDING&role=&cursor=&limit=` · approve: `{}`; guardian requests require `{studentUserId}` (the same-school VERIFIED student the evidence matched → `guardian_links` row in the approve tx) · reject: `{reason}` (10–500 chars, required) · roster: `?role=&status=&q=&cursor=&limit=` |
| **Result** | list: `200 {data:[{id, user{name,role,phoneMasked}, evidence, createdAt, reminderCount}], nextCursor}` · approve: same tx flips `users.status=VERIFIED` (+ inserts `guardian_links` for guardians), then enqueues provisioning (→ 04 `OnUserVerified`); reject stores reason + notifies via 06 · roster: `200 {data:[user], nextCursor}` (names, roles, statuses, masked phones) |
| **Errors** | `FORBIDDEN` (wrong school/role, ambassador reject) · `NOT_FOUND` · `CONFLICT` (already decided) · `VALIDATION_FAILED` · `NOT_VERIFIED` (unverified verifier) · `TENANT_MISMATCH` (roster cross-school) |
| **Rate limit** | `auth`; ambassador approvals additionally capped/day |
| **Audit** | `verification.approved` / `verification.rejected` (verifier, target, reason) |
| **Stories** | `IDT-US-007` `IDT-US-008` `IDT-US-009` `IDT-US-010` |

### Web Server Action / Route Handler (Next.js)

`/login` and `/verification-pending` call the endpoints above through the generated
`openapi-fetch` client with `credentials: include` (session cookie on the shared site domain) and
the `X-CSRF-Token` header on mutations. No web route handler touches the database. Server
middleware reads cookie **presence** for redirects only — every real decision is made by the API.

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `IDT-BE-007` | `phone.Normalize` / `phone.ValidateBdMobile` | E.164 `+880…`; rejects non-BD prefixes | — | — |
| `IDT-BE-008` | `otp.Issue(phone, purpose)` | caps: 60 s cooldown, 5/hour/phone, 20/hour/IP; HMAC storage; enqueues SMS outbox | — | — |
| `IDT-BE-009` | `otp.Verify(phone, code, purpose)` | ≤3 attempts, TTL, atomic consume, constant-time compare | — | — |
| `IDT-BE-010` | `smsout.Deliver` (worker step) | outbox rows → gateway call → retry ×5 backoff → `failed` state + metric | — | — |
| `IDT-BE-011` | `auth.Register` | one tx: user + auth_identities + verification_request; hierarchy placement via 04 interface; staff email+password path (argon2id) | `verification:queue:{schoolId}` | `user.registered` |
| `IDT-BE-012` | `auth.LoginPassword` | argon2id verify; enumeration-safe generic error + dummy-verify timing; user status respected | `auth:me` | `user.login` |
| `IDT-BE-013` | `token.IssueAccess / Rotate / DetectReuse` | 15-min JWT claims from DB; single-use rotation; reuse ⇒ revoke family + audit | `auth:me` | `auth.refresh_reuse` |
| `IDT-BE-014` | `session.Create / GetByHash / Revoke / RevokeAllForUser` | new session per login (fixation); SHA-256 storage; Redis cache w/ invalidation | `session:{hash}`, `auth:me` | logout-all |
| `IDT-BE-015` | `sso.Google / sso.GitHub` | signed state + PKCE; link-on-verified-email; never sets VERIFIED; link-intent guard | `auth:me` | `auth.sso_linked` |
| `IDT-BE-016` | `verification.List / Approve / Reject` | BR-005 matrix; one tx (request + status); enqueue provisioning job; reject requires reason; notify via 06 | `verification:queue:{schoolId}`, `status:{userId}`, `auth:me` | approved/rejected |
| `IDT-BE-017` | `auth.Authenticate / RequireRole / RequireVerified` middleware | chain: authenticate → role claims → tenant-scope → role → verified (DB-authoritative status, Redis 30 s) | `status:{userId}` | — |
| `IDT-BE-018` | `users.GetMe / PatchMe` | locale persist; role/status immutable here | `auth:me` | — |
| `IDT-BE-019` | `users.Suspend / Reinstate` | BR-007: revoke sessions + refresh families + invalidate status cache | `status:{userId}`, `auth:me`, `school:users:{id}` | suspended/reinstated |
| `IDT-BE-020` | `audit.Emit` helper | redacted actor/target payloads for all BR-010 events | — | — |
| `IDT-BE-032` | `bootstrap.CreateSuperAdmin` (one-off CLI) | env credentials; refuses if a super_admin exists | — | `user.registered` |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `IDT-BE-022` | `users.Insert / GetByPhone / GetByEmail / UpdateLocale / UpdateStatus` | point lookups + updates | unique phone/email; PK |
| `IDT-BE-023` | `users.ListBySchool(role, status, q, cursor)` | tenant-filtered page | `(school_id, role, status)` |
| `IDT-BE-024` | `otp.Insert / CountRecent(phone, since) / GetActiveLatest / Consume` | cap counter + atomic `UPDATE … WHERE consumed_at IS NULL AND attempts < 3 AND expires_at > now() RETURNING` | `(phone_e164, created_at DESC)` |
| `IDT-BE-025` | `sessions.Insert / GetByHash / Touch / DeleteByUser / DeleteExpired` | hash lookup; batch revoke | `token_hash`; `(user_id, expires_at)` |
| `IDT-BE-026` | `refresh.InsertFamily / Rotate / GetByHash / RevokeFamily / ListByUser` | single-use tx: revoke old + insert new | `token_hash`; `family_id` |
| `IDT-BE-027` | `verif.Insert / ListBySchool(status, cursor) / Decide / CountOpenForUser` | tenant-filtered queue; partial-unique respected | `(school_id, status, created_at)` |
| `IDT-BE-028` | `verif.ListPendingOlderThan(threshold)` | SLA job scan | `(status, created_at)` |

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `IDT-BE-029` | `verification-sla-reminder` | hourly; PENDING requests older than SLA | ✅ (`last_reminder_at` guard; daily repeat) | send failure → retry next tick; reminder via 06 |
| `IDT-BE-030` | `otp-outbox-retry` | every minute; queued SMS | ✅ (outbox state machine) | ×5 backoff → `failed` + metric + alert |
| `IDT-BE-031` | `provision-verified-user` | enqueued by approve | ✅ (job row per user; 04 call idempotent by contract) | ×5 retry → alert; user status stays VERIFIED |
| — | `session-refresh-cleanup` | daily | ✅ | deletes expired rows (housekeeping, no alert) |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `IDT-UT-001` | BD phone normalization table (valid/invalid/edge prefixes) | Unit | `validation.phone.invalid` contract |
| `IDT-UT-002` | OTP HMAC storage + constant-time compare + attempt counter logic | Unit | BR-003 mechanics |
| `IDT-UT-003` | JWT issue/verify round-trip, expiry, wrong-aud rejection, claim refresh on rotation | Unit | token contract |
| `IDT-UT-004` | Refresh rotation state machine incl. reuse ⇒ family revoke | Unit | BR-012 |
| `IDT-UT-005` | Password login: identical error body + timing bucket for unknown user vs wrong password | Unit | enumeration safety |
| `IDT-UT-006` | Role/verified guard matrix (6 roles incl. vendor × route classes × statuses) | Unit | BR-001/BR-002/BR-005 |
| `IDT-UT-007` | CSRF double-submit accept/reject paths | Unit | web mutation safety |
| `IDT-IT-001` | **OTP flow**: issue → verify → expiry → 3-attempt death → cooldown → hourly cap | Integration (testcontainers Postgres + fake gateway) | BR-003 end-to-end |
| `IDT-IT-002` | **Refresh rotation + reuse detection** revokes the family; victim re-login works | Integration | BR-012, `INV-4` |
| `IDT-IT-003` | **Cross-tenant read denied**: school_admin B requests school A's queue/roster → `TENANT_MISMATCH`/404, no rows leaked | Integration | BR-011, `INV-6` |
| `IDT-IT-004` | **Unverified user blocked**: valid PENDING token on a participatory probe endpoint → `NOT_VERIFIED`; same token post-approve → allowed | Integration | BR-001 |
| `IDT-IT-005` | **SSO account-link flow**: fake OIDC provider, verified email matches phone-registered user → linked, no duplicate; unverified email → refused | Integration | BR-006, `US-005` |
| `IDT-IT-006` | Register golden path: tx creates user PENDING + request row; wrong hierarchy → `CONFLICT` | Integration | `US-001` |
| `IDT-IT-007` | Approve → status VERIFIED + provisioning job enqueued + audit row + status-cache invalidated | Integration | `US-007` |
| `IDT-IT-008` | Ambassador scope: same-school student OK; teacher request / other school / reject → `FORBIDDEN` | Integration | BR-005, `US-008` |
| `IDT-IT-009` | Suspend revokes sessions + refresh families; suspended login refused; reinstate works | Integration | `US-010`, BR-007 |
| `IDT-IT-010` | Rate limits: 60 s resend cooldown, 5/hour/phone, password attempt caps → `RATE_LIMITED` | Integration (Redis + DB fallback) | BR-003 |

Mandatory coverage included: unauthenticated denial per protected endpoint (UT-006 matrix), field
validation rejection (UT-001 + contract validators), cross-tenant denial for every tenant-scoped
table (IT-003), verified-gate enforcement (IT-004).

## 7. Task Checklist

### Schema

- [ ] `IDT-BE-001` `users` migration + constraints + indexes
- [ ] `IDT-BE-002` `auth_identities`
- [ ] `IDT-BE-003` `otp_codes`
- [ ] `IDT-BE-004` `sessions`
- [ ] `IDT-BE-005` `refresh_tokens`
- [ ] `IDT-BE-006` `verification_requests`
- [ ] `IDT-BE-006a` `guardian_links`

### Repository · Service · Entry points · Seed · Tests

- [ ] `IDT-BE-007`–`BE-010` phone/otp/sms services + outbox worker
- [ ] `IDT-BE-011` register service (+ staff password path) · `IDT-BE-012` password login (enumeration-safe)
- [ ] `IDT-BE-013` token service (JWT + rotation + reuse detection) · `IDT-BE-014` session service (cookie flags, CSRF, fixation)
- [ ] `IDT-BE-015` Google + GitHub OIDC services · `IDT-BE-016` verification service (list/approve/reject + provisioning enqueue)
- [ ] `IDT-BE-017` middleware chain (authenticate/role/tenant/verified) · `IDT-BE-018` `/me` handlers
- [ ] `IDT-BE-019` suspend/reinstate · `IDT-BE-020` audit helper wiring
- [ ] `IDT-BE-021` OpenAPI `securitySchemes` + route registration for all §2 endpoints
- [ ] `IDT-BE-022`–`BE-028` sqlc repositories
- [ ] `IDT-BE-029`–`BE-031` jobs (SLA reminder, OTP retry, provisioning) + cleanup
- [ ] `IDT-BE-032` bootstrap Super Admin CLI (env; `TODO: Confirm` contacts)
- [ ] `IDT-BE-033` `guardian_links` migration + repository + `guardians.*` exports (written in the guardian approve tx)
- [ ] `IDT-BE-035` email OTP channel (`otp_codes.channel/email`, `reset` purpose) + forgot/reset endpoints; OTP emails via 06 `notify.SendEmail`
- [ ] `IDT-BE-034` `users.GetWithSelection`, `users.UpsertRosterUser`, `users.SetPlan`, `users.CreateVendorLogin`, `verification.PendingCount` exports (see `06-integration-tasks.md` §2)
- [ ] `IDT-UT-001`–`007` unit tests green in CI · `IDT-IT-001`–`010` integration tests green on testcontainers Postgres

# Identity & Access — User Stories

**Module:** `03-identity-access` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

---

## 1. Purpose

Module 03 is the trust gateway of Kushol Connect. It registers and authenticates every user across
the five end-user roles (Super Admin, School Admin, Teacher, Student, Guardian) plus the platform-scoped `vendor` portal login (created only by 07 vendor approval) via phone OTP (local SMS
gateway), email+password (staff, argon2id) and Google/GitHub SSO, then runs the verification
workflow (`PENDING → VERIFIED`) that `prd.md` §5.1 makes mandatory before anyone participates. It
serves `brd.md` §2 Goal 1 (20,000+ onboard users in year 1): no post, message, purchase or AI call
exists for an unverified account.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Visitor (no account) | Picks language (bn default), registers via phone OTP / staff password / SSO |
| Unverified user (PENDING) | Owns an account + session; sees only the pending explainer — every participatory route answers `NOT_VERIFIED` |
| Student | Registers into city → school → class → section; may hold the Student Ambassador flag; verifies same-school peers |
| Guardian | Registers against the child's school + class + student ID; verified like students |
| Teacher | Registers (email+password or phone); waits for School Admin approval; governs classes after (module 05) |
| School Admin | Approves/rejects own school's requests, views own roster, suspends/reinstates own users, grants/revokes ambassador flags |
| Super Admin | Platform scope (`school_id NULL`): bootstrap account, verifies the first School Admin with module 04, suspends anyone |
| System (jobs, webhooks) | 48 h SLA reminders, OTP outbox retries, session/token cleanup, provisioning hand-off to module 04 |

Student Ambassador is **a flag on a verified student** (`users.is_ambassador`), not a sixth role.

## 3. Scope

**In scope**

- Data model owned here: `users`, `auth_identities`, `otp_codes`, `sessions`, `refresh_tokens`, `verification_requests`
- Registration (language → role → hierarchy → contact → OTP → `PENDING`, incl. guardian link evidence)
- Login paths: phone OTP, staff email+password (argon2id), Google/GitHub OIDC; logout / logout-all
- Tokens & sessions: 15-min access JWT + rotating refresh (mobile), http-only server-side session (web)
- Verification workflow API + approve/reject + ambassador verification + 48 h SLA reminder job; role guards middleware (authenticate → role claims → tenant scope → verified gate, server-side)
- Web `/login` + `/verification-pending`; app onboarding stack, pending gate, settings; bn/en strings in each app's `src/i18n` (`auth.*`, `verification.*`, `validation.*`)

**Out of scope** (explicit — prevents scope drift)

- City/school/class/section data and tenant CRUD; `OnUserVerified` provisioning internals — module 04
- School Admin verification **queue UI** (`/school/users`) — built in 07-command-center-web
- Push delivery infrastructure (06) · roster CSV upload/matching (14) · participation features (05/08/10/11)

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 01 foundations | RFC-7807 error envelope, `audit_log`, jobs table + worker, config parsing, test harness |
| 02 design-system | tokens, RN + web primitives, bn/en catalog machinery |
| 04 organization-hierarchy (read-only) | hierarchy reads + `OnUserVerified` — consumed behind an interface (`06` §3) so 03 builds/tests with fakes before 04 lands |

---

## 4. User Stories

### `IDT-US-001` — Student registers with phone OTP

**Priority:** P0 · **Traces:** BR-01 (`brd.md` §5), PRD §5.1, `prompt.txt` §2 #3 · **Depends on:** —

**Story** — As a **student**, I want to choose my language, class and section and verify my phone with a 6-digit OTP, so that my account is bound to my exact class group and queued for school verification.

**Acceptance criteria**

- **Given** I complete language → role → city → school → class+section with a valid Bangladeshi phone, **when** I tap "send code", **then** a 6-digit OTP arrives by SMS within seconds and is valid 5 minutes.
- **Given** I submit the correct code in time, **when** registration finishes, **then** my account exists `PENDING`, my locale is saved, a `verification_requests` row sits in my school's queue, and I land on the "what happens now" screen.
- **Given** I mistype 3 times, **when** I retry, **then** the code is dead; resend waits 60 s and is capped at 5 codes/hour/phone (`RATE_LIMITED` beyond).

### `IDT-US-002` — Guardian registers and links to their child

**Priority:** P0 · **Traces:** PRD §5.1, §5.3 · **Depends on:** `IDT-US-001`

**Story** — As a **guardian**, I want to register against my child's school, class and student ID, so that the school verifies I belong to that child before I see any notice or chat.

**Acceptance criteria**

- **Given** I pick role "Guardian", **when** the contact step renders, **then** my phone plus the student's school, class and student ID are required before an OTP can be sent.
- **Given** I verify my phone, **when** registration completes, **then** the link evidence is stored on my request row, my account is `PENDING`, and a roster mismatch keeps me in the admin queue (never auto-approved).

### `IDT-US-003` — Returning user logs in with phone OTP

**Priority:** P0 · **Traces:** `prompt.txt` §9 · **Depends on:** `IDT-US-001`

**Story** — As a **student or guardian**, I want to log in with just my phone number and an OTP, so that I never manage a password on a low-end phone.

**Acceptance criteria**

- **Given** my verified phone, **when** I request a login OTP and enter the correct code, **then** I receive tokens (app) or a session cookie (web) and land on `/(tabs)`.
- **Given** a `SUSPENDED` account or an exhausted 5/hour/phone cap, **when** I attempt login or resend, **then** no tokens are issued — the bilingual suspension message, or `RATE_LIMITED` with a countdown, identical whether or not the phone is registered.

### `IDT-US-004` — Staff logs in with email and password

**Priority:** P0 · **Traces:** `prompt.txt` §9 · **Depends on:** —

**Story** — As a **teacher or school admin**, I want to log in with email and password, so that my staff account works without a phone-OTP flow.

**Acceptance criteria**

- **Given** correct staff credentials (argon2id), **when** I submit, **then** I get a session (web) or tokens (app) — and while `PENDING`, only the pending explainer.
- **Given** a wrong password **or** unknown email, **when** I submit, **then** I get the identical generic error at near-identical latency (no enumeration), with 10/hour/account and 30/hour/IP caps.

### `IDT-US-005` — Sign in with Google or GitHub

**Priority:** P0 · **Traces:** `tech-stack.md` (Auth row), `prompt.txt` §9 · **Depends on:** `IDT-US-006`

**Story** — As a **teacher**, I want to sign in with my Google or GitHub account, so that I avoid another password — while the school still verifies me before I participate.

**Acceptance criteria**

- **Given** I finish the OIDC round-trip with no existing account, **when** I return, **then** I pick language/role/hierarchy and my account is created `PENDING` — SSO authenticates, it never verifies.
- **Given** an SSO email matching an existing account with a provider-verified email, **when** I sign in, **then** the identity is linked (no duplicate account); an unverified provider email demands OTP proof instead.

### `IDT-US-006` — Unverified users are fenced out of everything

**Priority:** P0 · **Traces:** PRD §5.1, `prompt.txt` §2 #3 · **Depends on:** `IDT-US-001`

**Story** — As a **product owner**, I want the verified gate enforced server-side on every participatory route, so that a pending account with a valid token still cannot post, message, buy, sell or call the AI.

**Acceptance criteria**

- **Given** a `PENDING` user with valid tokens, **when** any participatory endpoint is called, **then** the API answers `NOT_VERIFIED` with the explainer link — the UI gate is a convenience, not the enforcement.
- **Given** the app user is `PENDING`, **when** they open any tab, **then** the tabs render the friendly pending status screen; on mid-session verification the gate opens without re-login once the status cache invalidates (≤30 s).

### `IDT-US-007` — School Admin approves a verification request

**Priority:** P0 · **Traces:** PRD §5.1, BR-01 · **Depends on:** `IDT-US-001`

**Story** — As a **school admin**, I want a queue of my school's pending join requests with declared hierarchy, so that I can approve real students and staff with one tap.

**Acceptance criteria**

- **Given** my school's pending requests only, **when** I open the verification queue (07's screen, this module's API), **then** I see name, role, class/section, guardian evidence and requested time — never another school's rows.
- **Given** I approve, **when** the action lands, **then** the user becomes `VERIFIED`, 04's `OnUserVerified` provisioning is enqueued, the requester is notified via 06, and an audit entry records who approved whom; an already-decided request answers `CONFLICT`.

### `IDT-US-008` — Student Ambassador verifies same-school peers

**Priority:** P0 · **Traces:** PRD §3 (Phase 1), PRD §5.1 · **Depends on:** `IDT-US-007`

**Story** — As a **verified Student Ambassador**, I want to verify same-school student and guardian requests, so that onboarding doesn't stall when the admin is busy.

**Acceptance criteria**

- **Given** I hold the ambassador flag and am `VERIFIED`, **when** I list requests, **then** I see only same-school student/guardian requests — teachers/admins never appear.
- **Given** a same-school student request, **when** I approve, **then** the same pipeline as `IDT-US-007` runs with my ID audited as verifier; rejecting, targeting teachers/admins or another school answers `FORBIDDEN`, approvals are daily-capped, and the School Admin can revoke my flag.

### `IDT-US-009` — Reject with reason and resubmit

**Priority:** P1 · **Traces:** PRD §5.1 · **Depends on:** `IDT-US-007`

**Story** — As a **school admin**, I want to reject with a required reason, so that the applicant knows what to fix and can try again cleanly.

**Acceptance criteria**

- **Given** I reject without a 10–500 char reason, **when** I submit, **then** `VALIDATION_FAILED` — reason is mandatory.
- **Given** a rejected user, **when** they next log in, **then** they see the reason (bn/en) and can resubmit a fresh `PENDING` request (one open request per user).

### `IDT-US-010` — Suspend and reinstate an account

**Priority:** P0 · **Traces:** `prompt.txt` §9, `brd.md` §6 · **Depends on:** `IDT-US-007`

**Story** — As a **school admin** (or Super Admin), I want to suspend a misbehaving user, so that they lose all access immediately — sessions included.

**Acceptance criteria**

- **Given** a `VERIFIED` user of my school, **when** I suspend them, **then** status flips to `SUSPENDED`, every session and refresh family is revoked (web instant, app ≤15 min), and an audit entry is written.
- **Given** a suspended user, **when** they attempt login, **then** they see the suspension message; reinstatement returns them to `VERIFIED` with fresh login required.

### `IDT-US-011` — Switch language any time

**Priority:** P0 · **Traces:** `prompt.txt` §2 #6 · **Depends on:** `IDT-US-001`

**Story** — As a **user**, I want Bengali by default with a one-tap switch to English, so that the app speaks my language everywhere, forever.

**Acceptance criteria**

- **Given** onboarding, **when** I first open the app, **then** Bengali is preselected (regardless of device locale) and my choice persists to `users.locale`.
- **Given** I switch in settings, **when** `PATCH /me` lands, **then** every screen re-renders and the next access JWT carries the new `locale` claim.

### `IDT-US-012` — Log out here, everywhere, and see devices

**Priority:** P0 (device list P1) · **Traces:** `prompt.txt` §9 · **Depends on:** `IDT-US-003`

**Story** — As a **user**, I want to log out of one device or all at once, so that a lost phone never means a lost account.

**Acceptance criteria**

- **Given** "log out", **when** I confirm, **then** only the current session/refresh family dies.
- **Given** "log out everywhere", **when** I confirm, **then** every session and family is revoked + audited; the device list (P1) shows device, IP, last-seen and single-device revoke.

### `IDT-US-013` — Teacher registers and waits for verification

**Priority:** P1 · **Traces:** PRD §5.1 · **Depends on:** `IDT-US-004`

**Story** — As a **teacher**, I want to register with my school email and be verified by my School Admin, so that I only get class-governance powers once the school confirms me.

**Acceptance criteria**

- **Given** I register as teacher (email+password, phone optional), **when** registration completes, **then** my account is `PENDING` in my school's queue — ambassadors never see it.
- **Given** I am a `PENDING` teacher, **when** I log in, **then** I see only the pending explainer — no rosters, no moderation tools.

### `IDT-US-014` — 48-hour verification SLA reminder

**Priority:** P1 · **Traces:** PRD §5.1 · **Depends on:** `IDT-US-007`

**Story** — As a **school admin**, I want an automatic reminder when join requests sit unverified for 48 hours, so that students don't silently rot in the queue.

**Acceptance criteria**

- **Given** a request `PENDING` >48 h, **when** the hourly SLA job runs, **then** the school's verifiers get a push/email via module 06 and `reminder_count` increments.
- **Given** a still-undecided request, **when** 24 h pass after a reminder, **then** it repeats daily until decided.

### `IDT-US-015` — Staff/vendor password reset and email OTP

**Priority:** P0 · **Traces:** prompt.txt §5 (auth) · owner decision 2026-09-30 (`noreply@kusholconnect.com` sends OTPs) · **Depends on:** `IDT-US-004`, 06 email channel

**Story** — As a **School Admin, Teacher, Super Admin or vendor**, I want to reset a forgotten password with a code sent to my email, so that I can get back in without calling support.

**Acceptance criteria**

- **Given** any email, **when** I submit "forgot password", **then** I always see the same "if this account exists, we sent a code" message (bn + en) — no account enumeration.
- **Given** a staff/vendor account, **when** the code arrives from `noreply@kusholconnect.com` (bn default + en, subject without personal data, 5-minute validity) and I enter it with a new password, **then** the password changes, every session and refresh token is revoked, and `user.password_reset` is audited.
- **Given** a newly approved vendor, **when** 07 approval calls `users.CreateVendorLogin`, **then** the vendor receives the same email code to set a first password.
- **Given** SMS is delayed and my account has a verified email, **when** I choose "send code by email", **then** a login OTP is emailed with the same limits as SMS (60 s cooldown, 5/hour, 3 attempts).
- **Given** 5 reset requests in an hour for one email, **when** I request again, **then** `RATE_LIMITED` with a countdown.

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `IDT-BR-001` | Unverified (`PENDING`) users participate in nothing — server-side `NOT_VERIFIED` gate on every participatory route (`prd.md` §5.1) | Service/middleware (`RequireVerified`), never UI-only |
| `IDT-BR-002` | `role` ∈ super_admin/school_admin/teacher/student/guardian/vendor (vendor: platform scope, `school_id` NULL, never self-registered); `plan` ∈ free/pro; `status` ∈ PENDING/VERIFIED/SUSPENDED; `locale` ∈ bn/en (bn default) | DB CHECK constraints + service |
| `IDT-BR-003` | OTP: 6 digits, 5-min expiry, max 3 attempts per code, 60 s resend cooldown, 5 codes/hour/phone; hashed at rest | Service + Redis/DB counters |
| `IDT-BR-004` | Phone is the primary identity for students/guardians; E.164-normalized (`+880…`) and unique; email unique; email optional for consumers, required for staff | DB partial unique indexes + service |
| `IDT-BR-005` | Verifier matrix: School Admin → everything in own school; Student Ambassador → same-school student/guardian requests, approve-only; Super Admin → everything | Service (queue + decide guards) |
| `IDT-BR-006` | SSO authenticates, never verifies — Google/GitHub users stay `PENDING` until hierarchy chosen + verifier approves | Service (SSO account creation) |
| `IDT-BR-007` | Status changes (verify/suspend/reinstate) invalidate affected sessions + refresh families; the verified gate reads authoritative DB status (Redis ≤30 s, invalidated on change) | Service + middleware |
| `IDT-BR-008` | Bengali is the default locale for every new account, regardless of device locale | Service (registration default) |
| `IDT-BR-009` | Rejection requires a reason (10–500 chars); ≤1 open request per user; resubmission allowed | DB partial unique + service |
| `IDT-BR-010` | Every approve/reject/suspend/reinstate/logout-all/refresh-reuse event is written to `audit_log` (module 01) | Service |
| `IDT-BR-011` | `super_admin` has `school_id NULL` (platform scope); every other role is tenant-scoped by `school_id` on every query | Repository layer |
| `IDT-BR-012` | Refresh tokens are single-use within a family; presenting a revoked token revokes the whole family (reuse detection) + audit | Service |

No publishable content is seeded here; the bootstrap Super Admin comes from env config
(`TODO: Confirm` contact details — `IDT-BE-032`) and audit rows reference real events only.

## 6. Validation Rules

| Field | Rule | Message key (per-app `src/i18n` catalog) |
| --- | --- | --- |
| phone | Required for student/guardian; `^(?:\+?880\|0)1[3-9]\d{8}$`, normalized to `+8801XXXXXXXXX` | `validation.phone.invalid` |
| phone (staff) | Optional; same format when present | `validation.phone.invalid` |
| otp_code | Exactly 6 digits | `validation.otp.format` |
| password | 10–128 chars; staff registration only | `validation.password.weak` |
| email | RFC-5322, lowercased, unique when present; required for staff | `validation.email.invalid` |
| full_name | 2–80 chars after trim | `validation.name.length` |
| locale | `bn` \| `en`, default `bn` | `validation.locale.invalid` |
| school/class/section | Must exist and be active in module 04 hierarchy data | `validation.hierarchy.invalid` |
| guardian student_code | Required when role=guardian; 3–20 chars | `validation.guardian.studentCode` |
| reject reason | 10–500 chars, required on reject | `verification.reject.reasonRequired` |

Example copy (bn default + en) for the two most important strings:

| Key | Bengali (bn) | English (en) |
| --- | --- | --- |
| `auth.otp.prompt` | আপনার মোবাইলে পাঠানো ৬ সংখ্যার কোডটি লিখুন | Enter the 6-digit code we sent to your mobile |
| `verification.pending.body` | রেজিস্ট্রেশন সম্পন্ন হয়েছে! আপনার স্কুলের অ্যাডমিন বা স্টুডেন্ট অ্যাম্বাসেডর অনুমোদনের পর আপনি চ্যাট, নোটিশসহ সব সুবিধা ব্যবহার করতে পারবেন। সাধারণত এতে ৪৮ ঘণ্টার বেশি লাগে না। | Registration complete! Once your school's admin or a Student Ambassador approves you, chat, notices and everything else open up. This usually takes no more than 48 hours. |

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to a protected action | `UNAUTHENTICATED`, no side effect |
| 2 | School Admin A touches School B's verification request or roster | `TENANT_MISMATCH`/404, no data leaked |
| 3 | Unverified (pending) user hits a participatory endpoint | Refused with `NOT_VERIFIED` + explainer link |
| 4 | SMS gateway down when an OTP is requested | OTP queued with retry; `auth.smsDelayed` shown; SSO/password unaffected |
| 5 | OTP brute-force (3 wrong attempts, scripted resends) | Code dead after 3 attempts, 60 s cooldown, 5/hour/phone then `RATE_LIMITED` |
| 6 | Stolen refresh token replayed after rotation | Reuse detected → whole family revoked + audit; both parties re-login |
| 7 | SSO email collides with an existing phone-registered account | Link only on provider-verified email; otherwise OTP proof; never a second account |
| 8 | Offline OTP submit (app) | Refused with a clear "needs internet" message — never silently lost |
| 9 | Reduced motion enabled | Static forms of every animation (no shake/pulse/slide) |

## 8. Reporting Needs

- Pending vs verified counts per school and platform-wide — consumed by 07 dashboards.
- Median and p90 time-to-verify vs the 48 h SLA; SLA-breach list per school.
- Rejection-reason distribution; OTP delivery failure + resend ratio (SMS vendor ops input).
- Active sessions/devices per user (support + security).

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Student Ambassador criteria and verification SLA? | Rahul | Open | Any verified Student Ambassador of the same school may verify same-school join requests; SLA 48 h with auto-reminder (via 06-notifications) |
| 2 | SMS gateway vendor for OTP delivery? | Rahul | Open | SSLWireless-class local gateway (`TODO: Confirm` vendor + contract); integrated behind `SMS_GATEWAY_*` env vars |
| 3 | How is guardian↔student linking proven? | Rahul | Open | Guardian enters student's school + class + student ID; School Admin approves in the verification queue; module 14 roster upload enables automatic matching later |
| 4 | Registrable domain shared by web + api (session cookie scope)? | Rahul | **Resolved 2026-09-30** | Domain `kusholconnect.com`. Web on the apex; browser API calls go same-origin via `kusholconnect.com/api/*` (Nginx → api), so the web session cookie is a host-only `__Host-` cookie on the apex (no Domain attribute, no CORS). Mobile uses `api.kusholconnect.com` with bearer JWT + refresh tokens (no cookies) |

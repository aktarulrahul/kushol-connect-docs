# Identity & Access — Frontend Tasks

**Module:** `03-identity-access`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Motion · Embla · RHF + Zod
**Last updated:** 2026-09-30

---

## 1. Screen Inventory

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/login` | Login (bn-default) | Server shell + Client island | Public |
| 2 | `/verification-pending` | Pending-verification status | Client Component | Authenticated (`PENDING`) |
| 3 | `/auth/sso/return` | SSO return landing | Client Component | Public — routing flow lives in `SsoButtons` (§2.1) |
| 4 | `/school/users` | Verification queue | — | **Built by 07-command-center-web** (consumes this module's APIs; layout is specified there, not here) |

## 2. Screen Breakdown

### 2.1 `Login` — `/login`

**Layout**

```text
┌──────────────────────────────────┐
│ কুশল CONNECT          [বাং | EN] │
│ লগইন করুন                        │
│ ┌──────────────┬───────────────┐ │
│ │ ফোন OTP      │ পাসওয়ার্ড      │ │
│ └──────────────┴───────────────┘ │
│ মোবাইল নম্বর                      │
│ ┌──────────────────────────────┐ │
│ │ +880                         │ │
│ └──────────────────────────────┘ │
│ ┌──────────────────────────────┐ │
│ │        OTP পাঠান             │ │
│ └──────────────────────────────┘ │
│ ────── অথবা ──────               │
│ [ G Google দিয়ে ] [ GitHub দিয়ে ] │
└──────────────────────────────────┘
(≥1024px: brand value copy (bn-first) beside this card; OTP sent → 6 auto-advance
 boxes, resend countdown, delayed-SMS notice)
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `LanguageToggle` | Client | bn default; persists via `PATCH /me` post-login, cookie pre-login |
| `LoginTabs` | Client | Phone OTP (default) / Password (staff) |
| `PhoneOtpForm` / `PasswordForm` | Client | RHF + zod from each app's `src/schemas`; OTP boxes auto-advance |
| `SsoButtons` | Client | open `/api/v1/auth/google/start` · `/auth/github/start`; on return, `/auth/sso/return` calls `GET /me` then routes `PENDING` → `/verification-pending`, `VERIFIED` staff → role shell, error → `/login` with `auth.ssoFailed` |
| `PendingNotice` | Client | inline notice when a fresh login is `PENDING` → routes to `/verification-pending` |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton on the card; button spinners only |
| OTP sent | Six input boxes focus + countdown "আবার পাঠান ৬০s"; `auth.otp.sent` banner |
| Invalid / expired OTP | `validation.otp.format`/generic invalid message; inputs clear, focus first; 3rd failure offers resend |
| Rate limited / SMS delayed | `auth.rateLimited` countdown with resend disabled; `auth.smsDelayed` banner after 15 s without delivery |
| Pending verification | Success → `/verification-pending` (see 2.2) |
| Suspended / Error | `auth.suspended` message + contact-school hint (no session UI) · problem+json boundary with retry + request id |
| Success | Staff/admin → role shell (07); consumers on web → pending or account home |

### 2.2 `Verification pending` — `/verification-pending`

**Layout**

```text
┌──────────────────────────────┐
│ ✓ রেজিস্ট্রেশন সম্পন্ন হয়েছে      │
│   অ্যাকাউন্ট যাচাই চলছে          │
│ ১. তথ্য স্কুল ভেরিফায়ারের কাছে    │
│ ২. অনুমোদনে পুশ নোটিফিকেশন      │
│ ৩. ক্লাস গ্রুপে স্বয়ংক্রিয় যুক্ত     │
│ ⏱ সাধারণত ৪৮ ঘণ্টার মধ্যে        │
│        [ লগআউট ]              │
└──────────────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `PendingSteps` | Client | `verification.pending.*` steps bn+en; screen-reader ordered list |
| `LogoutButton` | Client | `POST /auth/logout` → `/login` |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Steps skeleton |
| Rejected | Shows `decision_reason` (bn/en) + "fix & resubmit" → onboarding contact step |
| Verified mid-view | Poll/mutation notices status flip → routes onward |
| Error | Retry with request id |

### 2.3 `SSO return` — `/auth/sso/return`

A bare landing route: consumes the one-time result code, calls `GET /me`, routes per the
`SsoButtons` note in §2.1. States: loading (branded spinner) · success (auto-route) · error
(message + back-to-login). No queue layout duplicated here.

## 3. Forms

| Field | Control | Zod rule | Default | Conditional on |
| --- | --- | --- | --- | --- |
| phone | tel input + `+880` prefix | `validation.phone.*` (shared schema) | bn keypad hint | always (OTP tab) |
| otp_code | 6 boxed inputs, numeric | `validation.otp.format` | — | OTP requested |
| email · password | email input · password input | `validation.email.invalid` · `validation.password.weak` | — | Password tab |
| locale | segmented toggle | `validation.locale.invalid` | `bn` | always |

Submission: same Zod schema server-side · disable while pending · map problem+json `errors.fields`
· never lose input · leave-guard on `/login` once OTP is sent.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| OTP request/verify, password login | Client island → generated `openapi-fetch` client (`credentials: include`) → api |
| Session establishment | api sets the http-only session cookie on the shared site domain (`OQ-4`); web never sees the token |
| `/me` reads · mutations | TanStack Query (`auth:me`, no-store) · `X-CSRF-Token` double-submit header on every POST/PATCH |
| Redirects only | `middleware.ts` checks cookie presence for `/admin\|/school\|/vendor` — real authorization is always the API's |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Tab switch (OTP/password) | 150 ms cross-fade | tab change | context switch | instant swap |
| Invalid OTP | 2× horizontal shake, 200 ms | verify failure | error location | static red border + message |
| Resend countdown | numeric text only | OTP sent | wait time | same (no pulse) |
| Card entrance | 120 ms fade+rise | route load | arrival | opacity only |

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 | ≥ 1024 |
| --- | --- | --- | --- |
| `/login` | single card, full-width buttons, 16px inputs (no iOS zoom) | centred card, max-w-md | two-panel brand + card |
| `/verification-pending` | single column, thumb-reach logout | centred column | centred, wider steps |

## 7. Accessibility

- [ ] Landmarks, one `h1`, heading order
- [ ] Keyboard path complete; focus visible and never lost (OTP boxes arrow-navigable)
- [ ] Labels, descriptions, error announcements (`aria-live=polite` on OTP + login errors)
- [ ] Contrast in both themes (deep-teal on paper ≥ 4.5:1)
- [ ] Motion: reduced-motion variant verified

## 8. Design-System Compliance

`docs/design-reference/README.md` usage rules hold (tokens, Hind Siliguri + Inter, logo
clear-space); every string ships in bn + en from the `auth.*` / `verification.*` /
`validation.*` catalogs — no hard-coded copy anywhere on the two screens.

## 9. Task Checklist

- [x] `IDT-FE-001` `/login` route shell + `LanguageToggle` · `IDT-FE-002` `PhoneOtpForm` with all §2.1 states — 2026-10-15
- [x] ~~`IDT-FE-003` `PasswordForm` (staff)~~ — SUPERSEDED 2026-10-02 (owner: passwordless email OTP; password login removed; teacher-registration password = G-1) · `IDT-FE-004` `SsoButtons` + `/auth/sso/return` routing — 2026-10-15
- [x] `IDT-FE-005` `/verification-pending` screen incl. rejected state · `IDT-FE-006` csrf + credentials-inclusive client; cookie-presence middleware — 2026-10-15
- [x] `IDT-FE-007` problem+json → field errors + `RATE_LIMITED` countdown mapping · `IDT-FE-008` bn/en keys wired from each app's `src/i18n` — 2026-10-15
- [ ] `IDT-FE-009` axe pass + reduced-motion verification on both screens
- [ ] `IDT-FE-010` hand-off note + contract reference for 07's `/school/users` queue (no layout duplicated)

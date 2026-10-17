# Identity & Access — App Tasks (Mobile)

**Module:** `03-identity-access`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

> **Visual direction (owner, 2026-09-30):** onboarding carousel, login/register, OTP (6 boxes) and
> success modals follow the CircleUp auth layouts in Kushol teal — `docs/design-reference/README.md` §6.1.

---

## 1. Screen Inventory

| # | Route (expo-router) | Screen | Access | Deep link source |
| --- | --- | --- | --- | --- |
| 1 | `/onboarding/language` | Language pick (bn default) | Public | none |
| 2 | `/onboarding/role` | Role pick | Public | none |
| 3 | `/onboarding/hierarchy` | City → School → Class → Section picker | Public | none |
| 4 | `/onboarding/contact` | Phone (+ guardian link) | Public | none |
| 5 | `/onboarding/otp` | OTP verify | Public | none |
| 6 | `/onboarding/sso` | Google/GitHub sign-in | Public | none |
| 7 | `/onboarding/pending` | "What happens now" gate | Authenticated `PENDING` | none |
| 8 | `/(tabs)/_layout` | Verified-only gate around all tabs | `VERIFIED` (else renders screen 7) | push (approval via 06) |
| 9 | `/settings` | Language, logout, devices (P1) | Authenticated | none |

School Admin / Super Admin day-to-day work lives on web (07); the app offers no admin surfaces.

## 2. Screen Breakdown

### 2.1 `Language + Role` — `/onboarding/language`, `/onboarding/role`

**Layout**

```text
┌─ 360px ─────────────────────┐    ┌─ 360px ─────────────────────┐
│ কুশল CONNECT      [বাং|EN]  │    │ আপনি কে?                    │
│ আপনার ভাষা বাছুন             │    │ ◉ ছাত্র/ছাত্রী               │
│ ◉ বাংলা   ○ English         │    │ ○ অভিভাবক                   │
│                             │    │ ○ শিক্ষক                    │
│ [ ───────────────────────► ]│    │ (অ্যাডমিন? ওয়েব পোর্টাল লিংক)  │
│        [পরবর্তী ▸]          │    │        [পরবর্তী ▸]          │
└─────────────────────────────┘    └─────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `LanguagePicker` | Client | bn preselected regardless of device locale (BR-008) |
| `RolePicker` | Client | student/guardian/teacher; admin → web link; guardian adds link fields later (2.3) |
| `StepProgress` | Client | shared module-02 primitive; back-guard preserves input |

**States**

| State | Behaviour |
| --- | --- |
| Loading | none (local) |
| Error | retry + support path; never a blank screen |
| Success | advances with entered data intact |

### 2.2 `Hierarchy picker` — `/onboarding/hierarchy`

**Layout**

```text
┌─ 360px ─────────────────────┐
│ ‹ ফিরে যান   আপনার স্কুল      │
│ ┌─────────────────────────┐ │
│ │ 🔍 শহর / স্কুল খুঁজুন      │ │  ← one search across city+school
│ └─────────────────────────┘ │
│ ঢাকা ▸                      │
│   ডেমো উচ্চ বিদ্যালয় ▸         │
│     নবম শ্রেণি ▸              │
│       বিভাগ: ক ◉  খ ○        │
│ [ ───────────────────────► ]│
│        [পরবর্তী ▸]          │
└─────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `HierarchySearch` | Client + TanStack Query | data via 04 read functions (interface per `06` §3); SWR 5 min |
| `SectionPicker` | Client | chips, min touch target 44pt |

**States**

| State | Behaviour |
| --- | --- |
| Loading | skeleton rows matching list shape; no blocking spinners |
| Empty | "আপনার স্কুল এখনো যুক্ত হয়নি" + school-signup hint |
| Error | retry + "অফলাইন — পরে চেষ্টা করুন" when offline |
| Success | selection stored in onboarding zustand draft |

### 2.3 `Contact + OTP` — `/onboarding/contact`, `/onboarding/otp`

**Layout**

```text
┌─ 360px ─────────────────────┐    ┌─ 360px ─────────────────────┐
│ মোবাইল নম্বর                 │    │ OTP কোড                      │
│ ┌──+880───────────────────┐ │    │ ┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐   │
│ │ 1XXXXXXXXX              │ │    │ └──┘└──┘└──┘└──┘└──┘└──┘   │
│ └─────────────────────────┘ │    │ আপনার মোবাইলে পাঠানো ৬ সংখ্যার  │
│ (guardian) ছাত্রের ID+শ্রেণি    │    │ কোডটি লিখুন                  │
│ ┌──────────┐ ┌───────────┐ │    │ আবার পাঠান (৬০s)             │
│ │ ID       │ │ শ্রেণি      │ │    │ [ ──────────────────────► ] │
│ └──────────┘ └───────────┘ │    │        [যাচাই করুন]         │
│        [OTP পাঠান]          │    └─────────────────────────────┘
└─────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `PhoneInput` | Client | shared zod `validation.phone.*`; keypad numeric |
| `GuardianLinkFields` | Client | student ID + class, only when role=guardian (`OQ-3` evidence) |
| `OtpBoxes` | Client | auto-advance; paste support; error clears + refocuses |
| `ResendControl` | Client | 60 s countdown; shows `auth.smsDelayed` after 15 s |

**States**

| State | Behaviour |
| --- | --- |
| Loading | button state only; form stays interactive |
| Invalid/expired OTP | generic message after 3 tries → resend offered |
| Rate limited | `auth.rateLimited` + countdown, resend disabled |
| SMS delayed | `auth.smsDelayed` banner; SSO alternative hint |
| Offline | "এর জন্য ইন্টারনেট লাগবে" — auth never queues silently |
| Success | tokens → secure store → route `/onboarding/pending` |

### 2.4 `Pending gate` — `/onboarding/pending` + `/(tabs)/_layout` guard

**Layout**

```text
┌─ 360px ─────────────────────┐
│ ✓ অ্যাকাউন্ট যাচাই চলছে          │
│ এখন কী হবে?                  │
│ ১. তথ্য স্কুল ভেরিফায়ারের কাছে   │
│ ২. অনুমোদনে নোটিফিকেশন পাবেন    │
│ ৩. ক্লাস গ্রুপে স্বয়ংক্রিয় যুক্ত    │
│ ⏱ সাধারণত ৪৮ ঘণ্টার মধ্যে        │
│        [সেটিংস] [লগআউট]      │
└─────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `PendingExplainer` | Client | `verification.pending.*` bn+en; numbered list, reading order |
| `TabsGate` | Client | layout-level check of `auth:me`; `PENDING`/`SUSPENDED` renders this screen instead of tabs |
| `RejectedNotice` | Client | shows `decision_reason` + "fix & resubmit" → contact step |

**States**

| State | Behaviour |
| --- | --- |
| Loading | explainer skeleton |
| Approved (push/deep link or poll) | status refetch → tabs unlock → welcome toast bn+en |
| Rejected | reason + resubmit path |
| Suspended | `auth.suspended` message; session cleared |
| Offline | cached status; banner "স্ট্যাটাস পুরোনো হতে পারে" |

### 2.5 `SSO` — `/onboarding/sso` and `LoginButtons` on `/login` (app side)

Google/GitHub via system browser (expo auth-session), state + PKCE, redirect back through the app
deep link (`kushol://auth/sso`). New SSO users land on `/onboarding/hierarchy` (SSO never
verifies, BR-006); verified-email match links the identity silently.

### 2.6 `Settings` — `/settings`

| Component | Notes |
| --- | --- |
| `LanguageSwitch` | `PATCH /me {locale}` → instant re-render (bn/en) |
| `LogoutButtons` | "এই ডিভাইস থেকে লগআউট" · "সব ডিভাইস থেকে লগআউট" (confirm sheet) |
| `DeviceList` (P1) | `GET /school/users`-independent; per-user sessions/refresh list, revoke one |

## 3. Forms & Input

| Field | Control | zod rule (per-app `src/schemas`) | Default | Conditional on |
| --- | --- | --- | --- | --- |
| locale | segmented | `validation.locale.invalid` | `bn` | always |
| role | cards | enum | student | always |
| schoolId/sectionId (class level shown from the section) | search + chips | `validation.hierarchy.invalid` | — | always |
| phone | tel | `validation.phone.invalid` | — | student/guardian required; staff optional |
| otp_code | 6 boxes | `validation.otp.format` | — | after request |
| student_code + class | inputs | `validation.guardian.studentCode` | — | role=guardian |
| email/password | inputs | `validation.email.invalid` / `validation.password.weak` | — | teacher staff path |

Submission: same contract shapes as the API · disable while pending · map field errors · never
lose input on error · keyboard-aware (submit button rises above the keyboard).

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Register / OTP / login | generated OpenAPI client → api; tokens persisted in expo-secure-store (never AsyncStorage) |
| `/me` + status | TanStack Query key `auth:me`; tabs gate reads it; refetch on app foreground |
| 401 handling | single-flight refresh interceptor (`POST /auth/refresh`); rotation failure → clear session → onboarding/pending |
| Hierarchy reads | TanStack Query `hierarchy:{cityId}` via 04 interface (faked until 04 lands) |
| Push | approval/rejection pushes are sent by 06; deep link `kushol://(tabs)/chat` (approved) declared here |
| No media | none in this module |

## 5. Motion Spec

| Element | Technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Onboarding step change | 160 ms horizontal slide | next/back | progress | instant swap |
| OTP error | 2× shake, 200 ms | wrong code | error | static border |
| Resend countdown | text number only | OTP sent | wait | same |
| Tabs unlock | 200 ms fade of gate → tabs | approval | success | opacity only |
| Press feedback | scale 0.98 (primitives) | touch | tactility | opacity only |

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| 360px width (primary) | single column; primary action in thumb arc; OTP boxes fit 6×44pt |
| ≥ 600px (tablet) | centred 400dp column; no split panes needed |
| Low-end Android / 3G | no images on auth screens; skeleton lists; requests < 10 kB payloads |
| Bengali content | Hind Siliguri renders; no clipped glyphs; bn numerals in countdown copy |

## 7. Accessibility

- [ ] Screen-reader labels on every interactive element; meaningful reading order (OTP digits announced as "digit 1 of 6")
- [ ] Touch targets ≥ 44pt; visible focus/press states
- [ ] Contrast meets WCAG AA against the themed background
- [ ] Motion: reduced-motion form verified
- [ ] Both languages verified on-device (bn default, en secondary)

## 8. Offline Behaviour

Auth requires connectivity by design — nothing is silently queued.

| Action offline | Queued? | Conflict rule on reconnect |
| --- | --- | --- |
| OTP request / verify | No — refused with "ইন্টারনেট লাগবে" message | user retries manually |
| Registration submit | No — form state kept, submit blocked | n/a |
| Tabs status check | Cached `auth:me` shown + staleness banner | refetch on reconnect |
| Logout | Local always works; server revoke retries once on reconnect | server state wins |

## 9. Task Checklist

- [x] `IDT-AP-001` onboarding navigator (zustand draft, back-guard, resume-safe) — 2026-10-15
- [x] `IDT-AP-002` language screen (bn default enforced) — 2026-10-15
- [x] `IDT-AP-003` role screen + admin→web hint — 2026-10-15
- [x] `IDT-AP-004` searchable hierarchy picker (04 interface) — 2026-10-15
- [x] `IDT-AP-005` contact form + guardian link fields — 2026-10-15
- [x] `IDT-AP-006` OTP screen (countdown, delayed-SMS, rate-limit states) — 2026-10-15
- [x] `IDT-AP-007` SSO screens + deep-link return + link flow — 2026-10-15
- [x] `IDT-AP-008` pending gate screen + `/(tabs)` layout guard + rejected/resubmit — 2026-10-15
- [x] `IDT-AP-009` secure token store + single-flight refresh interceptor — 2026-10-15
- [x] `IDT-AP-010` settings language switch (`PATCH /me`) — 2026-10-15
- [x] `IDT-AP-011` settings logout / logout-all — 2026-10-15
- [ ] `IDT-AP-012` device list (P1)
- [x] `IDT-AP-013` bn/en catalog wiring (`auth.*`, `verification.*`, `validation.*`) — 2026-10-15
- [ ] `IDT-AP-014` Maestro golden-path spec + reduced-motion + 360px verification

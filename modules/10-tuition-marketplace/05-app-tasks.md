# Tuition Marketplace — App Tasks (Mobile)

**Module:** `10-tuition-marketplace`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) and
> `docs/tech-stack.md` (app table) are binding: tokens only, every user-facing string in Bengali +
> English, 360px-first layouts.

---

## 1. Screen Inventory

| # | Route (expo-router) | Screen | Access | Deep link source |
| --- | --- | --- | --- | --- |
| 1 | `/(tabs)/marketplace` | Marketplace home — "Find a tutor" section + entry points | Verified (Pending → gate) | none (tab root) |
| 2 | `/(tabs)/marketplace/find` | Tutor browse (subject/area filters; verified locked ON) | Verified | none |
| 3 | `/(tabs)/marketplace/tutors/[id]` | Tutor public profile + "টিউটর হিসেবে অনুরোধ / Request as tutor" CTA | Verified | browse tap |
| 4 | `/(tabs)/marketplace/requirements/new` | Post-requirement wizard (4 steps) | Verified | profile CTA (pre-filled) |
| 5 | `/(tabs)/marketplace/requirements` | My requirements (status chips + interested counts) | Verified | none |
| 6 | `/(tabs)/marketplace/requirements/[id]` | Requirement detail + interested tutors + accept | Verified poster | push `type=tuition_interest` |
| 7 | `/(tabs)/marketplace/matches` | Tutor-side: incoming matches + status tracker | Verified tutor | push `type=tuition_match` |
| 8 | `/(tabs)/marketplace/tutor-setup` | Tutor profile editor (draft) | Verified | matches empty CTA |
| 9 | `/(tabs)/marketplace/tutor-setup/evidence` | Evidence upload + submit-for-review + status tracker | Verified | push `type=tuition_verification` |
| 10 | `/(tabs)/marketplace/premium` | Premium upsell (P2, disabled CTA) | Verified tutor | none |
| 11 | `/(modals)/location-picker` | Area + map pin picker (shared by wizard + tutor setup) | Verified | in-app |

## 2. Screen Breakdown

### 2.1 Marketplace home — `/(tabs)/marketplace`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ মার্কেটপ্লেস        [bn⇄en]   (header) │
│ ┌────────────────────────────────────┐ │
│ │ 🎓 টিউটর খুঁজুন                     │ │ ← "Find a tutor" section
│ │ বিষয় ও এলাকা অনুযায়ী ভেরিফাইড     │ │
│ │ সিনিয়র টিউটর      [ খুঁজুন → ]     │ │
│ ├────────────────────────────────────┤ │
│ │ ✍️ টিউশন রিকোয়ারমেন্ট পোস্ট করুন  │ │
│ ├────────────────────────────────────┤ │
│ │ 📋 আমার রিকোয়ারমেন্ট (২)          │ │ ← poster entry (hidden for tutors w/o posts)
│ │ 👩‍🏫 আমার ম্যাচ (৩)                │ │ ← tutor entry (only with a profile)
│ └────────────────────────────────────┘ │
│ [ Chat ][ Notices ][ AI Hub ][ Market ]│
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `FindTutorCard` | Client | Entry to browse; shows live `VerifiedTutorCount` for the user's school/area when cached |
| `EntryRow` | Client | Requirements / matches entries with count badges |
| `VerifiedGate` | Client | Full-screen NOT_VERIFIED state (below) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton cards; no blocking spinners |
| Pending verification | `VerifiedGate`: "আপনার অ্যাকাউন্ট এখনো ভেরিফাই হয়নি / Your account isn't verified yet" + how-to (module 03 copy) |
| Error | Retry + support path; cached rows stay visible |
| Offline | Cached counts + offline banner; actions refusable per §8 |

### 2.2 Post-requirement wizard — `/(tabs)/marketplace/requirements/new`

**Layout (step 1 of 4; one question-group per step, thumb-reachable)**

```text
┌──────────────────────────────── 360px ─┐
│ ←  রিকোয়ারমেন্ট পোস্ট   ধাপ ১/৪        │
│ ■■□□  (progress)                       │
│ কোন বিষয়ে টিউটর দরকার?                │
│ ┌──────┐ ┌──────────┐ ┌──────┐        │
│ │গণিত ✓│ │পদার্থবিজ্ঞান│ │রসায়ন │        │ ← bn-first chips, multi ≤ 5
│ └──────┘ └──────────┘ └──────┘        │
│ ┌──────┐ ┌──────┐ …                   │
│ │ইংরেজি │ │ আইসিটি│                    │
│ └──────┘ └──────┘                     │
│ শ্রেণি: [ দশম ▾ ]                      │
│ ┌────────────────────────────────────┐ │
│ │ পরবর্তী →                          │ │ ← bottom, thumb zone
│ └────────────────────────────────────┘ │
└────────────────────────────────────────┘
```

Steps: ① subjects + class level → ② budget (৳ min–max inputs + slider, Bangla numerals) + gender
pref → ③ area + location pin (`/(modals)/location-picker`) + schedule note → ④ summary review →
"পোস্ট করুন / Post". Success: "রিকোয়ারমেন্ট পোস্ট হয়েছে — ম্যাচ হলে আমরা জানাবো / Requirement
posted — we'll notify you when tutors match".

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `SubjectChips` | Client (RHF) | Shared catalog bn/en; selection capped at 5 |
| `BudgetInput` | Client | ৳ prefix, integer inputs + linked slider; bn numerals via `Intl` |
| `GenderPrefSegment` | Client | যেকোনো/ছেলে/মেয়ে — any/male/female |
| `LocationPickerSheet` | Client modal | `expo-location` + pin drop; text-area fallback always available |
| `SummaryReview` | Client | All values editable inline before submit |

**States**

| State | Behaviour |
| --- | --- |
| Loading | n/a (local form state) |
| Validation error | Field-level messages from shared zod (`validation.tuition.*`), bn first |
| Offline submit | Queued with banner "অফলাইন — ইন্টারনেট চালু হলে পোস্ট হবে / Offline — will post when online" (§8) |
| `NOT_VERIFIED` | Gate before step 1; nothing posts |
| Success | Confirmation + navigate to my-requirements |

### 2.3 Requirement detail — `/(tabs)/marketplace/requirements/[id]`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ ←  গণিত · দশম শ্রেণি     [খোলা] chip   │
│ ৳২,০০০–৪,০০০ · মিরপুর · মেয়ে টিউটর    │
│ সময়: বিকাল ৫টা–সন্ধ্যা ৭টা              │
│ মেয়াদ: ১১ দিন বাকি                     │
│ ── আগ্রহী টিউটর (২) ──                 │
│ ┌────────────────────────────────────┐ │
│ │ [🖼] তানভীর হাসান   ✓ভেরিফাইড টিউটর│ │ ← badge, no contact shown
│ │ ঢাকা বিশ্ববিদ্যালয় · গণিত, পদার্থ   │ │
│ │ ৳৩০০/ঘণ্টা (ইঙ্গিত)                │ │
│ │ [ ✅ গ্রহণ করুন ]  [ বিস্তারিত ]   │ │
│ └────────────────────────────────────┘ │
│ 🔕 এখনো কোনো আগ্রহী টিউটর নেই          │ ← empty state
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `StatusChip` | Client | খোলা/ম্যাচড/বন্ধ/মেয়াদোত্তীর্ণ — open/matched/closed/expired |
| `InterestedTutorCard` | Client | Public-safe fields + verified badge; **never contact** |
| `AcceptDialog` | Client | Confirm → `POST /matches/{id}/accept` → success overlay → deep-link row into 05 chat (DM or "Message Request sent" state) |
| `CloseAction` | Client | Poster close (confirm); audit note not shown to poster |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton cards |
| Empty | "এখনো কোনো আগ্রহী টিউটর নেই — ম্যাচ হলে আমরা জানাব / No interested tutors yet — we'll notify you" |
| Matched | Banner showing accepted tutor + "চ্যাট চালু করুন / Open chat"; interested list frozen |
| Accept race (`CONFLICT`) | Toast "এই রিকোয়ারমেন্ট ইতিমধ্যে ম্যাচ হয়ে গেছে / This requirement is already matched" + refetch |
| Expired | "মেয়াদ শেষ / Expired" chip + re-post CTA |

### 2.4 Tutor browse + public profile — `find` + `tutors/[id]`

Browse: filter bar (subject chips, area text; "ভেরিফাইড / Verified" chip ON and **locked** for
non-admins) + tutor cards (photo, name, university, subject chips, rate hint, badge). Empty:
"এখনো কোনো ভেরিফাইড টিউটর নেই — প্রথম ভেরিফাইড টিউটর হোন / No verified tutors yet — be the
first verified tutor" with a "টিউটর প্রোফাইল বানান / Create a tutor profile" CTA. Profile:
public-safe fields + bio + availability + **"টিউটর হিসেবে অনুরোধ করুন / Request as tutor"**
CTA → opens the wizard pre-filled (subjects/area); contact fields never render pre-accept.

### 2.5 Tutor side — `matches`, `tutor-setup`, `tutor-setup/evidence`

**Matches list**: cards = requirement summary (subjects, class, area, budget band, schedule) with
status chip (নোটিফাইড/আগ্রহী/গৃহীত/বাতিল/মেয়াদোত্তীর্ণ) and per-card **"আগ্রহী / I'm
interested"** CTA; guardian contact stays hidden until the guardian accepts — after acceptance the
card shows contact + "চ্যাট করুন / Chat" deep link into 05.

**Tutor setup**: form (university, subjects, classes taught, bio bn/en, rate hint ৳, availability,
area+pin, photo) saving as draft; **Evidence screen**: national ID + ≥ 1 subject evidence via the
05 media flow (compress → presign → PUT R2 → confirm), then "রিভিউয়ের জন্য পাঠান / Submit for
review". **Status tracker**: খসড়া → রিভিউ চলছে → ✓ভেরিফাইড / ✕বাতিল (with the reviewer's reason
shown on rejection + "ঠিক করে আবার পাঠান / Fix & resubmit").

## 3. Forms & Input

| Field | Control | zod rule (per-app `src/schemas`) | Default | Conditional on |
| --- | --- | --- | --- | --- |
| `subjects` | multi-select chips | `validation.tuition.subjects_required` (1–5 catalog keys) | profile CTA pre-fill | wizard step 1 |
| `classLevel` | select sheet | `validation.tuition.class_level_invalid` | student's own class (student poster) | wizard step 1 |
| `budgetMin`/`budgetMax` | ৳ inputs + slider | `validation.tuition.budget_range` | — | wizard step 2 |
| `genderPref` | segmented | `validation.tuition.gender_pref_invalid` | `any` | wizard step 2 |
| `locationArea` + `lat/lng` | text + pin sheet | `validation.tuition.area_length` · `geo_bounds` | current area hint | wizard step 3 |
| `scheduleNote` | multiline | `validation.tuition.schedule_length` | — | wizard step 3 |
| Tutor `university`/`subjects`/`classesTaught`/`bio`/`rateHint`/`availability` | form fields | `validation.tuition.*` (bio contact-regex guard) | — | tutor setup |
| Evidence files | image/PDF pickers | `validation.tuition.evidence_required` + media caps | — | evidence screen |

Submission: same contract shape as the API · disable while pending · map field errors · never lose
input on error · keyboard-aware layout (submit stays reachable).

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| List / detail read | TanStack Query → generated OpenAPI client → api; cache keys per `06` §4 (`tuition:tutors:{area}` server-side; query keys `['tuition','tutors',filters]` app-side) |
| Mutation (post/interest/accept/decline/profile) | Optimistic update where safe (interest) → confirm → rollback with message on failure; accept is never optimistic (financial/safety) |
| Push | expo-notifications; `type=tuition_match` → `/marketplace/matches`, `type=tuition_interest` → `/marketplace/requirements/[id]`, `type=tuition_verification` → evidence tracker (payloads carry ids + labels only — never contact) |
| Media (evidence, photo) | Compress on device → `media.PresignUpload` → PUT R2 → `ConfirmUpload` (05 flow) |
| Location | `expo-location` (foreground permission only) + manual area text fallback |

## 5. Motion Spec

| Element | Technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Wizard step transition | horizontal slide (≤ 200 ms) | next/back | progress direction | instant swap |
| Chip select | scale press feedback (≤ 100 ms) | tap | selection | colour swap only |
| Accept success overlay | fade + check draw | accept confirmed | commitment made | instant overlay |
| Status tracker advance | step highlight move | status refetch | verification progress | static highlight |
| Interest tap | button state morph | mutation | action registered | instant state |

Keep motion purposeful and cheap (low-end Android): layout transitions and press feedback only.

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| 360px width (primary) | Single column; one question-group per wizard step; primary action in the bottom thumb zone; chips wrap at 2 rows + "আরও / more" expander |
| ≥ 600px (tablet) | Two-pane: my-requirements list + open detail; browse list + profile preview |
| Low-end Android / 3G | Evidence images compressed (05 flow, ~1 MB target); paginated browse; no blocking loads |
| Bengali content | Hind Siliguri everywhere; bn numerals for ৳ budgets and dates (`Intl`, locale `bn`); no clipped glyphs |

## 7. Accessibility

- [ ] Screen-reader labels on every interactive element; wizard announces "ধাপ X/৪ / Step X of 4"
- [ ] Location: pin has a text-area alternative; never pointer-only
- [ ] Verified badge = icon + text label (never colour-only)
- [ ] Touch targets ≥ 44pt; visible focus/press states
- [ ] Contrast meets WCAG AA against the themed background
- [ ] Motion: reduced-motion form verified
- [ ] Both languages verified on-device (bn default, en secondary)

## 8. Offline Behaviour

Posting is queued; safety/financial actions require connectivity by design.

| Action offline | Queued? | Conflict rule on reconnect |
| --- | --- | --- |
| Submit requirement (wizard) | Yes — banner "will post when online" | Replayed once; server validation failures surface as a reviewable failed item (input preserved) |
| Express interest | No — refused with offline notice | Retry manually (keeps the match list honest) |
| Accept / decline match | No — requires connectivity (financial/safety) | Explained inline |
| Edit tutor profile | Draft saved locally; submit-for-review requires connectivity | Resubmit prompt on reconnect |
| Browse | Reads served from cache | Refetch on reconnect |

## 9. Task Checklist

- [ ] `TUT-AP-001` Marketplace home (Find-a-tutor card, entries, `VerifiedGate`)
- [ ] `TUT-AP-002` Post-requirement wizard (4 steps, shared zod, summary review, offline queue)
- [ ] `TUT-AP-003` Location picker modal (pin + text fallback, bounds validation)
- [ ] `TUT-AP-004` My requirements list (status chips, interested counts, expiry countdown)
- [ ] `TUT-AP-005` Requirement detail + interested tutors + accept dialog + matched/expired states
- [ ] `TUT-AP-006` Tutor browse (filters, verified chip locked ON, area empty state bn/en)
- [ ] `TUT-AP-007` Tutor public profile (public-safe DTO render, request-as-tutor CTA → pre-filled wizard)
- [ ] `TUT-AP-008` Tutor setup form (draft autosave, contact-regex guard messaging)
- [ ] `TUT-AP-009` Evidence screen (05 media flow, compress → presign → confirm) + submit-for-review
- [ ] `TUT-AP-010` Verification status tracker (incl. rejection reason + resubmit path)
- [ ] `TUT-AP-011` Matches list (tutor side) + interest CTA + staged contact/chat deep link after accept
- [ ] `TUT-AP-012` Push deep links (`tuition_match` / `tuition_interest` / `tuition_verification`) wired to 06 payloads
- [ ] `TUT-AP-013` Premium upsell screen (P2, disabled CTA, `TODO: Confirm` benefits)
- [ ] `TUT-AP-014` Offline queue for wizard posts + §8 refusal copy
- [ ] `TUT-AP-015` bn/en strings `tuition.*` verified on-device; bn numerals for ৳ + dates
- [ ] `TUT-AP-016` Maestro specs for `06` §9 (post → interest → accept → chat) + reduced-motion pass

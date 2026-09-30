# AI Study Hub — App Tasks (Mobile)

**Module:** `08-ai-study-hub`
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
| 1 | `/(tabs)/ai-hub` | AI Hub home — 3 entries: নোট স্ক্যানার · অটো-সিটি · স্টাডি ম্যাটেরিয়াল | Verified (Pending → gate) | none (tab root) |
| 2 | `/(tabs)/ai-hub/scan` | Scan flow: capture → preview → retake/confirm → progress | Verified student | none |
| 3 | `/ai-hub/scan/[id]` | Scan detail: tags, summary, share toggle, delete | Verified (owner / same-school) | push `type=scan_ready` |
| 4 | `/(tabs)/ai-hub/archive` | Archive browser: search bar, tag chips, own/shared list | Verified (student + teacher read) | push `type=scan_ready` (list) |
| 5 | `/(tabs)/ai-hub/tests` | Test list: practice vs class tests, published/closed, quota chip | Verified | push `type=class_test` |
| 6 | `/ai-hub/tests/[id]` | Test-taking: question pager, options, submit confirm | Verified (eligible student) | push `type=class_test` |
| 7 | `/ai-hub/tests/[id]/result` | Result: score ring, per-question ✓/✗ + explanation | Verified (attempt owner / creator teacher) | in-app navigation |
| 8 | `/(modals)/quota-exhausted` | Quota exhausted + Kushol Pro upsell | Verified student | `QUOTA_EXCEEDED` response |

## 2. Screen Breakdown

### 2.1 AI Hub home — `/(tabs)/ai-hub`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ এআই হাব                                 │
│ ┌ নোট স্ক্যানার ──────────── [ স্ক্যান ] ┐ │  ← primary: capture
│ └ হাতের লেখা নোট — AI গুছিয়ে দেবে      ┘ │
│ ┌ অটো-সিটি (ক্লাস টেস্ট)  ৩/৫ বাকি      ┐ │  ← QuotaChip from GET /ai/usage
│ └ MCQ প্র্যাকটিস            [ শুরু ]    ┘ │
│ ┌ স্টাডি ম্যাটেরিয়াল        [ খুলুন ]    ┐ │  → archive
│ └ আমার ও স্কুলের শেয়ারকৃত নোট          ┘ │
│ ── নতুন ক্লাস টেস্ট · প্রকাশিত (tap →) ──│  ← when a section test is live
│ [ Chat ][ Notices ][ AI Hub ][ Market ]│
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `HubCard` | Client | module 02 primitive; bn-first copy, one primary action each |
| `QuotaChip` | TanStack Query | "৩/৫ বাকি / 3 of 5 left" or "প্রো / Pro"; live region for screen readers |
| `ClassTestBanner` | TanStack Query | latest published section test → `/ai-hub/tests/[id]` |
| `AIPausedBanner` + `VerifiedGate` | Client | breaker flag → "এআই সাময়িকভাবে বন্ধ — শীঘ্রই ফিরবে / AI is paused — back soon"; pending user → NOT_VERIFIED gate |

**States** — Loading: skeleton cards, no blocking spinners · Empty: "এখনো কোনো টেস্ট নেই — প্র্যাকটিস শুরু করুন / No tests yet — start a practice test" · Error: retry + cached cards stay · Offline/AI-paused: banner; generation CTAs disabled (not hidden) · Success: quota chip updates after each generation.

### 2.2 Scan flow — `/(tabs)/ai-hub/scan`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ ←  নোট স্ক্যানার                         │
│ ┌────────────────────────────────────┐ │
│ │     camera viewport (4:3)          │ │  ← bn hint: "নোটটি সমান আলোয়
│ │                                    │ │     পুরোটা রাখুন / keep the whole
│ └────────────────────────────────────┘ │     note in frame"
│   [ গ্যালারি ]          ( তুলুন )       │  ← gallery pick · shutter
│ ── preview ──  [ আবার তুলুন ] [ আপলোড ] │  ← retake · confirm upload
│ ── progress ─█ AI আপনার নোট পড়ছে…       │  ← shimmer; leave-screen OK
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `CameraCapture` | Client | expo-camera; gallery fallback (expo-image-picker); permission-denied → settings deep link |
| `ScanPreview` | Client | confirm → compress (~1 MB) → 05 `PresignUpload` → R2 PUT → `ConfirmUpload` → `POST /ai/notes` |
| `ScanProgress` | TanStack Query poll 3 s | "AI আপনার নোট পড়ছে… / AI is reading your notes…"; detail on READY; safe to leave — push completes the journey |
| `QuotaGuard` | Client | pre-flight `GET /ai/usage`; exhausted → `/(modals)/quota-exhausted` before camera opens |

**States** — Loading: skeleton frame · Error (upload): "আপলোড ব্যর্থ — আবার চেষ্টা করুন / Upload failed — try again", captured image preserved (§8) · Offline: capture queued, confirm blocked with message · Quota denied: `QUOTA_EXCEEDED` → 2.8 · AI failed: `failed` + "আবার চেষ্টা করুন / Try again" (quota-refunded copy) · Success: push/toast "নোট স্ক্যান সম্পন্ন হয়েছে / Note scan complete" → 2.3.

### 2.3 Scan detail — `/ai-hub/scan/[id]`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ ←  আমার নোট                     [ ∙∙∙ ] │  ← delete
│ ┌────────────────────────────────────┐ │
│ │        scanned note image          │ │  ← short-lived R2 URL
│ └────────────────────────────────────┘ │
│ (পদার্থবিজ্ঞান)(অধ্যায় ৩)(গতিবিদ্যা)      │  ← tag chips subject/chapter/topic
│ ── AI সারসংক্ষেপ (AI-এর লেখা) ──         │  ← summary as returned + trust label
│ গতির সংজ্ঞা, ভেক্টর যোগ ও উদাহরণ…        │
│ ┌ স্কুলে শেয়ার করুন              [ ⬤ ] ┐ │  ← toggle, default বন্ধ (OFF)
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `TagChipRow` + `SummaryBlock` | Client | level-coloured chips; "AI-এর লেখা / AI-generated" label (trust signal) |
| `ShareToggle` | Client (optimistic) | "স্কুলে শেয়ার করুন / Share with school"; default off; rollback + toast on failure |
| `DeleteAction` | Client | confirm sheet → `DELETE /ai/notes/{id}` → archive |

**States** — Processing: inline progress + poll · Ready: chips + summary render · Failed: "স্ক্যান ব্যর্থ — কোটা ফেরত দেওয়া হয়েছে / Scan failed — your quota was refunded" + retry · Image unavailable: "ছবি পাওয়া যায়নি / Image unavailable" placeholder; tags/summary intact · Unshared elsewhere: "নোটটি আর শেয়ার করা হয়নি / This note is no longer shared" (non-owner).

### 2.4 Archive browser — `/(tabs)/ai-hub/archive`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ স্টাডি ম্যাটেরিয়াল                        │
│ ┌ নোট খুঁজুন…                    [আর?] ┐ │  ← search submits on submit
│ [আমার নোট] [স্কুলে শেয়ারকৃত]   ← scope  │
│ (সব)(পদার্থবিজ্ঞান)(অধ্যায় ৩)(গতিবিদ্যা)  │  ← tag chips (AND filter, ≤10)
│ ┌ [img] গতিবিদ্যার সূত্র     ৩০ সেপ্টে  ┐ │
│ └ (পদার্থবিজ্ঞান)(অধ্যায় ৩)             ┘ │  ← 20/page infinite list
│ ┌ [img] রসায়ন ল্যাব নোট     ২৮ সেপ্টে  ┐ │
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `SearchBar` | RHF + zod | `validation.ai.query_length` → `GET /ai/notes/search?q=&tags=&scope=` |
| `ScopeTabs` | Client | mine / shared (teachers: shared read-only) |
| `TagChipFilter` + `ScanRow` | TanStack Query infinite | chips from school facet; rows = thumbnail, first tags, bn date |

**States** — Loading: skeleton rows · Empty: "কোনো নোট মেলেনি — বানান বদলে দেখুন বা নোট স্ক্যান করুন / No matching notes — try another spelling or scan a note" · Error: inline retry, previous results stay · Offline: cached list read-only; search disabled (§8).

### 2.5 Test list — `/(tabs)/ai-hub/tests`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ অটো-সিটি     [ + নতুন প্র্যাকটিস ] ৩/৫ বাকি│
│ ── ক্লাস টেস্ট (শিক্ষক প্রকাশিত) ──       │
│ │ পদার্থ · অধ্যায় ৩ · ১০ প্রশ্ন  প্রকাশিত│ → take
│ │ রসায়ন · অধ্যায় ১২                 বন্ধ│ → result only
│ ── আমার প্র্যাকটিস ──                    │
│ │ গতিবিদ্যা প্র্যাকটিস          স্কোর ৭/১০│
│ │ জেনারেট হচ্ছে…              (polling) │  ← until ready
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `TestRow` | TanStack Query | kind badge (প্র্যাকটিস/ক্লাস টেস্ট), status (প্রকাশিত/বন্ধ/জেনারেট হচ্ছে…), score when graded |
| `GenerateSheet` | RHF + zod | subject + chapter (+topic) + count slider 5–30 (default 10); teacher variant adds own-section picker |

**States** — Generating: row polls; leave-safe (push on ready) · Quota exhausted: → 2.8 · Failed: row shows "আবার চেষ্টা করুন / Try again" + refund copy · Empty: "প্রথম প্র্যাকটিস টেস্ট বানান / Create your first practice test".

### 2.6 Test-taking — `/ai-hub/tests/[id]`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ ← পদার্থ · অধ্যায় ৩         প্রশ্ন ৩/১০   │
│ ┌────────────────────────────────────┐ │
│ │ একটি বস্তুর সময়-বেগ স্থির হলে       │ │  ← stem (bn per test locale)
│ │ ত্বরণ কত?                          │ │
│ │ ( A ) শূন্য                ← নির্বাচিত│ │  ← ≥ 44pt touch targets
│ │ ( B ) ধ্রুবক                        │ │
│ │ ( C ) ক্রমবর্ধমান                   │ │
│ │ ( D ) পরিবর্তনশীল                  │ │
│ ├────────────────────────────────────┤ │
│ │ [ ← পূর্ববর্তী ]  [ পরবর্তী → ]      │ │
│ │           [ জমা দিন ] (last Q)     │ │
│ └────────────────────────────────────┘ │
│ ── confirm sheet: ২টি প্রশ্নের উত্তর বাকি ──│
│ [ সম্পাদনা ]  [ জমা দিন ]               │
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `QuestionPager` | Client | FlatList paging; progress "প্রশ্ন ৩/১০"; selections restore from server on remount |
| `OptionRow` | Client | tap → `POST /ai/attempts/{id}/answers` upsert (latest wins); failure keeps local state + retries |
| `SubmitConfirm` | Client | unanswered-count warning before terminal submit |

**States** — Loading: skeleton question; cached selections render instantly · Error (save): non-blocking "উত্তর সংরক্ষিত হয়নি — আবার চেষ্টা হবে / Answer not saved — will retry", selection kept · Offline: **blocked** — "পরীক্ষার জন্য ইন্টারনেট প্রয়োজন — অফলাইনে উত্তর জমা হয় না / Internet is required for tests — answers aren't saved offline" (§8) · Closed: "টেস্টটি বন্ধ / This test is closed" → list · Already attempted: → result · KeyGuard: payloads never contain the answer key pre-submit (server-enforced).

### 2.7 Result — `/ai-hub/tests/[id]/result`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ ←  ফলাফল                                │
│            ╭─────────╮                  │
│            │  ৭/১০   │  ← score ring    │
│            ╰─────────╯                  │
│ ┌ ✓ প্রশ্ন ১ · সঠিক                      │
│ │ ✗ প্রশ্ন ২ · ভুল                       │
│ │   সঠিক উত্তর: (B) ধ্রুবক               │
│ │   ব্যাখ্যা: সময়-বেগ স্থির মানে…         │
│ │ ✓ প্রশ্ন ৩ · সঠিক                      │
│ └──────────────────────────────────────┘
│ (teacher view: গড় ৬.২ · প্রতি প্রশ্নে miss%)│
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `ScoreRing` | Client | one-shot animation; reduced-motion → static ring; bn numerals via `Intl` |
| `QuestionResultRow` | Client | ✓/✗ + correct answer + explanation — one semantic unit for screen readers |
| `TestStats` (teacher) | TanStack Query | attempts, average, per-question miss % (`AttemptStats` export) |

**States** — Loading: skeleton ring + rows · Not graded: "ফলাফল আসছে… / Results coming…" (transient) · Forbidden: "এই ফলাফল দেখার অনুমতি নেই / Not allowed to view this result" · Success: cached → offline-readable.

### 2.8 Quota exhausted — `/(modals)/quota-exhausted`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│   এই সপ্তাহের ফ্রি কোটা শেষ               │
│   প্র্যাকটিস টেস্ট: ৫/৫ ব্যবহৃত · রিসেট: সোমবার│
│ ┌ কুশল প্রো ───────────────────────────┐ │
│ │ আনলিমিটেড অটো-সিটি + স্ক্যান · ৯৯৳/মাস│ │
│ │            [ প্রো নিন ]               │ │  → "শীঘ্রই আসছে / Coming soon"
│ └──────────────────────────────────────┘ │
│           [ এখন না, পরে ]                │
└────────────────────────────────────────┘
```

English mirror: "This week's free quota is used up · Practice tests: 5/5 used · Resets Monday ·
Kushol Pro: unlimited Auto-CT + scans · BDT 99/mo · [Get Pro] · [Not now]". Never a dead end —
archive browsing and taking already-generated tests still work.

## 3. Forms & Input

| Field | Control | zod rule (per-app `src/schemas`) | Default | Conditional on |
| --- | --- | --- | --- | --- |
| Search `q` | search bar (submit-on-search) | `validation.ai.query_length` (0–100) | empty (browse mode) | — |
| Tag filters | chip multi-select | `validation.ai.tags_invalid` (≤ 10) | none | — |
| Test `subject`/`chapter`/`topic` | text inputs | `validation.ai.scope_required` · `scope_length` (1–120) | last-used subject | generate sheet |
| Test `count` | slider 5–30 | `validation.ai.count_range` | 10 | generate sheet |
| Test `sectionId` (teacher) | picker of own sections | `validation.ai.section_not_yours` | first taught section | teacher kind=class_test |
| Answer `chosenIndex` | option row tap | `validation.ai.choice_invalid` (0–3) | none | in-progress attempt |
| Share `shared` | toggle | `validation.ai.share_invalid` | false (always) | own scan detail |

Submission: same contract shape as the API · disable while pending · map field errors · never lose
input on error · keyboard-aware layout (avoid the keyboard covering the submit).

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| List / detail read | TanStack Query → generated OpenAPI client → api; cache keys declared in `06` §4 |
| Generation (scan/practice/class) | Presign → R2 PUT → confirm (05 flow) → POST create → job; poll 3 s while processing/generating; 06 push cancels polling |
| Mutation (share/delete/answers/submit) | Optimistic where safe (share) → confirm → rollback with message on failure |
| Quota | `GET /ai/usage` before + after every generation; `QUOTA_EXCEEDED` routes to 2.8 |
| Realtime | 06 pushes (`scan_ready`, `class_test`) deep-link via §1 table; no WS in this module |
| Media | Compress on device (~1 MB) → R2 presigned upload → confirm to api (05 sniffs magic bytes) |

Poll → push precedence: a `scan_ready` push invalidates the scan query; polling stops on any
terminal status (`ready`/`failed`). Dates/numerals render via `Intl` bn (৩০ সেপ্টেম্বর, ৭/১০).

## 5. Motion Spec

| Element | Technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Scan progress shimmer | 1200 ms loop on the progress card | scan `processing` | AI working, not frozen | static card + text only |
| Score ring | one-shot sweep ≤ 800 ms | result mount | score magnitude | static full ring + number |
| Tag chips | group fade-in ≤ 200 ms | scan READY | content arrived | instant render |
| Quota chip change | crossfade ≤ 150 ms | usage refetch | quota spent/refunded | instant swap |
| Submit confirm sheet | slide-up | submit tap | irreversible action | instant sheet |
| AI-paused banner | slide-down, once | breaker flag | feature state | instant show |

Keep motion purposeful and cheap (low-end Android): layout transitions and press feedback only,
unless the module's `02` §7 says otherwise.

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| 360px width (primary) | Single column; option rows full-width ≥ 44pt; pager arrows thumb-zone; chips wrap to 2 lines |
| ≥ 600px (tablet) | Two-pane: archive list + detail; test list + pager side-by-side |
| Low-end Android / 3G | Images compressed ~1 MB before upload; 20/page lists; polls (not sockets); Hermes; no blocking loads |
| Bengali content | Hind Siliguri renders; no clipped glyphs; bn numerals via `Intl`; AI content arrives in the user's locale (bn question text for bn students) |
| Camera | Permission-denied → settings deep link; low-light framing hint overlay |

## 7. Accessibility

- [ ] Screen-reader labels on every interactive element; meaningful reading order
- [ ] Touch targets ≥ 44pt; visible focus/press states
- [ ] Contrast meets WCAG AA against the themed background
- [ ] Motion: reduced-motion form verified (§5)
- [ ] Both languages verified on-device (bn default, en secondary)
- [ ] Result rows announced as one unit ("প্রশ্ন ২ — ভুল, সঠিক উত্তর…"); quota chip is a live region
- [ ] Quota-exhausted modal announced on open; focus trapped; escape = "এখন না / Not now"

## 8. Offline Behaviour

AI actions are server-bound, so the offline contract is honest queueing or clear refusal — never
silent loss:

| Action offline | Queued? | Conflict rule on reconnect |
| --- | --- | --- |
| Capture scan photo | Yes — image + metadata stored locally, banner "অফলাইন — ইন্টারনেট চালু হলে আপলোড হবে / Offline — will upload when online" | Auto-uploads (05 flow) when online; if quota was consumed meanwhile → `QUOTA_EXCEEDED` modal, image kept as draft |
| Confirm scan / generate test | No — refused with message (needs presign + enqueue) | Input preserved for retry |
| Take test / save answer / submit | No — **blocked with a clear message**; local selections kept so nothing typed is lost | Resume on reconnect; selections replay via answers upsert |
| Browse archive / result | Read-only from cache | Refetch on reconnect |
| Search | No — needs server pg_trgm | Retry when online |
| Share toggle | No — refused (visibility is safety-relevant) | — |

## 9. Task Checklist

- [ ] `AIH-AP-001` AI Hub tab: 3 `HubCard` entries + `QuotaChip` + `ClassTestBanner` + `VerifiedGate`
- [ ] `AIH-AP-002` Scan capture: camera + gallery + bn framing hint + permission-denied path
- [ ] `AIH-AP-003` Upload pipeline: compress ~1 MB → 05 presign → R2 PUT → confirm → `POST /ai/notes`
- [ ] `AIH-AP-004` Scan progress ("AI আপনার নোট পড়ছে…") + 3 s poll + push-handoff + leave-safe
- [ ] `AIH-AP-005` Scan detail: tag chips, AI-generated summary block, short-lived image URL
- [ ] `AIH-AP-006` Share toggle (optimistic, default off) + delete confirm + audited flow
- [ ] `AIH-AP-007` Archive browser: search bar, scope tabs, tag-chip filters, infinite list, empty states
- [ ] `AIH-AP-008` Test list: practice/class sections, status badges (জেনারেট হচ্ছে…/প্রকাশিত/বন্ধ), scores
- [ ] `AIH-AP-009` Generate sheet (student practice + teacher class-test variant w/ section picker)
- [ ] `AIH-AP-010` Test-taking pager: option select + answers upsert + resume + submit confirm w/ unanswered warning
- [ ] `AIH-AP-011` Result screen: animated score ring, per-question ✓/✗ + explanation, bn numerals
- [ ] `AIH-AP-012` Teacher stats view on own test results (avg, per-question miss %)
- [ ] `AIH-AP-013` Quota states: remaining chip everywhere + quota-exhausted modal with Pro upsell (12 placeholder CTA)
- [ ] `AIH-AP-014` `AIPausedBanner` + processing/failed states ("we'll notify you", refund copy, retry)
- [ ] `AIH-AP-015` Offline contract (§8): capture queue, test-taking block, cached reads
- [ ] `AIH-AP-016` Push deep links: `scan_ready` → detail, `class_test` → test (06 payload contract)
- [ ] `AIH-AP-017` Reduced-motion variants for all §5 animations
- [ ] `AIH-AP-018` bn/en `ai.*` + `validation.ai.*` catalogs complete in each app's `src/i18n`
- [ ] `AIH-AP-019` Maestro specs for `06` §9 E2E flows (scan → tags ready; practice test → graded result)

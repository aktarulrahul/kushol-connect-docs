# Teacher Analytics — App Tasks (Mobile)

**Module:** `09-teacher-analytics`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

`docs/design-reference/README.md` and `docs/tech-stack.md` (app table) are binding: tokens only,
every user-facing string in Bengali + English (`analytics.*`), 360px-first layouts, Hind Siliguri.
The app surface is **read-only** (refresh stays a web-dashboard action) — a teacher glances at the
week's top weaknesses between classes.

---

## 1. Screen Inventory

| # | Route (expo-router) | Screen | Access | Deep link source |
| --- | --- | --- | --- | --- |
| 1 | `/(tabs)/ai-hub/matrix` | Weekly pain-point summary — top 3 topics per owned section (cards) | Verified Teacher | push `type=analytics_weekly` (module 06, P1) · AI Hub entry card |
| 2 | `/(tabs)/ai-hub/matrix/[sectionId]` | Section detail — full topic list + per-source counts + week navigation | Verified Teacher (owner) | summary card tap · push payload |

## 2. Screen Breakdown

### 2.1 Weekly summary — `/(tabs)/ai-hub/matrix`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ ←  দুর্বলতা ম্যাট্রিক্স    [bn⇄en]      │
│ এই সপ্তাহ: ২৮ সেপ্টে–৪ অক্টো            │ ← week window, Intl bn
│ ┌────────────────────────────────────┐ │
│ │ অবস বি১০ · বিজ্ঞান                 │ │ ← owned section card
│ │ ১. ক্যালকুলাসের লিমিট   ███ ৬০%    │ │ ← top 3, severity colour + bn numerals
│ │ ২. রাসায়নিক বিক্রিয়া    ██ ৪৮%    │ │
│ │ ৩. গতিবিদ্যা             █ ৩১%    │ │
│ │ বিস্তারিত দেখুন ›                   │ │
│ ├────────────────────────────────────┤ │
│ │ অবস নবম · গণিত                     │ │ ← second owned section
│ │ এই সপ্তাহে যথেষ্ট তথ্য নেই          │ │ ← inline empty (suppressed/no data)
│ └────────────────────────────────────┘ │
│ ℹ চ্যাট বিশ্লেষণ নেই — শুধু টেস্টের তথ্য │ ← degraded note when PARTIAL
│ [ AI Hub হোম › ]                        │
└─────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `SectionSummaryCard` | Client (TanStack Query) | Per owned section: top 3 topics (tag as-is + `language` chip), rate bar, severity colour; tap → detail |
| `WeekWindowCaption` | Client | `Intl` bn/en date range of `weekStart` |
| `DegradedNote` | Client | `status = "PARTIAL"` explanation, bn/en |
| `EmptyWeek` | Client | Inline insufficient-data / no-activity copy |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton cards matching the final layout; no blocking spinners |
| Empty — insufficient data | "এই সপ্তাহে যথেষ্ট তথ্য নেই — কমপক্ষে ৫ জন শিক্ষার্থীর ডেটা প্রয়োজন / Not enough data yet — data from at least 5 students is required" |
| Empty — no activity | "এই সেকশনে এই সপ্তাহে কোনো টেস্ট বা চ্যাট কার্যক্রম হয়নি / No test or chat activity in this section this week" |
| Error | Retry + cached cards stay visible; never a blank screen |
| Offline | Last cached matrix rendered + "অফলাইন — সর্বশেষ হিসাব দেখানো হচ্ছে / Offline — showing the last computed matrix" banner (§8) |
| Not verified / forbidden | `VerifiedGate` / "এই সেকশনের রিপোর্ট দেখার অনুমতি নেই / You're not allowed to view this section's report" |
| Success | Cards reflect the weekly push content 1:1 |

### 2.2 Section detail — `/(tabs)/ai-hub/matrix/[sectionId]`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ ←  অবস বি১০ · বিজ্ঞান    ‹ আগের সপ্তাহ › │ ← week navigation (≤12 weeks)
│ ┌────────────────────────────────────┐ │
│ │ ৬০% শিক্ষার্থী ক্যালকুলাসের লিমিটে   │ │ ← insight sentence (bn default)
│ │ দুর্বল                              │ │
│ │ MCQ টেস্ট  ▮▮▮ ৬০% · ২৫ জন          │ │ ← per-source counts only
│ │ চ্যাট প্রশ্ন ▮ ৩১% · ১৮ জন          │ │
│ ├────────────────────────────────────┤ │
│ │ রাসায়নিক বিক্রিয়া                  │ │ ← next topic row
│ │ MCQ টেস্ট  ██ ৪৮% · ২৫ জন          │ │
│ └────────────────────────────────────┘ │
│ লুকানো সারি: ২ (গোপনীয়তা)              │ ← suppressedCount caption
└─────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `TopicDetailRow` | Client | Insight sentence, severity chip, per-source rate + `sampleSize`; tag renders as-is |
| `WeekNav` | Client | Prev/next through the weeks list (`GET …/weeks`); disabled at ends |
| `SuppressionCaption` | Client | Hidden-rows count (privacy) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton rows per topic |
| Empty | Per-week empty copy (§2.1), week nav stays usable |
| Error | Inline retry; cached week stays rendered |
| Offline | Cached week + banner; week nav works on cached weeks only |
| Success | Tap targets ≥ 44pt; deep link from push lands on the right week |

## 3. Forms & Input

N/A — read-only surface. The only inputs are the section id (route param) and week index (local
state), both validated by the generated contract shapes (`validation.section_uuid`,
`analytics.week_invalid`) before fetch; no keyboard, no forms.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Summary / detail read | TanStack Query → generated OpenAPI client → `GET /api/v1/analytics/weekly-matrix?sectionId=…` (+ `…/weeks`); cache keys declared in `06` §4 |
| Offline cache | react-query persist (MMKV) keyed `analytics:matrix:{sectionId}:{week}` — serves the last computed matrix |
| Push | expo-notifications payload `type=analytics_weekly {sectionId, weekStart}` → deep link to route 2 (P1, module 06) |
| Realtime | None — weekly data; pull-to-refresh is the only re-fetch affordance |

## 5. Motion Spec

| Element | Technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Card press | NativeWinds press scale (≤ 100 ms) | tap section card | navigable | static highlight |
| Rate bar fill | Width animation ≤ 200 ms | week/section data lands | magnitude of weakness | instant full-width |
| Week change | Fade ≤ 150 ms | `WeekNav` | new dataset | instant swap |

Keep motion purposeful and cheap (low-end Android): layout transitions and press feedback only.

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| 360px width (primary) | Single column; rate bars inline with labels; topic tags wrap without clipping Bangla glyphs |
| ≥ 600px (tablet) | Two-pane: section list + detail; centred column otherwise |
| Low-end Android / 3G | One query per screen, cached matrix first; no images; bn numerals via `Intl` (no extra font weight) |
| Bengali content | Hind Siliguri renders; no clipped glyphs; tags stored bn or en display as-is with chip |

## 7. Accessibility

- [ ] Screen-reader labels on cards/rows ("ক্যালকুলাসের লিমিট — ৬০ শতাংশ, সতর্কতা"); meaningful order
- [ ] Touch targets ≥ 44pt; visible press states
- [ ] Contrast meets WCAG AA (severity fills vs text) in theme
- [ ] Motion: reduced-motion forms verified
- [ ] Both languages verified on-device (bn default, en secondary); week navigation announced

## 8. Offline Behaviour

| Action offline | Queued? | Conflict rule on reconnect |
| --- | --- | --- |
| View matrix | Served from MMKV-cached last matrix + offline banner | Pull-to-refresh revalidates on reconnect; newest `computedAt` wins |
| Week navigation | Cached weeks only; uncached weeks show "সংযোগ প্রয়োজন / Connection needed" | — |
| Refresh action | N/A — not available in-app (web only) | — |

No write path exists in this module's app surface — nothing to queue, nothing silently lost.

## 9. Task Checklist

- [ ] `ANL-AP-001` AI Hub entry + `/(tabs)/ai-hub/matrix` summary with per-section top-3 cards (360px wireframe) — ____
- [ ] `ANL-AP-002` Section detail screen: insight rows, per-source counts, `SuppressionCaption` — ____
- [ ] `ANL-AP-003` `WeekNav` over the weeks list (≤ 12 weeks, cached navigation) — ____
- [ ] `ANL-AP-004` Offline cache (react-query persist) + "last computed matrix" banner — ____
- [ ] `ANL-AP-005` Empty states (insufficient data / no activity) + degraded "no chat analysis" note, bn/en — ____
- [ ] `ANL-AP-006` Push deep link `analytics_weekly` → correct section + week (P1, with module 06 payload) — ____
- [ ] `ANL-AP-007` Forbidden / unverified gates with module 03 copy — ____
- [ ] `ANL-AP-008` a11y pass (§7) incl. reduced motion + bn numerals via `Intl` — ____
- [ ] `ANL-AP-009` `analytics.*` catalog wiring bn + en; tags rendered as-is with language chip — ____
- [ ] `ANL-AP-010` Maestro E2E: seeded teacher → summary card → detail → offline airplane-mode render — ____

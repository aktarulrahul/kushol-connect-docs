# Teacher Analytics — Frontend Tasks

**Module:** `09-teacher-analytics`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Recharts (heatmap) · TanStack Query · Motion · RHF + Zod
**Last updated:** 2026-09-30

`docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) is binding: tokens
only from each app's `src/i18n`, every user-facing string in Bengali + English (`analytics.*`,
`validation.*` catalogs). Charts use the brand deep-teal scale; severity colours are an additive
signal, never the only one.

---

## 1. Screen Inventory

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/school/ai-matrix` | Pain Point Matrix dashboard — role-adaptive: teacher = own section(s); School Admin = school-wide grid + section filter | Server Component (first paint) + TanStack Query client islands | School Admin · Teacher (verified) |
| 2 | `/school/ai-matrix` (drilldown panel) | Topic drilldown — insight sentence, sample size, per-source breakdown | Client (panel within route 1) | same as route 1 |

Module 07 owns the Command Center shell/navigation entry ("AI Pain Point Matrix" item per
`prd.md` §4A); this module owns everything under the route.

## 2. Screen Breakdown

### 2.1 Matrix dashboard — `/school/ai-matrix`

**Layout**

```text
┌────────────────────────────────────────────────────────────── desktop ≥1024 ┐
│ শিক্ষার্থীর দুর্বলতা ম্যাট্রিক্স · ডেমো উচ্চ বিদ্যালয়   [সপ্তাহ ▾] [সেকশন ▾] │
│ Pain Point Matrix · Demo High School                  [week ▾] [section ▾]  │ ← section ▾ admin-only
│ ┌──────────────────────────────────────────────────────────────────────┐    │
│ │ heatmap: rows = topic tags · columns = sections (admin) / weeks      │    │
│ │ ┌──────────────────────────┬────────┬────────┬────────┐              │    │
│ │ │ ক্যালকুলাসের লিমিট  bn     │ ███ 60%│ ██ 45% │ ─  n/a │              │    │ ← cell: % + severity colour
│ │ │ সীমাবদ্ধতা: সতর্কতা        │ alert  │ watch  │        │              │    │
│ │ ├──────────────────────────┼────────┼────────┼────────┤              │    │
│ │ │ Calculus limits      en  │ ███ 52%│ █ 22%  │ ─      │              │    │
│ │ └──────────────────────────┴────────┴────────┴────────┘              │    │
│ └──────────────────────────────────────────────────────────────────────┘    │
│ ℹ চ্যাট বিশ্লেষণ নেই — শুধু টেস্টের তথ্য দেখানো হচ্ছে   [এখনই আপডেট] [CSV ⬇]  │ ← degraded note (teacher) · refresh · export P2
│ লুকানো সারি: ২ (গোপনীয়তা) · হিসাব: সপ্তাহ ২৮ সেপ্টে–৪ অক্টো ২০২৬            │ ← suppressedCount + week window
└─────────────────────────────────────────────────────────────────────────────┘
```

Teacher scope: the grid collapses to the selected own section (single-column heatmap: rows = topic
tags, cell = fail rate + sample chips). School Admin scope: topics × sections grid; the section
selector narrows to one section (full teacher-style matrix).

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `MatrixHeader` | Server | Title bn/en, school name, week window caption (`Intl`, Asia/Dhaka) |
| `WeekSelector` | Client | Weeks from `GET …/weeks`; URL search param `?week=`; labels "২৮ সেপ্টে–৪ অক্টো / Sep 28–Oct 4" |
| `SectionSelector` | Client | School Admin only; sections from the school matrix payload |
| `PainHeatmap` (Recharts) | Client | Cells = `failRate`, 4-step severity scale from brand tokens (steady→critical); numeric label in every cell; topic tag as-is with `language` chip |
| `DrilldownPanel` | Client | Slide-over panel per 2.2 |
| `DegradedNote` | Client | Shown when `status = "PARTIAL"` — "চ্যাট বিশ্লেষণ নেই — শুধু টেস্টের তথ্য দেখানো হচ্ছে / No chat analysis — showing test data only" |
| `RefreshButton` (P1 feature) | Client | Teacher only; POST refresh → 202 → poll weeks/matrix until `computedAt` changes; disabled with `retryAfter` on `RATE_LIMITED` |
| `ExportButton` (P2) | Client | CSV download for the rendered week; disabled on EMPTY weeks |
| `SuppressionCaption` | Server | "লুকানো সারি: ২ (গোপনীয়তা) / 2 rows hidden (privacy)" when `suppressedCount > 0` |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton matching the final heatmap grid (topic-row placeholders); no blocking spinners |
| Empty — insufficient data | "এই সপ্তাহে যথেষ্ট তথ্য নেই — কমপক্ষে ৫ জন শিক্ষার্থীর ডেটা প্রয়োজন / Not enough data yet — data from at least 5 students is required" + `suppressedCount` caption |
| Empty — no activity | "এই সেকশনে এই সপ্তাহে কোনো টেস্ট বা চ্যাট কার্যক্রম হয়নি / No test or chat activity in this section this week" |
| Error | Boundary with retry + request id; last rendered week stays visible |
| Forbidden | Teacher hitting another section (deep link): "এই সেকশনের রিপোর্ট দেখার অনুমতি নেই / You're not allowed to view this section's report" (`FORBIDDEN`) |
| Rate limited | Refresh button shows "আজ এই সেকশনের জন্য আপডেট সীমা শেষ — কাল আবার চেষ্টা করুন / Today's refresh for this section is used up — try again tomorrow" + `retryAfter` |
| Success | `computedAt` caption; drilldown opens on cell/row activation |

### 2.2 Topic drilldown — panel within `/school/ai-matrix`

**Layout**

```text
┌──────────────────────────────────── 360–480px panel ─┐
│ ✕  ক্যালকুলাসের লিমিট  [bn]            সপ্তাহ: ২৮ সেপ্টে│
│ ┌──────────────────────────────────────────────────┐ │
│ │ ৬০% শিক্ষার্থী ক্যালকুলাসের লিমিটে দুর্বল          │ │ ← insightText (or template re-render)
│ │ 60% of students are struggling with Calculus      │ │    limits (en toggle)
│ └──────────────────────────────────────────────────┘ │
│ MCQ টেস্ট      ▮▮▮ ৬০% · ২৫ জন শিক্ষার্থী             │ ← per-source: rate + sample size (counts only)
│ চ্যাট প্রশ্ন    ▮ ৩১% · ১৮ জন                        │
│ তথ্য: ৪৩টি প্রশ্নের উত্তর · হিসাব ২৮ সেপ্টে–৪ অক্টো     │ ← definition tooltip source line
└──────────────────────────────────────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `DrilldownPanel` (slide-over) | Client | Focus-trapped; Esc/✕ closes; focus returns to the originating cell |
| `InsightCard` | Client | Stored `insightText`; locale toggle re-renders bn/en from `analytics.insight.*` + `insightParams` |
| `SourceBreakdown` | Client | One row per source (`mcq`/`chat`) — fail rate bar + `sampleSize`; counts only, never message text (`ANL-BR-005`) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Not applicable — data ships in the matrix response |
| Empty | Not reachable (rows drive the panel) |
| Error | Panel shows retry for a stale refetch |
| Success | Severity chip + bn/en insight + sources |

## 3. Forms

N/A — no forms on this surface. Week/section selection uses URL search params validated by the
generated contract schemas (server re-validates); the refresh action carries only `sectionId` from
route state, mirrored by a zod schema from each app's `src/i18n`. Error keys: `validation.required`,
`analytics.week_invalid`, `analytics.section_not_in_school`.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Matrix first paint | Server Component → generated OpenAPI client → `GET /api/v1/analytics/weekly-matrix` (teacher) / `…/school` (admin) → cached tag `school:{id}:matrix:{week}` |
| Interactive updates | TanStack Query (`queryKey: ["analytics","matrix", schoolId, sectionId, week]`) for selectors, refresh polling, drilldown |
| Refresh | Client → Route Handler (session → role check) → `POST /api/v1/analytics/weekly-matrix/refresh` → 202 → poll matrix until `computedAt` changes (max 60 s) → toast bn/en |
| CSV export (P2) | Route Handler → re-fetch matrix (same scope) → stream `text/csv`; suppressed rows excluded server-side |
| Cache coherence | Refresh/weekly-job completions revalidate `school:{id}:matrix:{week}` + `school:{id}:matrix:index` (`06` §4) — stale reads self-heal on next navigation |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Heatmap cell fill | Colour transition ≤ 150 ms | week/section change | data changed | instant swap |
| Drilldown panel | Slide-in + fade (≤ 200 ms) | cell/row activation | detail context opens | instant show |
| Refresh spinner | Button-afforded inline spinner | POST 202 → polling | recompute in progress | static "আপডেট হচ্ছে… / Updating…" label |
| Degraded note | Fade-in | `status = "PARTIAL"` | data caveat | instant show |

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 (tablet target) | ≥ 1024 |
| --- | --- | --- | --- |
| Heatmap | Horizontal scroll with sticky topic column; cells ≥ 44px touch | Grid fits; selectors collapse into a filter row | Full grid + side-by-side drilldown on wide screens |
| Drilldown | Full-screen sheet | Side panel (overlay) | Side panel (push) |
| Selectors | Stacked full-width controls | Inline row | Inline row + caption right-aligned |

## 7. Accessibility

- [ ] Landmarks, one `h1`, heading order (heatmap is a labelled `table`/grid role)
- [ ] Keyboard path complete: selectors → cells (roving tab index) → drilldown → Esc back; focus visible and never lost
- [ ] Every cell has an aria-label with topic, percent and severity ("ক্যালকুলাসের লিমিট — ৬০%, সতর্কতা"); severity never colour-only (numeric label in-cell)
- [ ] Contrast: severity fills meet WCAG 2.2 AA against cell text in both themes
- [ ] Status messages (refresh, rate limit, degraded note) announced via live region
- [ ] Motion: reduced-motion variants verified (§5)
- [ ] axe clean on all states (loading/empty/error/forbidden/success)

## 8. Design-System Compliance

Tokens only from each app's `src/theme` (deep-teal primary; severity scale derived + contrast-tested);
Hind Siliguri for all Bangla including in-chart labels and numerals (`Intl` bn); logo clear-space in
the header; no dashboard chrome invented outside module 02 primitives + shadcn/ui. Every string
verified in bn + en (`analytics.*`, `validation.*`); topic tags render as-is with a `bn`/`en`
language chip (`ANL-BR-009`).

## 9. Task Checklist

- [ ] `ANL-FE-001` Route `/school/ai-matrix` shell: role-adaptive scope (teacher = own sections, admin = school), Server Component first paint + 07 shell entry — ____
- [ ] `ANL-FE-002` `PainHeatmap` (Recharts): severity scale, in-cell numerals, topic rows as-is with language chips — ____
- [ ] `ANL-FE-003` `WeekSelector` + weeks list wiring (`?week=` param, `Intl` bn/en window captions) — ____
- [ ] `ANL-FE-004` `SectionSelector` (School Admin) + school topics×sections grid — ____
- [ ] `ANL-FE-005` `DrilldownPanel` + `InsightCard` (bn/en template re-render) + `SourceBreakdown` (counts only) — ____
- [ ] `ANL-FE-006` Empty states: insufficient-data + no-activity (bn/en) + `SuppressionCaption` — ____
- [ ] `ANL-FE-007` Error boundary + forbidden state + retry with request id — ____
- [ ] `ANL-FE-008` `RefreshButton`: 202 → polling → tag-coherent refetch; `RATE_LIMITED` copy with `retryAfter` — ____
- [ ] `ANL-FE-009` CSV export Route Handler (P2, scope-safe, suppressed rows excluded) — ____
- [ ] `ANL-FE-010` `analytics.*` / `validation.*` catalog wiring bn + en; Bangla numerals via `Intl` — ____
- [ ] `ANL-FE-011` A11y pass (§7) + axe clean on all states — ____
- [ ] `ANL-FE-012` Motion + reduced-motion variants (§5); tablet/360 responsive pass (§6) — ____

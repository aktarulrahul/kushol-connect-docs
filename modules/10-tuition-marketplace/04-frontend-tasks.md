# Tuition Marketplace — Frontend Tasks

**Module:** `10-tuition-marketplace`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Motion · RHF + Zod
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) is binding:
> tokens only from each app's `src/theme`, every user-facing string in Bengali + English.

---

## 1. Screen Inventory

The web build is the **admin surface** of the marketplace (guardians/students/tutors use the app,
`05-app-tasks.md`). Portal navigation entries live in module 07's shell — this module owns the
screens below and hands the nav contract to 07.

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/school/tutors` | Tutor-verification queue (routed: own-school rows; Super Admin sees the platform tab for `school_id` NULL rows) | Server Component + Server Actions | School Admin / Super Admin |
| 2 | `/school/tutors/[id]` | Verification detail + evidence viewer + approve/reject | Server Component + Client (viewer, forms) | School Admin (own school) / Super Admin (platform) |
| 3 | `/school/tuitions` | Requirements oversight list (read-only; close abusive) | Server Component + Server Actions | School Admin |

## 2. Screen Breakdown

### 2.1 Verification queue — `/school/tutors`

**Layout**

```text
┌──────────────────────────────────────────────────────────┐
│ School Admin › Tutors        [bn⇄en]   (07 shell chrome) │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ টিউটর ভেরিফিকেশন কিউ      ৪টি অপেক্ষমাণ (badge)      │ │
│ ├──────────────────────────────────────────────────────┤ │
│ │ তানভীর হাসান · ঢাকা বিশ্ববিদ্যালয় · গণিত, পদার্থবিজ্ঞান│ │
│ │ জমা: ৩০ সেপ্টেম্বর · SLA ৪৮ ঘণ্টা   [রিভিউ করুন →]    │ │
│ ├──────────────────────────────────────────────────────┤ │
│ │ … 3 more rows …                                      │ │
│ └──────────────────────────────────────────────────────┘ │
│ Tabs (Super Admin only): [ স্কুল | প্ল্যাটফর্ম ]          │
└──────────────────────────────────────────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `VerificationQueueTable` | Server Component | TanStack Table; columns: tutor, university, subjects (bn labels), submitted, SLA chip; row → detail |
| `QueueTabs` | Client | School ↔ Platform tabs (platform tab Super-Admin-only); `GET /school/tutor-verifications` scope switch |
| `SlAChip` | Server | "৪৮ ঘণ্টা পার / SLA overdue" when pending > 48 h (OQ-7 default) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton rows matching the table |
| Empty | "কোনো অপেক্ষমাণ ভেরিফিকেশন নেই / No pending verifications" |
| Error | Boundary with retry + request id |
| Cross-tenant row | Never renders (server-scoped); direct URL → branded 404 |
| Success | Decision returns to queue with the row removed + toast |

### 2.2 Verification detail — `/school/tutors/[id]`

**Layout**

```text
┌───────────────────────────┬────────────────────────────┐
│ তানভীর হাসান · ভেরিফিকেশন  │ প্রোফাইল                    │
│ জমা: ৩০ সেপ্টেম্বর ১৪:০৫   │ বিশ্ববিদ্যালয় · বিষয় · শ্রেণি │
│ ┌───────────────────────┐ │ ফি/availability (hint ৳)   │
│ │ [জাতীয় পরিচয়পত্র 🖼]   │ ├────────────────────────────┤
│ │ [বিষয় প্রমাণ ১ 🖼]     │ │ সিদ্ধান্ত                    │
│ │ [বিষয় প্রমাণ২ 🖼]      │ │ [✅ অনুমোদন]  [✕ বাতিল]     │
│ └───────────────────────┘ │ নোট/কারণ ( textarea )       │
│ evidence viewer (05)      │ reject ⇒ কারণ আবশ্যক        │
└───────────────────────────┴────────────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `EvidenceViewer` | Client | Reuses module 05's media viewer (short-lived R2 URLs); zoom + page-through for PDFs; degraded placeholder if an object is missing |
| `ApproveForm` / `RejectForm` | Client (RHF + zod) | approve: optional note · reject: `decisionNote` required (5–500); disable while pending; never lose input |
| `ProfileSummary` | Server | Public-safe profile fields for context (never contact) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Two-pane skeleton |
| Evidence missing (R2) | Degraded placeholder; decision buttons disabled for that item with explanation |
| Already decided | Read-only banner "সিদ্ধান্ত হয়ে গেছে / Already decided" + decision + reviewer + time |
| Success | Toast + redirect to queue; `tuition:tutors:{area}` / `tuition:tutor:{id}` tags revalidated |

### 2.3 Requirements oversight — `/school/tuitions`

Read-only table of the school's requirements (`GET /tuition/requirements` with School Admin
role): poster (name + role), subjects (bn), class, budget band ৳, area, status chip
(খোলা/ম্যাচড/বন্ধ/মেয়াদোত্তীর্ণ), posted date. Row action: **close** (`PATCH …/{id}` close) with
a confirm dialog + optional note — used for abusive posts only. States: loading skeleton; empty
"কোনো রিকোয়ারমেন্ট নেই / No requirements"; error boundary with retry; closed row shows the
closer + audit note. No editing of poster content from the web — oversight is read-only by
design.

## 3. Forms

| Field | Control | Zod rule | Default | Conditional on |
| --- | --- | --- | --- | --- |
| Approve note | textarea | ≤ 500 chars (optional) | — | approve action |
| Reject `decisionNote` | textarea | 5–500 chars, required (`validation.tuition.decision_note_required`) | — | reject action |
| Close note | textarea | ≤ 300 chars (optional) | — | oversight close action, behind confirm dialog |

Submission: same zod rules on the server (Server Actions) · disable while pending · map `fields`
errors · never lose input · unsaved-changes guard when navigating away from a half-written
decision.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Queue / detail / oversight reads | Server Components → generated `openapi-fetch` client → api (`GET /school/tutor-verifications`, `GET /tuition/requirements`) |
| Decisions / close | Server Actions → api (`POST …/approve|reject`, `PATCH /tuition/requirements/{id}`) → toast + `revalidateTag` |
| Evidence media | URLs resolved server-side from 05 media (short-lived R2 downloads); never cached |
| Tag subscription | `tuition:tutors:{area}`, `tuition:tutor:{id}` (declared in `06` §4) — busts land after decisions/profile edits |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Queue row removal | height collapse + fade (≤ 150 ms) | decision success | item resolved | instant removal |
| Decision toast | slide-in | approve/reject/close | outcome confirmed | instant show |
| Evidence viewer open | fade + scale (≤ 120 ms) | thumbnail tap | context switch | instant open |
| Status chip change | colour/label swap (no animation) | refetch | fresh state | static |

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 | ≥ 1024 |
| --- | --- | --- | --- |
| Queue table | Cards stacked (tutor + SLA + action) | Table with hidden low-priority columns | Full table |
| Verification detail | Single column (viewer above decision) | Two column | Two column (as wireframe) |
| Oversight table | Cards | Table | Table + row actions |

## 7. Accessibility

- [ ] Landmarks, one `h1`, heading order
- [ ] Keyboard path complete; focus visible and never lost (table rows, viewer, forms)
- [ ] Labels, descriptions, error announcements (decision note errors announced)
- [ ] Contrast in both themes; status never colour-only (text chips)
- [ ] Motion: reduced-motion variant verified
- [ ] axe clean (WCAG 2.2 AA) on all three routes

## 8. Design-System Compliance

`docs/design-reference/README.md` usage rules hold: tokens from each app's `src/theme`, Hind Siliguri
for Bangla admin copy (queue, decisions) with Inter for data, verified-badge component shared
with the app. Every string verified in bn + en — queue: "টিউটর ভেরিফিকেশন কিউ / Tutor
verification queue"; badge: "ভেরিফাইড টিউটর / Verified Tutor"; decisions: "অনুমোদন / Approve",
"বাতিল / Reject" (namespace `tuition.*`).

## 9. Task Checklist

- [ ] `TUT-FE-001` Queue route `/school/tutors` (table, tabs, SLA chips, states) + contract handoff of the nav entry to 07's shell
- [ ] `TUT-FE-002` Verification detail + `EvidenceViewer` (05 media reuse) + degraded-evidence state
- [ ] `TUT-FE-003` Approve/reject forms (shared zod `validation.tuition.*`, server actions, tag revalidation)
- [ ] `TUT-FE-004` Requirements oversight `/school/tuitions` (read-only table + guarded close action + audit note display)
- [ ] `TUT-FE-005` bn/en string keys `tuition.admin.*` added to each app's `src/i18n` + bilingual verification
- [ ] `TUT-FE-006` Motion + reduced-motion variants per §5
- [ ] `TUT-FE-007` Responsive tables/cards per §6
- [ ] `TUT-FE-008` Accessibility pass (§7) + Playwright smoke: queue → detail → approve → row removed

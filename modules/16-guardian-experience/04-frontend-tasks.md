# Guardian Experience — Frontend Tasks (web, institution console)

**Module:** `16-guardian-experience`
**Stack:** Next.js 16 App Router · TypeScript strict · Tailwind v4 tokens · shadcn-style primitives (`src/components/ui`) · TanStack Query · RHF + Zod · generated `openapi-fetch` client (`src/api/schema.gen.ts`)
**Last updated:** 2026-10-19

> **Status: planned, not built.** The web surface is for **institution admins only**. Guardians
> have no web portal: `dashboard-path.ts` sends guardians to the app download, and guardian
> sign-up stays app-only (03 G-12, OQ-17).
>
> Binding rules:
> - `docs/design-reference/README.md`: tokens only outside `src/components/ui/**`, Hind
>   Siliguri + Inter.
> - Every string goes through `useT()` with bn and en keys.
> - No new web namespace. Keys live under `school.guardians.*` and `school.nav.guardians`. The
>   web `NAMESPACES` length test (27) stays unchanged.

---

## 1. Screen Inventory

| # | Route | Screen | Rendering | Access | Phase |
| --- | --- | --- | --- | --- | --- |
| 1 | `/institution/guardians` (tab `links`, default) | Guardian links | Client component in the 07 console shell | School Admin; Super Admin (school picker, `?schoolId=`) | G1 |
| 2 | `/institution/guardians?tab=requests` | Link-request queue | Client | School Admin, Super Admin | G1 |
| 3 | `/institution/guardians?tab=invites` | Guardian invites | Client | School Admin, Super Admin | G2 |
| 4 | `/institution/users` (existing, WEB-FE-018) | Verification queue: guardian rows gain evidence and the student picker | Client | School Admin, Super Admin (ambassadors have no web portal) | G0 |
| 5 | `/institution/sections/[sectionId]` (existing) | Guardian count per section, with a link to the filtered links tab | Client | School Admin, Super Admin | G1 (optional) |
| 6 | `/institution/roster/new` (existing, 14) | Template help lists the optional guardian columns | Client | School Admin | G2 |
| 7 | `/register` (existing `register-island.tsx`) | Relation select widened (kept for parity even though phone OTP is refused on web) | Client | Public | G1 |

## 2. Screen Breakdown

### 2.1 Guardian links — `/institution/guardians`

**Layout**

```text
Desktop (≥1024)
┌ PageHeader: অভিভাবক / Guardians ─────────────── [+ Link guardian] ┐
│ Tabs: Links (n) | Requests (n · SLA badge) | Invites (G2)           │
│ Filters: [Section ▾] [Relation ▾] [Source ▾] [Status ▾] [Search…]   │
│ ┌ DataTable ─────────────────────────────────────────────────────┐ │
│ │ Guardian · masked phone │ Student · ID │ Class-Section │ Relation│ │
│ │ Primary ★ │ Source chip │ Status │ Linked on │ ⋯ (edit/revoke)    │ │
│ └────────────────────────────────────────────────────────────────┘ │
│ Pagination (cursor)                                                 │
└─────────────────────────────────────────────────────────────────────┘
Row click → right Sheet: guardian card (name, masked phone, status) +
"Children of this guardian" list + "Guardians of this student" list.

Mobile (<640): filters collapse into a "Filters" sheet; table → stacked cards
(guardian / student / relation / ⋯).
```

**Components** (`src/components/console/guardians/*`)

| Component | Server/Client | Notes |
| --- | --- | --- |
| `GuardiansPage` | Client | Tab state in the URL `?tab=`. Wraps the three panels. |
| `GuardianLinksTable` | Client | `ui/data-table` in server mode (cursor); filter chips; row action menu |
| `GuardianLinkSheet` | Client | `ui/sheet`. Shows the guardian's children and the student's guardians from the same list endpoint (`?guardianId=` / `?studentId=`). |
| `EditLinkDialog` | Client | Relation select plus a primary switch, with a warning that the current primary will be replaced |
| `RevokeLinkDialog` | Client | Reason textarea (10–500) with a counter, and a confirm step stating the guardian loses access at once |
| `LinkGuardianDialog` | Client | Student picker (search `/school/users?role=student&q=`), then an existing guardian picker **or** phone + name + relation (G2 creates an invite), plus a primary switch |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Table skeleton with 8 rows matching the columns |
| Empty | "No guardians linked yet" plus actions: Link guardian, and Upload roster (G2) |
| Error | Error boundary with retry and request id |
| Not found | n/a (list page) |
| Success | Toast "Link updated" / "Link revoked". The row updates in place and the query is invalidated. |

### 2.2 Link-request queue — `?tab=requests`

**Layout**

```text
┌ Request card ──────────────────────────────────────────────────────┐
│ করিম রহমান · +880 17•• ••• •09 · Father · 2 days ago [SLA 48h ⚠]   │
│ Claims: Student ID "ডেমো-0042" · name "রাফি" · Class 7 – B            │
│ Candidates:  (•) রাফি আহমেদ · ডেমো-0042 · 7-B   [code match]          │
│              ( ) রাফিউল ইসলাম · — · 7-A        [name match]           │
│              [Search other students…]                                │
│ [Reject…]                                         [Approve link]     │
└────────────────────────────────────────────────────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `LinkRequestQueue` | Client | Status filter (PENDING default). SLA badge reuses the WEB-FE-018 pattern. |
| `MatchStudentDialog` | Client | **Shared** with `/institution/users` (G0). Ranked candidates with a `matchedBy` chip, plus a search fallback. Approve is disabled until a student is picked. |
| `RejectRequestDialog` | Client | Reason 10–500 |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Card skeletons |
| Empty | "No pending requests" (positive tone) |
| Error | Retry plus request id. On `CONFLICT`: "Already decided by another admin" and refetch. |
| Success | Toast, then the card leaves the list with a collapse animation |

### 2.3 Invites — `?tab=invites` (G2)

A table showing student, masked phone, guardian name, relation, source (ADMIN/ROSTER/LMS), status,
SMS sent, expires, and a menu (Resend, Revoke). `InviteGuardianDialog` covers the student picker,
phone (BD), name, relation, and "Send SMS" (disabled with an explanation when the school has SMS
invites off).

### 2.4 Verification queue guardian rows — `/institution/users` (G0)

- Extend the fixture `VerificationRequest` type with
  `evidence?: { studentCode: string; relation: Relation }` and
  `guardianCandidates?: GuardianCandidate[]`.
- Guardian rows show the evidence. Approve opens `MatchStudentDialog` and sends
  `decideVerification(id, 'approve', { studentUserId })`.
- Without a pick, approve is impossible, matching the api's `VALIDATION_FAILED` rule.

## 3. Forms

| Field | Control | Zod rule | Default | Conditional on |
| --- | --- | --- | --- | --- |
| `studentUserId` | Candidate radio / search combobox | uuid, required | top candidate when `matchedBy='student_code'`, else none | approve |
| `reason` | Textarea with a counter | trimmed 10–500 | — | reject, revoke |
| `relation` | Native select | `GuardianRelation` enum (10 values) | current value | edit, link, invite |
| `isPrimary` | Switch | boolean | false | edit, link |
| `guardianUserId` | Combobox over `/school/users?role=guardian&q=` | uuid | — | link, "existing guardian" mode |
| `phone` | Input `tel`, BD hint | BD mobile regex, normalised to E.164 | — | link, "new guardian" mode (G2) / invite |
| `guardianName` | Input | 2–80, optional | — | invite |
| `sendSms` | Checkbox | boolean | true when the school's SMS invites are on | invite |

Submission: the same Zod schemas as the generated contract. Buttons are disabled while pending.
Server `fields` errors map onto the inputs. Input is never lost on error. Dialogs have an
unsaved-changes guard.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Lists (links, requests, invites, candidates) | TanStack Query → `src/fixtures/guardians.ts` seam (fictional ডেমো data mirroring the contract) → swapped for the generated client when 07's console glue is live (07/12 G-3 boundary) |
| Mutations | `useMutation` → seam/client → toast + `invalidateQueries(['school','guardian-links'])` and the related keys. CSRF via the console client (`consoleCSRF` on the api). |
| Student and guardian pickers | `GET /api/v1/school/users?role=…&q=` (exists), plus the new `studentCode` field |
| Section filter options | Existing sections seam (`/institution/sections`) |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Dialogs and sheet | Fade + 98→100% scale; sheet slide-in 200 ms | open/close | Focus moved to a task | Instant |
| Decided request card | Height collapse 180 ms | approve/reject success | Item left the queue | Instant removal |
| SLA badge | Static colour by age (no pulse on web) | render | Urgency | n/a |

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 | ≥ 1024 |
| --- | --- | --- | --- |
| Links table | Stacked cards, filters in a sheet | Table with fewer columns (source and date hidden) | Full table |
| Request cards | Full width; candidates stacked | Same | Two-column card (claim / candidates) |
| Link sheet | Full-screen drawer | Right sheet 480px | Right sheet 520px |

The page uses 16px side gutters and has no horizontal page scroll.

## 7. Accessibility

- [ ] Landmarks, one `h1` ("Guardians"), heading order through the tabs
- [ ] Tabs are a roving-tabindex `tablist`. Row menus are keyboard reachable. Focus returns to the row after a dialog.
- [ ] Candidate list is a `radiogroup` with labels "{name}, ID {code}, {class}, matched by {kind}"
- [ ] Contrast checked in both themes. The SLA badge is not colour-only (it also shows text "48h+").
- [ ] Reduced-motion variants verified

## 8. Design-System Compliance

- Tokens only. Raw hex and px only inside `src/components/ui/**`.
- Primitives come from `src/components/ui` (data-table, dialog, sheet, badge, empty-state,
  native-select).
- New keys go under `school.guardians.*` (plus `school.nav.guardians`), added to **both**
  `src/i18n/en.json` and `bn.json` with Edit (shared catalogs). The parity test must pass.
- Existing `auth.relation.*` keys are reused, and the 7 new relation keys are added
  (`auth.relation.grandfather` … `legal_guardian`).

## 9. Task Checklist

> Status on 2026-10-19: planned, not built.

- [ ] `GRD-FE-001` Fixture seam `src/fixtures/guardians.ts` (types mirror the generated `GuardianLinkRow`, `GuardianLinkRequestRow`, `GuardianInvite` and `GuardianCandidate`), with fictional ডেমো data
- [ ] `GRD-FE-002` Nav entry in `INSTITUTION_NAV` (`admin-portal-layout.tsx`, shared file, anchored Edit): `{ href: "/institution/guardians", label: "school.nav.guardians", icon: … }`
- [ ] `GRD-FE-003` Route `src/app/institution/guardians/page.tsx` plus `GuardiansPage` tabs shell
- [ ] `GRD-FE-004` `GuardianLinksTable` plus `GuardianLinkSheet`
- [ ] `GRD-FE-005` `LinkRequestQueue` plus `RejectRequestDialog`
- [ ] `GRD-FE-006` `MatchStudentDialog` (shared)
- [ ] `GRD-FE-007` `EditLinkDialog` and `RevokeLinkDialog`
- [ ] `GRD-FE-008` `LinkGuardianDialog` (existing-guardian mode in G1; phone mode in G2)
- [ ] `GRD-FE-009` Invites tab plus `InviteGuardianDialog` (G2)
- [ ] `GRD-FE-010` `/institution/users`: guardian evidence plus `MatchStudentDialog` on approve; fixture type extended (G0, with 07)
- [ ] `GRD-FE-011` Section page guardian count plus link (optional)
- [ ] `GRD-FE-012` `register-island.tsx` relation enum widened (with `GRD-INT-007`)
- [ ] `GRD-FE-013` i18n keys `school.guardians.*`, `school.nav.guardians` and `auth.relation.*` (bn + en)
- [ ] `GRD-FE-014` Vitest: seam contract shape, reason and phone zod rules, approve disabled without a pick, masked phones only. Playwright spec `guardians-console.spec.ts` (run by the owner).
- [ ] `GRD-FE-015` Swap the seam for the generated client when 07's console glue lands (prerequisite for Gate 3 on web)

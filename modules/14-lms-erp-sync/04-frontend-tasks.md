# LMS/ERP Sync — Frontend Tasks

**Module:** `14-lms-erp-sync`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Motion · Embla · RHF + Zod
**Last updated:** 2026-09-30

`docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) is binding:
tokens only from each app's `src/theme`, every user-facing string in Bengali + English.

---

## 1. Screen Inventory

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/school/roster` | Roster home: imports history + summary cards (fills the 07 stub §2.13 row 21) | Dynamic | School Admin |
| 2 | `/school/roster/new` | Upload wizard (3 steps + summary: template → upload → dry-run report → commit) | Dynamic | School Admin |
| 3 | `/school/roster/imports/[id]` | Import status + totals + error rows + error-CSV download | Dynamic | School Admin |
| 4 | `/school/integrations` | ERP webhook endpoints (fills 07's `/school/integrations` stub, row 22; nav label "ইন্টিগ্রেশন / Integrations") | Dynamic | School Admin |
| 5 | `/school/roster/reconciliation` | Reconciliation report (roster vs platform drift) — linked from roster home + `/school` dashboard card | Dynamic | School Admin |

## 2. Screen Breakdown

### 2.1 Roster home — `/school/roster`

**Layout**

```text
TABLET 640–1023 (portal ≥768 target)
┌──────────────────────────────────────────────┐
│ Roster (রোস্টার)        [নতুন আপলোড ▸]        │
│ ┌─────────┐ ┌─────────┐ ┌─────────┐          │
│ │ last    │ │ active  │ │ drift   │ cards    │
│ │ import  │ │ students│ │ flagged │          │
│ └─────────┘ └─────────┘ └─────────┘          │
│ Imports table (TanStack): file, date, status,│
│ totals (✓/↻/⨯), [view] — poll while running  │
│ Links: [গণনা মিলিয়ন দেখুন / Reconciliation]  │
└──────────────────────────────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `ImportSummaryCards` | Server | Last import totals + platform ACTIVE count + drift flag |
| `ImportsTable` (TanStack Table) | Client | Status badges; row click → `/school/roster/imports/[id]`; polls while `validating`/`committing` |
| `ReconciliationLink` | Server | Deep link to §2.5 |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton matching cards + table rows |
| Empty | "এখনো কোনো আপলোড নেই" / "No uploads yet" + primary action [টেমপ্লেট ডাউনলোড → আপলোড শুরু] |
| Error | Boundary with retry + request id |
| Running import | Status badge + auto-poll (3 s) until terminal state |
| Success | Totals toast after commit lands (bn/en, see §8 examples) |

### 2.2 Upload wizard — `/school/roster/new`

**Layout**

```text
Step 1              Step 2                Step 3 (report → commit)
┌───────────┐   ┌──────────────────┐   ┌────────────────────────┐
│ [CSV টেম- │   │ Drop zone / pick │   │ ✔ 4,812 valid          │
│ প্লেট ডাউন-│ → │ file · dry_run   │ → │ ⨯ 12 error rows table  │
│ লোড] bn/en │   │ toggle (default  │   │   (row no + bn reason) │
│ instruction│   │ on) · progress   │   │   [error CSV ডাউনলোড]  │
│ sheet note │   │ bar >500 rows    │   │ [আবার আপলোড] [কমিট]   │
└───────────┘   └──────────────────┘   └──→ summary panel ────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `TemplateStep` | Server + client button | Download via `GET /school/roster/template`; explains bn/en sheet + English headers |
| `UploadStep` | Client (RHF + zod) | Presigned PUT → confirm (05 flow) → `POST /school/roster/imports`; progress bar for > 500 rows |
| `DryRunReport` | Client | Error table: `rowNo`, i18n `errorKey` message, detail; commit disabled while `validated_with_errors` (`LMS-BR-003`) |
| `CommitSummary` | Client | created/updated/skipped/errored counts + link to detail; unsaved-changes guard on wizard exit |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Step skeletons; upload shows bytes-progress, then "যাচাই চলছে… / Validating…" |
| Empty | N/A (wizard) |
| Error | Upload failure keeps file selection + reason (`sync.import.*`); boundary for report load |
| Hash no-op | Same-file re-upload → panel "এই ফাইল আগে আপলোড হয়েছে" + link to the original import (200 no-op) |
| Success | Summary counts + audit note ("কমিট হয়েছে") |

### 2.3 Import detail — `/school/roster/imports/[id]`

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `ImportStatusHeader` | Server + poll | status badge, `dryRun` flag, committed-at, fail reason (`failed`) |
| `TotalsRow` | Server | rows/created/updated/skipped/errored |
| `ErrorRowsTable` | Client | paged `result=error` rows; download error CSV (`?as=csv`) |
| `CommitButton` | Client | Visible iff `ready`; confirm dialog with counts → 202 + poll |

**States** — Loading (skeleton) · Empty (no errors → success panel) · Error (retry) ·
Polling while `committing` · Cross-tenant → branded 404 · Success (terminal totals).

### 2.4 Integrations — `/school/integrations`

**Layout**

```text
┌────────────────────────────────────────────────────────┐
│ ERP/Webhook ইন্টিগ্রেশন          [+nতুন এন্ডপয়েন्ट]      │
│ Endpoint table: name · url · status · v(n) ·           │
│ last success · [টেসট] [রোটেট] [ইভেন্ট লগ] [রিভোক]      │
│ Secret modal (create/rotate): raw secret ONCE +        │
│ bn/en warning + [কপি] + acknowledge checkbox           │
│ Event log drawer: time · type · status · reason ·      │
│ [redrive] on error rows                                │
└────────────────────────────────────────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `EndpointsTable` | Client | Health columns; revoked rows greyed, actions hidden |
| `SecretRevealModal` | Client | Focus-trapped; `aria-live="assertive"` warning: "এই সিক্রেট আর কখনো দেখানো হবে না" / "This secret will never be shown again"; copy button; ack required to close |
| `TestEventButton` | Client | Posts test → success/failure feedback inline (`LMS-US-006`) |
| `RotateSecretDialog` | Client | Overlap window shown (24 h default); returns new raw secret into `SecretRevealModal` |
| `EventLogDrawer` | Client | Paged log (`GET …/events`); `redrive` action on `error` rows with result feedback |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Table skeleton |
| Empty | "কোনো এন্ডপয়েন্ট নেই" / "No endpoints yet" + primary create action + integration guide link |
| Error | Boundary + retry |
| Test failed | Failure reason + "check your ERP URL" hint; endpoint stays ACTIVE |
| Success | Test ✓ inline; rotation/creation modals close after ack |

### 2.5 Reconciliation — `/school/roster/reconciliation`

**Components** — `BaselineCard` (last import + totals or "no baseline" state) ·
`PlatformCountsCard` · `DriftTable` (per-section delta, flagged rows highlighted, no PII).

**States** — Loading (skeleton) · Empty/no baseline (explained, not an error) · Error (retry) ·
Success (drift table + print-friendly layout).

## 3. Forms

| Field | Control | Zod rule | Default | Conditional on |
| --- | --- | --- | --- | --- |
| upload `file` | dropzone/file input | `csv\|xlsx` extension + ≤ 20 MB (mirror `sync.import.*`) | — | — |
| upload `dryRun` | switch | boolean | `true` | — |
| endpoint `name` | input | 1–80 chars (`sync.endpoint.name_invalid`) | — | — |
| endpoint `url` | input | HTTPS URL ≤ 500 (`sync.endpoint.url_invalid`) | — | — |
| rotate `overlapHours` | stepper | int 1–72 | 24 | rotate dialog |
| secret ack | checkbox | must be `true` to close modal | `false` | secret modal |
| redrive confirm | dialog | none (single event id) | — | `error` event rows |

Submission: same Zod schemas on the Route Handler (mirrors the OpenAPI contract) · disable while
pending · map `fields` errors · never lose input · unsaved-changes guard on the wizard.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Portal reads (history, endpoints, events, report) | Server Component first paint → TanStack Query tables; poll 3 s while `validating`/`committing` (stop on terminal) |
| Upload | Client → `POST /media/upload-url` → PUT R2 → `POST /media/{id}/confirm` → `POST /school/roster/imports` (multipart ref) → job id + poll |
| Mutations (commit, endpoints, rotate, test, revoke, redrive) | Route Handler → generated `openapi-fetch` → api → toast + table invalidation (`school:{id}:roster`) |
| Template / error CSV | `GET` streams with `Content-Disposition: attachment`; `no-store` |
| Secret display | Only from the create/rotate response kept in memory — never refetched, never cached |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Wizard step change | 200 ms translate + fade | next/previous | progression | instant swap |
| Upload/validate progress | determinate bar; indeterminate only while polling | bytes / poll ticks | work happening | static % text |
| Status badge | colour + label change only (no pulse) | poll | state | same |
| Secret modal | scale-fade 150 ms | create/rotate | context switch | instant |
| Toast | slide-in 150 ms, auto-dismiss 4 s | mutation result | feedback | fade only |
| Skeleton shimmer | 1.2 s loop | loading | data arriving | static grey blocks |

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 | ≥ 1024 |
| --- | --- | --- | --- |
| Roster home / reconciliation | stacked cards, table → card rows | cards 2-up, table scroll-x | full table + side links |
| Wizard | full-width steps | centred panel 560 px | centred panel 640 px |
| Integrations | actions in row overflow menu | table scroll-x | full table + drawer |
| Event log drawer | bottom sheet | side drawer 480 px | side drawer 480 px |

## 7. Accessibility

- [ ] Landmarks, one `h1`, heading order
- [ ] Keyboard path complete (upload, commit, test, rotate, redrive); focus visible, trapped in modals, never lost
- [ ] Labels, descriptions; secret warning announced (`aria-live="assertive"`); status changes announced politely
- [ ] Error tables: real `<table>`, scoped headers, row numbers as text
- [ ] Contrast in both themes; status never colour-only (icon + label); motion reduced-motion variants verified (§5)

## 8. Design-System Compliance & bn/en Strings

Tokens from each app's `src/theme` only; Hind Siliguri for bn; every string via `sync.*` (bn default +
en). Representative catalog entries:

| Key | bn | en |
| --- | --- | --- |
| `sync.import.success` | আপলোড সফল: ৪,৮১২ সফল, ১২ ত্রুটি, ০ বাদ | Upload finished: 4,812 valid, 12 errors, 0 skipped |
| `sync.row.section_unknown` | সারি {row}: সেকশন "{section}" পাওয়া যায়নি | Row {row}: section "{section}" not found |
| `sync.import.hash_noop` | এই ফাইল আগেই আপলোড হয়েছে — আগের ফলাফল দেখানো হলো | This file was already uploaded — showing the original result |
| `sync.webhook.test_success` | টেস্ট ইভেন্ট সফল হয়েছে ({ms} মি.সে.) | Test event succeeded ({ms} ms) |
| `sync.webhook.test_failed` | টেস্ট ব্যর্থ: {reason} — ERP URL ও সিক্রেট যাচাই করুন | Test failed: {reason} — check your ERP URL and secret |
| `sync.secret.warning` | ⚠ এই সিক্রেট আর কখনো দেখানো হবে না — এখনই ERP-তে সংরক্ষণ করুন | ⚠ This secret will never be shown again — store it in your ERP now |

## 9. Task Checklist

- [x] `LMS-FE-001` `/school/roster` home (cards + history table + polling) — ____
- [x] `LMS-FE-002` wizard step 1: template download + bn/en instruction explainer — ____
- [x] `LMS-FE-003` wizard step 2: upload (05 presign flow) + `dryRun` toggle + progress — ____
- [x] `LMS-FE-004` wizard step 3: dry-run report (error table + error-CSV) + hash no-op panel — ____
- [x] `LMS-FE-005` commit action + summary panel + totals toast — ____
- [x] `LMS-FE-006` `/school/roster/imports/[id]` detail (status, totals, error rows, commit button) — ____
- [x] `LMS-FE-007` `/school/integrations` endpoints table + create form — ____
- [x] `LMS-FE-008` `SecretRevealModal` (show-once, copy, bn+en warning, ack) — ____
- [x] `LMS-FE-009` test-event button + success/failure feedback — ____
- [x] `LMS-FE-010` rotate-secret dialog + overlap display — ____
- [x] `LMS-FE-011` event log drawer + redrive action — ____
- [x] `LMS-FE-012` `/school/roster/reconciliation` report screen + dashboard link — ____
- [x] `LMS-FE-013` replace 07 stubs: `/school/roster` + `/school/integrations` nav entries — ____
- [x] `LMS-FE-014` bn/en catalog entries (`sync.*`) in each app's `src/i18n` + zod schemas mirrored — ____
- [x] `LMS-FE-015` a11y pass (§7) + axe specs in `e2e/lms.spec.ts` — run pending owner (G-1) — 2026-10-04
- [x] `LMS-FE-016` responsive pass (cards stack < 640, tables scroll-x, wizard max-w-2xl) — 2026-10-04

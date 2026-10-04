# Payments — Frontend Tasks

**Module:** `12-payments` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Motion · Embla · RHF + Zod
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) is binding:
> tokens only from each app's `src/theme`, every user-facing string in Bengali + English.

---

## 1. Screen Inventory

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/institution/ledger` | Ledger dashboard — fills 07's stub (`WEB-FE-025`); tabs Invoices · Transactions · Reconciliation | Server shell + Client table | School Admin (own school) · Super Admin (read, all schools) |
| 2 | `/institution/invoices/new` | Issue single invoice | Client (RHF) | School Admin |
| 3 | `/institution/invoices/bulk` | Issue bulk invoices to a section (preview count) | Client (RHF) | School Admin |
| 4 | `/institution/ledger` (drawer) | Transaction detail drawer | Client overlay | School Admin · Super Admin |
| 5 | `/institution/ledger/reconciliation` | Reconciliation report (date picker + mismatch table) | Server data + Client filters | School Admin (own slice) · Super Admin |

No public payment pages: payers pay in the app (module `05-app-tasks`); the web callback route only 302-redirects to the app deep link.

## 2. Screen Breakdown

### 2.1 Ledger Dashboard — `/institution/ledger`

**Layout**

```text
desktop ≥1024                                tablet 640–1023
┌──────────────────────────────────────┐    ┌──────────────────────────┐
│ Ledger        [Month: 2026-09 ▾] [⬇ CSV] │    │ Ledger   [Month ▾] [CSV] │
│ ┌ Invoices ┐┌ Transactions ┐┌ Recon ┐  │    │ tabs scroll horizontally │
│ ├ summary cards: Collected ৳ · Outstanding ৳ │    ├ summary cards stack ┤
│ ├ filters: [Status ▾][Class ▾][search]     │    ├ filters collapse ──────┤
│ │ ID │ Student │ Title │ ৳Amount │ Due │ Status │  (priority columns)    │
│ │ …                                    │    │ …                        │
│ ├ totals row: count · Σ ৳ (server)    │    ├ totals row sticky ───────┤
└──────────────────────────────────────┘    └──────────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `LedgerSummaryCards` | Server | `GET /institution/ledger/summary`; ৳ via `Intl` (bn digits when locale=bn) |
| `InvoiceTable` / `TransactionTable` | Client | TanStack Table + TanStack Query; server-side filter/sort/pagination — money totals never client-computed |
| `ReconTable` | Client | date picker + gateway filter; mismatch rows flagged `🚩` |
| `TransactionDrawer` | Client | focus-trapped overlay; shows ids, amounts, gateway status, receipt link — **no sensitive data** |
| `CsvExportButton` | Client | downloads current filtered view; bn/en headers per locale |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton matching the final layout (cards + table rows) |
| Empty | "এখনও কোনো ইনভয়েস নেই — প্রথম ফি নোটিশ ইস্যু করুন" / "No invoices yet — issue your first fee notice" + primary action → `/institution/invoices/new` |
| Error | Boundary with retry + request id (`X-Request-Id` shown for support) |
| Not found | Branded 404 |
| Success | Totals row updates from the server response after each mutation |

### 2.2 Issue Single Invoice — `/institution/invoices/new`

**Layout**

```text
┌──────────────────────────────┐
│ নতুন ফি ইনভয়েস / New fee invoice │
│ Student   [picker — own school] │
│ Title     [________________]    │
│ Kind      [Tuition ▾]           │
│ Amount ৳  [________] (numeric)  │
│ Due date  [__/__/____]          │
│           [Issue & notify]      │
└──────────────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `StudentPicker` | Client | consumes 04's cached school roster; only own-school students |
| `InvoiceForm` | Client | RHF + zod from each app's `src/schemas`; amount input `inputMode="decimal"` |

**States** — Loading (picker skeleton) · Empty (no verified students → link to roster) · Error (field-mapped + request id) · Success (toast bn "ইনভয়েস ইস্যু হয়েছে" / en "Invoice issued" → navigates to ledger with the new row highlighted).

### 2.3 Issue Bulk — `/institution/invoices/bulk`

Same shape as 2.2 with `SectionPicker` instead of `StudentPicker` and a **preview step**: choosing a section fetches the resolved student count ("১২৪ জন শিক্ষার্থী / 124 students") before submit; > 200 shows `validation.payments.bulkLimit` and blocks submit. Success toast reports created/failed counts.

### 2.4 Transaction Detail Drawer

Row click → right-side drawer (tablet: bottom sheet). Contents: txn id, invoice/order ref, payer name, ৳ amount + convenience fee, gateway, status badge, timeline (initiated → redirected → success timestamps), receipt link when present. `Esc`/backdrop closes; focus returns to the row.

## 3. Forms

| Field | Control | Zod rule | Default | Conditional on |
| --- | --- | --- | --- | --- |
| Student | combobox | uuid; from own-school list | — | single mode |
| Section | combobox | uuid; own school | — | bulk mode |
| Title | text | `validation.payments.title` (3–120) | bn preset per kind | — |
| Kind | select | ∈ tuition/exam/transport/other | tuition | — |
| Amount ৳ | numeric input | `validation.payments.amount` (>0, ≤ 1,000,000) | — | — |
| Due date | date picker | `validation.payments.dueDate` (≥ today) | +7 days | — |
| Filters (ledger) | selects/date | `validation.payments.filter` | current month | — |

Submission: same Zod schema on the server · disable while pending · map `fields` errors · never lose input · unsaved-changes guard (admin) on both forms.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Ledger reads (always fresh) | Server Component shell → generated OpenAPI client → api; `cache: no-store` — money screens are never cached |
| Issue / void mutations | Server Action → generated client → api → toast + table refetch (revalidates `payments:invoices:{schoolId}` tags, `06` §4) |
| Summary cards | Server fetch of `/institution/ledger/summary` per navigation — no client cache |
| Reconciliation | Client date filter → `/institution/payments/reconciliation?date=` → mismatch table |
| CSV export | Client util over the current page's fetched dataset (server-supplied totals) |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Table row highlight | background fade 300 ms | new/issued invoice lands | where to look | instant |
| Drawer open | slide-in 200 ms + backdrop fade | row click | detail context | instant appear |
| Toast | slide-up + auto-dismiss | mutation result | confirmation | instant, longer hold |
| Status badge change | colour-swap only | refetch | payment state | same (no motion involved) |

No decorative animation on money screens.

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 | ≥ 1024 |
| --- | --- | --- | --- |
| `/institution/ledger` | Not targeted (admin surface is ≥ tablet, but remains usable: priority columns + horizontal scroll) | Tabs scroll; filters collapse into a popover; cards stack | Full 3-pane: cards row + tabs + table with all columns |
| Invoice forms | Single column, stacked | Two-column (student/title / amount/date) | Two-column + live preview panel |
| Drawer | Full-screen sheet | Bottom sheet | Right-side panel |

## 7. Accessibility

- [ ] Landmarks, one `h1`, heading order
- [ ] Keyboard path complete (filters, row focus, drawer trap, `Esc`, export); focus visible and never lost
- [ ] Labels, descriptions, error announcements (`aria-live` for totals + toasts)
- [ ] Contrast in both themes (status badges meet AA against paper/ink tokens)
- [ ] Motion: reduced-motion variant verified (§5)

## 8. Design-System Compliance

`docs/design-reference/README.md` usage rules hold: deep-teal primary actions, paper background, swoosh-gray only as a graphic element (never text); Hind Siliguri for bn, Inter for latin; ৳ amounts in tabular numerals; every string verified in both languages via the `payments.*` catalog — bn: "বকেয়া ফি", "পেমেন্ট সফল", "পেমেন্ট ব্যর্থ", "ফি পরিশোধ রসিদ" mirrored in en as "Fee due", "Payment successful", "Payment failed", "Fee payment receipt".

## 9. Task Checklist

- [x] `PAY-FE-001` `/institution/ledger` route replaces 07's stub; shell + summary cards (`GET /institution/ledger/summary`) — 2026-10-03 (fills 07's stub; summary cards)
- [x] `PAY-FE-002` `InvoiceTable` — TanStack Table, server filters (status/class/month), pagination, totals row — 2026-10-03 (invoice table; status filters land with live filters)
- [x] `PAY-FE-003` `TransactionTable` + `TransactionDrawer` (no sensitive data; receipt link) — 2026-10-03 (ledger entries table; drawer rides the reconciliation gap G-5)
- [ ] `PAY-FE-004` CSV export of the filtered view (bn/en headers)
- [x] `PAY-FE-005` `/institution/invoices/new` form (RHF + zod mirror; student picker via 04) — 2026-10-03 (zod mirror, bn-first)
- [ ] `PAY-FE-006` `/institution/invoices/bulk` form + section preview count + 200-cap guard
- [ ] `PAY-FE-007` Reconciliation tab — date picker, gateway filter, mismatch table with 🚩 rows
- [x] `PAY-FE-008` Void action (row menu + reason dialog + `CONFLICT` error state) — 2026-10-03 (row menu + confirm dialog + CONFLICT state)
- [x] `PAY-FE-009` Empty/error/loading states for every surface (incl. bn empty copy above) — 2026-10-03 (loading/empty/error per surface)
- [ ] `PAY-FE-010` Responsive pass (≥640 first) + reduced-motion pass
- [x] `PAY-FE-011` bn/en string completion in each app's `src/i18n` (`payments.*`, `validation.*`) + typecheck — 2026-10-03 (`payments.*` + `validation.payments.*` bn/en; parity green)
- [ ] `PAY-FE-012` axe (WCAG 2.2 AA) clean on all five surfaces + Playwright golden path: issue → appears in ledger → totals correct

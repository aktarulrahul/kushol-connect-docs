# B2B Ads & Events — Frontend Tasks

**Module:** `13-b2b-ads-events`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Motion · Embla · RHF + Zod
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) is binding:
> tokens only from each app's `src/theme`, every user-facing string in Bengali + English. This module
> **fills module 07's stubs**: the `/admin/campaigns` "ships in module 13" placeholder is replaced
> by the moderation queue below, and the vendor portal gains its ads/events sections.

---

## 1. Screen Inventory

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/vendor/ads` | Campaign list (status chips, spend/budget, actions) | Server Component + client table | Vendor (approved gate) |
| 2 | `/vendor/ads/new` | Campaign builder wizard (targeting → creative → schedule/budget → review+submit) | Client Component (form) | Vendor |
| 3 | `/vendor/ads/[id]` | Campaign detail + daily analytics (Recharts) + status timeline | Server shell + client chart | Vendor (own) |
| 4 | `/vendor/events` | Event manager list (status, tickets sold, revenue net) | Server Component + client table | Vendor |
| 5 | `/vendor/events/new`, `/vendor/events/[id]/edit` | Event create/edit form | Client Component (form) | Vendor |
| 6 | `/admin/moderation` | Moderation queue — campaigns + events tabs (fills 07's `/admin/campaigns` stub; stub route redirects) | Server shell + client decision cards | Super Admin |
| 7 | `/admin/ads` | Ads overview (spend, counts, ticket revenue/commission) | Server Component | Super Admin |
| 8 | `/events` | Public event listing, city filter | ISR (tagged) | Public |
| 9 | `/events/[id]` | Public event detail + register/buy + my-ticket state | ISR shell + client ticket action | Public / verified buyer |

## 2. Screen Breakdown

### 2.1 Campaign builder wizard — `/vendor/ads/new`

**Layout**

```text
desktop                              360px / tablet
┌────────────────────────────┐      ┌──────────────┐
│ Steps 1─4 (stepper)        │      │ stepper      │
│ ┌────────────┬───────────┐ │      │ field stack  │
│ │ fields     │ live      │ │      │ sticky est.  │
│ │            │ audience  │ │      │ estimate bar │
│ │            │ estimate  │ │      │ [Continue]   │
│ └────────────┴───────────┘ │      └──────────────┘
│ [Back] [Continue/Submit]   │
└────────────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `TargetingPicker` | Client | City (04 picker data) → grade → sections; **no user-level control exists** (BR-003); estimate card debounces `GET /vendor/audience-estimate`; `unknown` renders "estimate unavailable" — never a fake number |
| `CreativeEditor` | Client | bn/en side-by-side panes (bn first); per-locale title/body counters; image upload via 05 presign; **sponsored-label preview chip "স্পনসর্ড · Sponsored" locked on** (BR-005) |
| `ScheduleBudgetForm` | Client | datetime pickers, budget with ৳ formatting (`Intl`, bn digits) |
| `ReviewSubmitPanel` | Client | read-only summary + submit; disabled until zod-valid |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton matching step layout |
| Empty | No cities → explanation + contact path |
| Error | Boundary with retry + request id; estimate error never blocks the step |
| Not found | Branded 404 |
| Success | Submit → toast + redirect to `/vendor/ads/[id]` (pending_review state) |

### 2.2 Moderation queue — `/admin/moderation`

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `ModerationQueue` (tabs: Campaigns · Events) | Client (TanStack Table) | pending only; fresh data (no-store); SLA badge from queue age |
| `DecisionCard` | Client | creative preview (bn/en toggle), targeting summary ("চট্টগ্রাম · ক্লাস ১২ · ৩টি সেকশন"), budget/schedule, `cta_url` shown as link text |
| `ModerationChecklist` | Client | banned-category items (gambling/tobacco/age-inappropriate + policy `TODO: Confirm` link); approve disabled until all checked; checklist version sent with decision |
| `RejectDialog` | Client | reason textarea required (min 10 chars); submits reject |
| `AdsOverview` (`/admin/ads`) | Server | stat cards: spend, campaigns by status, events, tickets, gross/commission/net |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Table skeleton |
| Empty | "Queue clear" illustration + copy (`ads.moderation.empty`) |
| Error | Boundary with retry |
| Conflict | `CONFLICT` → row refresh + "already decided" banner |
| Success | Optimistic row removal; toast; audit note |

### 2.3 Public event detail — `/events/[id]`

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `EventHero` | Server | bn title default, city + venue + schedule (`Intl` bn), organiser badge; cancelled banner when applicable |
| `TicketAction` | Client | free → instant confirm; priced → reserve + "payment pending (বাকাশ/নগদ শীঘ্রই)" honest state — no dark patterns; remaining-capacity display |
| `MyTicketState` | Client | buyer's ticket status + cancel (before start) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | ISR shell + client slot skeleton |
| Empty / not found | Branded 404; unapproved ids never resolve (BR-012) |
| Error | Retry boundary |
| Sold out | Disabled action + capacity copy, never fake scarcity |
| Success | bn/en confirmation with ticket summary |

### 2.4 Vendor campaign list — `/vendor/ads` (and `/vendor/events`, `/admin/ads` same pattern)

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `CampaignTable` (TanStack Table) | Client | status chip (`ads.status.*`), schedule window, spend/budget bar, row actions (edit draft/rejected, pause/resume, view) |
| `StatusChip` | Client | token-mapped colour + text — never colour-only; rejected rows carry a reason banner (`ads.rejected_reason`) |
| `OverviewCards` (`/admin/ads`) | Server | spend, campaigns by status, events, tickets, gross/commission/net — explicit "connects module 13" only until this module ships the data (07 convention) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Table skeleton |
| Empty | Vendor: "no campaigns yet" + primary CTA to the builder; Admin: per-card zero states with labels |
| Error | Boundary with retry + request id |
| Success | Row actions toast + refresh (no-store surfaces refetch on focus) |

## 3. Forms

| Field | Control | Zod rule | Default | Conditional on |
| --- | --- | --- | --- | --- |
| campaign `name` | text input | 3–120 chars | — | — |
| targeting `cityId` | select (04 data) | uuid, required | vendor's city if known | — |
| targeting `grade` | select (class levels) | optional | — | city chosen |
| targeting `sectionIds` | multi-select | optional; each ∈ city | — | city chosen |
| creative `titleBn/bodyBn`, `titleEn/bodyEn` | textarea ×4 | required; ≤120/≤500 | — | — |
| creative `kind` | radio | `push` \| `native_banner` | `push` | — |
| creative `imageMediaId` | 05 upload | confirmed media uuid | — | kind = native_banner (required) |
| `ctaLabel` / `ctaUrl` | input | ≤40 / absolute https | — | — |
| `scheduleStart/End`, `budgetBdt` | datetime + number | order + >0 | now + 7d / — | — |
| event `cityId`, `titleBn/En`, `descriptionBn/En`, `venue` | as above | required | — | — |
| event `startsAt/endsAt`, `capacity` | datetime + number | order + future; 1–100,000 | — | — |
| event `ticketPriceBdt` | number + "free" toggle | null or ≥ 0 | free | — |
| ticket `qty` | stepper | ≥1 ≤ remaining | 1 | — |

Submission: same Zod schema on the server · disable while pending · map `fields` errors · never lose
input · unsaved-changes guard (vendor + admin).

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Vendor/admin reads | Server Components → generated OpenAPI client → api (no-store; money + moderation freshness) |
| Public events | ISR reads tagged `events:city:{id}`; revalidated by api mutations (06 §4) |
| Mutations (create/submit/pause/approve/reject/tickets) | Server Actions / Route Handlers → generated client → api → toast + refreshed view |
| Audience estimate | Client debounce → `GET /vendor/audience-estimate` (Redis-backed, 5-min) |
| Analytics chart | `GET /vendor/campaigns/{id}/analytics` (`ads_daily`) → Recharts; table fallback |
| Push/deep links | No web work — app push is module 06's contract; web receives campaign clicks via `cta_url` |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Wizard step change | slide-fade 200 ms | Continue/Back | progress | instant swap |
| Audience estimate update | number crossfade 150 ms | debounced fetch | liveness | instant value swap |
| Queue card decision | collapse + fade 200 ms | approve/reject | completion | instant removal |
| Chart draw-in | progressive series render | first view | data scope | full chart static |
| Status chip change | colour/token swap | poll/refresh | lifecycle | instant |

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 | ≥ 1024 |
| --- | --- | --- | --- |
| Builder wizard | single column, sticky estimate bar | 2-step panes | fields + estimate sidebar |
| Moderation queue | stacked decision cards | dense table | table + preview drawer |
| Vendor lists | card list | table | table + filters row |
| Event detail | single column, sticky ticket action | centred column | hero + meta 2-col |

## 7. Accessibility

- [ ] Landmarks, one `h1`, heading order
- [ ] Keyboard path complete (wizard, queue decisions, ticket action); focus visible and never lost
- [ ] Labels, descriptions, error announcements (`aria-live` on estimate + queue toasts)
- [ ] Contrast in both themes; sponsored label never colour-only
- [ ] Charts: data-table equivalent + summary text
- [ ] Motion: reduced-motion variant verified

## 8. Design-System Compliance

`docs/design-reference/README.md` usage rules hold (tokens, typography, logo clear-space); every
string verified in both languages. Namespaces `ads.*` (builder, queue, statuses, sponsored label),
`events.*` (listing, detail, tickets), `validation.ads.*` / `validation.events.*` added to
each app's `src/i18n` with module 02's parity gate. Bengali copy reviewed by Rahul before build sign-off;
honest-state copy everywhere (payment pending, estimate unknown, sold out) — no dark patterns.

## 9. Task Checklist

- [ ] `ADS-FE-001` Vendor `/vendor/ads` list + status chips + actions
- [ ] `ADS-FE-002` Builder wizard: `TargetingPicker` + live estimate (incl. `unknown` state)
- [ ] `ADS-FE-003` Builder wizard: `CreativeEditor` bn/en + locked sponsored-label preview
- [ ] `ADS-FE-004` Builder wizard: schedule/budget + review/submit; zod schemas from shared
- [ ] `ADS-FE-005` Campaign detail + Recharts analytics + table fallback
- [ ] `ADS-FE-006` Vendor events manager + create/edit forms (free toggle)
- [ ] `ADS-FE-007` `/admin/moderation` queue replacing 07 stub (+ `/admin/campaigns` redirect)
- [ ] `ADS-FE-008` Decision card: preview, targeting summary, checklist-gated approve, reason reject
- [ ] `ADS-FE-009` `/admin/ads` overview cards
- [ ] `ADS-FE-010` Public `/events` listing with city filter (ISR tags)
- [ ] `ADS-FE-011` Public `/events/[id]` detail + honest ticket states + cancel
- [ ] `ADS-FE-012` i18n catalogs `ads.*`/`events.*` (bn default) verified both languages
- [ ] `ADS-FE-013` Playwright + axe golden paths (builder → submit; queue → approve; event → free ticket)

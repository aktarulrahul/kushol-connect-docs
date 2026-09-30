# B2B Ads & Events — User Stories

**Module:** `13-b2b-ads-events` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

---

## 1. Purpose

Module 13 is revenue Stream 2 (`brd.md` §7): approved vendors run **demographic-targeted campaigns**
(BR-05 — e.g. "শুধুমাত্র চট্টগ্রামের ক্লাস ১২ এর বিজ্ঞান বিভাগ") as sponsored push over module 06's hierarchy
topics and native banners on web surfaces, every campaign Super-Admin-moderated — no exploitative targeting
of minors, demographic dimensions only (`prompt.txt` §9, `persona.md` SME duty). It also ships **city-wide
event listings with ticketing** at a 10% platform commission (PRD §7).

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Unverified user (pending) | Cannot buy tickets and receives no sponsored pushes — hierarchy topics (and thus campaign reach) attach only on verification (module 06 via module 04) |
| Student / Guardian / Teacher | Receives labelled, frequency-capped sponsored pushes on their `city-{id}`/`section-{id}` topics; browses public events; registers/buys tickets; cancels before start — guardians buy for their child; teachers are never an ad target distinct from their section topics |
| School Admin | No ads role — school data reaches vendors only as aggregate counts via module 04 exports |
| Super Admin | Moderates the campaign/event queue (approve / reject with reason + checklist, audit-logged); views the platform ads overview; can organize platform events |
| Vendor / EdTech brand | Creates campaigns and events (only after `vendors.Approve` from module 07), submits for review, edits drafts/rejected, pauses/resumes, views aggregate analytics and ticket revenue |
| System (jobs, webhooks) | `campaign.dispatch` / `campaign.complete` / `ads.daily_aggregate` / `tickets.sweep` jobs; module 06 broadcast at schedule time; module 12 fills `payment_transaction_id` when delivered |

> The five roles (Super Admin / School Admin / Teacher / Student / Guardian) plus Vendors are defined by
> module 03 (`03-identity-access`). Verification gates every participatory action (`prd.md` §5.1) — here it
> gates ticket purchase and campaign reach.

## 3. Scope

**In scope**

- `ad_campaigns` + `ad_creatives` lifecycle (draft → pending_review → approved/rejected → scheduled → running → paused → completed) with demographic-only targeting.
- Audience estimate from 04 counts; sponsored-push dispatch via `notify.BroadcastTopic` (targeting IS topic selection); native-banner selection for **web** surfaces (P1); moderation queue APIs + checklist; audit; pseudized aggregate-only `ad_events` analytics.
- `events` + `event_tickets`: listing, approval, free (instant) and paid (reserved → 12 seam) tickets, 10% commission, buyer cancellation, organizer revenue view.

**Out of scope** (explicit — prevents scope drift)

- In-app native ad slots and in-app event purchase — **recorded gap**: README scopes 13 to `api` + `web`; needs a future module amendment (Open Questions #3). Individual-level/behavioural targeting of minors and per-user ad profiles — forbidden (`persona.md`, `prompt.txt` §9).
- Real-time auctions and third-party ad SDKs — rejected (`02` §10). Payment capture, gateways and refunds — module 12 owns them; 13 only reserves tickets and exposes the `payment_transaction_id` seam.
- Email/SMS ad channels; A/B multi-creative testing; recurring schedules beyond a single start/end window.

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 06 notifications | `notify.BroadcastTopic` for sponsored push (topics `city-{id}`/`school-{id}`/`section-{id}`); `type=campaign` payload; push labels rendered per its contract |
| 07 command-center-web | `vendors.Approve` gate (only approved vendor accounts advertise); the `/admin/campaigns` moderation stub this module fills; `landing_leads` as top-of-funnel |
| 04 organization-hierarchy · 05 communication-engine | `cities/schools/sections` targeting dimensions + aggregated verified-user counts (`hierarchy.AudienceCount`, declared in 04 `06` §2); `media_assets` (R2 presign + magic-byte confirm) for creative images |
| 03 identity-access · 01 foundations | Role guards + buyer verification (03); `jobs.Enqueue`, `audit.Record`, RFC-7807 envelope, `default` limiter (01) |
| 12 payments | Seam only — `event_tickets.payment_transaction_id` filled by 12 once delivered; **not a build dependency** (README) |

---

## 4. User Stories

### `ADS-US-001` — Approved vendor creates a targeted campaign

**Priority:** P0 · **Traces:** BR-05 (`brd.md` §5) / PRD §7 · **Depends on:** 07 vendor approval

**Story** — As an **approved vendor**, I want **to build a campaign by picking a city, grade and sections, seeing a live audience estimate, writing the creative in Bengali + English, and setting schedule and budget**, so that **I can reach exactly the demographic I sell to**.

**Acceptance criteria**

- **Given** an approved vendor account, **when** the builder opens, **then** targeting offers city (required), grade and sections (optional) only — no user-level selection exists anywhere in the UI — and the estimate (aggregate count from 04) updates on each change.
- **Given** a complete creative (bn **and** en title/body, CTA label + https URL), schedule and budget, **when** saved, **then** the campaign is stored `draft` with targeting `{city_id, grade, section_ids[]}` and the sponsored label reserved server-side (vendor cannot type or remove it).

### `ADS-US-002` — Vendor submits a campaign for review

**Priority:** P0 · **Traces:** BR-05 / `prompt.txt` §9 · **Depends on:** ADS-US-001

**Story** — As an **approved vendor**, I want **to submit a draft campaign for moderation**, so that **nothing is served to students before a human approves it**.

**Acceptance criteria**

- **Given** a complete `draft`, **when** the vendor submits, **then** status becomes `pending_review`, the campaign appears in the Super Admin queue, and further edits are refused (`CONFLICT`).
- **Given** an incomplete draft or an unmodified rejected campaign, **when** submit is attempted, **then** `VALIDATION_FAILED` with field keys, or `CAMPAIGN_REJECTED` respectively.

### `ADS-US-003` — Super Admin approves or rejects with reason

**Priority:** P0 · **Traces:** `prompt.txt` §9 (Super Admin moderation) · **Depends on:** ADS-US-002

**Story** — As a **Super Admin**, I want **a queue showing each pending campaign with creative preview, targeting summary and a safety checklist, and to approve or reject with a mandatory reason**, so that **no exploitative or age-inappropriate ad ever reaches minors**.

**Acceptance criteria**

- **Given** a `pending_review` campaign, **when** the queue card opens, **then** creative (bn/en), targeting summary ("Chattogram · Class 12 · 3 sections"), budget/schedule and the moderation checklist (banned: gambling, tobacco, age-inappropriate — `TODO: Confirm` written policy) display.
- **Given** the checklist confirmed, **when** approve is clicked, **then** status becomes `approved` (→ `scheduled`/`running` per schedule) with `audit.Record` capturing actor, decision and checklist version; reject with a typed reason sets `rejected`, surfaces the reason banner to the vendor, and is audit-logged (reject stays disabled without a reason).

### `ADS-US-004` — System dispatches an approved sponsored push at schedule time

**Priority:** P0 · **Traces:** BR-05 / `brd.md` §7 Stream 2 · **Depends on:** ADS-US-003

**Story** — As the **system**, I want **a job that, at a campaign's schedule start, expands its demographic targeting into hierarchy topics and broadcasts the sponsored push via module 06**, so that **"শুধুমাত্র চট্টগ্রামের ক্লাস ১২ এর বিজ্ঞান বিভাগের ছাত্রদের" push arrives exactly on the chosen section topics**.

**Acceptance criteria**

- **Given** an approved campaign whose `schedule_start` is reached, **when** `campaign.dispatch` runs, **then** targeting expands to topics (sections → `section-{id}`; city+grade → matching sections; city only → `city-{id}`) and `notify.BroadcastTopic` is called per topic with `type=campaign`, class `campaigns`, title/body carrying "স্পনসর্ড / Sponsored".
- **Given** projected cost exceeding remaining budget, **when** dispatch is attempted, **then** the campaign auto-pauses and nothing sends (BR-006); otherwise aggregate impression rows (per topic, audience count, day bucket) are recorded, spend accrues, and the dispatch is audit-logged and idempotent.

### `ADS-US-005` — Student receives a labelled, frequency-capped sponsored push

**Priority:** P0 · **Traces:** `prompt.txt` §9 / `persona.md` (no dark patterns) · **Depends on:** ADS-US-004, module 06

**Story** — As a **verified student**, I want **to receive at most one sponsored push per week, clearly labelled "স্পনসর্ড / Sponsored"**, so that **ads never flood or deceive me**.

**Acceptance criteria**

- **Given** a subscribed topic receives a sponsored broadcast, **when** rendered, **then** title/body show the sponsored label in bn and en (injected server-side, not vendor-supplied).
- **Given** the topic already got a sponsored push in the trailing 7 days, **when** dispatch is attempted, **then** it is skipped and logged `frequency_cap_skipped` (default 1/user/week — `TODO: Confirm`); a tapped CTA records a pseudized `click` row — never a per-student profile.

### `ADS-US-006` — Vendor views aggregate campaign analytics

**Priority:** P1 · **Traces:** PRD §7 · **Depends on:** ADS-US-004

**Story** — As a **vendor**, I want **daily impressions, clicks, CTR and spend-vs-budget for my own campaign**, so that **I can judge whether the demographic reach worked**.

**Acceptance criteria**

- **Given** a campaign with activity, **when** its analytics open, **then** a daily chart plus totals, CTR and spend render from the aggregate store — only for the vendor's own campaigns (others → 404).
- **Given** any analytics request, **when** served, **then** no per-student row is returned or queryable (BR-008); the chart ships a data-table fallback (a11y).

### `ADS-US-007` — Vendor manages campaign state: edit, pause, resume

**Priority:** P1 · **Traces:** BR-006, BR-011 · **Depends on:** ADS-US-002, ADS-US-004

**Story** — As a **vendor**, I want **to edit my campaign while it is `draft` or after rejection, and pause/resume it while running**, so that **I control content and spend mid-flight**.

**Acceptance criteria**

- **Given** a `draft` or `rejected` campaign, **when** PATCH is sent with valid changes, **then** the update persists and a rejected campaign becomes resubmittable; any review-state row returns `CONFLICT` (immutable).
- **Given** a `running` campaign, **when** pause is clicked, **then** status `paused`, the dispatch job skips it and native selection stops serving it (budget exhaustion auto-pauses too, BR-006); **when** resumed inside the window, **then** it re-enters `running` at the next dispatch tick.

### `ADS-US-008` — Vendor lists an event and gets it published

**Priority:** P0 · **Traces:** BR-05 / `brd.md` §7 Event Ticketing / PRD §7 · **Depends on:** 07 vendor approval

**Story** — As an **approved vendor**, I want **to list a city-wide event (science fair) with venue, schedule, capacity and free or priced tickets, and have it published after Super Admin approval**, so that **students and guardians can discover it**.

**Acceptance criteria**

- **Given** an approved vendor, **when** the event form is saved, **then** the event is `draft` (city, bn/en title + description, venue, starts/ends, capacity, `ticket_price_bdt` nullable for free events).
- **Given** a submitted event, **when** the Super Admin approves it in the same queue, **then** status `published` and it appears in public listings for its city; rejection requires a reason and is audit-logged. Platform-organized events reuse this path with `organizer_kind=platform`.

### `ADS-US-009` — Student/Guardian discovers and views a published event

**Priority:** P0 · **Traces:** `brd.md` §7 · **Depends on:** ADS-US-008, module 06 (push)

**Story** — As a **student or guardian**, I want **to browse upcoming published events in my city on the web (and via push deep links), in Bengali by default**, so that **I can decide to attend**.

**Acceptance criteria**

- **Given** published events for city Dhaka, **when** `/events` is opened (city filter), **then** only published, non-cancelled, upcoming events render with bn title first; drafts/rejected never leak.
- **Given** a 06 event/campaign push tap, **when** the deep link opens, **then** event detail renders with venue, schedule, price (free or ৳), remaining capacity and a register/buy action. (In-app listing/purchase surface is the recorded app gap — Open Questions #3.)

### `ADS-US-010` — Buyer registers or buys a ticket

**Priority:** P0 · **Traces:** PRD §7 (10% commission) · **Depends on:** ADS-US-009, 03 verification

**Story** — As a **verified buyer**, I want **to reserve or buy tickets for an event**, so that **my place is held**.

**Acceptance criteria**

- **Given** a free event with capacity, **when** tickets are requested, **then** the ticket is confirmed `paid` instantly (৳0 amount, ৳0 commission) with a bn/en confirmation.
- **Given** a priced event, **when** tickets are requested, **then** the ticket is `reserved` with `payment_transaction_id` null until module 12 fills it (seam) — an honest "payment pending" state, never a dark pattern.
- **Given** remaining capacity < requested qty, **when** requested, **then** `VALIDATION_FAILED` (`validation.events.qty_exceeds_capacity`) and no partial hold.

### `ADS-US-011` — Organizer views the ticket list and revenue

**Priority:** P0 · **Traces:** PRD §7 · **Depends on:** ADS-US-010

**Story** — As the **organizer**, I want **my event's ticket list with counts and revenue gross, 10% commission and net**, so that **I can run entry checks and know my payout**.

**Acceptance criteria**

- **Given** the organizer's own event, **when** the ticket list opens, **then** active tickets (buyer, qty, status) and totals — gross `amount_bdt`, `commission_bdt` = 10% of paid amounts, net — render; other vendors' events → 404.
- **Given** cancelled tickets, **when** totals compute, **then** they are excluded from gross/net but shown as a count.

### `ADS-US-012` — Buyer cancels a ticket before the event starts

**Priority:** P1 · **Traces:** BR-010 · **Depends on:** ADS-US-010

**Story** — As a **buyer**, I want **to cancel my ticket any time before the event starts**, so that **my place frees for someone else**.

**Acceptance criteria**

- **Given** a `reserved` or `paid` ticket and `starts_at` in the future, **when** the buyer cancels, **then** status `cancelled`, capacity freed, and paid tickets state that the refund follows module 12's manual path (`TODO: Confirm` SLA).
- **Given** `starts_at` passed, **when** cancel is attempted, **then** refused (`CONFLICT`). Only the buyer or a Super Admin may cancel.

### `ADS-US-013` — Super Admin monitors ads & events platform-wide

**Priority:** P2 · **Traces:** `brd.md` §7 · **Depends on:** ADS-US-004, ADS-US-010

**Story** — As a **Super Admin**, I want **one overview of ad spend, campaign/event counts and ticket revenue with commission**, so that **Stream 2 revenue is visible on the platform dashboard**.

**Acceptance criteria**

- **Given** `/admin/ads`, **when** opened, **then** totals render from `GET /admin/ads/overview` (campaigns by status, published events, tickets sold, gross, commission, net) — feeding module 07's `/admin/stats` revenue placeholder.
- **Given** a campaign reaching `schedule_end`, **when** `campaign.complete` runs, **then** status `completed` and a final per-day report is available to the vendor and reflected in the overview.

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `ADS-BR-001` | Only vendors with an **approved** `vendor_accounts` row (07 `vendors.Approve`) may create/submit; re-checked on every `/vendor/*` mutation | Service (07 export read), DB FK |
| `ADS-BR-002` | Nothing serves/publishes without Super Admin approval; rejection **requires a reason**; every decision `audit.Record`-ed | Service + audit (01) |
| `ADS-BR-003` | Targeting is **demographic only** — keys `{city_id, grade, section_ids[]}` and nothing else; dispatch expands topics from the hierarchy; no user-level selection | DB CHECK + service + OpenAPI |
| `ADS-BR-004` | Frequency cap: max **1 sponsored push/user/week** (default, `TODO: Confirm`) — per-topic weekly at broadcast, per-user via `ads.CanServeToUser` | Service (dispatch pre-check) |
| `ADS-BR-005` | Every rendering carries the sponsored label "স্পনসর্ড / Sponsored", injected server-side; vendors cannot opt out or edit it | Service (payload/serve) + FE render |
| `ADS-BR-006` | Budget guard: projected cost (audience × rate, `TODO: Confirm` ৳0.25/impression) must fit remaining `budget_bdt`, else auto-`pause` before anything sends | Service (pre-dispatch), job |
| `ADS-BR-007` | Banned categories (gambling, tobacco, age-inappropriate) enforced by the moderation checklist; checklist version audited; policy `TODO: Confirm` | Moderation UI + audit |
| `ADS-BR-008` | Ad analytics **aggregate-only**: pseudized `user_ref`; daily aggregates only; no per-student ad profile ever built or queryable | Repository + service |
| `ADS-BR-009` | `commission_bdt` = 10% of `amount_bdt` on **paid** tickets (`brd.md` §7), server-computed; free tickets ৳0/৳0 | Service |
| `ADS-BR-010` | Cancellation: buyer (own ticket) or Super Admin, only before `starts_at`; capacity recomputed; paid refunds via 12's manual path | Service |
| `ADS-BR-011` | Edits in `draft`/`rejected` only; unmodified rejected resubmit → `CAMPAIGN_REJECTED`; review-state rows immutable | Service |
| `ADS-BR-012` | Public reads return `published`, non-cancelled events only; drafts/rejected never leak (incl. cached reads) | Repository + cache tags |
| `ADS-BR-013` | Content accuracy (`prompt.txt` §12): seeds clearly fictional + marked; `TODO: Confirm` copy blocks submission | Validation + seed |

## 6. Validation Rules

| Field | Rule | Message key (per-app `src/i18n` catalog) |
| --- | --- | --- |
| campaign `name` / `objective` | name required, 3–120 chars; objective ∈ `awareness` \| `event_promo` | `validation.ads.name_length` · `validation.ads.objective_invalid` |
| targeting `city_id` / `grade` / `section_ids` | city required, must exist in 04; grade optional, known class level; sections optional, each within `city_id` | `validation.ads.city_required` · `validation.ads.city_not_found` · `validation.ads.grade_invalid` · `validation.ads.section_city_mismatch` |
| `schedule_start` / `schedule_end` / `budget_bdt` | required; start < end; start ≥ now at submit; budget > 0 | `validation.ads.schedule_order` · `validation.ads.schedule_future` · `validation.ads.budget_positive` |
| creative `title_*` / `body_*` / `cta_url` / `image_media_id` | bn + en required; title ≤ 120, body ≤ 500; https CTA; image required for `native_banner` (confirmed 05 asset) | `validation.ads.creative_required` · `validation.ads.creative_length` · `validation.ads.cta_url_https` · `validation.ads.image_required` |
| event `city_id` / `title_*` / `description_*` / `venue` | required; title ≤ 150, description ≤ 2000 | `validation.events.city_required` · `validation.events.title_required` · `validation.events.description_length` |
| event `starts_at`/`ends_at`/`ticket_price_bdt`/`capacity` | start < end, start future at submit; price null or ≥ 0 (null = free); capacity 1–100,000 | `validation.events.schedule_order` · `validation.events.schedule_future` · `validation.events.price_invalid` · `validation.events.capacity_invalid` |
| ticket `qty` | ≥ 1 and ≤ remaining capacity | `validation.events.qty_invalid` / `validation.events.qty_exceeds_capacity` |

> Mirrored exactly by the OpenAPI contract (server validation) and the zod form schemas
> (web) generated from it. Both languages from day one.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to a protected action | `UNAUTHENTICATED`, no side effect |
| 2 | Vendor A reads/writes vendor B's campaign, event or tickets | `TENANT_MISMATCH` / 404 (account-scoped), nothing leaked |
| 3 | Unverified (pending) user requests tickets | Refused `FORBIDDEN` with verify-first copy; no hold created |
| 4 | Creative image deleted / R2 object missing | Native slot renders placeholder; text-only push still dispatches; never a crash |
| 5 | Reduced motion enabled | Charts and queue transitions render static (04 §5) |
| 6 | Offline submit (web) | Form state preserved with retry banner — never silently lost |
| 7 | Duplicate `campaign.dispatch` (job retry/race) or two Super Admins deciding simultaneously | Idempotent status guard — single broadcast; loser gets `CONFLICT` |
| 8 | Event cancelled after tickets sold | Buyers notified via 06 (`notify.SendToUser`), tickets → `cancelled`, refunds via 12 manual path |
| 9 | 04 counts unavailable at estimate/dispatch time; rejected campaign resubmitted without edits | Estimate `unknown`, dispatch retries, numbers never invented; resubmit → `CAMPAIGN_REJECTED` |

## 8. Reporting Needs

- `GET /admin/ads/overview`: campaigns by status, spend, published events, tickets sold, gross/commission/net — consumed by module 07's platform dashboard (`/admin/stats` placeholder).
- `ads_daily` aggregate (campaign × day: impressions, clicks, spend) powering vendor analytics charts (ADS-US-006); ticket totals per event for the organizer view and platform roll-up.
- Dispatch log (campaign × topic × result: sent / skipped-frequency-cap / paused-budget) for ops debugging — served alongside the overview.

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Written ads moderation policy (banned categories beyond gambling/tobacco/age-inappropriate, appeal path) | Rahul | Open | Checklist with the three banned categories above; ALL campaigns + events Super-Admin-approved; rejection requires reason; no individual-level targeting of minors — demographic dimensions only |
| 2 | Sponsored push frequency cap | Rahul | Open | Max 1 sponsored push per user per week (per-topic weekly at broadcast level) |
| 3 | In-app native banner slots and in-app event listing/ticket purchase surface | Rahul | Open | **Recorded gap** — README scopes module 13 to `api`+`web`; app-side slots need a future module amendment; until then sponsored push (labelled, via 06) and push deep links are the only app-side ad/event touchpoints |
| 4 | Paid-ticket payment path (module 12 delivery date) | Rahul | Open | Tickets settle via module 12's transaction path; seam = `event_tickets.payment_transaction_id` filled by 12 once delivered; until then tickets are reserved/unpaid or free — 13 does not build-depend on 12 |
| 5 | Impression/click attribution granularity | Rahul | Open | Pseudized user refs only; aggregated reporting only; no per-student ad profiles |
| 6 | Ad pricing model & rate (per-impression ৳?) | Rahul | Open | Simple per-impression rate ৳0.25 accruing `spend_bdt` against `budget_bdt`; budget guard blocks dispatch when exhausted |
| 7 | Event `status` set — spec base list is draft/published/cancelled | Rahul | Open | Add moderation states `pending_review`/`rejected` (same queue as campaigns, per module hints); draft/published/cancelled remain the public-facing subset |

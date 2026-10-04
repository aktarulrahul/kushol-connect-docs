# B2B Ads & Events — Solution Approach

**Module:** `13-b2b-ads-events` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `ad_campaigns` | A vendor's demographic-targeted campaign: objective (`awareness`/`event_promo`), targeting jsonb `{city_id, grade?, section_ids[]}`, schedule window, budget/spend, lifecycle status | Yes |
| `ad_creatives` | Push or native-banner creative for a campaign: title/body in bn+en, optional image (05 media ref), CTA label + https URL | Yes |
| `ad_events` | Impression/click fact rows: pseudized user ref (nullable), kind, `served_at`, day bucket, `audience_count` (push rows = one row per topic broadcast), `topic` — aggregate-friendly, never exposed per-student | Yes |
| `events` | City-wide educational event: organizer (vendor or platform), city (04), bn/en title/description, venue, schedule, nullable `ticket_price_bdt` (free allowed), capacity, lifecycle status | Yes |
| `event_tickets` | A buyer's ticket hold: qty, amount, `commission_bdt` (10%), status `reserved`/`paid`/`cancelled`, nullable `payment_transaction_id` (12 seam) | Yes |
| `ads_daily` | Read-model aggregate (campaign × day: impressions, clicks, spend) rebuilt by the nightly job; serves vendor charts | Yes |
| `vendor_accounts` / `landing_leads` | Approved-vendor gate (`vendors.Approve`); campaign-inquiry top-of-funnel | No — 07 |
| `cities` / `schools` / `sections` | Targeting dimensions + dispatch topic expansion + audience counts | No — 04 |
| `media_assets` | Creative images (R2 presign, magic-byte confirm) | No — 05 |
| `users` | Buyer identity + verification; pseudization source for `ad_events` | No — 03 |
| `payment_transactions` | Paid-ticket settlement (fills `payment_transaction_id`) | No — 12 |

### 1.2 Relationships

```text
vendor_accounts (07, approved only) 1 ──── * ad_campaigns 1 ──── * ad_creatives 0..1 ─── media_assets (05)
                                             │ 1
                                             └──── * ad_events  (impression|click · user_ref pseudized · day bucket)
                                                    │ (push rows carry topic: city-{id} / school-{id} / section-{id})
cities (04) 1 ──── * events 1 ──── * event_tickets 0..1 ─── payment_transactions (12 seam)
schools/sections (04) ── referenced by targeting jsonb; dispatch expands targeting → topics via 06
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| ADS-INV-1 | Status transitions only per §3 table; review-state rows immutable (BR-011) | Service guards + `CONFLICT` |
| ADS-INV-2 | `targeting` keys ⊆ `{city_id, grade, section_ids}` — demographic only (BR-003) | DB CHECK + OpenAPI schema + service |
| ADS-INV-3 | No serve/dispatch of an unapproved campaign or unpublished event (BR-002) | Job/serve pre-checks + status machine |
| ADS-INV-4 | `spend_bdt` never exceeds `budget_bdt`; dispatch blocked when projected cost doesn't fit (BR-006) | Service pre-dispatch check |
| ADS-INV-5 | `ad_events.user_ref` is pseudized (HMAC, rotating daily salt); no query joins it back to `users` for reads (BR-008) | Repository (no such query exists) |
| ADS-INV-6 | Every creative has bn **and** en title/body; sponsored label injected server-side at render (BR-005) | DB NOT NULL + service |
| ADS-INV-7 | Active (reserved+paid) ticket qty ≤ capacity, checked under row lock (BR-009/INV-7 family) | Transaction + `SELECT … FOR UPDATE` |
| ADS-INV-8 | `commission_bdt` = round(10% × `amount_bdt`), server-computed, paid tickets only (BR-009) | Service |
| ADS-INV-9 | Every `section_ids` entry belongs to a school within `city_id` | Service (04 reads) + validation |

## 2. Module Boundary

**Owns (writes):** `ad_campaigns`, `ad_creatives`, `ad_events`, `events`, `event_tickets`, `ads_daily`, dispatch log; all `/vendor/campaigns*`, `/vendor/events*`, `/admin/moderation/*`, `/admin/ads/*`, `/events*`, `/event-tickets*`, `/vendor/audience-estimate`, `/ads/serve|track` endpoints.

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 07 | `vendors.Approve` status gate; moderation shell (`/admin/campaigns` stub); `leads.Create` funnel | Vendor lifecycle and B2B acquisition belong to 07; 13 only enforces the gate and fills the stub |
| 04 | `hierarchy.ResolveUserNodes`, sections-by-city+grade+stream reads, aggregated `hierarchy.AudienceCount` (declared in 04 `06` §2) | Hierarchy is 04's data model; 13 never stores copies of city/institution/section rows |
| 06 | `notify.BroadcastTopic` (sponsored push — same hierarchy topics), `notify.SendToUser` (event cancel notices) | All FCM/Expo machinery is 06's; 13 never touches push credentials |
| 05 | `media_assets` presign/confirm for creative images | R2 uploads live in 05 |
| 03 | Role claims + verification status of buyers | Auth chain is 03's |
| 01 | `jobs.Enqueue` (dispatch/complete/aggregate/sweep), `audit.Record`, RFC-7807 envelope, limiter | Platform primitives |
| 12 | Payment seam: 12 fills `event_tickets.payment_transaction_id` → calls `events.MarkTicketPaid` | Gateway ownership is 12's; **not a build dependency** |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4 (`events:city:{id}` is the public contract; vendor/admin surfaces are no-store).

## 3. Lifecycle

```text
ad_campaigns:
  draft ──submit──▶ pending_review ──approve──▶ approved ──(start reached, job)──▶ running ──(end reached, job)──▶ completed
                        │                          │                                   │ ⇄ paused (vendor / budget guard)
                        └──reject(reason)──▶ rejected ──edit+resubmit──▶ pending_review
events:
  draft ──submit──▶ pending_review ──approve──▶ published ──cancel──▶ cancelled
                        └──reject(reason)──▶ rejected
event_tickets:
  reserved ──12 seam (MarkTicketPaid)──▶ paid ──cancel before start──▶ cancelled
        └──unpaid at event start (sweep job)──▶ cancelled        (free events: reserved → paid instantly)
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| draft | submit | pending_review | complete creative (bn+en), future schedule, budget > 0, vendor gate (BR-001) | none |
| pending_review | approve | approved (→ `scheduled` if start future, else `running` + immediate dispatch) | Super Admin role; checklist confirmed | `audit.Record` (actor, checklist version) |
| pending_review | reject | rejected | reason required | `audit.Record`; vendor sees reason banner |
| approved/scheduled | start reached | running | job; budget + frequency-cap pre-check (BR-004/006) | `notify.BroadcastTopic` per topic; impression rows; spend accrual; audit |
| running | end reached | completed | job | final report available; overview refresh |
| running | pause (vendor / budget) | paused | owner or system | native selection stops serving; dispatch skips |
| paused | resume | running | within schedule window, budget available | — |
| published event | cancel | cancelled | organizer/Super Admin | buyer notices via `notify.SendToUser`; tickets cancelled |
| reserved ticket | pay (12 seam) | paid | `payment_transaction_id` set by 12 | `commission_bdt` finalized |
| reserved/paid ticket | cancel | cancelled | before `starts_at`; buyer or Super Admin (BR-010) | capacity freed |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| `/vendor/ads*`, `/vendor/events*` (own lists, analytics) | Dynamic SSR, **no-store** (fresh money/analytics data) | none | none |
| `/admin/moderation` queue (fills 07 stub) | Dynamic SSR + Server Actions, **no-store** | none | none |
| `/admin/ads` overview | Dynamic SSR | none (compute from aggregates per request) | none |
| `/events` public listing (by city) | ISR / short TTL | yes, 60 s | `events:city:{cityId}` |
| `/events/{id}` public detail | ISR / short TTL | yes | `events:city:{cityId}` (+ on-page state for ticket holders) |
| `GET /api/v1/ads/serve` (native selection, P1) | api response | selection not cached; frequency check per request | none |

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| Frequency-cap window (default 7 days) | 10% ticket commission (`brd.md` §7) |
| Per-impression rate (default ৳0.25, `TODO: Confirm`) | Demographic-only targeting dimensions (BR-003) |
| Moderation checklist text + banned-category list (`TODO: Confirm` policy) | Sponsored label injection ("স্পনসর্ড / Sponsored") |
| Native placements on/off per web surface | Pseudization scheme; aggregate-only analytics (BR-008) |
| Reserved-ticket sweep lead time | Single start/end schedule window per campaign |

## 6. Security

| Entry point family | Auth chain (authenticate → role claims → tenant-scope) | Scope rule |
| --- | --- | --- |
| `/api/v1/vendor/campaigns*`, `/vendor/events*`, `/vendor/audience-estimate` | vendor role + **account scope**: every query filters `vendor_account_id` from the session's vendor claim (07 gate re-checked) | Vendor sees/writes only own rows; others → 404 |
| `/api/v1/admin/moderation/queue`, `/admin/campaigns/{id}/approve│reject`, `/admin/events/{id}/approve│reject`, `/admin/ads/overview` | Super Admin role | Platform-wide by definition; every decision `audit.Record`-ed |
| `GET /api/v1/events`, `/events/{id}` | public (no auth) | Repository returns `published` ∧ ¬cancelled only (BR-012) |
| `POST /events/{id}/tickets`, `POST /event-tickets/{id}/cancel` | authenticated + VERIFIED (03) | Buyer scope on own tickets; organizer list = own events only |
| `GET /events/{id}/tickets` | vendor (organizer) or Super Admin | Account scope per event |
| `GET /ads/serve`, `POST /ads/track/click` (P1) | public/optional auth | Serving limited to `running` campaigns; clicks pseudized |

Validation against the OpenAPI contract at every entry point; creative images only via 05 presign + magic-byte confirm; `cta_url` https-only; sanitised rendering of vendor text. Rate-limit class `default` on all routes. Privacy: demographic targeting only (BR-003), pseudized ad events (BR-008), frequency cap as an anti-harassment measure (BR-004) — the module is deliberately incapable of building per-student ad profiles.

## 7. Accessibility & Motion

Web surfaces follow `04-frontend-tasks.md`: moderation queue and builder are keyboard-complete with visible focus; analytics charts ship a data-table equivalent; every transition (wizard step, queue card) has a reduced-motion static form. Push rendering (labels, bn typography) is module 06's contract.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | 06/FCM down at dispatch time | `BroadcastTopic` error in `campaign.dispatch` | Push delayed; campaign stays `running` with dispatch pending | Job retries with backoff (01 worker); nothing is lost — dispatch is idempotent |
| 2 | Budget overflow attempt | Pre-dispatch check (INV-4) | Dispatch refused | Campaign auto-pauses; vendor notified in dashboard |
| 3 | Duplicate dispatch (job retry/race) | Status guard + dispatch-log unique key | None — single broadcast | Idempotent no-op on second run |
| 4 | Module 12 undelivered | Tickets stuck `reserved` | Paid tickets can't settle | Tickets remain reserved (clear "payment pending" state); `tickets.sweep` cancels unpaid at event start; seam fills retroactively for 12 |
| 5 | 04 counts unavailable | `hierarchy.AudienceCount` error | Estimate shows `unknown`; dispatch expansion fails | Builder usable; dispatch job retries; never invents numbers |
| 6 | Creative media missing (R2) | Serve-time lookup miss | Placeholder in native slot; text-only push still viable | Vendor re-upload path |
| 7 | Redis down | Cache miss/fall-through | Public events slower; vendor/admin paths unaffected (no-store) | TTL cache rebuilds |
| 8 | Neon cold start | Slow queries | Portal reads lag; jobs queue | 01 worker drains; warm-up ping per module 15 runbook |

## 9. Performance

- Volumes (pilot): ~50 campaigns/month, dispatches fan to ≤ a few hundred topics; `ad_events` is the only high-volume table → **batched inserts** (100 rows/statement) from dispatch/click paths; no per-request vendor reads on the hot path.
- `ads_daily` rebuilt nightly 00:05 Asia/Dhaka (`ads.daily_aggregate`); charts read the aggregate, never raw `ad_events`.
- Audience estimate: `hierarchy.AudienceCount` result cached in Redis (TTL 5 min) keyed by targeting hash.
- Indexes: `ad_events(campaign_id, day)`, `ad_events(day)`, `ad_events(topic, served_at)` (frequency-cap lookups); `ad_campaigns(vendor_account_id, status)`, `ad_campaigns(status, schedule_start)` (dispatch scan); `events(city_id, status, starts_at)`; `event_tickets(event_id, status)`; `event_tickets(buyer_user_id)`.
- Web bundle: Recharts already in the 07 stack (no new dependency); no client-side ad JS — labels and selection are server-side.

## 10. Alternatives Considered

### Option A — Scheduled topic broadcast (chosen) · Option B — Real-time ad server

| | A: scheduled broadcast | B: real-time ad server (per-request selection/auction) |
| --- | --- | --- |
| Advantages | Reuses 06's proven FCM topic fan-out; targeting = topic selection; trivially auditable; fits 2-vCPU VPS; moderation gate is a hard pre-check | Millisecond targeting, per-user capping, pacing — the industry model |
| Disadvantages | Coarser capping at broadcast level; no per-request optimization | Needs impression infrastructure, latency budgets, an auction/pacing engine; overshoots MVP scale and the shared VPS |
| Complexity / weight | Low — one dispatch job + aggregate table | High — new hot path, new failure modes, real-time budgeting |

**Recommendation:** A. Sponsored push dispatches via `jobs.Enqueue` at schedule time through `notify.BroadcastTopic`; native web slots use a simple server-side selector over `running` campaigns (P1). **ADR:** record in this module's `07-progress.md`.

**Also rejected:** per-user ad profiles and behavioural targeting (violates the minors-protection stance — `persona.md`, `prompt.txt` §9); third-party ad SDKs (data control, latency, trust — vendor JS never loads next to school content).

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | Vendors accept demographic (city/grade/section) reach instead of individual targeting | Sales friction | Lead with audience estimates and CTR reporting; the platform's trust position is the differentiator |
| 2 | Weekly frequency cap depresses ad revenue | Lower Stream-2 income | Cap is owner-configurable (§5); revisit with Rahul once CTR data exists (Open Question #2) |
| 3 | Module 12 arrives later than 13 | Paid tickets can't complete | Free + reserved flows ship standalone; reserved state is explicit, refunds manual; seam fills retroactively |
| 4 | Topic broadcast reach ≠ exact live audience (counts drift) | Impression accounting approximate | Impression rows store `audience_count` at dispatch time; reports label them as delivered-estimate |
| 5 | Moderation queue becomes a bottleneck | Campaigns delayed | Queue shows checklist + preview for 30-second decisions; SLA `TODO: Confirm` |
| 6 | Grade expansion depends on 04 data freshness | Slight over/under-reach | Expansion reads 04 live at dispatch; misses fail loudly and retry |

# B2B Ads & Events — Technical Document

**Module:** `13-b2b-ads-events`
**Version:** 0.1
**Status:** 📝 Draft 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

## 1. Overview

### 1.1 Purpose

Revenue Stream 2 (`brd.md` §7): approved vendors run **demographic-targeted campaigns** (BR-05 —
"শুধুমাত্র চট্টগ্রামের ক্লাস ১২ এর বিজ্ঞান বিভাগ") as sponsored push over module 06's hierarchy topics
and native banners on web surfaces — every campaign Super-Admin-moderated, demographic dimensions
only, no exploitative targeting of minors. Also ships **city-wide event listings with ticketing**
at a 10% platform commission (PRD §7).

### 1.2 Scope

**In:** `ad_campaigns`/`ad_creatives` lifecycle with demographic-only targeting; audience estimate
from 04 counts; sponsored-push dispatch via `notify.BroadcastTopic` (targeting IS topic selection);
native-banner selection for **web** (P1); moderation queue APIs + checklist; audit; pseudized
aggregate-only `ad_events` analytics; `events`/`event_tickets` with free (instant) and paid
(reserved → 12 seam) tickets, 10% commission, cancellation, organizer revenue view.

**Out:** in-app native ad slots and in-app event purchase (**recorded gap** — README scopes 13 to
`api` + `web`); individual-level/behavioural targeting of minors and per-user ad profiles
(forbidden); real-time auctions and third-party ad SDKs; payment capture/gateways/refunds (12
owns; 13 only reserves + exposes the seam); email/SMS ad channels; A/B testing; recurring schedules.

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 06 notifications | `notify.BroadcastTopic` (sponsored push, topics `city-{id}`/`school-{id}`/`section-{id}`, payload `type=campaign`); `notify.SendToUser` (event-cancel buyer notices) |
| consumes | 07 command-center-web | `vendors.Approve` gate re-checked per `/vendor/*` mutation; `/admin/campaigns` moderation stub this module fills; `leads.Create` funnel |
| consumes | 04 organization-hierarchy · 05 communication-engine | sections-by-city+grade+stream reads + aggregated `hierarchy.AudienceCount` (declared in 04 `06` §2); `media_assets` presign/confirm for creative images |
| consumes | 03 identity-access · 01 foundations | auth chain + buyer VERIFIED check (03); `jobs.Enqueue`, `audit.Record`, RFC-7807 envelope, `default` limiter (01) |
| consumed by | 12 payments | seam: 12 fills `event_tickets.payment_transaction_id`, then calls `events.MarkTicketPaid` — **not a build dependency** |
| consumed by | 07 · web · 06 (render) | REST §5.1 for `/vendor/ads|events*`, `/admin/moderation`, `/admin/ads`, public `/events*`; 13 owns the `type=campaign` payload + labels, 06 owns FCM/Expo delivery/rendering |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| api | Go · chi handlers · services · tenant-scoped repos · sqlc + pgx · PostgreSQL | Campaign/event/ticket domain + scheduled topic broadcast serving | Stack per `docs/tech-stack.md` api table; testcontainers-go for IT; contracts generated from `applications/api/openapi/openapi.yaml` |
| api (jobs) | In-DB job table + 01 Go worker | `campaign.dispatch`, `campaign.complete`, `ads.daily_aggregate`, `tickets.sweep` | No Kafka/RabbitMQ (`tech-stack.md`) |
| web | Next.js App Router · Server Components/Actions · TanStack Table · Recharts · RHF + zod | Vendor portal + moderation queue + public events; charts reuse 07's Recharts — no new dependency | `tech-stack.md` web table; no client-side ad JS — labels/selection are server-side |
| web + app (per app) | each app's `src/i18n` catalogs `ads.*`, `events.*`, `validation.ads.*`, `validation.events.*` | bn (default) + en strings from day one | Parity gate from module 02 |
| app | None — README scopes module 13 to `api` + `web` | Sponsored push arrives via 06; no RN screens built here | Recorded gap, §6.2 |

---

## 3. Architecture

### 3.1 Component diagram

```text
web (/vendor/ads·events, /admin/moderation, /admin/ads, /events) ──openapi-fetch──►
api (chi) ── ads/events services ── tenant-scoped repos ── sqlc ── PostgreSQL
        │        (ad_campaigns, ad_creatives, ad_events, events, event_tickets, ads_daily)
        ├─ 04: sections by city+grade, hierarchy.AudienceCount
        ├─ 07: vendors.Approve gate (fail-closed)   ├─ 06: notify.BroadcastTopic / SendToUser
        ├─ 05: media_assets presign/confirm          ├─ 01: jobs · audit.Record · RFC-7807 · limiter
        └─ seam: 12 fills payment_transaction_id → events.MarkTicketPaid
```

### 3.2 Boundary

**Owns (tables / services):** `ad_campaigns`, `ad_creatives`, `ad_events`, `events`,
`event_tickets`, `ads_daily`, dispatch log; all `/vendor/campaigns*`, `/vendor/events*`,
`/admin/moderation/*`, `/admin/ads/*`, `/events*`, `/event-tickets*`, `/vendor/audience-estimate`, `/ads/serve|track`.

**Reads (via exported service functions only):** 07 `vendors.Approve` gate; 04 sections reads +
`hierarchy.AudienceCount`; 06 `notify.*`; 05 `media_assets`; 03 role claims + verification; 01
`jobs`/`audit`/limiter. Cache contract (`06` §4): `events:city:{id}` public; vendor/admin no-store.

### 3.3 Request / data flows

```text
1. Campaign build → approval: wizard → POST /vendor/campaigns (draft, targeting
   {city_id, grade, section_ids[]}) → submit → pending_review → Super Admin queue →
   approve (checklist version audited) → scheduled/running; reject(reason) → rejected.
2. Scheduled dispatch: 01 tick → ads.DispatchCampaign → status gate (INV-3) → budget guard
   (BR-006; else auto-pause, zero sends) → frequency cap (BR-004, trailing 7d per topic) →
   expand targeting → topics via 04 → notify.BroadcastTopic per topic (06, label server-injected)
   → batched ad_events rows (100/insert) + spend accrual → audit + per-topic dispatch log.
   Idempotent (status guard + dispatch-log key).
3. Native serve (P1): GET /ads/serve → selector over running native_banner campaigns →
   impression row; tap → POST /ads/track/click → pseudized click row.
4. Events & tickets: vendor submits event → same queue → published (revalidate
   events:city:{cityId}) → /events (ISR 60 s) → POST /events/{id}/tickets → ReserveTicketTx
   (row-locked capacity) → free: paid instantly (৳0/৳0); priced: reserved → 12 fills
   payment_transaction_id + MarkTicketPaid → totals gross/10%/net; cancel before starts_at;
   tickets.sweep cancels unpaid at event start.
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| `ad_campaigns` | draft, pending_review, approved, rejected, scheduled, running, paused, completed | draft → pending_review (submit; complete creative bn+en, future schedule, budget > 0, vendor gate) · pending_review → approved (Super Admin + checklist; → scheduled if start future, else running + immediate dispatch) · pending_review → rejected (reason required) · rejected → pending_review (edit + resubmit) · approved/scheduled → running (start reached, job; budget + cap pre-check) · running → completed (end reached, job) · running ⇄ paused (vendor or budget guard; resume within window) · review-state rows immutable (`CONFLICT`) |
| `events` | draft, pending_review, published, rejected, cancelled | draft → pending_review (submit) · pending_review → published (approve) / rejected (reason) · published → cancelled (organizer/Super Admin; buyer notices via 06; tickets cancelled) |
| `event_tickets` | reserved, paid, cancelled | reserved → paid (free instant ৳0; priced via 12 seam `MarkTicketPaid`) · reserved/paid → cancelled (buyer or Super Admin, before `starts_at`; capacity freed) · reserved unpaid at start → cancelled (`tickets.sweep`) |

---

## 4. Data Model (summary)

Mirror of `03-backend-tasks.md` §1 (column detail stays there). Scope owner = **vendor account**
(B2B platform-wide resource), not a school tenant.

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `ad_campaigns` | Vendor campaign: objective (`awareness`\|`event_promo`), targeting jsonb, schedule window, budget/spend, lifecycle status | `vendor_account_id` (FK → 07; scope owner) | `(vendor_account_id, status)`, `(status, schedule_start)`, partial `(status)` on pending_review | CHECKs: targeting keys ⊆ `{city_id, grade, section_ids}` (demographic only), start < end, budget > 0 |
| `ad_creatives` | Push or native_banner creative: bn+en title/body, optional 05 image, CTA label + https URL | via `campaign_id` | `campaign_id` | UNIQUE `(campaign_id, kind)`; bn + en both required (NOT NULL); image required for `native_banner` |
| `ad_events` | Impression/click facts: pseudized `user_ref` (HMAC, daily-rotating salt), kind, topic, `audience_count`, Asia/Dhaka `day` | none by design — platform metrics; vendor access only via campaign-ownership aggregates | `(campaign_id, day)`, `(day)`, `(topic, kind, served_at)` | `bigint` identity PK (high volume); never joined back to `users` for reads (BR-008) |
| `events` | City-wide event: organizer vendor/platform, 04 city, bn/en title/description, venue, schedule, nullable price (null = free), capacity | `vendor_account_id` (null ⇒ platform) | `(city_id, status, starts_at)`, `(vendor_account_id, status)`, partial `(status)` queue | status adds moderation states to the spec base set (Open Question #7) |
| `event_tickets` | Buyer hold: qty, amount, `commission_bdt` (10% paid), status, nullable `payment_transaction_id` (12 seam) | buyer `buyer_user_id` + event organizer | `(event_id, status)`, `(buyer_user_id)`, partial reserved → sweep | active qty ≤ capacity under row lock (INV-7) |
| `ads_daily` | Read-model aggregate (campaign × day: impressions, clicks, spend) | via campaign ownership | PK `(campaign_id, day)` | rebuilt nightly; vendor analytics read only this (BR-008) |

Migrations 1–2 (both reversible). Seed: one fictional draft campaign + one fictional draft event,
clearly marked, publish blocked until the `TODO: Confirm` seed policy lands (ADS-BR-013).

---

## 5. Contracts

### 5.1 REST endpoints

All under `/api/v1`; `{ "data": … }` / RFC-7807. Full request/response shapes: `03` §2.

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | `POST/GET /vendor/campaigns` · `PATCH /vendor/campaigns/{id}` · `POST …/submit` · `POST …/pause` · `POST …/resume` | Vendor (07 gate re-checked) | Campaign CRUD, submit, pause/resume (draft/rejected edits only) | `FORBIDDEN` · `VALIDATION_FAILED` · `NOT_FOUND`/`TENANT_MISMATCH` · `CONFLICT` · `CAMPAIGN_REJECTED` · `RATE_LIMITED` | ADS-US-001/002/007 |
| 2 | `GET /vendor/campaigns/{id}/analytics` | Vendor (own) | Daily impressions/clicks/CTR/spend from `ads_daily` | `NOT_FOUND` (others') | ADS-US-006 |
| 3 | `GET /vendor/audience-estimate` | Vendor | Aggregate count from 04 (Redis 5-min); `count: null` = unknown, never fabricated | — | ADS-US-001 |
| 4 | `POST/GET /vendor/events` · `POST /vendor/events/{id}/submit` | Vendor | Event create/list + submission | as #1 | ADS-US-008 |
| 5 | `GET /admin/moderation/queue` · `POST /admin/campaigns/{id}/approve│reject` · `POST /admin/events/{id}/approve│reject` | Super Admin | Moderation queue (campaigns + events) with checklist payload; reject needs reason | `FORBIDDEN` · `CONFLICT` (already decided) · `VALIDATION_FAILED` (no reason) | ADS-US-003/008 |
| 6 | `GET /admin/ads/overview` | Super Admin | Campaigns by status, spend, events, tickets, gross/commission/net (feeds 07 `/admin/stats`) | — | ADS-US-013 |
| 7 | `GET /events?cityId=` · `GET /events/{id}` | Public | Published ∧ ¬cancelled upcoming only (BR-012); ISR tagged `events:city:{id}` | `NOT_FOUND` | ADS-US-009 |
| 8 | `POST /events/{id}/tickets` · `GET /events/{id}/tickets` (organizer/Super Admin) · `POST /event-tickets/{id}/cancel` | VERIFIED buyer / organizer | Reserve/buy, organizer list + totals, cancel before start | `FORBIDDEN` (unverified) · `VALIDATION_FAILED` (capacity) · `TENANT_MISMATCH` · `CONFLICT` (after start) | ADS-US-010–012 |
| 9 | `GET /ads/serve` · `POST /ads/track/click` (P1) | Public/optional auth | Native selection over running campaigns, labels injected; pseudized clicks | `NOT_FOUND` (house slot) · `RATE_LIMITED` | ADS-US-005 |

### 5.2 Realtime / jobs

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| `campaign.dispatch` (ADS-BE-035) | 01 scheduler tick; `approved`/`scheduled` with start ≤ now | Expand targeting → topics; `notify.BroadcastTopic` per topic; impression rows + spend; per-topic result log | 06 FCM; `ad_events`/`ads_daily` | Idempotent (status guard + log key); retry ×3 backoff on 06/04 failure; budget → auto-pause |
| `campaign.complete` (ADS-BE-036) | `running` with end ≤ now | Status → completed; final per-day report from `ads_daily` | vendor + admin overview | retry |
| `ads.daily_aggregate` (ADS-BE-037) | Nightly 00:05 Asia/Dhaka | Full per-day rebuild of `ads_daily` | vendor charts | retry; lag alarm per 01/15 runbooks |
| `tickets.sweep` (ADS-BE-038) | Hourly | Cancel `reserved` unpaid at `starts_at`; notify buyer via 06 `SendToUser` | buyers | retry |

### 5.3 Exported service functions

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `ads.DispatchCampaign(ctx, campaignID)` | 01 worker (`campaign.dispatch`) | per-topic results (sent / skipped: frequency-cap / paused: budget) + impression/spend totals | `NOT_FOUND`, `CONFLICT` (wrong status), `VALIDATION_FAILED`; hard moderation gate inside (BR-002/INV-3) |
| `ads.CanServeToUser(ctx, userID)` | future per-user ad surfaces (amendment) | bool — trailing 7-day sponsored-push check (BR-004) | `VALIDATION_FAILED`; pseudized lookup only |
| `events.ListByCity(ctx, cityID)` | web `/events` (ISR), 07 dashboard, future app amendment | `[]EventDTO` (bn/en, price, schedule, capacity-left); published ∧ ¬cancelled only | `NOT_FOUND` (city) |
| `events.MarkTicketPaid(ctx, ticketID, paymentTransactionID)` | module 12 settlement path | void; `reserved`→`paid`, commission finalized (INV-8); idempotent | `NOT_FOUND`, `CONFLICT` (already paid/cancelled) |

Exports return DTOs (never sqlc rows); additive-first; the four signatures are frozen for Phase-3
consumers (`06` §7).

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| `/vendor/ads` | Campaign list (status chips, spend/budget bar, actions) | Server + client table, no-store | Vendor (approved gate) |
| `/vendor/ads/new` | Builder wizard: TargetingPicker (live estimate, `unknown` state) → CreativeEditor (bn/en, locked "স্পনসর্ড · Sponsored" chip) → schedule/budget → review+submit | Client form | Vendor |
| `/vendor/ads/[id]` | Campaign detail + daily analytics (Recharts + data-table fallback) + status timeline | Server shell + client chart | Vendor (own) |
| `/vendor/events`, `/vendor/events/new`, `/vendor/events/[id]/edit` | Event manager + create/edit (free toggle) | Server list + client forms | Vendor |
| `/admin/moderation` | Queue — campaigns + events tabs (fills 07's `/admin/campaigns` stub; stub redirects); DecisionCard + checklist-gated approve + required-reason reject | Server shell + client cards, no-store | Super Admin |
| `/admin/ads` | Ads overview cards (spend, statuses, events, tickets, gross/commission/net) | Server Component | Super Admin |
| `/events` | Public listing, city filter | ISR (tag `events:city:{id}`, 60 s) | Public |
| `/events/[id]` | Public detail + TicketAction (free instant / honest "payment pending") + MyTicketState + cancel | ISR shell + client ticket action | Public / verified buyer |

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| N/A — README scopes module 13 to `api` + `web`; no RN screens are built here | — | Sponsored push and event pushes deep-link per 06's route map; taps land on web or app home per 06 | Pushes cache in the OS tray like any notification; no queueing introduced |

Recorded gaps (Open Questions #3; `ADS-AP-002` tracks the amendment): in-app native ad slots and
an in-app event listing/ticket purchase surface both need a future module amendment — until then
sponsored push (labelled "স্পনসর্ড / Sponsored", via 06) and push deep links are the only app-side
touchpoints; `ADS-AP-001`/`003` verify labelled push + the pseudized click round-trip on 360px.

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| None direct | 13 holds **no external secrets** — FCM/Expo credentials live in 06 (13 calls `notify.*` only), R2 in 05, payment gateways in 12, SMS/SSO in 03 (`06` §5) | — | — | — | — |

Indirect degradation: 06/FCM down → dispatch retries, campaign stays `running`; 07 gate down →
vendor mutations fail closed; 04 down → estimate `unknown`, dispatch retries (never invents
counts); 12 undelivered → tickets "payment pending"; 05 down → text-only push still viable; 01
worker down → dispatches queue and drain; Redis down → no-store surfaces unaffected. Full matrix:
`06` §8.

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| None new | — | — | 13 introduces no env vars of its own; platform config (DATABASE_URL, REDIS_URL, …) is parsed by 01's config modules and inventoried in module 15's `15-deployment-operations` technical document §8.1 |

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| Frequency-cap window (default 7 days) | 10% ticket commission (`brd.md` §7) |
| Per-impression rate (default ৳0.25, `TODO: Confirm`) | Demographic-only targeting dimensions (BR-003) |
| Moderation checklist text + banned-category list (gambling/tobacco/age-inappropriate; policy `TODO: Confirm`) | Sponsored label injection ("স্পনসর্ড / Sponsored") |
| Native placements on/off per web surface | Pseudization scheme; aggregate-only analytics (BR-008) |
| Reserved-ticket sweep lead time | Single start/end schedule window per campaign |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | authenticate → load role claims → tenant-scope (`02` §6); validation against the OpenAPI contract at every entry point |
| Role matrix | Vendor: own campaigns/events/analytics/tickets (account scope; 07 approved-gate re-checked per mutation, BR-001) · Super Admin: moderation queue, approve/reject, `/admin/ads` overview, platform events · Buyer: VERIFIED users only reserve/buy/cancel (03) · Public: reads of published events; `/ads/serve`/`track` public/optional auth |
| Tenant scope | Every vendor query filters `vendor_account_id` from the session claim; organizer ticket list = own events; foreign rows → `TENANT_MISMATCH`/404 (audited) |
| Rate limits | Class `default` on all routes (01) |
| Audit events | Approve/reject (actor, decision, reason, checklist version), dispatch, pause/resume, submit, ticket cancel (financial), event cancel |
| Privacy / minors | **Safety-critical:** demographic-only targeting — keys `{city_id, grade, section_ids}` and nothing else (BR-003, DB CHECK + OpenAPI); no user-level selection exists anywhere; frequency cap 1 sponsored push/user/week as anti-harassment (BR-004); label server-injected, vendors cannot remove it (BR-005); banned categories enforced by checklist (BR-007); `ad_events.user_ref` pseudized (HMAC, daily salt), daily aggregates only, no per-student ad profile ever built or queryable (BR-008, ADS-INV-5); creative images only via 05 presign + magic-byte confirm; `cta_url` https-only; sanitised rendering of vendor text |

---

## 10. Error Handling

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `CAMPAIGN_REJECTED` | Resubmission without edits after rejection | `POST /vendor/campaigns/{id}/submit` on unmodified rejected campaign (BR-011) | Vendor edits the campaign; reason banner from `rejection_reason` (`ads.rejected_reason`) |
| `CONFLICT` | Immutable/already-decided state | PATCH on review-state rows, double approve, concurrent dispatch, cancel after `starts_at`, already-paid ticket | Refresh + "already decided / state changed" banner |
| `VALIDATION_FAILED` | Bad input | Targeting/creative/schedule/budget rules; reject without reason; qty > remaining capacity (`validation.events.qty_exceeds_capacity`) | Field-level zod/OpenAPI errors mapped to `validation.ads.*`/`validation.events.*` keys |
| `TENANT_MISMATCH` / `NOT_FOUND` | Cross-account attempt / foreign row | Vendor B reading vendor A's campaigns, events, tickets | Branded 404; attempt audited |
| `FORBIDDEN` | Unverified buyer / unapproved vendor / non-Super-Admin | Ticket purchase without verification; vendor gate fail-closed; moderation by non-Super-Admin | Verify-first copy / licence-style gate message |
| `UNAUTHENTICATED` / `RATE_LIMITED` | No session / `default` class exceeded | All protected routes | Login redirect / retry-after |

All errors surface as RFC-7807 `application/problem+json`; user-visible messages resolve via
each app's `src/i18n` — every key ships in **bn + en** (Bengali default), e.g. honest-state copy for
payment pending, estimate unknown, sold out.

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | slog via 01; module adds dispatch-log rows (campaign × topic × result: sent / skipped-frequency-cap / paused-budget) served alongside the admin overview for ops debugging; no PII in logs (pseudized refs only) |
| Metrics / counters | `/admin/ads/overview` totals; spend vs budget per campaign; queue age (SLA badge); dispatch retry counts |
| Health contribution | None — 13 adds no new dependency probed by `/readyz` (DB/Redis coverage is 01's) |
| Jobs & retries | 4 jobs on the 01 worker (§5.2); dispatch idempotent, retry ×3 backoff on 06/04 failure → drain on restore; `ads_daily` lag alarms per 01/15 runbooks |
| Runbook pointers | Dispatch retries: requeue is safe (status guard) — ops notes in `07-progress.md`; Neon cold start → slow portal reads, warm-up ping per module 15 runbook; moderation bottleneck risk watched via queue-age badge (`02` §11 risk 5) |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Targeting validator (demographic keys only), topic expansion, frequency-cap decision, budget guard + auto-pause boundary, commission math, pseudization, cache tags | `ADS-UT-001`–`007` | `go test` green in CI |
| Integration | **Moderation gate** (unapproved never dispatches / unpublished never lists), **frequency cap** (7-day skip + `CanServeToUser` window), **budget guard** (spend at budget ⇒ zero sends + auto-pause), vendor isolation, status machine `CONFLICT`s, ticket concurrency (last seat), dispatch e2e with fake 06, public reads never leak drafts, content-hash-free idempotency set, 12 seam + sweep | `ADS-IT-001`–`012` | testcontainers Postgres; mandatory rows marked in `03` §6 / `06` §9 |
| E2E | Golden path 1: builder (estimate, bn/en creative, sponsored-label preview) → approve in queue → dispatch logs broadcast + impression + audit · Golden path 2: event → approve → public listing → free ticket → organizer totals with 10% commission | `ADS-E2E-001`–`002` | Playwright + axe |
| CI | Always-include set: unauthenticated calls denied per entry point; validation rejects bad input; cross-account → `TENANT_MISMATCH`/404; `TODO: Confirm` copy blocks submission (BR-013); public reads never return drafts/rejected | — | quality gate on `api` + `web` |

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | ~50 campaigns/month (pilot); dispatch fans to ≤ a few hundred topics; `ad_events` is the only high-volume table |
| Hot paths + indexes | Batched `ad_events` inserts (100 rows/statement) from dispatch/click paths; frequency-cap lookups on `(topic, kind, served_at)`; dispatch scans on `(status, schedule_start)`; analytics on `(campaign_id, day)` |
| Latency targets | Charts read `ads_daily` (rebuilt nightly 00:05 Asia/Dhaka), never raw `ad_events`; audience estimate cached in Redis (TTL 5 min, keyed by targeting hash) |
| Bundle / payload impact | Recharts already in the 07 stack — no new dependency; no client-side ad JS (labels and selection server-side) |
| Caching | Public `/events` ISR 60 s tagged `events:city:{id}`; vendor/admin/analytics surfaces no-store |

---

## 14. Risks & Open Questions

Consolidated from `01` §9 + `02` §11 — the table to review in module readiness checks; unconfirmed
items keep their `TODO: Confirm` marker.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Written ads moderation policy (banned categories beyond gambling/tobacco/age-inappropriate, appeal path) | Checklist scope; legal exposure | Rahul | Open | Checklist with the three banned categories; ALL campaigns + events Super-Admin-approved; rejection requires reason; demographic dimensions only |
| 2 | Sponsored push frequency cap (per user/week) | Revenue vs user trust | Rahul | Open | Max 1 sponsored push per user per week (per-topic weekly at broadcast) |
| 3 | In-app native banner slots + in-app event listing/purchase | App-side ad/event surface missing | Rahul | Open — recorded gap | No app UI until a module amendment; push + deep links only |
| 4 | Paid-ticket payment path (module 12 delivery date) | Priced tickets can't settle | Rahul | Open | Free + reserved flows standalone; seam fills retroactively; 13 never build-depends on 12 |
| 5 | Ad pricing model & rate; impression/click attribution granularity | Revenue model; privacy posture | Rahul | Open | Per-impression ৳0.25 accruing `spend_bdt`; pseudized refs, aggregate-only reporting |
| 6 | Event `status` set beyond spec base list | Public contract stability | Rahul | Open (default accepted) | Add `pending_review`/`rejected`; public reads expose only `published`/`cancelled` |
| 7 | Vendors accepting demographic reach instead of individual targeting; weekly cap depressing revenue | Sales friction; Stream-2 income | Rahul | Risk | Lead with audience estimates + CTR reporting; cap owner-configurable, revisit once CTR data exists |
| 8 | Moderation queue bottleneck; topic reach vs live audience drift; 04 freshness for grade expansion | Campaign delays; approximate impression accounting; over/under-reach | Rahul | Risk | 30-second checklist decisions (SLA `TODO: Confirm`); `audience_count` stored at dispatch, labelled delivered-estimate; expansion reads 04 live, retries loudly |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| BR-05 (demographic-targeted advertising + event ticketing) / BR-006, BR-008, BR-010, BR-011 (module rules ADS-BR-001–013) | §7 (Stream 2 + ticketing commission) | `ADS-US-001`–`013` | `ADS-BE-001`–`038` · `ADS-FE-001`–`013` · `ADS-AP-001`–`003` (gap tracking) · `ADS-INT-001`–`008` | `ADS-UT-001`–`007` · `ADS-IT-001`–`012` · `ADS-E2E-001`–`002` |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-10-04 | Build executed contract-first: 17 routes + 24 `Ads*` schemas (public events routes `security: []`); targeting JSONB struct-constrained to demographic keys (BR-003); dispatch job = status gate → budget auto-pause → 7-day per-topic cap → topic expansion → server-injected "স্পনসর্ড \| Sponsored" labelled BroadcastTopic → batched pseudized impression rows + spend accrual; aggregate-only analytics via `ads_daily`; ticket reservation = row-locked capacity CTE, free→paid instantly, 10% commission on paid only; event moderation states added per OQ-7; additive `campaign` push type in 06's builder; migrations `20270220100000–101000`. App surface = recorded gap (OQ-3). | Kilo |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Consistency pass: migrations re-versioned `20270220…` (after 12); `hierarchy.AudienceCount` declared by 04 with `Streams` (04 `sections.stream`) for BR-05 | Claude |

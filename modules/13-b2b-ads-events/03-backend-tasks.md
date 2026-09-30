# B2B Ads & Events — Backend Tasks & Database Design

**Module:** `13-b2b-ads-events`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `contracts/openapi/openapi.yaml` · slog logging
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms · generated `openapi-fetch` client → api
**Last updated:** 2026-09-30

Schema first. Nothing below is designed until the schema is settled. Every table states its
tenant-scope column/rule — unscoped tables are a defect (`prompt.txt` §9). Scope owner here is the
**vendor account** (B2B platform-wide resource), not a school tenant.

---

## 1. Database Design

### 1.1 Tables

#### `ad_campaigns` (model `AdCampaign`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `vendor_account_id` | `uuid` | no | — | FK → 07 `vendor_accounts(id)`; **scope owner** (account isolation) |
| `name` | `text` | no | — | 3–120 chars |
| `objective` | `text` | no | — | CHECK `awareness` \| `event_promo` |
| `targeting` | `jsonb` | no | '{}' | Keys CHECK-limited to `{city_id, grade, section_ids}` — demographic only (ADS-INV-2); `section_ids` ⊆ schools of `city_id` (INV-9, service-validated) |
| `schedule_start` | `timestamptz` | no | — | dispatch window opens |
| `schedule_end` | `timestamptz` | no | — | auto-complete |
| `budget_bdt` | `numeric(12,2)` | no | — | > 0 |
| `spend_bdt` | `numeric(12,2)` | no | `0` | accrues at dispatch (rate × audience) |
| `status` | `text` | no | `draft` | CHECK `draft` \| `pending_review` \| `approved` \| `rejected` \| `scheduled` \| `running` \| `completed` \| `paused` |
| `rejection_reason` | `text` | yes | `null` | required when `rejected` |
| `created_by` | `uuid` | no | — | FK → 03 `users(id)` |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** CHECKs above; `CHECK (schedule_start < schedule_end)`; `CHECK (budget_bdt > 0)`.
**Indexes:** `(vendor_account_id, status)` → vendor lists; `(status, schedule_start)` → dispatch/complete job scans; `(status)` partial on `pending_review` → moderation queue.

#### `ad_creatives` (model `AdCreative`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `campaign_id` | `uuid` | no | — | FK → `ad_campaigns(id)` ON DELETE CASCADE |
| `kind` | `text` | no | — | CHECK `push` \| `native_banner` |
| `title_bn` / `title_en` | `text` | no | — | ≤ 120; bn required (school-facing), en required (bilingual rule) |
| `body_bn` / `body_en` | `text` | no | — | ≤ 500 |
| `image_media_id` | `uuid` | yes | `null` | FK → 05 `media_assets(id)`; required for `native_banner` (service) |
| `cta_label` | `text` | no | — | bn/en via i18n keys at render; vendor label ≤ 40 |
| `cta_url` | `text` | no | — | CHECK absolute https |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** one active creative per kind per campaign — `UNIQUE (campaign_id, kind)`.
**Indexes:** `campaign_id` → creative fetch at dispatch/serve.

#### `ad_events` (model `AdEvent` — aggregate fact table)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | identity | PK (high-volume table; uuid v7 deliberately not used) |
| `campaign_id` | `uuid` | no | — | FK → `ad_campaigns(id)`; the only vendor-facing access path (scope via campaign ownership) |
| `user_ref` | `text` | yes | `null` | **Pseudized** (HMAC-SHA256 of user id, daily-rotating salt); never joined to `users` for reads (ADS-INV-5) |
| `kind` | `text` | no | — | CHECK `impression` \| `click` |
| `topic` | `text` | yes | `null` | push rows: `city-{id}`/`school-{id}`/`section-{id}` (frequency-cap lookups); null for native |
| `audience_count` | `int` | yes | `1` | push impression rows = one row per topic broadcast with N recipients |
| `served_at` | `timestamptz` | no | `now()` | |
| `day` | `date` | no | — | Asia/Dhaka bucket of `served_at`; aggregate-friendly |
| `created_at` | `timestamptz` | no | `now()` | |

**Constraints:** none beyond CHECKs. **No tenant column by design** — rows are platform metrics; vendor access only through campaign-ownership-scoped aggregate queries (BR-008).
**Indexes:** `(campaign_id, day)` → analytics; `(day)` → aggregation job; `(topic, kind, served_at)` → frequency-cap pre-check.

#### `events` (model `Event`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `organizer_kind` | `text` | no | `vendor` | CHECK `vendor` \| `platform` |
| `vendor_account_id` | `uuid` | yes | `null` | FK → 07 `vendor_accounts(id)`; null ⇒ platform-organized; **scope owner** |
| `city_id` | `uuid` | no | — | FK → 04 `cities(id)` |
| `title_bn` / `title_en` | `text` | no | — | ≤ 150 |
| `description_bn` / `description_en` | `text` | no | — | ≤ 2000 |
| `venue` | `text` | no | — | |
| `starts_at` / `ends_at` | `timestamptz` | no | — | CHECK `starts_at < ends_at` |
| `ticket_price_bdt` | `numeric(10,2)` | yes | `null` | null ⇒ free event |
| `capacity` | `int` | no | — | 1–100,000 |
| `status` | `text` | no | `draft` | CHECK `draft` \| `pending_review` \| `published` \| `rejected` \| `cancelled` — spec base set `draft/published/cancelled` + moderation states (Open Question #7) |
| `rejection_reason` | `text` | yes | `null` | required when `rejected` |
| `created_by` | `uuid` | no | — | FK → 03 `users(id)` |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Indexes:** `(city_id, status, starts_at)` → public listing; `(vendor_account_id, status)` → organizer lists; partial `(status)` on `pending_review` → queue.

#### `event_tickets` (model `EventTicket`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `event_id` | `uuid` | no | — | FK → `events(id)`; scope derived from event organizer |
| `buyer_user_id` | `uuid` | no | — | FK → 03 `users(id)`; buyer scope |
| `qty` | `int` | no | — | ≥ 1; ≤ remaining capacity (tx) |
| `amount_bdt` | `numeric(12,2)` | no | — | unit price × qty; 0 for free |
| `commission_bdt` | `numeric(12,2)` | no | — | 10% of `amount_bdt` when paid (INV-8) |
| `status` | `text` | no | `reserved` | CHECK `reserved` \| `paid` \| `cancelled` |
| `payment_transaction_id` | `uuid` | yes | `null` | **seam to 12** — filled by `events.MarkTicketPaid` |
| `reserved_at` | `timestamptz` | no | `now()` | |
| `paid_at` / `cancelled_at` | `timestamptz` | yes | `null` | |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Indexes:** `(event_id, status)` → capacity + organizer totals; `(buyer_user_id)` → "my tickets"; `(status, event_id)` partial on `reserved` → sweep job.

#### `ads_daily` (model `AdsDaily` — read-model aggregate)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `campaign_id` / `day` | `uuid` / `date` | no | — | PK pair |
| `impressions` / `clicks` | `int` | no | `0` | SUM of `audience_count` / click rows |
| `spend_bdt` | `numeric(12,2)` | no | `0` | |

Rebuilt nightly; vendor analytics read only this table (BR-008).

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20270220100000_ad_campaigns_creatives_events` (ads pair + events) | ✅ |
| 2 | `20270220101000_ad_events_tickets_daily` (fact table + tickets + aggregate) | ✅ |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| 1 demo campaign ("Demo EdTech — Chattogram Class 12", status `draft`, never served) + 1 demo event ("Demo District Science Fair — Dhaka", `draft`) — clearly fictional and marked | `DRAFT` | `brd.md` §5 BR-05 / §7; publishing blocked by `TODO: Confirm` seed policy (ADS-BR-013) |

---

## 2. Server Contracts

### Vendor campaign & event endpoints — `/api/v1/vendor/…` (Go, generated from the OpenAPI spec)

`POST /vendor/campaigns` · `GET /vendor/campaigns` (own) · `PATCH /vendor/campaigns/{id}` (draft/rejected only) · `POST /vendor/campaigns/{id}/submit` · `GET /vendor/campaigns/{id}/analytics` · `POST /vendor/campaigns/{id}/pause` · `POST /vendor/campaigns/{id}/resume` · `POST /vendor/events` · `GET /vendor/events` (own) · `POST /vendor/events/{id}/submit` · `GET /vendor/audience-estimate?cityId=&grade=&sectionIds=`

| | |
| --- | --- |
| **Auth** | middleware: authenticate → load role claims (vendor) → scope to session `vendor_account_id`; 07 approved-gate re-checked per mutation (BR-001) |
| **Input** | contract-generated validator; request structs from `oapi-codegen`; targeting schema constrained to demographic keys |
| **Result** | `{ "data": … }` / RFC-7807 `application/problem+json` |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` (vendor not approved / not verified) · `VALIDATION_FAILED` · `NOT_FOUND` (other vendors' rows) · `TENANT_MISMATCH` (audited cross-account attempt) · `CONFLICT` (immutable state) · `CAMPAIGN_REJECTED` · `RATE_LIMITED` |
| **Rate limit** | class `default` |
| **Audit** | submit + pause/resume logged; approve/reject/dispatch audited (below) |
| **Stories** | ADS-US-001, 002, 006–008 |

### Moderation & admin endpoints — `/api/v1/admin/…`

`GET /admin/moderation/queue` (pending campaigns + events, checklist payload) · `POST /admin/campaigns/{id}/approve` · `POST /admin/campaigns/{id}/reject` · `POST /admin/events/{id}/approve` · `POST /admin/events/{id}/reject` · `GET /admin/ads/overview`

| | |
| --- | --- |
| **Auth** | authenticate → Super Admin claim (03 role guards) |
| **Result / Errors** | `{ "data": … }`; `FORBIDDEN` (non-Super-Admin), `CONFLICT` (already decided), `VALIDATION_FAILED` (reject without reason), `NOT_FOUND`, `RATE_LIMITED` |
| **Rate limit** | class `default` |
| **Audit** | every approve/reject (`audit.Record`: actor, decision, reason, checklist version) — destructive gate |
| **Stories** | ADS-US-003, 008, 013 |

### Public events & ticketing — `/api/v1/…`

`GET /events?cityId=` (published, upcoming, by city) · `GET /events/{id}` · `POST /events/{id}/tickets` · `GET /events/{id}/tickets` (organizer/Super Admin) · `POST /event-tickets/{id}/cancel`

| | |
| --- | --- |
| **Auth** | reads public (repository returns `published` ∧ ¬cancelled only, BR-012); ticket write/cancel requires VERIFIED user (03); organizer list requires owning vendor or Super Admin |
| **Input / Result** | contract validators; `{ "data": … }` |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` (unverified buyer) · `VALIDATION_FAILED` (capacity/qty) · `NOT_FOUND` · `TENANT_MISMATCH` (foreign ticket/event) · `CONFLICT` (cancel after start) · `RATE_LIMITED` |
| **Rate limit** | class `default` |
| **Audit** | ticket cancel (financial), event cancel |
| **Stories** | ADS-US-009–012 |

### Native ad serving (P1) — `/api/v1/ads/serve`, `/api/v1/ads/track/click`

| | |
| --- | --- |
| **Auth** | public/optional auth; server-side selection over `running` `native_banner` campaigns; labels injected; impressions/clicks pseudized |
| **Errors / Rate limit** | `NOT_FOUND` (nothing eligible → surface renders house slot), `RATE_LIMITED`; class `default` |
| **Stories** | ADS-US-005 (cap), BR-005/008 |

### Web Server Action / Route Handler (Next.js)

Calls the Go API through the generated `openapi-fetch` client — never the database directly.
Same auth + input (zod) + result rows as above.

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `ADS-BE-006` | `ads.CreateCampaign(principal, in)` | BR-001 gate; targeting demographic-only (INV-2/9); creative bn+en (INV-6); status `draft` | none (no-store) | no |
| `ADS-BE-007` | `ads.UpdateCampaign(principal, id, in)` | draft/rejected only (BR-011) else `CONFLICT` | none | no |
| `ADS-BE-008` | `ads.SubmitCampaign(principal, id)` | completeness + future schedule; unmodified rejected → `CAMPAIGN_REJECTED`; → `pending_review` | none | yes |
| `ADS-BE-009` | `ads.ReviewCampaign(actor, id, decision, reason, checklistVersion)` | Super Admin; reject requires reason; approve → approved/scheduled/running per schedule; concurrent decision → `CONFLICT` | admin queue (no-store) | yes |
| `ADS-BE-010` | `ads.PauseCampaign` / `ads.ResumeCampaign(principal, id)` | owner; running ⇄ paused | none | yes |
| `ADS-BE-011` | `ads.DispatchCampaign(campaignId)` — job entry | status gate (INV-3); budget guard (BR-006); frequency cap (BR-004); expand targeting → topics via 04; `notify.BroadcastTopic` per topic (06); batched impression rows; spend accrual; idempotent | none | yes |
| `ADS-BE-012` | `ads.CanServeToUser(ctx, userID)` | pseudized trailing-7d sponsored-push lookup (BR-004) — consumed by future per-user surfaces | — | no |
| `ADS-BE-013` | `ads.RecordClick(campaignId, userRef?)` | pseudized insert (BR-008) | none | no |
| `ADS-BE-014` | `ads.CampaignAnalytics(principal, id)` | ownership; reads `ads_daily` only (BR-008) | none | no |
| `ADS-BE-015` | `ads.SelectNativeAd(params)` (P1) | running ∧ approved only (INV-3); labels injected (BR-005) | none | impression row |
| `ADS-BE-016` | `events.CreateEvent` / `events.SubmitEvent(principal, in)` | BR-001; `ticket_price_bdt` null = free; → `draft`/`pending_review` | `events:city:{id}` (on publish only) | submit: yes |
| `ADS-BE-017` | `events.ReviewEvent(actor, id, decision, reason, checklistVersion)` | same queue as campaigns (BR-002) | `events:city:{id}` on approve | yes |
| `ADS-BE-018` | `events.ListByCity(ctx, cityID)` / `events.GetEvent(ctx, id)` | published ∧ ¬cancelled only (BR-012) | read-tagged | no |
| `ADS-BE-019` | `events.ReserveTicket(principal, eventID, qty)` | VERIFIED buyer; row-locked capacity (INV-7); free → `paid` instantly; priced → `reserved` | none | no |
| `ADS-BE-020` | `events.MarkTicketPaid(ctx, ticketID, paymentTransactionID)` | **12 seam**; sets `paid_at`, finalizes commission (INV-8); idempotent | none | yes |
| `ADS-BE-021` | `events.CancelTicket(principal, ticketID)` | buyer/Super Admin; before `starts_at` (BR-010); frees capacity | none | yes |
| `ADS-BE-022` | `events.ListEventTickets(principal, eventID)` | organizer scope; totals gross/commission/net (BR-009) | none | no |
| `ADS-BE-023` | `ads.AdminOverview(actor)` / `ads.AudienceEstimate(principal, params)` | Super Admin / vendor; estimate via 04 counts + Redis 5-min cache; `unknown` on 04 failure | none | no |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `ADS-BE-024` | `InsertCampaign` / `UpdateCampaign` / `GetCampaignForVendor` | all filtered `vendor_account_id = $session` | `(vendor_account_id, status)` |
| `ADS-BE-025` | `ListPendingCampaigns` / `ListPendingEvents` | `status = 'pending_review'` | partial `(status)` |
| `ADS-BE-026` | `TransitionCampaign(id, from, to)` | `UPDATE … WHERE status = $from` (optimistic guard ⇒ idempotent dispatch) | PK |
| `ADS-BE-027` | `InsertAdEvents(batch)` | batched multi-row INSERT (100/batch) | — |
| `ADS-BE-028` | `CountRecentSponsoredPush(topics, since)` | `kind='impression' AND topic = ANY($1) AND served_at > $2` | `(topic, kind, served_at)` |
| `ADS-BE-029` | `UpsertAdsDaily` / `SelectDailyByCampaign` | aggregate read-model | PK `(campaign_id, day)` |
| `ADS-BE-030` | `ListPublishedEvents(city)` | `status='published' AND cancelled_at IS NULL AND starts_at > now()` | `(city_id, status, starts_at)` |
| `ADS-BE-031` | `ReserveTicketTx` | `SELECT … FOR UPDATE` on event row → capacity check → INSERT ticket | `(event_id, status)` |
| `ADS-BE-032` | `MarkTicketPaid` / `CancelTicket` | status-guarded UPDATE; capacity recompute via `(event_id, status)` | `(event_id, status)` |
| `ADS-BE-033` | `TicketTotals(eventID)` | GROUP BY status → gross/commission/net | `(event_id, status)` |
| `ADS-BE-034` | `AdminOverview` | aggregate SELECTs over campaigns/events/tickets | partial `(status)`, `(event_id, status)` |

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `ADS-BE-035` | `campaign.dispatch` | 01 scheduler tick over `approved`/`scheduled` with `schedule_start ≤ now` | yes — status guard + dispatch-log key | retry w/ backoff on 06/04 failure; budget → auto-pause; logs per-topic result |
| `ADS-BE-036` | `campaign.complete` | `running` with `schedule_end ≤ now` | yes | retry; final report from `ads_daily` |
| `ADS-BE-037` | `ads.daily_aggregate` | nightly 00:05 Asia/Dhaka | yes — full rebuild per day | retry; lag alarm per 01/15 runbooks |
| `ADS-BE-038` | `tickets.sweep` | hourly; `reserved` unpaid at `starts_at` | yes | retry; cancel + notify buyer via 06 `SendToUser` |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `ADS-UT-001` | Targeting validator: demographic keys only; `section_ids` ⊆ city; rejects user-level keys | Unit | BR-003 / INV-2/9 |
| `ADS-UT-002` | Targeting → topic expansion (city / city+grade / sections) | Unit | dispatch contract with 06 |
| `ADS-UT-003` | Frequency-cap decision fn (trailing 7d, per topic/user) | Unit | BR-004 |
| `ADS-UT-004` | Budget guard: projected cost vs remaining; auto-pause boundary | Unit | BR-006 / INV-4 |
| `ADS-UT-005` | Commission math: 10% of paid amounts; free = 0; rounding | Unit | BR-009 / INV-8 |
| `ADS-UT-006` | Pseudization: stable per day, never reversible in repo queries | Unit | BR-008 / INV-5 |
| `ADS-IT-001` | Moderation gate: unapproved campaign never dispatches; unpublished event never lists (mandatory) | Integration | BR-002 / INV-3 |
| `ADS-IT-002` | Vendor isolation: vendor B cannot read/write vendor A's campaigns, events, tickets (mandatory) | Integration | §6 scope rule |
| `ADS-IT-003` | Status machine: illegal transitions (`PATCH` on pending_review, double approve) → `CONFLICT`; rejected-resubmit → `CAMPAIGN_REJECTED` | Integration | BR-011 / INV-1 |
| `ADS-IT-004` | Ticket reservation concurrency: N buyers, last seat — exactly one wins; free = instant `paid` (mandatory) | Integration | INV-7 |
| `ADS-IT-005` | Dispatch end-to-end w/ fake 06: topics expanded, labelled payload, impression rows + spend, audit entry | Integration | ADS-US-004 |
| `ADS-IT-006` | Public reads never return drafts/rejected/cancelled; unauthenticated writes denied on every entry point | Integration | BR-012 + always-include set |

> Always-include set holds: unauthenticated denial per protected entry point; validation rejects bad
> input; cross-account access → `TENANT_MISMATCH`/404; `TODO: Confirm` copy blocks submission
> (BR-013); public reads never leak drafts.

## 7. Task Checklist

> Tick with a date: `[x] <ID> … — YYYY-MM-DD`.

### Schema

- [ ] `ADS-BE-001` Migrations 1–2 (`ad_campaigns`, `ad_creatives`, `ad_events`, `events`, `event_tickets`, `ads_daily`) + sqlc models
- [ ] `ADS-BE-002` OpenAPI paths/schemas for all §2 endpoints; Go + TS clients regenerated
- [ ] `ADS-BE-003` CHECK constraints + indexes per §1.1
- [ ] `ADS-BE-004` i18n catalogs `ads.*`, `events.*`, `validation.ads.*`, `validation.events.*` in `packages/shared` (bn + en parity)
- [ ] `ADS-BE-005` Fictional seed (draft campaign + draft event, marked, blocked)

### Repository · Service · Entry points · Seed · Tests

- [ ] `ADS-BE-006`–`ADS-BE-010` campaign service CRUD/submit/review/pause-resume
- [ ] `ADS-BE-011`–`ADS-BE-015` dispatch, cap check, click, analytics, native selection (P1)
- [ ] `ADS-BE-016`–`ADS-BE-023` event + ticket services incl. 12 seam (`MarkTicketPaid`) and overview/estimate
- [ ] `ADS-BE-024`–`ADS-BE-034` repositories (batched inserts, FOR UPDATE reservation, aggregates)
- [ ] `ADS-BE-035`–`ADS-BE-038` jobs registered with the 01 worker
- [ ] `ADS-UT-001`–`006` unit suite green
- [ ] `ADS-IT-001`–`006` integration suite green (testcontainers Postgres)

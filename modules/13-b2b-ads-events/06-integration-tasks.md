# B2B Ads & Events — Integration Tasks

**Module:** `13-b2b-ads-events` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> `02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
> **contract**. **No cross-module call, cache key or external dependency may exist in code unless
> it is declared here** (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `06-notifications` | we call them | exported `notify.BroadcastTopic(topic, payload)` per expanded topic at dispatch (`city-{id}`/`school-{id}`/`section-{id}` — targeting IS topic selection); `notify.SendToUser` for event-cancel buyer notices | degraded — `campaign.dispatch` job retries; campaign stays `running` with pending dispatch |
| I-2 | `07-command-center-web` | we call them | `vendors.Approve` status gate before every `/vendor/*` mutation (BR-001); `leads.Create` reuse for the ads inquiry funnel | degraded — vendor mutations blocked fail-closed with clear copy |
| I-3 | `07-command-center-web` | they consume us | REST (§2): `/vendor/ads|events*` vendor portal screens, `/admin/moderation` queue (fills 07's stub), `/admin/ads` overview, public `/events*` | degraded — portal sections + queue show API error states; nothing else affected |
| I-4 | `04-organization-hierarchy` | we call them | sections-by-city+grade reads + aggregated `hierarchy.AudienceCount` (additive, 04 §7 additive-first) for estimates and dispatch expansion | degraded — estimate `unknown`; dispatch retries; never fatal |
| I-5 | `12-payments` | they call us | seam: 12 fills `event_tickets.payment_transaction_id` then calls `events.MarkTicketPaid(ticketID, txID)` | degraded — tickets stay `reserved` ("payment pending"); sweep at event start |
| I-6 | `05-communication-engine` | we call them | `media_assets` presign/confirm for creative images | degraded — text-only push still dispatchable; native slot placeholder |
| I-7 | `01-foundations` | we call them | `jobs.Enqueue` (`campaign.dispatch`, `campaign.complete`, `ads.daily_aggregate`, `tickets.sweep`), `audit.Record` (decisions, dispatches, cancels), RFC-7807 envelope, `default` limiter class | degraded — dispatches queue; audit failure aborts the wrapped decision by design |
| I-8 | `03-identity-access` | we call them | auth chain (authenticate → role claims → tenant-scope); buyer VERIFIED check on tickets | fatal to entry points by design (`UNAUTHENTICATED`/`FORBIDDEN`) |

## 2. Exported Contract

```text
ads.DispatchCampaign(ctx, campaignID uuid) (DispatchResultDTO, error)      // job entry; idempotent
ads.CanServeToUser(ctx, userID uuid) (bool, error)                          // frequency cap check (BR-004)
events.ListByCity(ctx, cityID uuid) ([]EventDTO, error)                     // published ∧ ¬cancelled only
events.MarkTicketPaid(ctx, ticketID uuid, paymentTransactionID uuid) error  // 12 seam (I-5)

REST (OpenAPI, consumed by web — 07 shell + this module's screens):
  POST/GET /api/v1/vendor/campaigns · PATCH /{id} · POST /{id}/submit · /{id}/pause · /{id}/resume
  GET      /api/v1/vendor/campaigns/{id}/analytics · GET /api/v1/vendor/audience-estimate
  POST/GET /api/v1/vendor/events · POST /{id}/submit
  GET      /api/v1/admin/moderation/queue · POST /admin/campaigns/{id}/approve|reject
  POST     /admin/events/{id}/approve|reject · GET /admin/ads/overview
  GET      /api/v1/events · /events/{id} · POST /events/{id}/tickets · GET /events/{id}/tickets
  POST     /api/v1/event-tickets/{id}/cancel · GET /ads/serve · POST /ads/track/click (P1)
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `ads.DispatchCampaign` | 01 worker (`campaign.dispatch`) | per-topic results (sent / skipped: frequency-cap / paused: budget), impression + spend totals | `NOT_FOUND`, `CONFLICT` (wrong status), `VALIDATION_FAILED` | Hard moderation gate inside (BR-002/INV-3): unapproved campaigns never dispatch; audit-logged |
| `ads.CanServeToUser` | future per-user ad surfaces (native slots amendment) | bool (trailing 7-day sponsored-push check) | `VALIDATION_FAILED` | Pseudized lookup only (BR-008); no profile built |
| `events.ListByCity` | web `/events` (ISR), 07 dashboard cards, future app amendment | `[]EventDTO` (bn/en, price, schedule, capacity-left) | `NOT_FOUND` (city) | Published, non-cancelled, upcoming only (BR-012) |
| `events.MarkTicketPaid` | module 12 settlement path | void; ticket `reserved`→`paid`, commission finalized | `NOT_FOUND`, `CONFLICT` (already paid/cancelled) | Idempotent; 13 never calls gateways itself |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `notify.BroadcastTopic` / `notify.SendToUser` | 06 | `campaign.dispatch` retries w/ backoff; buyer notices re-queued; push never sent unlabeled |
| `vendors.Approve` gate + `leads.Create` | 07 | Fail-closed: vendor mutations refused with `FORBIDDEN` copy; funnel degrades to 07's lead form |
| Sections reads + `hierarchy.AudienceCount` (additive — coordinate with 04 §7) | 04 | Estimate `unknown`; dispatch expansion retries; never invent counts |
| `media_assets` presign/confirm | 05 | Creative save blocked with retry; text-only push unaffected |
| `jobs.Enqueue` + worker runtime, `audit.Record` | 01 | Dispatches queue in job table; audit failure aborts decision (by design) |
| Auth chain + VERIFIED status | 03 | Entry points refuse (`UNAUTHENTICATED`/`FORBIDDEN`) |
| `events.MarkTicketPaid` result of 12 settlement | 12 (caller) | N/A — 12 owns its retries; ticket stays `reserved` until it arrives |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| Event approve → `published` | `events:city:{cityId}` |
| Event cancel / edit while published | `events:city:{cityId}` |
| Ticket create/cancel (capacity-left changes) | `events:city:{cityId}` (capacity display freshness) |
| Campaign/event mutations (vendor, moderation) | none — vendor + admin surfaces are no-store |

| Read | Tagged with |
| --- | --- |
| `GET /events?cityId=` (listing) | `events:city:{cityId}` (ISR/60 s) |
| `GET /events/{id}` | `events:city:{cityId}` |
| `/vendor/*`, `/admin/moderation`, `/admin/ads`, `/ads/serve` | never cached |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| None direct — N/A | — | — | — | — | FCM/Expo credentials live in 06 (13 calls `notify.*` only); R2 in 05; payment gateways in 12; SMS/SSO in 03. This module holds no external secrets |

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| Builder targeting step (`04` §2.1) | `GET /vendor/audience-estimate?cityId=&grade=&sectionIds=` | `{count: int \| null}` — `null` renders "estimate unavailable", never a fabricated number |
| Builder submit | `POST /vendor/campaigns` → `POST …/{id}/submit` | Draft then pending_review; `CAMPAIGN_REJECTED` copy on unmodified resubmit |
| Vendor analytics | `GET /vendor/campaigns/{id}/analytics` | Daily impressions/clicks/spend from `ads_daily` (aggregate-only) |
| Moderation queue | `GET /admin/moderation/queue` → `POST /admin/{campaigns\|events}/{id}/approve\|reject` | Reason required on reject; checklist version in payload; `CONFLICT` → refresh |
| Public events | `GET /events?cityId=` · `GET /events/{id}` | Published only; tagged reads |
| Ticket action | `POST /events/{id}/tickets` → free: `paid` instant · priced: `reserved` + "payment pending" honest state | Capacity errors map `validation.events.qty_exceeds_capacity` |
| Organizer tickets | `GET /events/{id}/tickets` | List + gross/commission/net totals (BR-009) |
| Ticket cancel | `POST /event-tickets/{id}/cancel` | Before-start guard; paid → refund-via-12 copy |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change. Frozen for Phase-3 consumers: the four §2
export signatures (06-independent, 07/12-facing) and the REST surface 07's shell renders against.
The 04 `hierarchy.AudienceCount` request is **additive** per 04 §7 — until merged, the estimate
endpoint returns `count: null` (`ADS-IT-009` proves the fallback). The `type=campaign` push payload
follows 06 §7's frozen v1 schema (additive type value; unknown types fall back home in old clients).
Event `status` carries moderation states beyond the spec base set (Open Question #7) — public reads
expose only `published`/`cancelled`, so the public contract is stable regardless.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| 06 / FCM down at dispatch | All REST surfaces; campaign stays `running` | No sponsored push yet | `campaign.dispatch` retries ×3 backoff → drain on restore; dispatch idempotent (`ADS-IT-007`) |
| 07 gate down | Public reads; moderation (Super Admin) | Vendor mutations refused fail-closed | Retry after 07 returns; no un-gated creation ever |
| 04 down | Existing estimates (Redis TTL), reads, ticket flows | Estimate "unavailable"; dispatch queued | Expansion retries; never invents counts (`ADS-IT-009`) |
| 12 undelivered (expected until Phase 3) | Free tickets; reservations | Priced tickets clearly "payment pending" | `tickets.sweep` cancels unpaid at start; `MarkTicketPaid` fills retroactively (`ADS-IT-011`) |
| 05 media down | Text-only push creatives | Image upload blocked w/ retry | Presign retry; native slot placeholder |
| 01 worker down | All reads/writes | Dispatches/aggregates lag | Status-scoped workers drain on restart; lag alarm per 15 |
| Redis down | All no-store surfaces; DB fall-through for events | Slower public events | TTL cache rebuilds |
| Neon cold start | Static/ISR pages | Slow portal first load | Warm-up per module 15 runbook |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `ADS-IT-007` | Targeting respects demographics only: user-level keys refused; dispatch produces **only** hierarchy-topic broadcasts (fake 06 records topics) | Integration | BR-003 / INV-2, minors protection |
| `ADS-IT-008` | Frequency cap: second sponsored push to same topic within 7 days skipped; `CanServeToUser` flips after window | Integration | BR-004 |
| `ADS-IT-009` | Moderation gate: `pending_review`/`rejected`/`draft` campaign never dispatches even when job runs early; unpublished event never in `ListByCity` | Integration | BR-002 / INV-3 / BR-012 |
| `ADS-IT-010` | Budget guard: spend at budget ⇒ dispatch refused + auto-pause, zero sends | Integration | BR-006 / INV-4 |
| `ADS-IT-011` | Ticket reservation under concurrency + 12 seam: free = instant `paid`; priced stays `reserved` until `MarkTicketPaid`; sweep cancels unpaid at start | Integration | INV-7 / I-5 |
| `ADS-IT-012` | Vendor isolation: cross-account campaign/event/ticket reads and writes → `TENANT_MISMATCH`/404 | Integration | §2 scope rules |
| `ADS-UT-007` | Cache tags: publish/cancel revalidate `events:city:{id}`; vendor/admin reads never cached | Unit | §4 contract |
| `ADS-E2E-001` | Playwright: vendor creates campaign (estimate visible, bn/en creative, sponsored-label preview) → Super Admin approves in queue → dispatch job logs broadcast + impression + audit | Playwright + axe | ADS-US-001→004 golden path |
| `ADS-E2E-002` | Playwright: vendor lists event → approve → public listing shows it → buyer takes free ticket → organizer sees totals with 10% commission | Playwright + axe | ADS-US-008→011 golden path |

(Backend unit/integration matrix — `ADS-UT-001`–`006`, `ADS-IT-001`–`006` — lives in
`03-backend-tasks.md` §6; rows here are the cross-module/integration set.)

## 10. Task Checklist

- [ ] `ADS-INT-001` Implement + export `ads.DispatchCampaign` (status/budget/cap gates, fake-able 06 client, audit) — ____
- [ ] `ADS-INT-002` Implement + export `ads.CanServeToUser` (pseudized trailing-window lookup) — ____
- [ ] `ADS-INT-003` Implement + export `events.ListByCity` (published-only) + `events.MarkTicketPaid` (12 seam, idempotent) — ____
- [ ] `ADS-INT-004` Consume 07 gate (`vendors.Approve`) + fill `/admin/campaigns` stub route with the moderation queue — ____
- [ ] `ADS-INT-005` Coordinate additive `hierarchy.AudienceCount` with 04; ship `count: null` fallback — ____
- [ ] `ADS-INT-006` Register 4 jobs with 01 worker; wire `audit.Record` on decisions/dispatch/cancels — ____
- [ ] `ADS-INT-007` Cache tags `events:city:{id}` + no-store enforcement on vendor/admin/serve reads — ____
- [ ] `ADS-INT-008` Tests `ADS-UT-007`, `ADS-IT-007`–`012`, `ADS-E2E-001`–`002` green in CI (Playwright + axe) — ____

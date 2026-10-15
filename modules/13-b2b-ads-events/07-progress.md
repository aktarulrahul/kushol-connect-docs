# 13-b2b-ads-events — Build Progress

Module: b2b-ads-events · Surfaces: **api + web** (README scope; app = recorded gap OQ-3) ·
**Last updated:** 2026-10-15

> Owner instruction: "complete 13-b2b-ads-events" — same through-stages precedent (06/10/11/12);
> gates 1–3 stay owner-manual.

## Stage / gate status

| Stage | Status | Evidence |
| --- | --- | --- |
| 1 Plan | ✅ 2026-10-03 | plan in-session; defaults OQ-1…7; deps 06/07 🚧 accepted per owner instruction |
| 2 UI (web, mock-driven) | ✅ 2026-10-03 | contract-first: 17 REST paths + 24 `Ads*` schemas landed FIRST; both clients generated; web: moderation queue, campaign list, public events on `fixtures/ads.ts` |
| Gate 1 | ✅ owner 2026-10-15 | owner approved in session ("complete all from Gate 1") |
| 3 Docs sync | ✅ 2026-10-04 | this file, 08-gaps, README → 🚧, checklist ticks, change log |
| 4 Backend | ✅ code-complete 2026-10-04 | 2 migrations, 2 sqlc files, `internal/ads` (service, targeting/topics/cap/budget pure fns, dispatch job, events+tickets, handler) + cmd/httpapi wiring |
| Gate 2 (SQL on Neon) | ✅ owner | 2026-10-09 — all migrations applied to Neon via 15 first deploy (`v0 → 20270302090001 dirty=false`), covers `20270220100000–101000` |
| 5 Integration | ✅ code-complete 2026-10-04 | web fixture seam until 07's console glue (G-3, 10/11/12 precedent); IT-001–006 specs exist — runs pending owner |
| Gate 3 | ⏳ pending | — |

## Decisions (ADR)

1. **ADR-1 (demographic-only targeting, BR-003/INV-2):** targeting JSONB keys struct-constrained to
   `{cityId, grade, sectionIds}` — user-level keys cannot enter the shape; UT-001 proves the parse.
2. **ADR-2 (dispatch = topic expansion + labelled 06 broadcast — ADS-BE-011):** sections →
   `section-{id}`, city → `city-{id}`; sponsored label "স্পনসর্ড | Sponsored" injected
   server-side into the payload title/body (BR-005); budget guard auto-pauses BEFORE any send
   (BR-006); per-topic 7-day frequency cap skips (BR-004); idempotent via from-status transitions.
3. **ADR-3 (aggregate-only analytics — BR-008/INV-5):** `ad_events` is a bigint fact table with
   daily-rotating HMAC `user_ref` (UT-006); vendor analytics read `ads_daily` only.
4. **ADR-4 (ticket lifecycle — INV-7/8):** row-locked capacity in the INSERT..WHERE CTE; free →
   `paid` instantly, priced → `reserved` with the 12 seam (`payment_transaction_id`); 10%
   commission server-computed on paid amounts only.
5. **ADR-5 (event moderation states — OQ-7):** `pending_review`/`rejected` added to the base set;
   same Super-Admin queue as campaigns; reject requires ≥5-char reason; every decision audited.

## Evidence (2026-10-04)

| Repo | Check | Result |
| --- | --- | --- |
| api | build/vet repo-wide | clean |
| api | golangci-lint `./internal/ads/...` | **0 issues** |
| api | `go test -race ./internal/ads/...` | UT-001 (targeting), UT-002 (topic expansion), UT-003 (cap), UT-004 (budget), UT-005 (commission), UT-006 (pseudization), sponsored-label privacy — green |
| api | `make contracts-check` | `contracts: no drift` |
| api | wiring | `campaign.dispatch` / `ads.daily_aggregate` / `tickets.sweep` registered; `adsBroadcastAdapter` marshals payloads for 06's raw-byte BroadcastTopic |
| api | `it_ads_test.go` | **not yet written** — IT-001–006 specs exist; the file lands with the integration pass (G-2) |
| web | typecheck ✓ · lint ✓ · tests 22 files green | moderation queue (campaigns+events+checklist+reject-reason), campaign list, public events |
| both clients | sync + generate | spec copies match the api |

## Gate 2 SQL hand-off (owner)

```text
db/migrations/20270220100000_ad_campaigns_creatives_events.up.sql  -- ad_campaigns + ad_creatives + events
db/migrations/20270220101000_ad_events_tickets_daily.up.sql        -- ad_events fact + event_tickets + ads_daily
```
Run in order against Neon; each has a `.down` reverse.

## Gate 1 review hand-off

Web (`pnpm dev`, fixtures): `/admin/moderation` (queue: approve / reject-with-reason dialog,
checklist panel), `/vendor/ads` (campaign table w/ status + spend/budget), `/events` (public
published-only listing). Desktop 1280 + 768.

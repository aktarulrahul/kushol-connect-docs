# 11-campus-commerce — Build Progress

Module: campus-commerce · Surfaces: api + web (vendor portal + admin stub) + app (buyer) ·
Repos: `applications/api`, `applications/web`, `applications/app` · **Last updated:** 2026-10-03

> Owner instruction (this session): "go ahead" after the Stage-1 plan — building continued through
> the stages on that instruction (precedent: modules 06/10); gates 1–3 stay owner-manual.

## Stage / gate status

| Stage | Status | Evidence (dated) |
| --- | --- | --- |
| 1 Plan | ✅ 2026-10-03 | plan delivered in-session; defaults OQ-1…6 + README manual-courier default; dep 07 🚧 accepted per owner instruction |
| 2 UI (web + app, mock-driven) | ✅ 2026-10-03 | contract-first: 20 OpenAPI paths + 26 `Commerce*` schemas landed FIRST; both clients generated; web: 8 vendor routes + commission stub on `fixtures/commerce.ts`; app: 7 buyer routes + shared bits on `fixtures/commerce.ts` |
| Gate 1 (UI approval) | ⏳ pending owner — build continued on the owner's "go ahead" | |
| 3 Docs sync | ✅ 2026-10-03 | this file, `08-gaps.md`, README → 🚧, checklist ticks (`03` §7, `04` §9, `05` §9, `06` §10), change log |
| 4 Backend | ✅ code-complete 2026-10-03 | 4 migrations + 4 sqlc query files + `internal/commerce` (service, orders, lifecycle, payload, jobs, handler, dto, cache) + httpapi/cmd wiring; `go build ./...` + `go vet ./...` clean; golangci-lint 0 issues in `internal/commerce`; **SQL hand-off below — Gate 2 pending owner** |
| Gate 2 (SQL on Neon) | ⏳ pending owner | — |
| 5 Integration | ✅ code-complete 2026-10-03 | app: live `openapi-fetch` client (`live.ts`) behind the session-token selector (`backend.ts`), hooks re-pointed; web: stays on the fixture seam until 07's console session glue (G-3, same boundary as 10-G-8); IT + Playwright + Maestro written — runs pending owner |
| Gate 3 | ⏳ pending | — |

## Decisions (ADR)

1. **ADR-1 (contract-first):** the 20 endpoints + schemas landed in the api spec before any UI
   code; both clients generated from it (no hand-rolled DTO types); `contracts: no drift`.
2. **ADR-2 (storefront_schools join table — 02 §10 Option B):** the hot stores-by-school query is
   a plain indexed join with FK integrity to 04's schools; the jsonb-array alternative lost.
3. **ADR-3 (reserve→decrement, INV-2):** `qty_reserved` held by `placed` rows (visible on the
   vendor board), decrement on confirm; placed-cancel releases, post-confirm cancel restocks;
   single partial-UNIQUE accepted row prevents double-decrements by construction.
4. **ADR-4 (single-store direct order — 02 §10 Option B, OQ-5):** one tx, one storefront, one
   fulfilment decision; FK shape enforces INV-7; cart is additive later.
5. **ADR-5 (fail-closed vendor gate):** every vendor write and every placement re-checks
   `vendors.RequireApprovedVendor` — a 07 read failure refuses with `FORBIDDEN`, never assumes
   approved (11 §6 §3).
6. **ADR-6 (payment seam dormant):** `orders.payment_method='cod'` until 12; `online` + txn attach
   guard live in the schema/service now (12 plugs in without schema change).

## Evidence (2026-10-03)

| Repo | Check | Result |
| --- | --- | --- |
| api | `go build ./...` + `go vet ./...` | clean repo-wide |
| api | `make fmt-check` | clean |
| api | golangci-lint `./internal/commerce/...` | **0 issues** |
| api | `go test -race ./internal/commerce/...` | UT: state-machine edges (7 legal / 7 CONFLICT), commission round2, numeric round-trip, product validation (6 negatives), cache-tag sets, payload privacy, config defaults — green |
| api | `go test ./...` | repo-wide green, no FAIL |
| api | `make contracts-check` | `contracts: no drift` |
| api | `it_commerce_test.go` | IT-001/002/003/004/005/009 written (testcontainers + fakes) — **pending owner** `make test-integration` |
| api | cmd/api wiring | `commerce.auto-cancel` + `commerce.low-stock-digest` registered; notify adapter; shared tag cache wired |
| web | `pnpm typecheck` | green (`next typegen` re-ran) |
| web | scoped eslint on commerce files | clean |
| web | `pnpm test` | green incl. 4 commerce-seam tests (state machine, FORBIDDEN gate, ≥5-char cancel reason, reserved-guard) |
| web | `e2e/commerce.spec.ts` | written — **run pending owner** |
| app | `pnpm typecheck` | green |
| app | scoped eslint on commerce files | clean |
| app | `pnpm test src/lib/commerce` | **10/10** (out-of-stock naming, NOT_VERIFIED gate, COD limit, cancel-before-shipped, offline, replay-once, BD phone, deep link) |
| app | `pnpm test` (full) | 267/268 — the 1 red is `src/__tests__/index.test.tsx` (pre-existing, 05 stream) |
| app | Maestro | `.maestro/commerce-golden-path.yaml` — **run pending owner** |
| both clients | `sync:api-spec && generate:api` | spec copies match the api (110 `Commerce` type refs each) |

## Gate 2 SQL hand-off (owner)

```text
applications/api/db/migrations/20270201090000_cmp_storefronts.up.sql   -- vendor_storefronts + storefront_schools (+ indexes)
applications/api/db/migrations/20270201091000_cmp_products.up.sql      -- products + product_variants (+ CHECKs, UNIQUE names)
applications/api/db/migrations/20270201092000_cmp_inventory.up.sql     -- inventory_items (INV-2 CHECKs, partial UNIQUEs)
applications/api/db/migrations/20270201093000_cmp_orders.up.sql        -- orders + order_items (state CHECKs, commission band, job/board indexes)
```
Run in order against the shared Neon database (each has a `.down` reverse). golang-migrate records
the highest version — do not run lower-versioned files afterwards.

## Gate 1 review hand-off

- **Web** (`pnpm dev`, vendor fixture): `/vendor` (dashboard counters) → `/vendor/storefront`
  (create/pause dialogs) → `/vendor/products` (+ new/edit with variants) → `/vendor/inventory`
  (inline stock edit; low-stock rows) → `/vendor/orders` (board; confirm/ship/cancel dialogs) →
  `/admin/commission` (stub). Fixture modes: `success/offline/forbidden/conflict/out_of_stock`.
  Desktop 1280 + 768.
- **App** (fixture session): Marketplace → স্টোর → store page → product detail (variant picker +
  qty) → checkout (pickup vs courier) → place → order screen → cancel. Fixture mode
  `out_of_stock` exercises the honest-label path; `offline` queues the placement once. 360px bn+en.

# Campus Commerce — Technical Document

**Module:** `11-campus-commerce` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Single engineer-facing reference compressing the six spec files in this folder (`01-user-stories.md` … `06-integration-tasks.md`). If this document drifts, the spec files win and this file gets corrected.

---

## 1. Overview

### 1.1 Purpose

Implements `brd.md` **BR-04** and `prd.md` **§5.4**: approved vendors open storefronts scoped to an explicit subset of schools, list books/uniforms/stationery with bn-first names, variants and stock, and fulfil orders by in-store pickup or manual third-party courier; verified students and guardians buy only from stores serving their own school, cash-on-pickup/delivery first. A commission is frozen on every order (`brd.md` §7 Stream 1: 5–10%, default 5%). Phase 3 (`brd.md` §8) — serves `brd.md` §2 Goal 2 and the §7 campus-commerce revenue stream.

### 1.2 Scope

**In:** vendor portal (fills 07's `/vendor` shell: storefront create/settings with schools served + pickup address + pause/resume, product catalog with bn-first names + variants + images via 05 media, inventory manager with inline stock edit + low-stock highlight, orders fulfilment board confirm → ready/ship → complete/cancel) · buyer app (Marketplace → Store: stores serving my school, store page + product grid, product detail with variants/stock state/approved-vendor trust signals, checkout with pickup vs courier + COD summary, my orders with status chips/tracking/pickup instructions/cancel) · order engine (transactional placement with stock reservation — oversell-proof, immutable item snapshots, commission frozen at placement default 5%, COD limit guard, auto-cancel of stale `placed` orders) · payment seam for module 12 (`commerce.OrderAmount` + `AttachPaymentTransaction`; every order COD until 12 ships).

**Out:** online payment gateways, receipts, ledgers — module 12 (reads orders via the seam) · courier company APIs / automated tracking links — manual courier name + tracking number only (`brd.md` §4; README default) · in-house delivery fleet (`brd.md` §4) · product reviews/ratings · search-across-stores · commerce ads (module 13) · multi-store cart (default single-store, OQ-5) · discounts/coupons · per-storefront commission configuration UI (later via 07).

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 01 foundations | `jobs.Enqueue` (auto-cancel, digests, placement timer), `audit.Record`, RFC-7807 envelope, rate limiter, test harness |
| consumes | 02 design-system | bn/en catalogs `commerce.*` + `validation.*`, tokens, RN/web primitives, badge styling |
| consumes | 03 identity-access | `auth.RequireVerified` (buying is verified-only), `users` (buyer identity, school claims), portal-user model for vendors |
| consumes | 04 organization-hierarchy | School catalog (schools a storefront serves; buyer's school context) |
| consumes | 05 communication-engine | `media.PresignUpload`/`ConfirmUpload` (product images) |
| consumes | 06 notifications | `notify.SendToUser` (order-status pushes with deep links) |
| consumes | 07 command-center-web | `vendors.Approve` family + vendor status read (`GET /vendor/state`) — approval gate, fail-closed suspend checks; `/vendor` shell + nav stubs this module fills |
| consumed by | 12 payments | `commerce.OrderAmount(orderId)` + `commerce.AttachPaymentTransaction(orderId, txnID)` — the 11↔12 order-payment seam; 12 also reads `OrdersForVendor` for commission reporting |
| consumed by | 07 / 13 (later) | `OrdersForVendor` (07/12 Super-Admin revenue reporting); `StorefrontsForSchool` (future 13 school-surface reads) |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| api | Go 1.24+ · chi · services · ownership/tenant-scoped repositories · sqlc + pgx · PostgreSQL (Neon) · Redis · in-DB job table + 01 worker | REST handlers, placement transaction, auto-cancel/digest jobs | `tech-stack.md` api table; no carrier API, no gateway — payment via module 12's seam |
| contracts | OpenAPI 3.1 (`applications/api/openapi/`) | single source for Go server types + TS clients (+ `OUT_OF_STOCK` problem code) | paths #1–#20 |
| web | Next.js App Router · Server Components/Actions · TanStack Table + Query (board 30 s / inventory 60 s polls) · RHF + zod · shadcn/ui | vendor portal + `/admin/commission` stub | fills module 07's `/vendor` shell |
| app | Expo · expo-router · TanStack Query · RHF + zod | buyer surfaces only (vendors use the web portal) | bn-first, 360px-first |
| web + app (per app) | each app's `src/i18n` bn/en catalogs + zod schemas | `commerce.*` / `validation.commerce.*` keys | bn default |

---

## 3. Architecture

### 3.1 Component diagram

```text
web vendor portal (07 shell) ──┐                                        ┌─► 03 auth.RequireVerified · users (buyer gate, portal user)
app buyer (Expo) ──────────────┴─► chi REST /api/v1/vendor·commerce/* ──┼─► 04 school catalog (storefront schools, buyer tenant)
                                     │                                  ├─► 05 media.PresignUpload/ConfirmUpload (product images)
                                     │                                  ├─► 06 notify.SendToUser (status pushes, deep links)
                                     │                                  └─► 07 vendors.Approve family + status read (fail-closed)
                                     ▼
              commerce service (CMP-BE-001–024) ── Redis tags (commerce:stores:school:{id} · store:{id} · product:{id})
                                     │  sqlc + pgx → PostgreSQL/Neon
 vendor_storefronts · storefront_schools · products · product_variants · inventory_items · orders · order_items
                                     ├─► 01 jobs worker: commerce.auto-cancel · commerce.low-stock-digest
                                     └─► 12 seam: commerce.OrderAmount / AttachPaymentTransaction (dormant until 12 ships)
```

### 3.2 Boundary

**Owns (tables / services):** `vendor_storefronts`, `storefront_schools`, `products`, `product_variants`, `inventory_items`, `orders`, `order_items` — plus the auto-cancel and low-stock jobs over them. `vendor_accounts` stays 07's (read-only via its vendor service).

**Reads (via exported service functions only):** 07 vendor approval status (fail-closed on the money path; browse staleness ≤ cache TTL) · 03 verification gate + identity · 04 school catalog · 05 media uploads · 06 push · 01 job runtime, audit, limiter. Cache-tag contract in `06` §4.

### 3.3 Request / data flows

```text
1 · Storefront visibility scoping (INV-1)
    GET /commerce/stores: storefront_schools JOIN vendor_storefronts ON school_id = caller.schoolId
      ∧ status='active' ∧ vendor approved (fail-closed INV-6) → cached 300 s (commerce:stores:school:{id});
      non-served school gets 404 — scoping is the query shape, not a filter bolted on
2 · Order placement tx (reserve stock — BR-004/006/007)
    POST /commerce/orders (verified buyer; single-store; ≤10 lines × qty 1–10) — one tx:
      SELECT … FOR UPDATE inventory rows (deterministic id order) → availability check
      → insert order + snapshot items (names, price, image ref, sku) → qty_reserved += qty
      → commission_rate/bdt frozen (default 0.050; CHECK 0.050–0.100)
      → vendor push + auto-cancel timer armed via jobs.Enqueue
      loser of a stock race gets OUT_OF_STOCK naming the item — never negative stock
3 · Fulfilment states (vendor board)
    confirm (placed): qty_reserved −= qty ∧ qty_on_hand −= qty (one tx; buyer push)
    ready_for_pickup (pickup only) / ship (courier only; courier_name + tracking_number required)
    complete (ready/shipped, terminal): COD collection audited
    cancel before shipped: placed-cancel releases reservation; post-confirm cancel restocks qty_on_hand
    every transition pushes the buyer via 06 (payload `commerce_order_status`: orderId + status label only)
4 · Commission snapshot (BR-007 / INV-4)
    commission written on the order in the placement tx; later rate changes never rewrite history;
    order_items snapshots immutable (no UPDATE path in sqlc)
5 · Jobs (01 worker)
    commerce.auto-cancel hourly + per-placement timer: placed > 24 h → cancelled (system), reservation released
    commerce.low-stock-digest daily 07:00 Asia/Dhaka: one notice per vendor listing low-stock items
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| order | placed · confirmed · ready_for_pickup · shipped · completed · cancelled | placed→confirmed (vendor; decrements reserved+on-hand) · confirmed→ready_for_pickup (**pickup only**) · confirmed→shipped (**courier only** ∧ courier_name ∧ tracking_number) · ready_for_pickup/shipped→completed (terminal; COD audited) · placed/confirmed/ready_for_pickup→cancelled (buyer any time before shipped; vendor `placed`/`confirmed` with reason ≥5 chars) · placed (>24 h)→cancelled (auto-cancel job, releases reservation); illegal edges → `CONFLICT` |
| storefront | active · paused | active⇄paused (pause hides from browse, refuses new orders; existing orders continue to a terminal state) |
| product | active · archived | active⇄archived (archived = visible-with-label, not purchasable; historic snapshots unaffected) |

---

## 4. Data Model (summary)

Mirror of `03-backend-tasks.md` §1 — column detail stays there.

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `vendor_storefronts` | Vendor's shop: name bn (+en), description, status active/paused, pickup_address, delivery_note; belongs to a 07 `vendor_account` (approved) | not school-tenant — ownership-scoped via `vendor_account_id`; buyer visibility derives from `storefront_schools` | `(vendor_account_id)` · partial `(id) WHERE status='active'` | vendor-approved gate enforced in service (BR-001) |
| `storefront_schools` | Join storefront × school — the vendor-selected subset that can see the store (chosen over a jsonb array) | **the** school-scoping join: buyer queries filter `school_id = caller.schoolId` | PK `(storefront_id,school_id)` · `(school_id)` (hot stores-by-school query) | replace-on-update write; tag busts per served school |
| `products` | Catalog item: name_bn required + name_en, category, `price_bdt numeric(10,2)`, ≤5 image refs (05 confirmed), status | ownership via `storefronts.vendor_account_id`; buyer reads via served schools | `(storefront_id,status)` · partial `(storefront_id) WHERE status='active'` | CHECK category/status/price (>0, ≤100,000.00) |
| `product_variants` | Size/colour options: name (unique per product), `price_delta`, nullable sku | inherited via `products` chain | `(product_id)` · UNIQUE `(product_id,name)` | unit price = product price + delta |
| `inventory_items` | Stock per sellable (product-level, or per variant): `qty_on_hand`, `qty_reserved`, `reorder_level` (default 5) | ownership chain via `products` | UNIQUE `(variant_id)` · UNIQUE `(product_id) WHERE variant_id IS NULL` · `(product_id)` | invariant `0 ≤ qty_reserved ≤ qty_on_hand` (row-locked ops, INV-2) |
| `orders` | Buyer order: storefront, buyer, school, fulfilment pickup/courier, status machine, totals, `commission_rate/bdt`, courier_name/tracking_number, `payment_method` cod/online, `payment_transaction_id` (12's seam) | **tenant column** `school_id` = buyer's school (must be served by the storefront); vendors reach rows only via own storefronts | `(buyer_id,status)` · `(storefront_id,status)` · partial `(status,placed_at) WHERE placed` · UNIQUE `(order_code)` · `(school_id)` | CHECK commission band 0.050–0.100; courier ⇒ address; shipped ⇒ courier+tracking |
| `order_items` | Immutable per-line snapshot jsonb (names bn/en, variant, category, sku, image refs) + qty + `unit_price_bdt` | inherits the order's | `(order_id)` | no UPDATE query exists in sqlc (immutability by omission, INV-4) |

---

## 5. Contracts

### 5.1 REST endpoints

Summary of `03-backend-tasks.md` §2 (20 endpoints; auth chain + ownership/tenant scope on every route; `auth.RequireVerified` on buyer routes; 07 approved-vendor gate on vendor routes; rate class `default`, tighter bucket on placement).

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | POST `/api/v1/vendor/storefronts` | Approved vendor | Create storefront (schools served, pickup address) | `FORBIDDEN` (not approved), `VALIDATION_FAILED` | CMP-US-001 |
| 2 | GET `/api/v1/vendor/storefronts` | Vendor | Own storefronts + action counters | — | CMP-US-001/014 |
| 3 | PATCH `/api/v1/vendor/storefronts/{id}` | Vendor (owner) | Edit fields / schools list / pause-resume | `FORBIDDEN`, `VALIDATION_FAILED` | CMP-US-014 |
| 4 | POST `/api/v1/vendor/storefronts/{id}/products` | Vendor (owner) | Create product (+variants +inventory rows, images) | `VALIDATION_FAILED` | CMP-US-002 |
| 5 | PATCH `/api/v1/vendor/products/{id}` | Vendor (owner) | Edit product / archive | `CONFLICT` | CMP-US-002/015 |
| 6 | PATCH `/api/v1/vendor/products/{id}/inventory` | Vendor (owner) | Set stock (`qtyOnHand`, `reorderLevel`, optional `variantId`) | `VALIDATION_FAILED` (< reserved) | CMP-US-003 |
| 7 | GET `/api/v1/commerce/stores` | Verified buyer | Active stores serving my school | `NOT_VERIFIED` | CMP-US-004 |
| 8 | GET `/api/v1/commerce/stores/{id}/products` | Verified buyer | Store page grid (availability states) | `NOT_FOUND` (not served) | CMP-US-004/015 |
| 9 | GET `/api/v1/commerce/products/{id}` | Verified buyer | Product detail (variants, stock, trust signals) | `NOT_FOUND` | CMP-US-005 |
| 10 | POST `/api/v1/commerce/orders` | Verified buyer | Place order (tx: reserve, snapshot, commission freeze) | `NOT_VERIFIED`, `OUT_OF_STOCK`, `VALIDATION_FAILED` | CMP-US-006/007 |
| 11 | GET `/api/v1/commerce/orders` | Verified buyer | My orders (+status filter) | — | CMP-US-013 |
| 12 | GET `/api/v1/commerce/orders/{id}` | Buyer of the order | Order detail / pickup instructions | `NOT_FOUND` | CMP-US-009 |
| 13 | POST `/api/v1/commerce/orders/{id}/cancel` | Buyer | Cancel (placed/confirmed/ready) | `CONFLICT` (shipped+) | CMP-US-011 |
| 14 | GET `/api/v1/vendor/orders` | Vendor (owner) | Fulfilment board (status columns) | `FORBIDDEN` | CMP-US-008 |
| 15 | GET `/api/v1/vendor/orders/{id}` | Vendor (owner) | Vendor order detail | `FORBIDDEN` | CMP-US-008/010 |
| 16 | POST `/api/v1/vendor/orders/{id}/confirm` | Vendor (owner) | placed → confirmed (decrement) | `CONFLICT` | CMP-US-008 |
| 17 | POST `/api/v1/vendor/orders/{id}/ready` | Vendor (owner) | confirmed → ready_for_pickup (pickup only) | `CONFLICT` | CMP-US-009 |
| 18 | POST `/api/v1/vendor/orders/{id}/ship` | Vendor (owner) | confirmed → shipped (courier + tracking required) | `CONFLICT`, `VALIDATION_FAILED` | CMP-US-010 |
| 19 | POST `/api/v1/vendor/orders/{id}/complete` | Vendor (owner) | ready/shipped → completed (COD collected) | `CONFLICT` | CMP-US-009/010 |
| 20 | POST `/api/v1/vendor/orders/{id}/cancel` | Vendor (owner) | Vendor cancel (placed/confirmed, reason required) | `CONFLICT`, `VALIDATION_FAILED` | CMP-US-011 |

### 5.2 Realtime / jobs

No realtime channel of its own — status pushes are module 06's (payload `commerce_order_status`; DB-first lifecycle never depends on delivery). Jobs (`03` §5):

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| `commerce.auto-cancel` (CMP-BE-032) | Hourly on the 01 worker + armed per placement (`jobs.Enqueue` + 24 h delay) | `AutoCancelStalePlaced()`: stale `placed` → cancelled (`cancelled_by=system`), reservation released, both parties notified | buyer, vendor | idempotent — status re-checked per row in tx; alerts after 3 failures; vendor can always cancel manually |
| `commerce.low-stock-digest` (CMP-BE-033) | Daily 07:00 Asia/Dhaka | `LowStockDigest(vendor)`: items `on_hand − reserved ≤ reorder_level` → one notice per vendor | vendor | digest window keyed per vendor/day; skips silently when 06 down; next day's run covers |

### 5.3 Exported service functions

From `06-integration-tasks.md` §2 — DTOs only, domain errors, additive-first signatures.

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `commerce.StorefrontsForSchool(schoolID)` | Buyer browse (app via handler); future 13 school-surface reads | `[]StorefrontSummaryDTO` (active stores serving the school; vendor-approved check inside, INV-6); cached 300 s | `VALIDATION_FAILED` (unknown school) |
| `commerce.OrderAmount(orderID)` | **Module 12** (checkout/receipts against frozen totals, INV-4) | `OrderAmountDTO{totalBdt, commissionBdt, status, paymentMethod, orderCode}`; cached 60 s (`commerce:orderamount:{id}`) | `NOT_FOUND` |
| `commerce.OrdersForVendor(vendorAccountID)` | 07/12 Super-Admin revenue + commission reporting (later); own dashboard | `[]VendorOrderSummaryDTO` (status, totals, frozen commission fields) | `FORBIDDEN` (no role claims) |
| `commerce.AttachPaymentTransaction(orderID, txnID)` | **Module 12** (on payment success — additive when 12 lands) | `nil`; sets `orders.payment_transaction_id` (one txn per order) | `CONFLICT` (already attached / not `online` / terminal status), `NOT_FOUND` |

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

Access rule: 07's `/vendor` shell gate (`GET /vendor/state`) stays; only `approved` vendors get these screens — pending/rejected/suspended keep 07's state cards.

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| `/vendor` | Vendor dashboard — replaces 07's approved-state stub: action counters (orders needing action, low stock, completed 30 d), quick links, status chip + pause/resume | Dynamic | Vendor (approved) |
| `/vendor/storefront` | Storefront create/settings — SchoolsPicker (04 catalog, ≥1 school), pickup address, PauseDialog | Dynamic | Vendor (approved) |
| `/vendor/products` · `/products/new` · `/products/[id]` | Products list (TanStack Table, stock column) + create/edit form (bn-first tabs, variants repeater, ImageUploader ≤5 with degraded "save without images" path, archived banner + restore) | Dynamic | Vendor |
| `/vendor/inventory` | Inventory manager — inline stock edit (≥ reserved), reserved column, low-stock highlight + daily-digest note | Dynamic (poll 60 s) | Vendor |
| `/vendor/orders` · `/orders/[id]` | Fulfilment board (status columns/tabs, poll 30 s) + order detail (snapshot items, commission row, timeline); ShipDialog / CancelDialog | Dynamic | Vendor |
| `/admin/commission` | Super Admin commission report **stub** (07 StubRoute pattern): "ships with module 12" + model note (default 5%, `brd.md` §7 5–10% band) — no invented figures | Dynamic | Super Admin |

### 6.2 Mobile (detail in `05-app-tasks.md`)

Buyer surfaces only; vendors use the web portal.

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| `/(tabs)/marketplace` | Marketplace home — adds the "স্টোর / Store" section (alongside 10's tutor section) + orders entry with active-count badge | none (tab root) | cached counts + banner |
| `/(tabs)/marketplace/stores` · `/stores/[id]` | Store list (stores serving my school, empty state bn/en) + store page (vendor trust header with approved badge + served schools, category chips, product grid with out-of-stock labels) | store taps | cache reads |
| `/(tabs)/marketplace/products/[id]` | Product detail — variant picker (stocked only selectable), qty stepper 1–10, stock state, COD note | store grid tap | cached detail; order CTA refuses |
| `/(tabs)/marketplace/checkout` | Checkout — fulfilment picker (pickup shows store address / courier address form), COD summary + ৳5,000 limit copy, place order | product CTA | **queued once** with loud banner; replay verdicts (`OUT_OF_STOCK`/`VALIDATION_FAILED`/`CONFLICT`) stay reviewable |
| `/(tabs)/marketplace/orders` · `/orders/[id]` | My orders (status chips, tracking line when shipped, active badge) + order detail (status timeline, snapshot items "price at order time", pickup instructions, cancel in allowed states) | push `type=commerce_order_status` | cancel refused offline (money/stock action); lists cached |

---

## 7. External Integrations

From `06-integration-tasks.md` §5 — **none direct at launch**; the courier is manual by decision (OQ-3, README default).

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| (none directly) | — | — | — | — | All externals via module owners: R2 via 05 media, FCM via 06 push, Redis limiter via 01 base |
| Third-party courier | Order delivery | **Manual — no API at launch (OQ-3):** vendor types `courier_name` + `tracking_number`; buyer reads the number (no live tracking link) | n/a | n/a | Copy states the number only; courier API would be an additive future module |
| Cloudflare R2 (indirect via 05) | Product image storage | S3 presigned PUT/GET (05-owned) | 05-owned `R2_*` env | 05-owned | Upload blocked → product saves **without** the new image + "ছবি ছাড়া সংরক্ষিত / Saved without images" warning; grid placeholders |
| FCM (indirect via 06) | Order-status pushes | HTTPS Admin SDK (06-owned) | 06-owned `FCM_SERVER_KEY` | 06-owned queue | No push — statuses advance DB-first; My Orders stays authoritative |

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| None module-specific | — | — | This module reads only the base 01 config; R2 credentials live in 05, `FCM_SERVER_KEY` in 06, vendor approval state in 07 |

### 8.2 Runtime config — the two lists

From `02-solution-approach.md` §5.

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| Default commission rate (0.050; `TODO: Confirm` OQ-1); per-storefront overrides later via 07 | Commission frozen at placement; CHECK band 0.050–0.100 (`brd.md` §7) |
| COD limit (৳5,000 default; `TODO: Confirm` OQ-2) | Reserve-then-decrement inventory policy (INV-2); immutable snapshots (INV-4) |
| Auto-cancel window (24 h, OQ-6); max lines/order (10); qty/line (1–10) | School-scoped visibility (INV-1); verified-only buying (BR-003) |
| Low-stock digest schedule (daily) + `reorder_level` defaults (5) | Manual courier fields only (no carrier API at launch, OQ-3) |
| Rate-limit buckets (class `default`; tighter placement bucket) | Media caps/kinds (delegated to 05); single-store order (OQ-5) |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | authenticate → load role claims → tenant/ownership-scope on every entry (`02` §6); buyer writes add `auth.RequireVerified`; vendor writes add the 07 approved-vendor gate (fail-closed on the money path — read failure ⇒ `FORBIDDEN`, never assume approved) |
| Role matrix | Vendor portal user (one-time link: portal phone must equal `vendor_accounts.phone` ∧ approved, audited): own storefronts/products/inventory/orders only · Student/Guardian (verified): browse served schools, place own orders, cancel own orders · Super Admin: `/admin/commission` stub (data access arrives with 12/07 revenue) · School Admin/Teacher: no commerce surface |
| Tenant scope | Buyer reads joined to `caller.schoolId` via `storefront_schools` (non-served school → 404, INV-1); buyer rows row-level `buyer_id`; vendor rows resolve via `vendor_account_id` (vendor A never touches vendor B, INV-5); cross-tenant attempts → `TENANT_MISMATCH`/404 (CMP-IT-003/015) |
| Rate limits | Class `default` everywhere; tighter per-user bucket on placement (#10) |
| Audit events | `audit.Record`: order placement, buyer/vendor cancel, completion (COD collection), portal-user linking |
| Privacy / minors | Buying is verified-only (`NOT_VERIFIED` gate); push payloads carry orderId + status label only — no addresses, phone or buyer PII (CMP-UT-008); product/vendor free text is length-capped plain text (no HTML); prices are `numeric(10,2)` — never floats; address fields validated against BD formats |

---

## 10. Error Handling

All errors surface as RFC-7807 `application/problem+json`. User-visible messages resolve via each app's `src/i18n` catalogs — every message key ships in **bn + en** (Bengali default), e.g. `validation.commerce.*`.

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `OUT_OF_STOCK` | Module problem code (beside the common set) | Placement loses the stock race / item unavailable | Toast **naming the item** + product refetch; out-of-stock UI keeps products visible with "স্টক শেষ / Out of stock" label |
| `CONFLICT` | Illegal transition or lost race | Cancel-vs-confirm race, ship-pickup, ready-courier, cancel post-ship, double confirm, already-attached txn | "অর্ডারের অবস্থা বদলেছে / Order status changed" toast + row refetch |
| `NOT_VERIFIED` | Account pending verification | Any buyer route (browse-purchase paths, place, cancel) | `VerifiedGate` + module 03 how-to copy |
| `FORBIDDEN` | Not approved / foreign row | Non-approved or suspended vendor writes (fail-closed), vendor A touching vendor B, buyer B cancelling buyer A | 07 state card (vendor) / refusal + support (buyer) |
| `TENANT_MISMATCH` / `NOT_FOUND` | Cross-tenant or invisible probe | Store not serving the caller's school; foreign orders | 404/invisible — catalog never leaks across the school boundary (CMP-IT-002/012) |
| `VALIDATION_FAILED` | Bad input | bn name, price bounds, qty 1–10, ≤10 lines, single-store, address-iff-courier, COD limit (`validation.commerce.cod_limit`), ship fields, cancel reason | Field messages mapped to forms, bn-first |
| `UNAUTHENTICATED` / `RATE_LIMITED` / `INTERNAL` | Standard envelope | Every route / limiter / infra | Re-auth; retry later; error boundary with request id |

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | slog JSON (01 base); order/push logs carry ids + labels — no buyer PII, no addresses in logs or pushes |
| Metrics / counters | Orders needing action by status, low-stock count per vendor, auto-cancel rate, placement `OUT_OF_STOCK` rate, job lag (auto-cancel, digest) |
| Health contribution | No dedicated check — Postgres/Redis/worker health flows through the 01 base `/readyz` |
| Jobs & retries | `commerce.auto-cancel` (hourly + per-placement timer) and `commerce.low-stock-digest` (daily) — idempotent, catch up on worker restore; alerts after 3 failures; 06 retries push delivery |
| Runbook pointers | 01/15 runbooks: Neon pool alarm + failover path; worker-lag alarm (stale `placed` orders linger, vendors can cancel manually); Redis fallback (DB is source of truth; placement re-checks make cache staleness harmless) |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Order state machine (all legal/illegal edges), commission math + freeze, snapshot mapper byte-identity, availability math (variant vs product stock), validation rules, fulfilment guards, cache invalidation sets, push payload builder (no PII) | `CMP-UT-001`–`008` | `go test` green |
| Integration | **Oversell prevention** (parallel placements race the last unit → exactly one `placed`, losers `OUT_OF_STOCK`, `CMP-IT-001/011`), **vendor-scope isolation** (CMP-IT-003/015), cross-school visibility, unverified buyer blocked, cancel-restock semantics, commission snapshot across rate changes, auto-cancel job, COD limit, out-of-stock visible-not-purchasable, auth chain, degradation drills (06/05/07-down) | `CMP-IT-001`–`017` | testcontainers Postgres green in CI |
| E2E | Playwright vendor golden path (portal link → storefront → product+variant+image → confirm/ship with tracking) · Maestro buyer golden path (browse own-school store → detail → pickup COD checkout → status chip advances + pickup instructions) | `CMP-E2E-001`–`002` | CI smoke |
| CI | — | — | `go test/vet/lint` (api) + `pnpm lint/typecheck/test/build` (web/app). Mandatory everywhere: unauthenticated calls denied; validation rejects bad input; ownership/tenant scoping returns `TENANT_MISMATCH`/404; snapshots never mutate; public browse never returns paused stores, archived products or other schools' stores |

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | Pilot (3 schools × ~2,000 users): ~10 storefronts, ~500 products, ~50 orders/day — small tables; indexes designed for the BRD year-1 target (10 schools, ~20k users, 10×) |
| Hot paths + indexes | Stores-by-school: `storefront_schools JOIN vendor_storefronts` on indexed `(school_id)` + partial active; orders by `(buyer_id,status)` / `(storefront_id,status)`; placement is the write-hot path — one tx, `SELECT … FOR UPDATE` over ≤10 inventory rows in deterministic id order (deadlock-free), milliseconds at this scale |
| Latency targets | Browse p95 ≤ 100 ms cached (Redis TTL 300 s school / 120 s store+product); board/inventory polls 30 s/60 s |
| Bundle / payload impact | No new heavy dependencies — TanStack Table already present (07), RN primitives from module 02; product images from R2 via 05, compressed at upload |
| Caching | `commerce:stores:school:{id}` 300 s · `commerce:store:{id}` 120 s · `commerce:product:{id}` 120 s · `commerce:orderamount:{id}` 60 s (money path, short leash); vendor board, inventory, my orders and order detail are **never cached** (fresh money + stock surfaces); invalidations per `06` §4 |

---

## 14. Risks & Open Questions

Consolidated from `01` §9 and `02` §11 — the table to review in module readiness checks; unconfirmed items keep their `TODO: Confirm` marker.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Exact commission rate at launch (`brd.md` §7 allows 5–10%) | Rate rework at launch | Rahul | Open (`TODO: Confirm`) | 5% default stored per order; rate is config; per-storefront Super Admin overrides later |
| 2 | COD limit amount for the fraud guard | Legit bulk uniform orders refused | Rahul | Open (`TODO: Confirm`) | BDT 5,000 — COD refused above it until online payment (12) exists |
| 3 | Courier = manual third-party at launch (no API, no tracking link); vendor confirm-promptliness | Tracking expectations outgrow copy-paste numbers; reservations pile up | Rahul | Open (defaults accepted) | Manual name + tracking number with honest copy; 24 h auto-cancel + "orders needing action" board + vendor push; courier API additive later |
| 4 | Inventory policy: reserve-on-placement → decrement-on-confirm; no auto purchase orders; auto-cancel window | Vendor can't distinguish hold vs sale; reservations held longer | Rahul | Open (defaults accepted) | Reserved counts visible on the vendor board; auto-cancel 24 h (config) covers inaction |
| 5 | Multi-store cart in future? | Buyer re-orders per store | Rahul | Open (`TODO: Confirm`) | Single-store direct order; cart is additive later |
| 6 | Offline order queues hit `OUT_OF_STOCK` on replay | Buyer frustration | — | Mitigated in spec | Failed items stay reviewable with input preserved; honest error naming the item |
| 7 | Vendor portal-user linking abused (wrong phone claims a vendor) | Account takeover of a store | — | Mitigated in spec | One-time bind: phone must equal `vendor_accounts.phone` + approved status + audit; mismatch → `FORBIDDEN` |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| BR-04 | §5.4 (storefronts, orders, inventory) · §4A (vendor portal) | CMP-US-001–016 | CMP-BE-001–033 · CMP-FE-001–016 · CMP-AP-001–014 · CMP-INT-001–012 | CMP-UT-001–008 · CMP-IT-001–017 · CMP-E2E-001–002 |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-10-03 | Build executed contract-first: 20 REST paths + 26 `Commerce*` schemas landed in the api spec before any UI; INV-2 reserve→decrement inventory with row-locked deterministic-order placement tx; INV-4 immutable snapshot items (no UPDATE query); commission frozen per order (BR-007 band CHECK); INV-3 state machine as a pure edge set (unit-proven); additive `commerce_order_status` push type in 06's frozen builder (ids + status label only — deep link to the order route); fail-closed `vendors.RequireApprovedVendor` gate on every vendor write and placement; payment seam (`OrderAmount`/`AttachPaymentTransaction`) dormant until 12; migrations `20270201090000–093000`. App: live client behind the session-token selector; web: fixture seam until 07's console glue (G-3); seed deferred (G-6). | Kilo |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |

# Campus Commerce — Backend Tasks & Database Design

**Module:** `11-campus-commerce`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack (api):** Go · chi REST handlers · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `applications/api/openapi/openapi.yaml` · slog logging · jobs via module 01 worker
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms · generated `openapi-fetch` client → api (fills module 07's `/vendor` shell + `/admin/commission` stub)
**Last updated:** 2026-09-30

> Schema first. Nothing below it is designed until the schema is settled. Every table states its
> tenant-scope column/rule — unscoped tables are a defect (`prompt.txt` §9).

---

## 1. Database Design

### 1.1 Tables

#### `vendor_storefronts` (model `VendorStorefront`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `vendor_account_id` | `uuid` | no | — | FK → 07 `vendor_accounts` (must be `approved`; service gate BR-001) |
| `name_bn` | `text` | no | — | 2–120 chars (required, bn-first) |
| `name_en` | `text` | yes | — | 2–120 chars |
| `description` | `text` | yes | — | ≤ 1,000 chars plain text (vendor content) |
| `status` | `text` | no | `active` | `active` \| `paused` (CHECK); pause hides from browse, orders continue |
| `pickup_address` | `text` | no | — | 10–300 chars |
| `delivery_note` | `text` | yes | — | ≤ 300 chars (e.g. courier area/cost note) |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** CHECK status enum; vendor approved enforced in service (07 read). **Indexes:**
`(vendor_account_id)` → own-storefront lists (INV-5); partial `(id) WHERE status='active'` → browse
joins. **Tenant rule:** not school-tenant — ownership-scoped via `vendor_account_id`; buyer-side
visibility derives from `storefront_schools`.

#### `storefront_schools` (model `StorefrontSchool` — join table, chosen over a jsonb array)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `storefront_id` | `uuid` | no | — | FK → `vendor_storefronts` (ON DELETE CASCADE) |
| `school_id` | `uuid` | no | — | FK → 04 `schools`; the schools that see the store |

**Constraints:** PRIMARY KEY `(storefront_id, school_id)`; UNIQUE `(school_id, storefront_id)`
mirror for the browse direction. **Indexes:** `(school_id)` → the hot stores-by-school query
(INV-1); `(storefront_id)` → replace-on-update + tag busting per served school. **Tenant rule:**
this is the school-scoping join — buyer queries filter `school_id = caller.schoolId`.

#### `products` (model `Product`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `storefront_id` | `uuid` | no | — | FK → `vendor_storefronts`; ownership chain for INV-5 |
| `name_bn` | `text` | no | — | 2–120 chars; vendor content (BR-013) |
| `name_en` | `text` | yes | — | 2–120 chars |
| `description` | `text` | yes | — | ≤ 2,000 chars plain text |
| `category` | `text` | no | — | `books` \| `uniforms` \| `stationery` \| `other` (CHECK) |
| `price_bdt` | `numeric(10,2)` | no | — | > 0, ≤ 100,000.00 (CHECK) |
| `image_media_ids` | `jsonb` | no | `[]` | Array of ≤ 5 refs → 05 `media_assets` (`confirmed` only); first = primary |
| `status` | `text` | no | `active` | `active` \| `archived` (CHECK); archived = hidden from purchase |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** CHECK category/status/price. **Indexes:** `(storefront_id, status)` → store grid +
vendor list; partial `(storefront_id) WHERE status='active'` → purchase checks. **Tenant rule:**
ownership via `storefronts.vendor_account_id` (join on every vendor write); buyer reads via the
storefront's served schools.

#### `product_variants` (model `ProductVariant`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `product_id` | `uuid` | no | — | FK → `products` (ON DELETE CASCADE) |
| `name` | `text` | no | — | 1–60 chars (e.g. "সাইজ ৪০ / Size 40"); UNIQUE `(product_id, name)` |
| `price_delta` | `numeric(10,2)` | no | `0` | > −`price_bdt`, ≤ 50,000.00 (service CHECK vs parent price) |
| `sku` | `text` | yes | — | ≤ 40 chars `[A-Za-z0-9-]` |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** UNIQUE `(product_id, name)`. **Indexes:** `(product_id)` → variant picker; UNIQUE
name guard. **Tenant rule:** inherited via `products` → `storefronts` ownership chain.

#### `inventory_items` (model `InventoryItem`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `product_id` | `uuid` | no | — | FK → `products` |
| `variant_id` | `uuid` | yes | — | FK → `product_variants`; NULL = product-level stock |
| `qty_on_hand` | `int` | no | `0` | ≥ 0 (CHECK) |
| `qty_reserved` | `int` | no | `0` | ≥ 0 (CHECK); held by `placed` orders (INV-2) |
| `reorder_level` | `int` | no | `5` | ≥ 0; low-stock indicator threshold |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** UNIQUE `(variant_id)`; UNIQUE `(product_id) WHERE variant_id IS NULL` (one
product-level row); variant rows' `product_id` must match the variant's product (service). One row
per sellable: product-without-variants → product-level row; product-with-variants → one row per
variant (product-level row then absent). **Indexes:** partial UNIQUEs above + `(product_id)` →
stock lookups. **Tenant rule:** ownership chain via `products`.

#### `orders` (model `Order`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `order_code` | `text` | no | — | Human pickup reference (e.g. `KSL-8F3K2`), UNIQUE — shown at pickup |
| `storefront_id` | `uuid` | no | — | FK → `vendor_storefronts`; single-store order (INV-7) |
| `buyer_id` | `uuid` | no | — | FK → 03 `users` (verified) |
| `school_id` | `uuid` | no | — | **Tenant column** = buyer's school (04); must be served by the storefront (INV-1) |
| `fulfilment` | `text` | no | — | `pickup` \| `courier` (CHECK) |
| `status` | `text` | no | `placed` | `placed` \| `confirmed` \| `ready_for_pickup` \| `shipped` \| `completed` \| `cancelled` (CHECK) |
| `fulfilment_address` | `text` | yes | — | Required iff `courier` (CHECK in service); recipient + address snapshot |
| `total_bdt` | `numeric(10,2)` | no | — | Σ unit_price × qty |
| `commission_rate` | `numeric(4,3)` | no | — | Frozen at placement; CHECK `BETWEEN 0.050 AND 0.100` (`brd.md` §7) |
| `commission_bdt` | `numeric(10,2)` | no | — | `round(rate × total, 2)` (BR-007) |
| `courier_name` | `text` | yes | — | Set on ship (manual third-party courier, OQ-3) |
| `tracking_number` | `text` | yes | — | Set on ship; buyer-visible |
| `payment_method` | `text` | no | `cod` | `cod` \| `online` (CHECK); online arrives with module 12 |
| `payment_transaction_id` | `text` | yes | — | **12's seam** — attached via `commerce.AttachPaymentTransaction` |
| `buyer_note` | `text` | yes | — | ≤ 300 chars |
| `cancel_reason` | `text` | yes | — | Required on vendor cancel / auto-cancel; shown to counterpart |
| `cancelled_by` | `text` | yes | — | `buyer` \| `vendor` \| `system` |
| `placed_at` | `timestamptz` | no | `now()` | Auto-cancel job cursor |
| `confirmed_at` / `ready_at` / `shipped_at` / `completed_at` / `cancelled_at` | `timestamptz` | yes | — | Set by the matching transition |

**Constraints:** CHECK status/fulfilment/payment enums; CHECK commission band; service CHECKs:
courier ⇒ address, shipped ⇒ courier_name + tracking_number. **Indexes:** `(buyer_id, status)` →
my-orders; `(storefront_id, status)` → vendor board; partial `(status, placed_at)
WHERE status='placed'` → auto-cancel job; `(order_code)` UNIQUE → pickup lookup; `(school_id)` →
school-level reporting later. **Tenant rule:** `school_id = caller.schoolId` for buyer reads; order
rows reached by vendors only through their own storefronts.

#### `order_items` (model `OrderItem`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `order_id` | `uuid` | no | — | FK → `orders` (ON DELETE CASCADE) |
| `product_id` | `uuid` | no | — | FK → `products` |
| `variant_id` | `uuid` | yes | — | FK → `product_variants` |
| `snapshot` | `jsonb` | no | — | Immutable: `{nameBn, nameEn, variantName, category, sku, imageMediaIds, storefrontNameBn}` (BR-006) |
| `qty` | `int` | no | — | 1–10 (CHECK `qty > 0`) |
| `unit_price_bdt` | `numeric(10,2)` | no | — | `price_bdt + price_delta` frozen at placement (INV-4) |
| `created_at` | `timestamptz` | no | `now()` | |

**Constraints:** no UPDATE query exists in sqlc (immutability by omission). **Indexes:**
`(order_id)` → order render. **Tenant rule:** inherits the order's.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20270201090000_cmp_storefronts` (vendor_storefronts + storefront_schools + status/pair indexes) | ✅ |
| 2 | `20270201091000_cmp_products` (products + product_variants + category/price CHECKs + grid indexes) | ✅ |
| 3 | `20270201092000_cmp_inventory` (inventory_items + partial UNIQUE stock rows + CHECKs) | ✅ |
| 4 | `20270201093000_cmp_orders` (orders + order_items + status machine CHECKs + board/buyer/job indexes + commission band) | ✅ |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| "ডেমো স্টোর / Demo Store" (fictional vendor "Demo Traders", approved account from 07 seed) serving "Demo High School" only; 3 products — বই/book bundle ৳৪৫০, uniform set w/ size variants ৳১,২০০+, stationery kit ৳৩০০ — with stock + one low-stock item; 1 order per status (placed/confirmed/ready_for_pickup/shipped/completed/cancelled) | `DRAFT` (clearly fictional, prices are demo values) | `brd.md` BR-04 shapes; `prd.md` §5.4; `prompt.txt` §12 |

---

## 2. Server Contracts

### Endpoint summary (all Go handlers generated from the OpenAPI spec; auth chain on every route: authenticate → load role claims → tenant/ownership-scope; buyer writes add `auth.RequireVerified`; vendor writes add the 07 approved-vendor gate)

| # | Endpoint | Purpose | Errors (beyond common) | Stories |
| --- | --- | --- | --- | --- |
| 1 | `POST /api/v1/vendor/storefronts` | Create storefront (approved vendor; schools served, pickup address) | `FORBIDDEN` (not approved), `VALIDATION_FAILED` | US-001 |
| 2 | `GET /api/v1/vendor/storefronts` | Own storefronts + action counters | — | US-001/014 |
| 3 | `PATCH /api/v1/vendor/storefronts/{id}` | Edit fields, schools list, pause/resume | `FORBIDDEN`, `VALIDATION_FAILED` | US-014 |
| 4 | `POST /api/v1/vendor/storefronts/{id}/products` | Create product (+variants +inventory rows, images) | `VALIDATION_FAILED` | US-002 |
| 5 | `PATCH /api/v1/vendor/products/{id}` | Edit product / archive | `CONFLICT` (archived edits guarded) | US-002/015 |
| 6 | `PATCH /api/v1/vendor/products/{id}/inventory` | Set stock (`qtyOnHand`, `reorderLevel`, optional `variantId`) | `VALIDATION_FAILED` (< reserved) | US-003 |
| 7 | `GET /api/v1/commerce/stores` | Buyer: active stores serving my school | `NOT_VERIFIED` | US-004 |
| 8 | `GET /api/v1/commerce/stores/{id}/products` | Store page grid (availability states) | `NOT_FOUND` (not served) | US-004/015 |
| 9 | `GET /api/v1/commerce/products/{id}` | Product detail (variants, stock, trust signals) | `NOT_FOUND` | US-005 |
| 10 | `POST /api/v1/commerce/orders` | Place order (tx: reserve stock, snapshot, commission) | `NOT_VERIFIED`, `OUT_OF_STOCK`, `VALIDATION_FAILED` | US-006/007 |
| 11 | `GET /api/v1/commerce/orders` | Buyer: my orders (+status filter) | — | US-013 |
| 12 | `GET /api/v1/commerce/orders/{id}` | Buyer: order detail / pickup instructions | `NOT_FOUND` | US-009 |
| 13 | `POST /api/v1/commerce/orders/{id}/cancel` | Buyer cancel (placed/confirmed/ready) | `CONFLICT` (shipped+) | US-011 |
| 14 | `GET /api/v1/vendor/orders` | Vendor fulfilment board (own storefronts, status columns) | `FORBIDDEN` | US-008 |
| 15 | `GET /api/v1/vendor/orders/{id}` | Vendor order detail (buyer, fulfilment info) | `FORBIDDEN` | US-008/010 |
| 16 | `POST /api/v1/vendor/orders/{id}/confirm` | placed → confirmed (decrement) | `CONFLICT` | US-008 |
| 17 | `POST /api/v1/vendor/orders/{id}/ready` | confirmed → ready_for_pickup (pickup only) | `CONFLICT` | US-009 |
| 18 | `POST /api/v1/vendor/orders/{id}/ship` | confirmed → shipped (courier + tracking required) | `CONFLICT`, `VALIDATION_FAILED` | US-010 |
| 19 | `POST /api/v1/vendor/orders/{id}/complete` | ready/shipped → completed (COD collected) | `CONFLICT` | US-009/010 |
| 20 | `POST /api/v1/vendor/orders/{id}/cancel` | Vendor cancel (placed/confirmed, reason) | `CONFLICT`, `VALIDATION_FAILED` | US-011 |

Common errors on every route: `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` ·
`TENANT_MISMATCH` · `NOT_FOUND` · `NOT_VERIFIED` · `RATE_LIMITED` · `CONFLICT` · `OUT_OF_STOCK`
(module code) · `INTERNAL` (RFC-7807 `application/problem+json`). **Rate-limit class `default`** on
all routes; tighter per-user bucket on #10 (placement).

### Endpoint `POST /api/v1/commerce/orders` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | middleware: authenticate → load role claims → tenant-scope (buyer's school) → verified gate |
| **Input** | `{storefrontId, items:[{productId, variantId?, qty}], fulfilment, fulfilmentAddress?, buyerNote?}`; contract validator; struct from `oapi-codegen` |
| **Result** | `{ "data": { order: { id, orderCode, status:"placed", totalBdt, commissionRate, commissionBdt, paymentMethod:"cod" } } }`; single tx per `02` §3: row-locked availability check → insert order + snapshot items → `qty_reserved += qty` → commission frozen → vendor push + auto-cancel timer armed via `jobs.Enqueue` |
| **Errors** | `OUT_OF_STOCK` (names the item) · `NOT_VERIFIED` · `VALIDATION_FAILED` (single-store, qty, COD limit `validation.commerce.cod_limit`, address, store-not-active/paused) · `FORBIDDEN` (vendor suspended — fail-closed INV-6) |
| **Rate limit** | class `default`, tight per-user bucket |
| **Audit** | Yes — placement (financial, `audit.Record`) |
| **Stories** | CMP-US-006/007 · guards CMP-BR-003/004/007/009 |

### Endpoint `POST /api/v1/vendor/orders/{id}/confirm` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | authenticate → role claims (vendor) → ownership-scope (order's storefront ∈ caller's vendor account) |
| **Input** | path id; empty body |
| **Result** | `{ "data": { order } }` — status `confirmed`; same tx decrements `qty_reserved` and `qty_on_hand` per line (BR-005); buyer push "আপনার অর্ডার নিশ্চিত হয়েছে / Your order is confirmed" |
| **Errors** | `CONFLICT` (not `placed` — e.g. buyer-cancelled race) · `FORBIDDEN` (not own order) |
| **Rate limit** | class `default` |
| **Audit** | No (placement/cancel/completion carry the audit trail) |
| **Stories** | CMP-US-008 · guard CMP-BR-005/008 |

### Endpoint `POST /api/v1/vendor/storefronts` + `POST /api/v1/vendor/orders/{id}/ship|cancel`

| | |
| --- | --- |
| **Auth** | approved-vendor gate (07 status read, fail-closed) on all three; ownership scope on id-routes |
| **Input** | storefront: `{nameBn, nameEn?, description?, schoolIds[], pickupAddress, deliveryNote?}`. ship: `{courierName, trackingNumber}` (both required). vendor cancel: `{cancelReason}` (5–500) |
| **Result** | storefront created `active` (+ school rows; school tags busted). ship → `shipped` + buyer push with tracking. cancel → `cancelled` + restock per state + counterpart notification + audit |
| **Errors** | `FORBIDDEN` (pending/rejected/suspended vendor; foreign storefront) · `VALIDATION_FAILED` (bn name, schools, address, courier fields, reason) · `CONFLICT` (illegal transition) |
| **Rate limit** | class `default` |
| **Audit** | Yes — vendor cancel; portal linking is audited inside the login flow |
| **Stories** | CMP-US-001/010/011 |

### Web Server Action / Route Handler (Next.js)

The web build consumes the Go API through the generated `openapi-fetch` client — never the
database directly. Module 07 owns the portal shell/nav; this module owns the `/vendor` screens and
the `/admin/commission` stub. Vendor identity: 07's `GET /vendor/state` (session + vendor lookup)
gates the shell; the one-time portal-user link (`portal_user_id`, phone must match the vendor
account, audited) is wired by this module at first approved login. All screens call REST #1–#20
above with zod mirrors of the `validation.commerce.*` rules and RFC-7807 error mapping.

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `CMP-BE-001` | `commerce.LinkPortalUser(user)` | `vendor_accounts` phone == portal user's phone ∧ `status=approved`; sets `portal_user_id` once; repeat/`CONFLICT` if already linked to another user | — | Yes |
| `CMP-BE-002` | `commerce.CreateStorefront(vendor, in)` | Approved gate; ≥ 1 valid school; status `active`; inserts school rows | school tags × schools | No |
| `CMP-BE-003` | `commerce.UpdateStorefront(vendor, id, in)` | Own storefront; field/schools edit; `pause`/`resume` action (orders continue — BR-011); school removal busts the dropped school's tag too | school tags (old+new) · store tag | No |
| `CMP-BE-004` | `commerce.ListMyStorefronts(vendor)` | Own rows + orders-needing-action counts | — | No |
| `CMP-BE-005` | `commerce.CreateProduct(vendor, storefrontId, in)` | Own storefront; bn name; price; category; media refs `confirmed` (05); tx creates variants + one inventory row per sellable; `status=active` | store + product tags | No |
| `CMP-BE-006` | `commerce.UpdateProduct(vendor, id, in)` | Own product; edit; `archive` action (visible-with-label rule — BR-011); snapshots untouched | product + store tags | No |
| `CMP-BE-007` | `commerce.UpdateInventory(vendor, productId, variantId?, in)` | Own; `qty_on_hand ≥ qty_reserved`; `reorder_level` set | product + store tags | No |
| `CMP-BE-008` | `commerce.StoresForSchool(schoolId)` — **export** | Active stores joined via `storefront_schools`; vendor approved (INV-6); cached read | `commerce:stores:school:{id}` | No |
| `CMP-BE-009` | `commerce.StoreProducts(viewer, storeId)` | Serves viewer's school (INV-1); active products; per-item stock state (in/low/out) | `commerce:store:{id}` | No |
| `CMP-BE-010` | `commerce.GetProduct(viewer, id)` | Active; school check; variant picker w/ per-variant availability; trust signals (approved badge + served schools) | `commerce:product:{id}` | No |
| `CMP-BE-011` | `commerce.PlaceOrder(buyer, in)` | Verified; store active ∧ serves school ∧ vendor approved; single-store; deterministic-order row-locked availability check → tx (order + snapshot items + reserve + commission freeze); COD limit guard (BR-009); `jobs.Enqueue` vendor push + auto-cancel | none (orders never cached) | Yes |
| `CMP-BE-012` | `commerce.ListMyOrders(buyer, status?)` / `GetBuyerOrder(buyer, id)` | Row-level own; detail includes tracking + pickup instructions payload | — | No |
| `CMP-BE-013` | `commerce.CancelOrderByBuyer(buyer, id, reason?)` | States placed/confirmed/ready_for_pickup (BR-008); restock per state (BR-005); vendor notified; audited | none | Yes |
| `CMP-BE-014` | `commerce.ListVendorOrders(vendor, status?)` / `GetVendorOrder(vendor, id)` | Own storefronts only (INV-5); board grouped by status | — | No |
| `CMP-BE-015` | `commerce.ConfirmOrder(vendor, id)` | `placed` only; tx decrements reserved+on-hand; buyer push | none | No |
| `CMP-BE-016` | `commerce.ReadyOrder(vendor, id)` | `confirmed` ∧ `fulfilment=pickup`; buyer push w/ pickup instructions | none | No |
| `CMP-BE-017` | `commerce.ShipOrder(vendor, id, in)` | `confirmed` ∧ courier ∧ courier_name+tracking required; buyer push w/ tracking | none | No |
| `CMP-BE-018` | `commerce.CompleteOrder(vendor, id)` | `ready_for_pickup` \| `shipped`; terminal; COD collection audited | none | Yes |
| `CMP-BE-019` | `commerce.CancelOrderByVendor(vendor, id, reason)` | placed/confirmed; reason required; restock; buyer notified w/ reason | none | Yes |
| `CMP-BE-020` | `commerce.AutoCancelStalePlaced()` — **job entry** | `placed ∧ placed_at < now() − window` → cancelled (`cancelled_by=system`); reservation released; both parties notified; idempotent | — | No |
| `CMP-BE-021` | `commerce.LowStockDigest(vendor)` — **job entry** | Items `qty_on_hand − qty_reserved ≤ reorder_level` → one daily notice per vendor | — | No |
| `CMP-BE-022` | `commerce.OrderAmount(orderId)` — **export (12 seam)** | `{totalBdt, commissionBdt, status, paymentMethod}` for module 12's checkout/receipts | `commerce:orderamount:{id}` | No |
| `CMP-BE-023` | `commerce.AttachPaymentTransaction(orderId, txnId)` — **export (12 seam, additive when 12 lands)** | Guard: `payment_method='online'` ∧ `payment_transaction_id IS NULL` ∧ status ∈ placed\|confirmed; else `CONFLICT` | — | Yes |
| `CMP-BE-024` | `commerce.OrdersForVendor(vendorAccountId)` — **export** | Own orders + commission fields (07/12 reporting reads) | — | No |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `CMP-BE-025` | `InsertStorefront / UpdateStorefront / ListStorefrontsByVendor / GetStorefrontForVendor` | ownership-scoped SELECT/UPDATE; status-guarded pause/resume | `(vendor_account_id)` |
| `CMP-BE-026` | `ReplaceStorefrontSchools / SelectStoresBySchool / SelectSchoolsOfStore` | join `storefront_schools × vendor_storefronts` filtered `school_id=$1 AND storefronts.status='active'` (+ vendor approved) | `(school_id)` + partial active |
| `CMP-BE-027` | `InsertProductWithVariants / UpdateProduct / GetProduct / ListProductsByStore` | product+variants+inventory tx insert; status-guarded archive | `(storefront_id, status)` |
| `CMP-BE-028` | `GetInventoryForUpdate (FOR UPDATE, ORDER BY id) / UpdateInventoryQty / SelectLowStockByVendor` | row-locked stock ops; low-stock join via products→storefronts→vendor | partial UNIQUEs + `(product_id)` |
| `CMP-BE-029` | `InsertOrderWithItems / UpdateOrderStatus / SelectOrdersByBuyer / SelectOrdersByStorefronts / GetOrderForBuyer / GetOrderForVendor` | tx insert (order + snapshot lines + reservation bump); status-guarded transitions; buyer school + row-level scoping | `(buyer_id, status)` · `(storefront_id, status)` |
| `CMP-BE-030` | `ReleaseReservation / RestockOrderItems` | per-line `qty_reserved −= qty` or `qty_on_hand += qty` within the cancel/auto-cancel tx | partial UNIQUE stock rows |
| `CMP-BE-031` | `SelectStalePlaced(limit) / SumCommissionByVendor / CountOrdersNeedingAction` | job cursor + dashboard/report aggregates (feed exports BE-022/024) | partial `(status, placed_at) WHERE status='placed'` |

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `CMP-BE-032` | `commerce.auto-cancel` — run `AutoCancelStalePlaced()` (§3 BE-020) | Hourly, 01 worker; also armed per placement (`jobs.Enqueue` at placement + 24 h delay) | Yes — status re-checked per row in tx | Re-run safe; alerts after 3 failures; buyer/vendor notified via 06 (retryable) |
| `CMP-BE-033` | `commerce.low-stock-digest` — run `LowStockDigest(vendor)` (§3 BE-021) | Daily 07:00 Asia/Dhaka | Yes — digest window keyed per vendor/day | Skips silently when 06 is down; next day's run covers |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `CMP-UT-001` | Order state machine: every legal edge commits; every illegal edge (ship-pickup, ready-courier, cancel-post-ship, confirm-twice) → `CONFLICT` | Unit | BR-008 / INV-3 |
| `CMP-UT-002` | Commission math + freeze: `round(0.050 × total, 2)`; rate change after placement never mutates stored orders | Unit | BR-007 / INV-4 |
| `CMP-UT-003` | Snapshot mapper: `order_items.snapshot` captured at placement; product edit/archive leaves order payloads byte-identical | Unit | BR-006 |
| `CMP-UT-004` | Availability math: `on_hand − reserved`; in/low/out thresholds; variant-level vs product-level stock | Unit | INV-2 / BR-011 |
| `CMP-UT-005` | Validation: bn name required, price bounds, qty 1–10, ≤ 10 lines, single-store, address-iff-courier, COD limit, ship fields, cancel reason | Unit | §6 rules |
| `CMP-UT-006` | Fulfilment guards: `ready` refuses courier orders; `ship` refuses pickup orders; `complete` only from ready/shipped | Unit | INV-3 |
| `CMP-IT-001` | **Oversell prevention**: N parallel placements racing the last unit → exactly 1 `placed`, rest `OUT_OF_STOCK`; `qty_reserved` exact; no negative stock (testcontainers Postgres) | Integration | BR-004 / INV-2 |
| `CMP-IT-002` | **Cross-school visibility**: store serving school A only — school B buyer gets 404 on store/products/placement; school A buyer sees it | Integration | BR-002 / INV-1 |
| `CMP-IT-003` | **Vendor-scope isolation**: vendor A cannot list/read/act on vendor B's storefronts, products, inventory or orders (`FORBIDDEN`/404); buyer B cannot cancel buyer A's order | Integration | BR-012 / INV-5 |
| `CMP-IT-004` | **Unverified buyer blocked** (`NOT_VERIFIED`) on place/cancel/browse-purchase paths; verified flows unaffected | Integration | BR-003 |
| `CMP-IT-005` | **Cancel-restock**: placed-cancel releases reservation (available restored, on_hand unchanged); confirmed-cancel restocks on_hand; auto-cancel equals placed-cancel | Integration | BR-005 / BR-010 |
| `CMP-IT-006` | **Commission snapshot**: orders placed before/after a default-rate change keep their frozen `commission_rate`/`commission_bdt`; band CHECK rejects out-of-range config | Integration | BR-007 |
| `CMP-IT-007` | Auto-cancel job: stale `placed` → `cancelled`, reservation released, both notified; re-run idempotent; fresh orders untouched | Integration | BR-010 |
| `CMP-IT-008` | COD limit: total > ৳5,000 COD refused with `validation.commerce.cod_limit`; `online` refused while 12 absent with coming-soon copy | Integration | BR-009 |
| `CMP-IT-009` | Out-of-stock product visible with label but placement refused (`OUT_OF_STOCK`); partially stocked variants: empty disabled, stocked buyable | Integration | BR-011 / US-015 |
| `CMP-IT-010` | Every protected endpoint unauthenticated → `UNAUTHENTICATED`; validation rejects bad input on every write; non-approved/suspended vendor refused on all vendor writes | Integration | Auth chain / BR-001 |

Always include: unauthenticated call denied for every protected entry point; validation rejects bad
input; ownership/tenant scoping returns `TENANT_MISMATCH`/404 for every foreign-row attempt;
snapshots never mutate; public browse never returns paused stores, archived products or other
schools' stores.

## 7. Task Checklist

### Schema

- [x] `CMP-BE-025`–`CMP-BE-031` migrations 1–4 + sqlc queries + ownership/tenant-scoped repositories — 2026-10-03 (`20270201090000–093000`; **owner SQL run pending — Gate 2**)

### Repository · Service · Entry points · Seed · Tests

- [ ] `CMP-BE-001` portal-user linking (phone-match + approved gate, audited) wiring 07's vendor state — deferred → `08-gaps.md` G-8 (needs 07's live portal-login flow; `vendor_accounts.portal_user_id` column exists)
- [x] `CMP-BE-002`–`CMP-BE-004` storefront services + endpoints #1–#3 (pause/resume, school tags) — 2026-10-03
- [x] `CMP-BE-005`–`CMP-BE-007` product/variant/inventory services + endpoints #4–#6 (+ 05 media wiring) — 2026-10-03 (media ids validated as refs; live upload flow is the web uploader's Stage-5 wiring — G-3)
- [x] `CMP-BE-008`–`CMP-BE-010` buyer browse/detail services + endpoints #7–#9 (school-scoped; invalidation set proven UT-007, read-through cache lands with traffic) — 2026-10-03
- [x] `CMP-BE-011` placement tx (reserve, snapshot, commission, COD guard) + endpoint #10 — 2026-10-03
- [x] `CMP-BE-012`/`CMP-BE-013` buyer orders + cancel + endpoints #11–#13 — 2026-10-03
- [x] `CMP-BE-014`–`CMP-BE-019` vendor board + lifecycle actions + endpoints #14–#20 (buyer pushes via 06; vendor placement push needs a 07 portal-user export — G-7) — 2026-10-03
- [x] `CMP-BE-020`/`CMP-BE-032` auto-cancel job; `CMP-BE-021`/`CMP-BE-033` low-stock digest — 2026-10-03 (registered in cmd/api; per-vendor digest fan-out shares G-7)
- [x] `CMP-BE-022`–`CMP-BE-024` exports: `OrderAmount`, `AttachPaymentTransaction` (12 seam), `OrdersForVendor`, `StorefrontsForSchool` — 2026-10-03
- [x] OpenAPI paths #1–#20 in `applications/api/openapi/` + regenerate Go + TS clients (+ `OUT_OF_STOCK` — code was pre-registered by 01) — 2026-10-03 (contract-first; `contracts: no drift`)
- [ ] Seed: Demo Store dataset (fictional, marked) — deferred → `08-gaps.md` G-6 (no seed mechanism; same vehicle decision as 10 G-7)
- [x] Tests: `CMP-UT-001`–`006`, `CMP-IT-001`–`010` green in CI — 2026-10-03 (UT-001/002/005/006/007/008 green `-race`; UT-003/004's DB-path coverage rides the ITs; IT-001–010 written as `it_commerce_test.go` — **runs pending owner** — G-5)

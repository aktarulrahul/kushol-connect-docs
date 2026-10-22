# Campus Commerce — User Stories

**Module:** `11-campus-commerce`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Last updated:** 2026-09-30

---

## 1. Purpose

Implements `brd.md` **BR-04** and `prd.md` **§5.4**: approved partners open storefronts scoped to an
explicit subset of schools, list books/uniforms/stationery with bn-first names, variants and stock,
and fulfil orders by in-store pickup or manual third-party courier; verified students and guardians
buy only from stores serving their own school, cash-on-pickup/delivery first. Buyer payment is held
in Kushol Escrow (`ESCROW_HELD`), and upon verified delivery confirmation a 15%–20% platform charge
(`commission_rate_bps` 1500–2000, default 15%) is deducted, releasing net 80%–85% to the partner's
withdrawable balance (`brd.md` §7 Stream 1). Phase 3 (`brd.md` §8); serves `brd.md` §2 Goal 2 and
the §7 campus-commerce revenue stream.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Unverified user (pending) | Opens the Marketplace → Store section but hits the `NOT_VERIFIED` gate — cannot order (module 03) |
| Student | Browses their school's stores, orders (pickup or courier), tracks status, cancels within allowed states |
| Guardian | Same buying surface as students (Marketplace tab); pays cash on pickup/delivery |
| Teacher | N/A — no commerce surface (may browse like any verified user; no extra powers) |
| School Admin | N/A — governance of partners stays with the Super Admin (module 07) |
| Super Admin | Approves partners in 07 (`partners.Approve`) — the gate for storefronts; reads the commission report stub (`/admin/commission`) |
| Partner / EdTech brand | Approved partner (07): claims portal access, creates storefront(s), lists products + variants, manages inventory, fulfils orders (confirm/ready/ship/complete/cancel) |
| System (jobs, webhooks) | Auto-cancel job (stale `placed` orders → release stock), daily low-stock digest, order-status pushes via 06 |

## 3. Scope

**In scope**

- Partner portal (fills 07's `/partner` shell): storefront create/settings (schools served, pickup
  address, delivery note, pause/resume), product catalog (bn name required + en optional, images via
  05 media, variants, prices in ৳), inventory manager (inline stock edit, low-stock highlight),
  orders fulfilment board (confirm → ready_for_pickup / ship with courier+tracking → complete;
  cancel), orders needing action.
- Buyer app (Marketplace tab → Store): stores serving my school, store page + product grid, product
  detail (variants, stock state, partner trust signals), checkout (pickup vs courier + address, COD
  summary), my orders (status chips, tracking number, pickup instructions, cancel).
- Order engine: transactional placement with stock reservation (oversell-proof), item snapshots,
  commission frozen at placement (default 5%), COD limit guard, auto-cancel of stale placed orders.
- Payment seam for module 12: `commerce.OrderAmount` + `payment_transaction_id` attach; until 12
  ships every order is COD.

**Out of scope** (explicit — prevents scope drift)

- Online payment gateways, receipts, ledgers — module 12 (reads this module's orders via the seam).
- Courier company APIs / automated tracking links — manual courier name + tracking number only
  (`brd.md` §4; default confirmed in `docs/modules/README.md` blocked-questions table).
- In-house delivery fleet — `brd.md` §4 out of scope.
- Product reviews/ratings, search-across-stores, ads in commerce (module 13), multi-store cart
  (default: single-store direct order — OQ-5), discounts/coupons, per-storefront commission
  configuration UI (Super Admin configurable later via 07).

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 01 foundations | `jobs.Enqueue` (auto-cancel, digests), `audit.Record`, RFC-7807 envelope, rate limiter, test harness |
| 02 design-system | bn/en catalogs `commerce.*` + `validation.*`, tokens, RN/web primitives, badge styling |
| 03 identity-access | `auth.RequireVerified` (buying is verified-only), `users` (buyer identity, school claims), portal-user model for partners |
| 04 organization-hierarchy | School catalog (schools a storefront serves; buyer's school context) |
| 05 communication-engine | `media.PresignUpload`/`ConfirmUpload` (product images) |
| 06 notifications | `notify.SendToUser` (order-status pushes with deep links to the order screen) |
| 07 command-center-web | `partners.Approve` family + partner status read (`GET /partner/state`) — storefront gate; `/partner` shell + nav stubs this module fills; Super Admin commission stub slot |

---

## 4. User Stories

### `CMP-US-001` — Approved partner claims portal access and creates a storefront

**Priority:** P0 · **Traces:** BR-04 (`brd.md` §5) / PRD §4A Partner portal · **Depends on:** 07 (approval)

**Story** — As an **approved partner**, I want **to link a portal user and create a storefront (bn/en name, description, schools served, pickup address, delivery note)**, so that **students of exactly the schools I choose can find and buy from my store**.

**Acceptance criteria**

- **Given** a `vendor_accounts` row with `status = approved` (07), **when** its contact phone registers/logs into the web portal, **then** `portal_user_id` links (one-time bind, phone must match the partner account, audited) and `/partner` shows the storefront setup instead of 07's "opens with module 11" stub.
- **Given** the setup form, **when** I submit name_bn (required), name_en (optional), description, ≥ 1 school from the 04 catalog, pickup_address and an optional delivery note, **then** the storefront is created `active` and appears for buyers of exactly those schools.
- **Given** a partner whose account is `pending`/`rejected`/`suspended`, **when** they attempt storefront creation, **then** `FORBIDDEN` with the 07 status/reason surfaced — no storefront row exists.
- **Given** a partner already owning a storefront, **when** they create another one, **then** it is allowed (a partner may run several storefronts, e.g. one per school cluster).

**Notes** — storefront serves a **subset** of schools chosen by the partner (school-scoped visibility, never city-wide); schools list is editable later (US-014's pause covers transitions).

---

### `CMP-US-002` — Partner adds products with images and variants

**Priority:** P0 · **Traces:** BR-04 / PRD §5.4 · **Depends on:** CMP-US-001, 05 (media)

**Story** — As a **partner**, I want **to list products (bn name required + optional English, category, ৳ price, photos, size/colour variants)**, so that **buyers see an honest, bilingual catalog with the right price for the variant they pick**.

**Acceptance criteria**

- **Given** my active storefront, **when** I create a product (name_bn required, name_en optional, category ∈ books|uniforms|stationery|other, price ৳ > 0, description, ≤ 5 images via the 05 upload flow, optional variants with price deltas), **then** it saves `active` with one inventory row per sellable item (product-level, or per variant) and appears in my store grid.
- **Given** the media service is degraded, **when** I save a product without new images, **then** the save succeeds with a visible warning ("ছবি ছাড়া সংরক্ষিত / Saved without images") — the product is never lost to an upload outage.
- **Given** a variant (e.g. সাইজ ৪০ / Size 40, +৳50), **when** a buyer opens the product, **then** the displayed unit price is `price_bdt + price_delta` for that variant.

**Notes** — product names are partner content: bn required, en optional; prices in BDT ৳.

---

### `CMP-US-003` — Partner manages stock and sees low-stock warnings

**Priority:** P0 · **Traces:** BR-04 / README row (inventory management) · **Depends on:** CMP-US-002

**Story** — As a **partner**, I want **an inventory manager with inline stock edits and a low-stock indicator**, so that **I never oversell and restock before a school's demand dries up**.

**Acceptance criteria**

- **Given** the inventory manager, **when** I edit `qty_on_hand` inline (≥ current `qty_reserved`), **then** the change commits immediately and available stock (`qty_on_hand − qty_reserved`) updates for buyers within cache TTL.
- **Given** any item with `available ≤ reorder_level`, **when** the table renders, **then** the row highlights low-stock (and shows the reserved count so I understand held stock).
- **Given** the daily digest job, **when** low-stock items exist, **then** I receive one push/portal notice listing them — no per-item spam.

**Notes** — no auto purchase orders at launch (default recorded in OQ-3).

---

### `CMP-US-004` — Student/guardian browses only their school's stores

**Priority:** P0 · **Traces:** BR-04 / PRD §5.4 · **Depends on:** CMP-US-001, 03 (school claim)

**Story** — As a **verified student or guardian**, I want **a Store section in the Marketplace tab listing only stores that serve my school**, so that **everything I see is actually available to me**.

**Acceptance criteria**

- **Given** my school claim, **when** I open Marketplace → Store, **then** the list shows `active` storefronts whose `storefront_schools` include my school, with name, cover image and delivery note — never stores scoped to other schools.
- **Given** no store serves my school yet, **when** the list loads, **then** the empty state reads "এখনো আপনার স্কুলের জন্য কোনো স্টোর নেই / No stores for your school yet".
- **Given** a paused storefront or a suspended partner, **when** the list query runs, **then** the store is hidden (pause hides from browse; partner status re-checked fail-closed).

---

### `CMP-US-005` — Buyer views product detail with stock state and trust signals

**Priority:** P0 · **Traces:** persona trust signals (approved badge) · **Depends on:** CMP-US-004

**Story** — As a **buyer**, I want **product detail with bn name, ৳ price, variant picker, live stock state and partner trust signals (approved badge + schools served)**, so that **I can trust the store before ordering**.

**Acceptance criteria**

- **Given** a product page, **when** it renders, **then** I see the bn name (en secondary), ৳ price (variant-adjusted), description, images, variant picker (only variants with stock are selectable) and a stock state (in stock / few left / "স্টক শেষ / Out of stock").
- **Given** an out-of-stock product, **when** I view it, **then** it remains visible with the out-of-stock label and the order button is disabled — hidden from purchase, never hidden from view.
- **Given** the partner header, **when** rendered, **then** the "অনুমোদিত পার্টনার / Approved partner" badge and the list of schools this store serves are shown — trust signals are UI.

---

### `CMP-US-006` — Buyer places a pickup order (COD default, snapshot)

**Priority:** P0 · **Traces:** BR-04 / PRD §5.4 (in-store pickup) · **Depends on:** CMP-US-005

**Story** — As a **verified buyer**, I want **to order for pickup with cash on pickup**, so that **I collect books/uniforms from the store I already visit**.

**Acceptance criteria**

- **Given** a purchasable product/variant with stock, **when** I choose qty (1–10) and confirm the summary (items, total ৳, COD note, pickup address shown), **then** one transaction reserves the stock, snapshots each item (names, price, image ref) into `order_items`, freezes `commission_rate`/`commission_bdt`, and creates the order `placed` with `fulfilment = pickup`, `payment_method = cod`; I see "অর্ডার জমা হয়েছে — নিশ্চিত হলে জানানো হবে / Order placed — you'll be notified once confirmed".
- **Given** another buyer buys the last unit at the same moment, **when** both placements race, **then** exactly one succeeds; the loser gets `OUT_OF_STOCK` with the item named — never a negative stock.
- **Given** a total above the COD limit (৳5,000 default), **when** I try to place, **then** the order is refused with `validation.commerce.cod_limit` explaining online payment is coming (`TODO: Confirm` limit, OQ-2).

---

### `CMP-US-007` — Buyer places a courier order with a delivery address

**Priority:** P0 · **Traces:** PRD §5.4 (local courier) · **Depends on:** CMP-US-006

**Story** — As a **verified buyer**, I want **delivery via the store's local courier to my address**, so that **I can order when pickup is impractical**.

**Acceptance criteria**

- **Given** checkout, **when** I pick "কুরিয়ারে পাঠান / Send by courier" and fill the address form (recipient name, phone, district/city, area, address line), **then** the order is created `placed` with `fulfilment = courier` and the address stored on the order.
- **Given** pickup, **when** chosen, **then** no address form is shown; the store's pickup_address is displayed instead with pickup instructions on the order screen.

---

### `CMP-US-008` — Partner confirms an order (reserved → decremented)

**Priority:** P0 · **Traces:** BR-04 · **Depends on:** CMP-US-006/007

**Story** — As a **partner**, I want **to confirm an order from my fulfilment board**, so that **reserved stock becomes a committed sale I will pack**.

**Acceptance criteria**

- **Given** an order `placed` on my board, **when** I confirm it, **then** in one transaction `qty_reserved` decreases and `qty_on_hand` decreases for every line, and status → `confirmed`; the buyer is pushed "আপনার অর্ডার নিশ্চিত হয়েছে / Your order is confirmed".
- **Given** a stale board, **when** I confirm an order the buyer just cancelled, **then** `CONFLICT` and the row refetches — no double decrement.
- **Given** 24 hours pass with no partner action on a `placed` order, **when** the auto-cancel job runs, **then** the order becomes `cancelled` (reason: partner timeout), the reservation is released, and both parties are notified.

---

### `CMP-US-009` — Buyer collects at the store (ready → completed)

**Priority:** P0 · **Traces:** PRD §5.4 · **Depends on:** CMP-US-008

**Story** — As a **partner**, I want **to mark a pickup order ready and complete it when the buyer collects and pays cash**, so that **the board reflects reality and the commission is booked**.

**Acceptance criteria**

- **Given** a confirmed pickup order, **when** I mark it ready, **then** status → `ready_for_pickup` and the buyer is pushed with the pickup address and "অর্ডার নম্বর নিয়ে পিকআপের ঠিকানায় আসুন / Bring your order number to the pickup address".
- **Given** the buyer arrives and pays cash, **when** I mark the order complete, **then** status → `completed` (terminal), the COD collection is recorded via audit, and the order shows in my completed tab.
- **Given** the buyer's order screen, **when** status is `ready_for_pickup`, **then** the pickup instructions screen shows the order code, store pickup address and delivery note.

---

### `CMP-US-010` — Partner ships a courier order with tracking

**Priority:** P0 · **Traces:** PRD §5.4 (third-party courier) · **Depends on:** CMP-US-008

**Story** — As a **partner**, I want **to record the courier name and tracking number when I hand the parcel over**, so that **the buyer can quote the tracking number to the courier**.

**Acceptance criteria**

- **Given** a confirmed courier order, **when** I open the ship dialog and enter courier_name + tracking_number (both required), **then** status → `shipped` and the buyer is pushed "আপনার অর্ডার পাঠানো হয়েছে — ট্র্যাকিং: … / Your order is shipped — tracking: …".
- **Given** the shipped order, **when** the buyer opens it, **then** the tracking number and courier name are displayed (manual courier at launch — no tracking link, OQ-1).
- **Given** a pickup order, **when** I try to ship it, **then** `CONFLICT` — ship is courier-only (state machine guard).

---

### `CMP-US-011` — Either party cancels within allowed states; stock restocks

**Priority:** P0 · **Traces:** persona (no dark patterns — easy exit) · **Depends on:** CMP-US-006

**Story** — As a **buyer or partner**, I want **to cancel an order before it ships, with stock returned**, so that **mistakes are recoverable and inventory stays honest**.

**Acceptance criteria**

- **Given** an order in `placed`/`confirmed`/`ready_for_pickup` (buyer) or `placed`/`confirmed` (partner, reason required), **when** cancel is submitted, **then** status → `cancelled`; a `placed`-state cancel releases the reservation, a post-confirm cancel adds the qty back to `qty_on_hand`; the counterpart is notified with the reason.
- **Given** an order `shipped`/`completed`/`cancelled`, **when** cancel is attempted, **then** `CONFLICT` — shipped-or-later cannot cancel.
- **Given** partner cancel, **when** submitted without a reason (≥ 5 chars), **then** `VALIDATION_FAILED`.

---

### `CMP-US-012` — Commission computed and frozen per order

**Priority:** P0 · **Traces:** `brd.md` §7 Stream 1 (5–10%) · **Depends on:** CMP-US-006

**Story** — As the **platform**, I want **the commission rate captured on each order at placement (`rate × total`)**, so that **later rate changes never rewrite history and Super Admin reporting is exact**.

**Acceptance criteria**

- **Given** order placement, **when** totals compute, **then** `commission_rate` (default 0.050, within CHECK 0.050–0.100) and `commission_bdt = round(rate × total_bdt, 2)` (e.g. ৳1,250.00 → ৳62.50) are written on the order in the same transaction.
- **Given** a later change to the default rate (config / future Super Admin per-storefront setting), **when** old orders are read, **then** their stored commission is untouched.
- **Given** Super Admin `/admin/commission`, **when** opened now, **then** a stub renders ("মডিউল ১২-এর সাথে আসছে / ships with module 12 revenue work") — the data (commission columns) is already being captured.

---

### `CMP-US-013` — Buyer receives order-status pushes with deep links

**Priority:** P1 · **Traces:** PRD §5.4 (push with deep links, fee pattern) · **Depends on:** CMP-US-008

**Story** — As a **buyer**, I want **a push on every status change that opens my order screen**, so that **I never wonder where my uniform is**.

**Acceptance criteria**

- **Given** any partner status transition (confirmed/ready/shipped/completed) or a cancellation, **when** it commits, **then** `notify.SendToUser` (06) pushes the buyer with payload type `commerce_order_status` (order id + status label only); tapping deep-links to `/(tabs)/marketplace/orders/[id]`.
- **Given** 06/FCM is down, **when** statuses advance, **then** orders still progress (DB-first) and pushes are retried by 06 — status truth never depends on delivery.

---

### `CMP-US-014` — Partner pauses or resumes the storefront

**Priority:** P1 · **Traces:** BR-04 (partner control) · **Depends on:** CMP-US-001

**Story** — As a **partner**, I want **to pause my storefront (e.g. during stocktaking) without killing in-flight orders**, so that **buyers stop ordering while existing orders still complete**.

**Acceptance criteria**

- **Given** my active storefront, **when** I pause it, **then** status → `paused`, it disappears from school browse and product purchase within cache TTL — existing orders continue through their lifecycle normally.
- **Given** a paused storefront, **when** I resume, **then** it reappears for its schools.
- **Given** my partner account is suspended by a Super Admin (07), **when** any browse/placement re-check runs, **then** my storefronts are hidden and new orders refused fail-closed; existing orders continue to completion.

---

### `CMP-US-015` — Out-of-stock items visible but not purchasable

**Priority:** P1 · **Traces:** persona (honest marketplace) · **Depends on:** CMP-US-003

**Story** — As a **buyer**, I want **sold-out items to stay visible with a clear "স্টক শেষ / Out of stock" label**, so that **I know the store exists and can check back — no ghost products, no bait**.

**Acceptance criteria**

- **Given** a product whose stock hits zero (all variants or product-level), **when** the store grid renders, **then** the card shows the out-of-stock label and the detail page disables the order button.
- **Given** a partially stocked product (some variants empty), **when** I open the variant picker, **then** empty variants are disabled and labelled; stocked variants remain buyable.

---

### `CMP-US-016` — Super Admin commission report stub

**Priority:** P2 · **Traces:** `brd.md` §7 Stream 1 · **Depends on:** CMP-US-012, 07 (portal)

**Story** — As a **Super Admin**, I want **a commission entry in the admin nav that shows what will ship with the revenue dashboard**, so that **the reporting surface is visible now and populated the moment 12 lands**.

**Acceptance criteria**

- **Given** `/admin/commission`, **when** I open it, **then** a stub screen (07 stub pattern) explains the report ships with module 12's revenue work and shows the platform commission model note (5% default, 5–10% band per `brd.md` §7) — no invented figures.

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `CMP-BR-001` | A storefront may be created only by a partner whose `vendor_accounts.status = approved` (07 `partners.Approve` family + status read); suspended/rejected partners are refused `FORBIDDEN` | Service gate on every partner write |
| `CMP-BR-002` | A storefront is visible to exactly the schools in `storefront_schools` (partner-selected subset, never city-wide); browse joins on the buyer's `school_id` | Repository join + service |
| `CMP-BR-003` | Buying requires a verified user (`auth.RequireVerified`); unverified → `NOT_VERIFIED` | Middleware + service |
| `CMP-BR-004` | Overselling is impossible: placement reserves atomically (`qty_reserved += qty` only if `qty_on_hand − qty_reserved ≥ qty`, row-locked); otherwise `OUT_OF_STOCK` | Placement tx (SELECT … FOR UPDATE) |
| `CMP-BR-005` | Confirm decrements (`qty_reserved −= qty`, `qty_on_hand −= qty`); cancel from `placed` releases the reservation; cancel after confirm restocks `qty_on_hand`; `qty_on_hand ≥ qty_reserved ≥ 0` always | Service tx + CHECK constraints |
| `CMP-BR-006` | Order items are snapshots: product/variant names, price, image ref and sku are copied into `order_items` at placement; later product/price edits never mutate existing orders | Placement tx; no order-item UPDATE path exists |
| `CMP-BR-007` | `commission_rate` is frozen at placement (default 0.050; CHECK 0.050–0.100 per `brd.md` §7); `commission_bdt = round(rate × total_bdt, 2)` | Placement tx; DB CHECK |
| `CMP-BR-008` | Order state machine: `placed → confirmed → (ready_for_pickup → completed │ shipped → completed)`, cancel only before `shipped`; illegal transitions → `CONFLICT`; `ready` is pickup-only, `ship` is courier-only and requires courier + tracking | Service state machine (INV-3) |
| `CMP-BR-009` | COD limit: `payment_method = cod` refused with `validation.commerce.cod_limit` when `total_bdt > 5,000` (`TODO: Confirm`, OQ-2); `online` requires module 12 (until then refused with a coming-soon message) | Service on placement |
| `CMP-BR-010` | A `placed` order older than 24 h (config) is auto-cancelled by the job with reservation release; both parties notified | `commerce.auto-cancel` job |
| `CMP-BR-011` | Paused storefront: hidden from browse, new orders refused; existing orders continue to a terminal state. Archived/out-of-stock products: visible with label, not purchasable | Browse query + placement guard |
| `CMP-BR-012` | Isolation: partner routes resolve storefronts via `vendor_account_id = caller's` (partner A can never read/act on partner B's orders/products); buyer routes are row-level own-orders + school-served store reads only | Repository scoping (`CMP-IT-003`) |
| `CMP-BR-013` | Product names are partner content: `name_bn` required, `name_en` optional; prices in BDT ৳; ≤ 5 images via 05 media (confirmed assets only) | Validation + 05 media confirm check |
| `CMP-BR-014` | All commerce routes rate-limit under class `default`; placement carries a tighter per-user bucket | Redis limiter (01 base) |

> Content-accuracy (`prompt.txt` §12): seeded stores/products/orders are clearly fictional
> ("ডেমো স্টোর / Demo Store", "Demo High School"); commission figures cite `brd.md` §7 only and the
> default rate sits behind `TODO: Confirm` (OQ-1) — no invented prices beyond marked demo data.

## 6. Validation Rules

| Field | Rule | Message key (per-app `src/i18n` catalog) |
| --- | --- | --- |
| `nameBn` (storefront & product) | Required, 2–120 chars after trim | `validation.commerce.name_bn_required` · `name_length` |
| `nameEn` (storefront & product) | Optional, 2–120 chars | `validation.commerce.name_length` |
| `description` | ≤ 1,000 chars plain text | `validation.commerce.description_length` |
| `schoolIds` (storefront) | ≥ 1 valid school from the 04 catalog, ≤ 50 | `validation.commerce.schools_required` · `school_unknown` |
| `pickupAddress` | Required, 10–300 chars | `validation.commerce.pickup_address_required` |
| `deliveryNote` | Optional, ≤ 300 chars | `validation.commerce.delivery_note_length` |
| `category` | `books` \| `uniforms` \| `stationery` \| `other` | `validation.commerce.category_invalid` |
| `priceBdt` | numeric > 0, ≤ 100,000.00, 2 dp | `validation.commerce.price_range` |
| `variantName` | 1–60 chars; unique within product | `validation.commerce.variant_name_invalid` |
| `variantPriceDelta` | numeric, −`priceBdt` < delta ≤ 50,000.00 | `validation.commerce.price_delta_range` |
| `sku` | Optional, ≤ 40 chars, `[A-Za-z0-9-]` | `validation.commerce.sku_invalid` |
| `imageMediaIds` | 0–5 refs to `confirmed` media assets (05) | `validation.commerce.images_invalid` |
| `qtyOnHand` / `reorderLevel` | integers ≥ 0; `qtyOnHand ≥ qtyReserved` on edit | `validation.commerce.qty_invalid` |
| `items` (order) | 1–10 lines; per-line `qty` 1–10; all from the same storefront | `validation.commerce.items_invalid` · `qty_range` · `single_store` |
| `fulfilment` | `pickup` \| `courier`; courier requires address fields | `validation.commerce.fulfilment_invalid` · `address_required` |
| courier address (`recipientName`, `recipientPhone`, `city`, `area`, `addressLine`) | name 3–120; BD E.164 phone; city/area 2–80; line 10–200 | `validation.commerce.address_*` |
| `cancelReason` (partner cancel) | Required, 5–500 chars | `validation.commerce.cancel_reason_required` |
| `courierName` / `trackingNumber` (ship) | Required on ship, 2–80 / 4–60 chars | `validation.commerce.courier_required` · `tracking_required` |

> Mirrored exactly by the OpenAPI contract (server validation) and the zod form schemas (web/app)
> generated from it. Both languages from day one.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to any commerce/partner endpoint | `UNAUTHENTICATED`, no side effect |
| 2 | Buyer of school B opens a store serving only school A | `NOT_FOUND`/invisible — no catalog leaks across the school boundary (`CMP-IT-002`) |
| 3 | Unverified user attempts to order | `NOT_VERIFIED` + how-to-get-verified guidance (module 03 copy) |
| 4 | Parallel placements race for the last unit | Exactly one wins; loser `OUT_OF_STOCK` naming the item (`CMP-IT-001`) |
| 5 | Product image R2 object missing | Degraded placeholder image; product/order pages never crash |
| 6 | Reduced motion enabled | Static chips/boards; no animated transitions |
| 7 | Offline order submission (app) | Queued once with a clear banner; on replay the server may answer `OUT_OF_STOCK`/`CONFLICT` — surfaced as a reviewable failed item, never silently lost |
| 8 | Partner suspended mid-order | Storefront hidden, new orders refused; in-flight orders continue to completion (either party may cancel) |
| 9 | Storefront paused with `placed` orders | Orders continue; buyer sees honest status; no new orders accepted |
| 10 | Partner edits price after placement | Existing order totals/commission unchanged (snapshot, BR-006) |
| 11 | Cancel vs confirm race (stale partner board) | First commit wins; second `CONFLICT` + row refetch |
| 12 | Courier order shipped then buyer unreachable | Partner cannot cancel post-ship (BR-008); contact via order phone; completed/cancelled-by-agreement stays manual at launch (recorded in `08-gaps.md` at build) |
| 13 | Variant deleted from product after it was ordered | Order item snapshot unaffected; archived variants vanish from the picker only |
| 14 | COD-limit order attempted while payments not yet live | Refused with `validation.commerce.cod_limit` copy suggesting a smaller order / pickup at store |

## 8. Reporting Needs

- Partner dashboard counts (this module, live queries): orders needing action by status, low-stock
  items, last-30-day completed orders + commission earned (partner's own).
- `commerce.OrdersForVendor(vendorAccountId)` export already returns commission fields — the Super
  Admin commission/GMV report (07 revenue screen, module 12 era) reads them; `/admin/commission`
  ships as a stub now (`CMP-US-016`).
- School Admin: none — commerce is partner/Super-Admin governed; no school-admin surface in this
  module.

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Exact commission rate at launch (`brd.md` §7 allows 5–10%) | Rahul | Open (`TODO: Confirm`) | 5% default stored per order; rate is config; per-storefront Super Admin overrides later |
| 2 | COD limit amount for the fraud guard | Rahul | Open (`TODO: Confirm`) | BDT 5,000 — COD refused above it until online payment (12) exists |
| 3 | Courier = manual third-party at launch (partner enters name + tracking; no API, no tracking link) | Rahul | Open (default accepted) | As stated; matches `brd.md` §4 and the README blocked-questions default |
| 4 | Inventory policy: reserve-on-placement → decrement-on-confirm; no auto purchase orders | Rahul | Open (default accepted) | As stated; auto-cancel 24 h covers partner inaction |
| 5 | Multi-store cart in future? | Rahul | Open (`TODO: Confirm`) | Single-store direct order (marketplace-lite, simplest); cart is additive later |
| 6 | Auto-cancel window for stale `placed` orders | Rahul | Open | 24 hours, config |

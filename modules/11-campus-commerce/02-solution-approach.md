# Campus Commerce — Solution Approach

**Module:** `11-campus-commerce` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> Written **before** any task list and any code (`docs/prompt/prompt-build.md` §4 step 1).

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `vendor_storefronts` | A partner's shop: name bn (+en), description, `status ∈ active\|paused`, pickup_address, delivery_note; belongs to a 07 `vendor_account` (approved) | Yes |
| `storefront_schools` | Join table storefront × school — the partner-selected subset of schools that can see the store (chosen over a jsonb array for queryability — §10) | Yes |
| `products` | Catalog item: name_bn (required) + name_en, description, `category ∈ books\|uniforms\|stationery\|other`, `price_bdt numeric(10,2)`, image refs (05 `media_assets`), `status ∈ active\|archived` | Yes |
| `product_variants` | Size/colour options: name, `price_delta`, nullable sku; unit price = product price + delta | Yes |
| `inventory_items` | Stock per sellable unit (product-level, or per variant): `qty_on_hand`, `qty_reserved`, `reorder_level`; availability = on_hand − reserved | Yes |
| `orders` | Buyer order: storefront, buyer, school (tenant), `fulfilment ∈ pickup\|courier`, `status ∈ placed\|confirmed\|ready_for_pickup\|shipped\|completed\|cancelled`, totals, `commission_rate numeric(4,3)`, `commission_bdt`, courier_name/tracking_number (nullable), `payment_method ∈ cod\|online`, `payment_transaction_id` (nullable — 12's seam) | Yes |
| `order_items` | Immutable per-line snapshot jsonb (product/variant names bn/en, category, image ref, sku) + qty + `unit_price_bdt` | Yes |
| `vendor_accounts` | Partner company + approval lifecycle `pending → approved\|rejected`, `approved ⇄ suspended`; `portal_user_id` link | No — module 07 (read-only via its partner service) |
| `media_assets` | Product images (presigned upload, magic-byte sniffed) | No — module 05 (`media.*`) |
| `users` + verified status / school claims | Buyer identity; verification gate; tenant context | No — modules 03/04 |
| Push delivery | Order-status pushes with deep links | No — module 06 (`notify.SendToUser`) |

### 1.2 Relationships

```text
vendor_accounts (07, approved) 1───* vendor_storefronts ──pause──▶ hidden from browse (orders continue)
vendor_storefronts 1───* storefront_schools *───1 school (04)     ← school-scoped visibility
vendor_storefronts 1───* products 1───* product_variants
products/product_variants 1───1 inventory_items (variant_id NULL = product-level stock)
products 0..*───media_assets (05; ≤ 5 confirmed images)
buyer user (03, VERIFIED) 1───* orders *───1 vendor_storefronts (served via storefront_schools ∋ buyer's school)
orders 1───* order_items (snapshot jsonb — immutable)
orders.payment_transaction_id ◀── module 12 (seam: commerce.OrderAmount + AttachPaymentTransaction)
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| INV-1 | Storefront browse/placement join on `storefront_schools` by the buyer's `school_id`; a buyer of a non-served school gets 404 — school-scoped visibility is a query shape, not a filter bolted on | Repository join (`CMP-IT-002`) |
| INV-2 | `0 ≤ qty_reserved ≤ qty_on_hand` at all times; placement reserves row-locked; confirm decrements both; placed-cancel releases the reservation; post-confirm cancel restocks | Tx with `SELECT … FOR UPDATE` + CHECKs (`CMP-IT-001/011`) |
| INV-3 | Order transitions are only the legal edges of the §3 state machine; `ready` requires `fulfilment=pickup`, `ship` requires `fulfilment=courier` + courier_name + tracking_number; cancel only before `shipped` | Service state machine + `CONFLICT` |
| INV-4 | `order_items` rows are immutable snapshots (no UPDATE path exists in sqlc); product/price edits after placement never mutate orders; commission rate/amount are frozen on the order row | Schema (no update query) + placement tx (`CMP-IT-013`) |
| INV-5 | Partner writes resolve rows via `storefronts.vendor_account_id` = the caller's partner account; buyer writes resolve via `orders.buyer_id`; nothing partner-partner or buyer-buyer is reachable | Repository scoping (`CMP-IT-003/015`) |
| INV-6 | Only `active` storefronts of `approved` partners appear in browse or accept placements — partner status is re-checked fail-closed on the money path (staleness on browse ≤ cache TTL) | Service gates (BR-001/011) |
| INV-7 | An order belongs to exactly one storefront and its lines come only from that storefront (single-store order) | Service validation + FK shape |

## 2. Module Boundary

**Owns (writes):** `vendor_storefronts`, `storefront_schools`, `products`, `product_variants`,
`inventory_items`, `orders`, `order_items` — plus the auto-cancel and low-stock jobs over them.

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 07 | `partners.Approve` family + partner account status read (`GET /partner/state` on web; api-side partner service read) — the approval gate and suspend checks | Partner lifecycle is 07's; we only consume `status = approved` |
| 03 | `auth.RequireVerified` (buying is verified-only), `users` identity/claims, portal-user model for partner login | Verification is identity's source of truth (`prd.md` §5.1) |
| 04 | School catalog (schools a storefront may serve; buyer's school context) | Hierarchy owns schools |
| 05 | `media.PresignUpload`/`ConfirmUpload` (product images) | Upload hardening lives once |
| 06 | `notify.SendToUser` (order-status pushes + deep links) | FCM fan-out and retry are 06's |
| 01 | `jobs.Enqueue` + worker (auto-cancel, digests), `audit.Record`, error envelope, rate limiter | Foundations own the plumbing |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4
(`commerce:stores:school:{id}`, `commerce:store:{id}`, `commerce:product:{id}`).

## 3. Lifecycle

Order state machine (the module's core flow — guards in **bold**):

```text
              POST /commerce/orders (verified buyer; single-store)
                │  tx: FOR UPDATE inventory rows → availability check
                │      → insert order + snapshot items → qty_reserved += qty
                │      → commission_rate/bdt frozen (BR-007)
                ▼
            placed ──partner confirm──▶ confirmed ──partner ready──▶ ready_for_pickup ──complete──▶ completed
               │                          │                                               (terminal)
               │                          └──partner ship (courier + tracking required)──▶ shipped ──complete──▶ completed
               ├──buyer cancel (reason optional)──▶ cancelled ◀──partner cancel (reason required)
               ├──auto-cancel job (placed > 24 h)──▶ cancelled   (releases reservation)
               └──cancel from confirmed/ready_for_pickup: restock qty_on_hand
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| (none) | buyer places | placed | verified ∧ store active+serves school ∧ partner approved ∧ stock available ∧ COD ≤ limit | stock reserved; snapshot items; commission frozen; partner push; auto-cancel timer armed |
| placed | partner confirm | confirmed | own storefront order ∧ still placed (else `CONFLICT`) | `qty_reserved −= qty`, `qty_on_hand −= qty`; buyer push |
| confirmed | partner ready | ready_for_pickup | `fulfilment = pickup` | buyer push w/ pickup instructions |
| confirmed | partner ship | shipped | `fulfilment = courier` ∧ courier_name ∧ tracking_number | buyer push w/ tracking number |
| ready_for_pickup / shipped | partner complete | completed | own order | COD collection audited (`audit.Record`) |
| placed | buyer/partner cancel | cancelled | before shipped; partner needs reason | reservation released (qty_reserved −= qty); counterpart notified; audited |
| confirmed / ready_for_pickup | buyer/partner cancel | cancelled | before shipped | `qty_on_hand += qty` (restock); counterpart notified; audited |
| placed (> 24 h) | auto-cancel job | cancelled | job idempotent, status-checked | reservation released; both parties notified |

Storefront: `active ⇄ paused` (pause hides from browse; orders continue). Product:
`active ⇄ archived` (archive hides from purchase; historic order snapshots unaffected).

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| Store browse (stores serving my school) | TanStack Query list (app) / RSC first paint (web) | Redis, TTL 300 s — reads often, changes rarely | `commerce:stores:school:{id}` |
| Store page + product grid | Detail query per store | Redis, TTL 120 s | `commerce:store:{id}` |
| Product detail | Detail query | Redis, TTL 120 s | `commerce:product:{id}` |
| Partner board / inventory / dashboards | Fresh — money + stock surfaces are never page-cached | TanStack Query memory | none |
| My orders / order detail | Fresh per user (status truth) | TanStack Query memory | none |

Invalidation: storefront create/update/pause and school-list changes bust
`commerce:stores:school:{id}` for every affected school + `commerce:store:{id}`; product and
inventory mutations bust `commerce:store:{id}` + `commerce:product:{id}` (+ school tags for served
schools); order mutations bust nothing (orders are never cached). Full contract in `06` §4.

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| Default commission rate (0.050; `TODO: Confirm` OQ-1); per-storefront overrides later via 07 | Commission frozen at placement; CHECK band 0.050–0.100 (`brd.md` §7) |
| COD limit (৳5,000 default; `TODO: Confirm` OQ-2) | Reserve-then-decrement inventory policy (INV-2); snapshots (INV-4) |
| Auto-cancel window (24 h, OQ-6); max lines/order (10); qty/line (1–10) | School-scoped visibility (INV-1); verified-only buying (BR-003) |
| Low-stock digest schedule (daily) + `reorder_level` defaults (5) | Manual courier fields only (no carrier API at launch, OQ-3) |
| Rate-limit buckets (class `default`; tighter placement bucket) | Media caps/kinds (delegated to 05); single-store order (OQ-5) |

## 6. Security

Entry points: 18 REST endpoints under `/api/v1/partner/*` and `/api/v1/commerce/*` (`03` §2); every
entry runs **authenticate → load role claims → tenant-scope**, plus `auth.RequireVerified` on buyer
routes (`NOT_VERIFIED` otherwise) and the 07 partner-approval gate on partner routes.

| Surface | Auth | Tenant/ownership scope rule |
| --- | --- | --- |
| `/partner/storefronts*`, `/partner/products*`, `/partner/inventory` | Partner portal user linked to an `approved` `vendor_account` (BR-001) | Rows resolve via `vendor_account_id` — a partner touches only own storefronts/products/orders (INV-5) |
| `/partner/orders*` (fulfilment) | Same partner identity | Order joined to own storefronts only (INV-5) |
| `/commerce/stores*`, `/commerce/products/{id}` | Any verified user | Store/product reads joined to the caller's school via `storefront_schools` (INV-1) |
| `/commerce/orders` (place) | `auth.RequireVerified` | Buyer's school must be served; rows row-level own (INV-1/5) |
| `/commerce/orders/{id}` (view/cancel) | Buyer of the order | Row-level `buyer_id` match |
| `/admin/commission` | Super Admin | Stub now; data access arrives with 12/07 revenue |

Sanitisation: product/partner free text is length-capped plain text rendered as text (no HTML);
prices are `numeric(10,2)` — never floats; phone/address fields validated against BD formats.
`OUT_OF_STOCK` is added as a module problem code beside the common RFC-7807 set. Audit
(`audit.Record`): order placement, both cancel paths, completion (COD collection), portal-user
linking. Rate limits: class `default` everywhere, tighter per-user bucket on placement.

## 7. Accessibility & Motion

Status is never colour-only: every order chip pairs a colour with a bn/en label
("পিকআপের জন্য প্রস্তুত / Ready for pickup") and an icon; stock state ("স্টক শেষ / Out of
stock") is text, not a greyed-out mystery. The variant picker announces per-option availability;
the qty stepper is keyboard/switch-access friendly with announced value. Motion is limited to chip
feedback, board column highlight and the order-placed success overlay — each with instant
reduced-motion forms (details in `04` §5, `05` §5). Screen-reader order: status chip → item summary →
primary action.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | Payment seam pending (module 12 not shipped) | By design until Phase 3 payments land | All orders COD; totals > COD limit refused with clear copy | Seam is additive (`commerce.OrderAmount`, `AttachPaymentTransaction`); 12 plugs in without schema change |
| 2 | 05 media down (product images) | Presign/confirm 5xx | New image attach fails | Product save succeeds **without** the new image + warning banner (BR/US-002); existing images unaffected; upload resumable |
| 3 | 06 notifications down | `notify.SendToUser` error | No pushes; statuses still advance | DB-first lifecycle; 06's queue retries on restore; buyer sees truth in My Orders |
| 4 | 01 worker down (auto-cancel/digests) | Job lag alarm | Stale `placed` orders linger; reservations held longer | Jobs idempotent — catch up on restore; partner can always cancel manually |
| 5 | Redis down | Cache/limiter errors | Browse falls through to Postgres (slower, TTL-stale tags rebuilt); limits fail safe | No wrong data — DB is source of truth; placement re-checks make cache staleness harmless |
| 6 | Neon (Postgres) degraded | Connection errors | Nothing commerce-side works (source of truth) | 01/15 runbooks: pool alarm, failover path |
| 7 | 07 partner suspended between browse and placement | Fail-closed status re-check on placement (INV-6) | Placement refused `FORBIDDEN` | Buyer sees honest refusal; browse staleness ≤ TTL |

## 9. Performance

- Volumes (pilot, 3 schools × ~2,000 users): ~10 storefronts, ~500 products, ~50 orders/day — small
  tables; indexes designed for the BRD year-1 target (10 schools, ~20k users, 10×).
- Hot query 1 — stores by school: `storefront_schools JOIN vendor_storefronts` on `school_id` with
  `status='active'` (+ partner approved) — index `(school_id)` on the join table; served from the
  `commerce:stores:school:{id}` cache, p95 ≤ 100 ms cached.
- Hot query 2 — orders by buyer/partner + status: `(buyer_id, status)` and
  `(storefront_id, status)` indexes; partner board reads are per-partner and small.
- Placement is the write-hot path: one tx, `SELECT … FOR UPDATE` over ≤ 10 inventory rows
  (deterministic id order to avoid deadlocks) — milliseconds at this scale; parallel-oversell
  proven by `CMP-IT-001`.
- Bundle impact: no new heavy dependencies — TanStack Table already present (07), RN primitives from
  module 02; product images served from R2 via 05 (compressed at upload).

## 10. Alternatives Considered

### Option A — schools as jsonb array on `vendor_storefronts` · Option B — `storefront_schools` join table (chosen)

| | A (jsonb array) | B (join table, chosen) |
| --- | --- | --- |
| Advantages | One row, no joins on write | Hot query (stores-by-school) is a plain indexed join; FK integrity to 04 schools; trivial counts/coverage reports |
| Disadvantages | Browse needs a GIN containment predicate; no FK to schools; renaming/re-keying schools orphans array values | One more table + replace-on-update write |
| Complexity / weight | Low write, worse read | Negligible — queryability wins for the read-hot path |

**Recommendation:** B (as assigned). **ADR:** record in this module's `07-progress.md`.

### Option A — decrement stock on placement · Option B — reserve on placement, decrement on confirm (chosen)

| | A (decrement at placement) | B (reserve → confirm, chosen) |
| --- | --- | --- |
| Advantages | Simplest cancel (always "restock") | `placed`-state stock stays visible as held (reserved counts on the partner board); auto-cancel semantics clean (release ≠ restock) |
| Disadvantages | Partner can't distinguish hold vs sale; buyer abandonment shrinks visible stock silently | Two stock columns + one guard each (still one tx) |
| Complexity / weight | Low | Low-medium — worth it for honest inventory |

**Recommendation:** B (as assigned; INV-2).

### Option A — full cross-store cart · Option B — direct single-store order, marketplace-lite (chosen)

| | A (cart) | B (single-store order, chosen) |
| --- | --- | --- |
| Advantages | Familiar e-commerce pattern; multi-partner baskets | One tx, one storefront, one courier/pickup decision per order; ships in an L-sized module; commission math trivial |
| Disadvantages | Checkout/shipping/commission complexity explodes across storefronts | Buyer re-orders per store (acceptable: uniform/book runs are single-store in practice) |
| Complexity / weight | High (cart entity, merge rules, split fulfilment) | Low |

**Recommendation:** B now; cart is additive later (`TODO: Confirm` OQ-5). ADR in `07-progress.md`.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | Partners confirm orders promptly | Reservations pile up; buyers wait | 24 h auto-cancel (BR-010) + "orders needing action" dashboard + partner push on placement |
| 2 | Manual courier (no API) stays acceptable | Tracking expectations outgrow copy-paste tracking numbers | Honest copy ("ট্র্যাকিং নম্বর / tracking number" only, no live link); courier API becomes an additive module later |
| 3 | COD limit (৳5,000) may block bulk uniform orders | Legit large orders refused | Limit is config; message suggests splitting/pickup; OQ-2 confirms with Rahul before launch |
| 4 | Commission default (5%) unconfirmed | Rate rework at launch | Rate is per-order data + config — changing the default never rewrites history (INV-4) |
| 5 | Offline order queues hit `OUT_OF_STOCK` on replay | Buyer frustration | Failed items stay reviewable with input preserved; honest error naming the item |
| 6 | Partner portal-user linking abused (wrong phone claims a partner) | Account takeover of a store | One-time bind: portal phone must equal `vendor_accounts.phone` + approved status + audit; mismatch → `FORBIDDEN` |

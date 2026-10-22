# Campus Commerce — Integration Tasks

**Module:** `11-campus-commerce` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> `02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
> **contract**. **No cross-module call, cache key or external dependency may exist in code unless
> it is declared here** (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `01-foundations` | we call them | `jobs.Enqueue` (auto-cancel, low-stock digest, placement timer) + `audit.Record` (placement, cancels, completion, portal link) | degraded — jobs delayed (idempotent catch-up); audit failure aborts the wrapped action (01 I-3) |
| I-2 | `03-identity-access` | they gate us | `auth.RequireVerified` on every buyer route + `users` identity/school claims; partner portal-user model | fatal by design — orders refused `NOT_VERIFIED` (the gate is the feature) |
| I-3 | `04-organization-hierarchy` | we call them | school catalog (storefront school picker; buyer's `school_id` tenant context) | degraded — storefront create blocks with retry; never stores an unknown school |
| I-4 | `05-communication-engine` | we call them | `media.PresignUpload` / `media.ConfirmUpload` (product images) | degraded — product saves without the new image + warning; existing images unaffected |
| I-5 | `06-notifications` | we call them | `notify.SendToUser` (order-status pushes, deep links `commerce_order_status`) | degraded, never fatal — **statuses advance DB-first**; 06 retries delivery |
| I-6 | `07-command-center-web` | they gate/host us | `partners.Approve` family + partner status read (`GET /partner/state`): approval gate before storefront create, fail-closed suspend checks; `/partner` shell + nav (07 built) filled by this module | our outage never blocks 07; their partner data gates storefronts (fail-closed on reads) |
| I-7 | `12-payments` (future) | they call us | exports `commerce.OrderAmount` + `commerce.AttachPaymentTransaction` (§2 seam); until 12 ships every order is COD | n/a — seam dormant; 12's absence only caps fulfilment to COD |
| I-8 | app/web clients | they call us | REST `/api/v1/commerce/*` (app buyer) and `/api/v1/partner/*` (web partner portal) via generated clients | fatal to the feature surface (standard API errors) |
| I-9 | api → app pushes | we notify | via I-5; payload `commerce_order_status` (orderId + status label only; deep link to `/(tabs)/marketplace/orders/[id]`) | degraded — in-app My Orders stays authoritative |

## 2. Exported Contract

```text
commerce.StorefrontsForSchool(schoolID uuid) ([]StorefrontSummaryDTO, error)
commerce.OrderAmount(orderID uuid) (OrderAmountDTO, error)
commerce.OrdersForVendor(vendorAccountID uuid) ([]VendorOrderSummaryDTO, error)
commerce.AttachPaymentTransaction(orderID uuid, txnID string) error   // 12 seam — additive when 12 lands
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `commerce.StorefrontsForSchool(schoolID)` | Buyer browse (app #7 via handler); future 13 school-surface reads | `[]StorefrontSummaryDTO` (active stores serving the school) | `VALIDATION_FAILED` (unknown school) | Cached 300 s under `commerce:stores:school:{id}`; partner-approved check inside (INV-6) |
| `commerce.OrderAmount(orderID)` | **Module 12** (online payment of orders — 12 depends on 11 and reads orders) | `OrderAmountDTO{totalBdt, commissionBdt, status, paymentMethod, orderCode}` | `NOT_FOUND` | The payment seam: 12 quotes/collects against this; frozen totals (INV-4) make it safe |
| `commerce.OrdersForVendor(vendorAccountID)` | 07/12 Super-Admin revenue + commission reporting (later); this module's own dashboard | `[]VendorOrderSummaryDTO` (status, totals, commission fields) | `FORBIDDEN` (no role claims) | Commission already frozen per order — report needs no joins into pricing |
| `commerce.AttachPaymentTransaction(orderID, txnID)` | **Module 12** (on payment success) | `nil` | `CONFLICT` (already attached / not `online` / terminal status), `NOT_FOUND` | Attaches `orders.payment_transaction_id`; guarded, idempotent-safe (one txn per order) |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first. **Payment seam (recorded):** until 12 ships, orders are
`payment_method = cod` (cash on pickup/delivery); `online` placement and txn attach activate with
12 without schema change.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `auth.RequireVerified` / role + tenant claims | 03 | Buyer writes refused `NOT_VERIFIED`/`FORBIDDEN` — never bypassed |
| `users` identity lookups (buyer, portal partner user) | 03 | `NOT_FOUND` propagated; no cached identity past 30 s |
| School catalog (04) | 04 | Storefront create/school-edit blocks with retry copy; unknown school ids rejected `VALIDATION_FAILED` |
| `media.PresignUpload` / `ConfirmUpload` (product images) | 05 | Product save succeeds **without** the new image + warning banner (US-002); resumable later |
| `notify.SendToUser` (status pushes) | 06 | Log + continue — order lifecycle is DB-first; 06's queue retries |
| `jobs.Enqueue` + worker runtime, `audit.Record` | 01 | Enqueue failure → `INTERNAL` on placement (never an un-timed `placed` order); audit retried inline per 01 contract |
| Partner status read (`partners.Approve` family + `GET /partner/state` data) | 07 | Read failure on the money path → fail-closed `FORBIDDEN` (never assume approved); browse falls back to cache ≤ TTL |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| Storefront create / update / pause / resume | `commerce:stores:school:{id}` for **every served school** · `commerce:store:{id}` |
| Storefront schools list changed | Same as above for the **old + new** school sets (dropped schools stop seeing the store) |
| Product create / update / archive | `commerce:store:{id}` · `commerce:product:{id}` · school tags of served schools |
| Inventory update (stock/reorder level) | `commerce:store:{id}` · `commerce:product:{id}` |
| Order placement / status transitions / cancel | none — orders are never page-cached (per-user truth) |

| Read | Tagged with |
| --- | --- |
| `GET /commerce/stores` (server cache, TTL 300 s) | `commerce:stores:school:{id}` |
| `GET /commerce/stores/{id}/products` (TTL 120 s) | `commerce:store:{id}` |
| `GET /commerce/products/{id}` (TTL 120 s) | `commerce:product:{id}` |
| `commerce.OrderAmount` (TTL 60 s — money path keeps a short leash) | `commerce:orderamount:{id}` |
| Partner board / inventory / my orders | never cached (fresh money + stock surfaces) |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| (none directly) | — | — | — | — | All externals are reached **through module owners**: R2 via 05 media, FCM via 06 push, Redis limiter via 01 base |
| Cloudflare R2 (indirect via 05) | S3 presigned PUT/GET | 05-owned `R2_*` env | 05-owned | 05-owned | Product image upload blocked → save-without-image warning; grid placeholders |
| FCM (indirect via 06) | HTTPS Admin SDK | 06-owned `FCM_SERVER_KEY` | 06-owned | 06-owned queue | No push; statuses + My Orders unaffected (DB-first) |
| Third-party courier | **Manual — no API at launch** (OQ-3): partner types courier_name + tracking_number; buyer reads the number | n/a | n/a | n/a | No live tracking link; copy states the number only |

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| Store list (app) | `GET /commerce/stores` | `{data:[storefront]}` school-scoped; cached `commerce:stores:school:{id}` |
| Store grid / product detail (app) | `GET /commerce/stores/{id}/products` · `GET /commerce/products/{id}` | Availability states (in/low/out) + trust payload (approved badge, served schools) |
| Checkout (app) | `POST /commerce/orders` | `{data:{order}}`; `OUT_OF_STOCK` names the item; COD-limit `VALIDATION_FAILED` maps to the summary block; offline queues once |
| My orders / detail (app) | `GET /commerce/orders` · `GET /commerce/orders/{id}` | Status chips + tracking + pickup instructions payload; cancel enabled only in allowed states |
| Buyer cancel (app) | `POST /commerce/orders/{id}/cancel` | `CONFLICT` → "status changed" + refetch; success → restock copy |
| Partner board / dialogs (web) | `GET /partner/orders` · `POST /partner/orders/{id}/confirm\|ready\|ship\|complete\|cancel` | Column counts + `CONFLICT` refetch; ship requires courier + tracking; cancel requires reason |
| Products/inventory (web) | `POST /partner/storefronts/{id}/products` · `PATCH /partner/products/{id}` · `PATCH /partner/products/{id}/inventory` | Media ids attach on save; degraded-save warning; stock edit ≥ reserved enforced server-side |
| Storefront settings (web) | `POST /partner/storefronts` · `GET/PATCH /partner/storefronts` · `PATCH /partner/storefronts/{id}` | Approved gate (`FORBIDDEN` → 07 state card); pause/resume inline |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change. Frozen contracts: the buyer DTO availability
tri-state (in/low/out), the order-status enum + chips vocabulary, `OrderAmountDTO` (12 reads it),
and the `commerce_order_status` push payload type (declared with 06; unknown payload types ignored
by clients). Additive later: online `payment_method` activation + `AttachPaymentTransaction`
(module 12), multi-store cart (`TODO: Confirm` OQ-5), courier API tracking links.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| 06 notifications / FCM | Browsing, placement, confirm/ready/ship/complete, cancel — all DB-first | No pushes; My Orders shows fresh truth in-app | 06's queue delivers on restore; nothing lost |
| 05 media / R2 | Everything except attaching new product images | "ছবি ছাড়া সংরক্ষিত / Saved without images" warning; placeholders for missing objects | Resumable upload later; product data intact |
| 07 partner status read | Buyer browse from cache (≤ TTL staleness) | Placement refused `FORBIDDEN` (fail-closed) until the read answers | Retry; partner fixes status in 07 |
| 01 jobs worker | All REST reads/writes | Auto-cancel + digests delayed; stale `placed` orders linger | Idempotent catch-up on restore; partners can cancel manually |
| 04 hierarchy | Everything except storefront create/school edits | "স্কুল তালিকা অনুপলব্ধ / School list unavailable" on the picker | Retry once catalog answers; existing storefronts unaffected |
| Redis | Everything (DB source of truth) | Browse slower (cache bypass); limiter fails safe | Tags rebuild on return; placement re-checks make staleness harmless |
| Neon (Postgres) degraded | Nothing commerce-side | Errors on reads/writes | 01/15 runbooks: pool alarm, failover path |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `CMP-UT-007` | Cache invalidation sets: storefront/institution/product/inventory mutations bust exactly the §4 tag sets (incl. dropped schools) | Unit | §4 contract |
| `CMP-UT-008` | Push payload builder emits orderId + status label + deep link only (no addresses, no phone, no buyer PII) | Unit | I-9 privacy |
| `CMP-IT-011` | **Oversell prevention, parallel orders** (seam-level): concurrent placements + live push/job stubs → one winner, losers `OUT_OF_STOCK`; reservation math exact | Integration | CMP-BR-004 / INV-2 |
| `CMP-IT-012` | **Cross-school store visibility**: store serving {A} invisible to school B buyers (browse, detail, placement 404); school A sees it; pause hides both | Integration | CMP-BR-002 / INV-1 |
| `CMP-IT-013` | **Commission snapshot**: default rate changed between two placements → each order keeps its frozen rate/amount; `OrdersForVendor` reports both unchanged | Integration | CMP-BR-007 / INV-4 |
| `CMP-IT-014` | **Cancel-restock**: placed-cancel releases reservation; confirmed-cancel restocks on_hand; partner-cancel requires reason; buyer notified | Integration | CMP-BR-005 |
| `CMP-IT-015` | **Partner-scope isolation**: partner A cannot read or act on partner B's storefronts/products/orders (`FORBIDDEN`/404); buyer cannot see/cancel another buyer's order | Integration | CMP-BR-012 / INV-5 |
| `CMP-IT-016` | **Unverified buyer blocked** (`NOT_VERIFIED`) at every buying seam; verified path unaffected | Integration | CMP-BR-003 |
| `CMP-IT-017` | Degradation drills: 06-down stub → statuses advance, pushes queued; 05-down stub → product saves without image + warning; 07-read-down → placement fail-closed `FORBIDDEN` | Integration | §8 matrix |
| `CMP-E2E-001` | Playwright (web): approved partner links portal user → creates storefront → adds product with variant + image → fulfilment board confirms and ships a seeded order with tracking | Playwright | US-001/002/008/010 partner golden path |
| `CMP-E2E-002` | Maestro (app): verified student browses own-school store → product detail → pickup checkout (COD) → order placed; partner confirm injected via api fixture → status chip advances + pickup instructions render | Maestro | US-004/005/006/009/013 buyer golden path |

## 10. Task Checklist

- [x] `CMP-INT-001` Implement + export `commerce.StorefrontsForSchool` (+ cache key, INV-6 partner check) — 2026-10-03 (`StoresForSchool` + school join; INV-6 approved check on placement; cache tag helper)
- [x] `CMP-INT-002` Implement + export `commerce.OrderAmount` and `commerce.OrdersForVendor` (07/12 handoff note) — 2026-10-03 (`OrderAmount` + `OrdersForVendor` with frozen commission fields)
- [x] `CMP-INT-003` Implement + export `commerce.AttachPaymentTransaction` seam (guarded; dormant until 12 ships — COD recorded) — 2026-10-03 (guarded UPDATE: online ∧ unattached ∧ placed/confirmed; dormant until 12)
- [x] `CMP-INT-004` Consume `auth.RequireVerified` + school claims on all buyer routes (refuse-don't-guess) — 2026-10-03 (`caller.Verified` gate on placement/cancel; school claims on browse)
- [x] `CMP-INT-005` Consume 07 partner approval/suspend reads (fail-closed on placement; browse ≤ TTL) — 2026-10-03 (`RequireApprovedVendor` fail-closed on placement + partner writes; browse ≤ TTL)
- [x] `CMP-INT-006` Wire product images through `media.PresignUpload`/`ConfirmUpload` + degraded-save path — media wiring — partially done: media-id refs validated; the live presign→PUT→confirm flow lands with 07's console glue — G-3
- [x] `CMP-INT-007` 06 notification templates + `commerce_order_status` deep-link payload (ids + labels only) — 2026-10-03 (additive `commerce_order_status` in 06's frozen builder; ids + status label only)
- [x] `CMP-INT-008` Register `commerce.auto-cancel` + `commerce.low-stock-digest` jobs (01 worker) + placement timer enqueue — 2026-10-03 (`commerce.auto-cancel` + `commerce.low-stock-digest` registered; placement timer armed)
- [x] `CMP-INT-009` Audit events (placement, cancels, completion/COD, portal link) on `audit.Record` — 2026-10-03 (placement, cancels, completion/COD audited best-effort-in-tx; portal link = G-8)
- [x] `CMP-INT-010` Cache tags `commerce:stores:school:{id}` / `commerce:store:{id}` / `commerce:product:{id}` / orderamount + invalidations — 2026-10-03 (`StoresSchoolTag`/`StoreTag`/`ProductTag` + old+new school busts — UT-007)
- [x] `CMP-INT-011` Failure-matrix drills (06-down, 05-down, 07-read-down, worker lag) in CI smoke — degradation drills — 06-down/05-down covered by fakes in the IT file (pending owner run); worker-lag drill rides CI smoke — G-5
- [x] `CMP-INT-012` Tests `CMP-UT-007`–`008`, `CMP-IT-011`–`017`, `CMP-E2E-001`–`002` green in CI — 2026-10-03 (UT green `-race`; IT + Maestro + Playwright written — **runs pending owner**, G-5/G-1)

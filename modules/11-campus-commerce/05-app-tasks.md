# Campus Commerce — App Tasks (Mobile)

**Module:** `11-campus-commerce`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) and
> `docs/tech-stack.md` (app table) are binding: tokens only, every user-facing string in Bengali +
> English, 360px-first layouts. Buyer surfaces only — vendors use the web portal (module `04`).

---

## 1. Screen Inventory

| # | Route (expo-router) | Screen | Access | Deep link source |
| --- | --- | --- | --- | --- |
| 1 | `/(tabs)/marketplace` | Marketplace home — **adds the "Store / স্টোর" section** (alongside 10's tutor section) | Verified (Pending → gate) | none (tab root) |
| 2 | `/(tabs)/marketplace/stores` | Store list — stores serving my school | Verified | store section tap |
| 3 | `/(tabs)/marketplace/stores/[id]` | Store page — vendor trust header + product grid | Verified | store list tap |
| 4 | `/(tabs)/marketplace/products/[id]` | Product detail — variant picker, qty, stock state, COD note | Verified | store grid tap |
| 5 | `/(tabs)/marketplace/checkout` | Checkout — fulfilment picker (pickup/courier), summary, place order | Verified | product CTA |
| 6 | `/(tabs)/marketplace/orders` | My orders — status chips, tracking when shipped | Verified | push `type=commerce_order_status` |
| 7 | `/(tabs)/marketplace/orders/[id]` | Order detail + pickup instructions + cancel | Verified | push `type=commerce_order_status` |

## 2. Screen Breakdown

### 2.1 Marketplace home Store section — `/(tabs)/marketplace`

**Layout (the Store block added under 10's tutor block)**

```text
┌──────────────────────────────── 360px ─┐
│ মার্কেটপ্লেস        [bn⇄en]   (header) │
│ (টিউটর সেকশন — মডিউল ১০)              │
│ ┌────────────────────────────────────┐ │
│ │ 🏪 স্কুলের স্টোর                    │ │ ← Store section
│ │ বই · ইউনিফর্ম · স্টেশনারি          │ │
│ │ আপনার স্কুলের অনুমোদিত দোকান       │ │
│ │               [ স্টোর দেখুন → ]    │ │
│ ├────────────────────────────────────┤ │
│ │ 📦 আমার অর্ডার (২)                 │ │ ← my orders entry (w/ active-count badge)
│ └────────────────────────────────────┘ │
│ [ Chat ][ Notices ][ AI Hub ][ Market ]│
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `StoreEntryCard` | Client | Entry to the store list; shows store count for my school when cached |
| `OrdersEntryRow` | Client | Active orders count badge (placed/confirmed/ready/shipped) |
| `VerifiedGate` | Client | Shared full-screen gate (module 10 pattern) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton cards; no blocking spinners |
| Pending verification | `VerifiedGate`: "অর্ডার করতে ভেরিফাইড অ্যাকাউন্ট প্রয়োজন / A verified account is required to order" + module 03 how-to |
| Error | Retry + support path; cached rows stay visible |
| Offline | Cached counts + offline banner; ordering refusable per §8 |

### 2.2 Store list + store page — `stores`, `stores/[id]`

**Store list (360px)**

```text
┌──────────────────────────────── 360px ─┐
│ ← স্টোর · ডেমো উচ্চ বিদ্যালয়           │
│ ┌────────────────────────────────────┐ │
│ │ [🖼] ডেমো স্টোর      ✓অনুমোদিত      │ │ ← approved badge (trust)
│ │ বই, ইউনিফর্ম ও স্টেশনারি           │ │
│ │ পিকআপ ও কুরিয়ার উভয়ই             │ │
│ └────────────────────────────────────┘ │
│ (empty) এখনো আপনার স্কুলের জন্য        │
│ কোনো স্টোর নেই / No stores for your    │
│ school yet                             │
└────────────────────────────────────────┘
```

**Store page**: vendor header (cover, name bn, approved badge, served-schools list — trust signals
per `CMP-US-005`), delivery note, category filter chips (বই/ইউনিফর্ম/স্টেশনারি), 2-col product grid:
image, bn name, ৳ price, stock state ("স্টক শেষ / Out of stock" label keeps the card visible,
button disabled).

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `StoreCard` | Client | List row: cover, name, approved badge, fulfilment chips |
| `VendorTrustHeader` | Client | Badge + schools served — never contact-first |
| `ProductGridCard` | Client | Stock-state aware; out-of-stock dims image only (label readable) |
| `CategoryChips` | Client | books/uniforms/stationery/other bn labels |

**States** — Loading: grid skeleton · Empty store grid: "পণ্য শীঘ্রই আসছে / Products coming soon" ·
Error: retry + cached rows.

### 2.3 Product detail — `products/[id]`

**Layout (360px, bn-first)**

```text
┌──────────────────────────────── 360px ─┐
│ ←  [🖼 image gallery (swipe)]          │
│ স্কুল ইউনিফর্ম সেট (ছেলে)             │
│ School uniform set (boys)   ✓অনুমোদিত │
│ ৳১,২০০ · ডেমো স্টোর                   │
│ সাইজ: (৩৮)(৩৯)(৪০ ✓)(৪২ ✕ স্টক শেষ)  │ ← variant picker; empty disabled+labelled
│ পরিমাণ: [ −  ১  + ]                    │ ← qty stepper 1–10
│ স্টক: কম (২টি বাকি)  · ঢাকায় কুরিয়ার  │ ← stock state + delivery note
│ ┌────────────────────────────────────┐ │
│ │ [ অর্ডার করুন — ৳১,২০০ ]          │ │ ← thumb-zone CTA (disabled when out)
│ └────────────────────────────────────┘ │
└────────────────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `ImageGallery` | Client | Swipe pager; degraded placeholder if a media object is missing |
| `VariantPicker` | Client | Chips; unavailable variants disabled + "স্টক শেষ" label; price updates ৳ |
| `QtyStepper` | Client | 1–10, accessible +/− with announced value |
| `StockStateLine` | Client | in stock / কম (few left) / স্টক শেষ — text + icon, never colour-only |

**States** — out-of-stock: CTA disabled w/ label (product stays visible — US-015) · `NOT_FOUND`
(store no longer serves my school): polite back-redirect · offline: cached detail, order CTA
refuses per §8.

### 2.4 Checkout — `checkout`

**Layout**

```text
┌──────────────────────────────── 360px ─┐
│ ← চেকআউট                              │
│ অর্ডার সারসংক্ষেপ                      │
│ · ইউনিফর্ম সেট (৪০) ×১    ৳১,২০০     │
│ · মোট                     ৳১,২০০     │
│ ডেলিভারি: (● পিকআপ) (○ কুরিয়ার)      │ ← fulfilment picker
│ পিকআপ ঠিকানা: ডেমো স্টোর, মিরপুর…    │ ← shown when pickup
│ — অথবা কুরিয়ার ফর্ম —                 │ ← recipient/phone/city/area/address
│ 💵 ক্যাশ অন ডেলিভারি (পিকআপ/ডেলিভারিতে)│ ← COD note; online "শীঘ্রই / soon"
│ ┌────────────────────────────────────┐ │
│ │ [ অর্ডার নিশ্চিত করুন ]            │ │
│ └────────────────────────────────────┘ │
└────────────────────────────────────────┘
```

Success: "অর্ডার জমা হয়েছে — নিশ্চিত হলে জানানো হবে / Order placed — you'll be notified once
confirmed" → navigate to the order screen. `OUT_OF_STOCK` → toast naming the item + product
refetch. COD-limit refusal → "৳৫,০০০-এর বেশি অর্ডারে অনলাইন পেমেন্ট লাগবে (শীঘ্রই) — অনুগ্রহ করে
অর্ডারটি ভাগ করুন / Orders above ৳5,000 will need online payment (coming soon) — please split the
order".

### 2.5 My orders + order detail — `orders`, `orders/[id]`

**Orders list**: cards with order_code, store name, first item +n, total ৳, status chip, tracking
number line when shipped ("কুরিয়ার: সুন্দরবন · ট্র্যাকিং: SB123456789"), cancel button in allowed
states only. **Order detail**: status timeline (chips below), items with snapshot prices ("যে দামে
অর্ডার হয়েছিল / price at order time"), fulfilment block, buyer note, cancel action, help link.

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `OrderStatusChip` | Client | জমা/নিশ্চিত/পিকআপের জন্য প্রস্তুত/পাঠানো হয়েছে/সম্পন্ন/বাতিল — placed/confirmed/ready_for_pickup/shipped/completed/cancelled (icon + text + colour) |
| `PickupInstructions` | Client | "অর্ডার কোড KSL-8F3K2 নিয়ে পিকআপের ঠিকানায় আসুন / Bring order code KSL-8F3K2 to the pickup address" + address + delivery note (US-009) |
| `TrackingLine` | Client | Courier + tracking number (manual courier — no link, OQ-3 copy) |
| `CancelAction` | Client | Confirm dialog (buyer: reason optional); hidden post-ship |
| `StatusTimeline` | Client | Placed → … → terminal; timestamps from the order |

**States** — `CONFLICT` on stale cancel: "অর্ডারের অবস্থা বদলেছে / Order status changed" + refetch ·
auto-cancelled: reason shown ("ভেন্ডর ২৪ ঘণ্টায় নিশ্চিত করেনি / vendor didn't confirm in 24 h") ·
offline: list from cache, actions refused per §8.

## 3. Forms & Input

| Field | Control | zod rule (per-app `src/schemas`) | Default | Conditional on |
| --- | --- | --- | --- | --- |
| `variantId` | chips | must be a stocked variant of the product | first stocked | product has variants |
| `qty` | stepper | 1–10 (`validation.commerce.qty_range`) | 1 | — |
| `fulfilment` | segmented | `fulfilment_invalid` | pickup | — |
| `recipientName` | input | 3–120 (`validation.commerce.address_name`) | buyer name | fulfilment=courier |
| `recipientPhone` | input (BD format) | E.164 (`validation.commerce.address_phone`) | buyer phone | courier |
| `city` / `area` / `addressLine` | inputs | 2–80 / 2–80 / 10–200 | school city hint | courier |
| `buyerNote` | multiline | ≤ 300 | — | both |
| `cancelReason` | dialog multiline | optional buyer-side, ≤ 500 | — | cancel |

Submission: same contract shape as the API · disable while pending · map field errors · never lose
input on error · keyboard-aware layout (submit stays reachable; address form scrolls).

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| List / detail read | TanStack Query → generated OpenAPI client → api; server cache per `06` §4 (`commerce:stores:school:{id}` etc.); query keys `['commerce','stores',schoolId]`, `['commerce','product',id]` |
| Order placement | **Never optimistic** (stock is server truth) → `POST /commerce/orders` → success navigates to the order; `OUT_OF_STOCK`/validation surface inline; offline → queued once (§8) |
| Cancel | Requires connectivity (money/stock action) — confirm dialog → `POST /commerce/orders/{id}/cancel` → refetch |
| Push | expo-notifications; `type=commerce_order_status` (orderId + status label only) → `/(tabs)/marketplace/orders/[id]`; unknown payloads ignored |
| Media (product images) | Read-only in app — served via 05/R2 URLs from product DTOs; no upload surface for buyers |

## 5. Motion Spec

| Element | Technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Order-placed success overlay | fade + check draw | placement confirmed | commitment made | instant overlay |
| Variant chip select | scale press (≤ 100 ms) + price tick | tap | selection updates price | colour swap only |
| Status timeline advance | step highlight move | refetch/push | order progress | static highlight |
| Store list/card press | press feedback ≤ 100 ms | tap | navigability | same |
| Stock-state change | label swap (no pulse) | refetch | honesty over urgency | same |

Keep motion purposeful and cheap (low-end Android): layout transitions and press feedback only.

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| 360px width (primary) | Single column; product grid 2-col with ≥ 44pt cards; checkout summary collapses to item count + total with an expander; primary action in the bottom thumb zone |
| ≥ 600px (tablet) | Store list + store page two-pane; product detail centred 480 px column |
| Low-end Android / 3G | Grid images compressed (R2 variants), paginated grid (20/page), skeleton loading, no blocking loads |
| Bengali content | Hind Siliguri everywhere; bn numerals for ৳ prices, qty and dates (`Intl`, locale `bn`); no clipped glyphs |

## 7. Accessibility

- [ ] Screen-reader labels on every interactive element; status chips announce label + timestamp
- [ ] Variant picker: unavailable options announced as "স্টক শেষ / out of stock", never silently disabled
- [ ] Stock state and trust badges = icon + text (never colour-only)
- [ ] Touch targets ≥ 44pt (stepper, chips, cancel); visible focus/press states
- [ ] Contrast meets WCAG AA against the themed background
- [ ] Motion: reduced-motion form verified
- [ ] Both languages verified on-device (bn default, en secondary)

## 8. Offline Behaviour

Browse is cached; money/stock actions need connectivity by design — except initial placement,
which queues exactly once with a loud banner (per module hint) and surfaces server verdicts on replay.

| Action offline | Queued? | Conflict rule on reconnect |
| --- | --- | --- |
| Browse stores/products/orders | Reads served from cache + offline banner | Refetch on reconnect |
| Place order | Yes — **once**, banner "অফলাইন — ইন্টারনেট চালু হলে জমা হবে / Offline — will submit when online" | Replay may return `OUT_OF_STOCK`/`VALIDATION_FAILED`/`CONFLICT` → item stays reviewable with input preserved; never silently lost, never double-submitted |
| Cancel order | No — refused with offline notice (money/stock action) | Retry manually when online |
| Review/act on a queued order result | After delivery | Success → order screen; failure → inline reason + edit |

## 9. Task Checklist

- [x] `CMP-AP-001` Marketplace home Store section + orders entry (`StoreEntryCard`, `OrdersEntryRow`, `VerifiedGate`) — 2026-10-03 (StoreEntryCard + OrdersEntryRow + VerifiedGate reuse)
- [x] `CMP-AP-002` Store list (school-scoped, empty state bn/en) — 2026-10-03 (school-scoped list, bn/en empty state)
- [x] `CMP-AP-003` Store page (VendorTrustHeader, category chips, ProductGrid w/ out-of-stock labels) — 2026-10-03 (approved badge header, category chips, grid with stock badges)
- [x] `CMP-AP-004` Product detail (ImageGallery, VariantPicker w/ availability, QtyStepper, StockStateLine) — 2026-10-03 (variant picker w/ announced out-of-stock, qty stepper 1–10, StockStateLine)
- [x] `CMP-AP-005` Checkout (fulfilment picker, courier address form, COD summary + limit copy, place order) — 2026-10-03 (fulfilment segmented, courier address form w/ zod, COD note + limit copy)
- [x] `CMP-AP-006` Order-placed success + `OUT_OF_STOCK`/COD-limit error surfaces — 2026-10-03 (placed overlay → order screen; OUT_OF_STOCK toast naming the item)
- [x] `CMP-AP-007` My orders list (status chips, tracking line, active badge) — 2026-10-03 (status chips, tracking line, orders entry)
- [x] `CMP-AP-008` Order detail (StatusTimeline, snapshot items, PickupInstructions, CancelAction) — 2026-10-03 (timeline, snapshot prices, pickup instructions, cancel in allowed states)
- [x] `CMP-AP-009` Push deep link `commerce_order_status` → order screen (06 payload) — 2026-10-03 (`deepLinkFor` additive entry `commerce_order_status` → orders/[id]; tested)
- [x] `CMP-AP-010` Offline queue for placement (once-only, banner, replay verdicts per §8) — 2026-10-03 (exactly-once queue + `replayPendingOrders` tested; persisted store lands with live wiring — G-4)
- [x] `CMP-AP-011` 360px pass: thumb-zone CTAs, 2-col grid, stepper/chips targets ≥ 44pt — 2026-10-03 (thumb-zone CTA, 2-col grid, ≥44pt stepper/chips)
- [x] `CMP-AP-012` Motion per §5 with reduced-motion variants — 2026-10-03 (press feedback + success overlay; reduced-motion = instant per 02 primitives)
- [x] `CMP-AP-013` bn/en strings `commerce.*` verified on-device; bn numerals for ৳ + dates — 2026-10-03 (`commerce.*` bn/en; bn numerals via Intl; parity tests green; on-device read rides Gate 1)
- [x] `CMP-AP-014` Maestro specs for `06` §9 (E2E-002) + a11y/reduced-motion pass — 2026-10-03 (`.maestro/commerce-golden-path.yaml` written — run pending owner, G-1)

# Campus Commerce — Frontend Tasks

**Module:** `11-campus-commerce`
**Status:** 📝 Spec drafted 2026-09-30
**Owner:** Rahul (product owner)
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Motion · RHF + Zod · TanStack Table + TanStack Query
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) is binding:
> tokens only from `packages/shared`, every user-facing string in Bengali + English, bn default.
> This module **fills module 07's `/vendor` shell** (nav/stubs were built in 07) and adds the
> `/admin/commission` stub slot.

---

## 1. Screen Inventory

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/vendor` | Vendor dashboard (replaces 07's approved-state stub): action counters, quick links | Dynamic | Vendor (approved) |
| 2 | `/vendor/storefront` | Storefront create/settings (schools served, pickup address, pause/resume) | Dynamic | Vendor (approved) |
| 3 | `/vendor/products` | Products list (TanStack Table: name, category, price ৳, stock, status) | Dynamic | Vendor |
| 4 | `/vendor/products/new` | Product create (bn/en names, category, price, images, variants) | Dynamic | Vendor |
| 5 | `/vendor/products/[id]` | Product edit + archive | Dynamic | Vendor |
| 6 | `/vendor/inventory` | Inventory manager (inline stock edit, low-stock highlight, reserved column) | Dynamic | Vendor |
| 7 | `/vendor/orders` | Fulfilment board (status columns/queue + action dialogs) | Dynamic | Vendor |
| 8 | `/vendor/orders/[id]` | Order detail (snapshot items, buyer, fulfilment, timeline) | Dynamic | Vendor |
| 9 | `/admin/commission` | Super Admin commission report **stub** (ships with 12/07 revenue) | Dynamic | Super Admin |

Access rule: 07's `/vendor` shell gate stays (`GET /vendor/state`); this module renders real screens
only for `approved` vendors — pending/rejected/suspended keep 07's state cards.

## 2. Screen Breakdown

### 2.1 Vendor dashboard — `/vendor`

**Layout**

```text
≥1024                                768–1023 (drawer nav)
┌──────────┬─────────────────────┐   ┌──────────────────────────┐
│ sidebar  │ স্টোর: ডেমো স্টোর [সক্রিয়]│   │ topbar + status chip     │
│ Dash·    ├─────────────────────┤   ├──────────────────────────┤
│ Storefront│ [৪ অর্ডার অ্যাকশন দরকার] │   │ action cards stacked     │
│ Products │ [২ স্টক কম] [৩ নতুন]   │   ├──────────────────────────┤
│ Inventory│ quick links grid     │   │ quick links 2-col        │
│ Orders   │ (products/inventory/ │   └──────────────────────────┘
│          │  orders/storefront)  │
└──────────┴─────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `StoreStatusChip` | Client | সক্রিয়/বিরতি — active/paused; pause/resume action inline |
| `ActionCard` ×3 | Server (counters) | Orders needing action (placed), low stock, completed 30 d — links to the board/inventory |
| `QuickLinkGrid` | Server | Products / inventory / orders / storefront settings |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton counters matching card layout |
| Empty (no storefront) | "প্রথমে একটি স্টোরফ্রন্ট তৈরি করুন / Create your storefront first" + CTA to `/vendor/storefront` |
| Error | Boundary with retry + request id |
| Suspended vendor | 07's state card (reason shown) — no screens |

### 2.2 Storefront settings — `/vendor/storefront`

**Layout** — create mode is a centred panel form; edit mode shows the same form + a status bar
(active/paused toggle) + schools-served checklist + danger-free pause (never delete while orders are
open — deletion is out of scope this module).

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `StorefrontForm` | Client (RHF) | nameBn (required) / nameEn tabs, description, pickup address, delivery note |
| `SchoolsPicker` | Client | Checkbox list from 04 catalog (`GET /hierarchy/schools`); ≥ 1 required; shows school count chip |
| `PauseDialog` | Client | Explains "ব্রাউজ থেকে সরে যাবে; চলমান অর্ডার স্বাভাবিক থাকবে / hidden from browse; running orders continue" |

**States** — `VALIDATION_FAILED` maps `validation.commerce.*` to fields; pause/resume toast +
refetch; unsaved-changes guard.

### 2.3 Products list + create/edit — `/vendor/products`, `/vendor/products/new`, `/vendor/products/[id]`

**List**: TanStack Table — image thumb, name (bn first), category chip, price ৳ (tabular figures),
available stock (on hand − reserved), status (active/archived); row → edit; "নতুন পণ্য / New
product" primary button. **Create/edit**: two-column ≥1024 (form + live preview card), stacked
<1024. Fields: name bn (required)/en, description, category select, price ৳, images (≤ 5, via 05
presign → PUT R2 → confirm; first = primary; drag to reorder), variants repeater (name, price
delta ±৳, sku) — each variant auto-creates its stock row shown in `/vendor/inventory`.

| Component | Server/Client | Notes |
| --- | --- | --- |
| `ProductTable` | Client (TanStack Query) | Filter by category/status; stock column colour + text label |
| `ProductForm` | Client (RHF) | Zod mirrors `validation.commerce.*`; bn-first tabs |
| `ImageUploader` | Client | 05 media flow; blocks submit while upload pending **unless** "ছবি ছাড়া সংরক্ষণ / save without images" chosen (degraded-save warning, US-002) |
| `VariantsRepeater` | Client | Price delta shown as ±৳; removing a variant warns it disappears from the picker |

**States** — archived banner on edit ("সংরক্ষণাগারে — ক্রেতা কিনতে পারবে না / Archived — not
purchasable") + restore action; `CONFLICT` on double-save refetches.

### 2.4 Inventory manager — `/vendor/inventory`

**Layout** — TanStack Table grouped by product: variant, on hand (inline number input + save),
reserved (read-only, explained "অর্ডারে সংরক্ষিত / held by orders"), available, reorder level;
low-stock rows highlighted amber with text "স্টক কম / Low stock" (never colour-only). Bulk note:
no auto purchase orders at launch — "স্টক কেনার কাজ ম্যানুয়াল / restocking is manual" hint.

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `InventoryTable` | Client (TanStack Query, poll 60 s) | Inline edit commits on blur/Enter; server validates ≥ reserved |
| `LowStockBadge` | Client | Amber + text; digest note ("প্রতিদিন সকাল ৭টায় রিপোর্ট / daily 7 am report") |

**States** — stock edit below reserved → inline field error (`validation.commerce.qty_invalid`);
offline → edits refused with offline notice (money/stock surfaces need connectivity).

### 2.5 Orders fulfilment board — `/vendor/orders`, `/vendor/orders/[id]`

**Layout**

```text
≥1024: columns নতুন (placed) → নিশ্চিত (confirmed) → প্রস্তুত/পাঠানো → সম্পন্ন | বাতিল
<1024: status filter tabs + stacked order cards (same data)
Card: order_code · buyer name+school · items n · total ৳ · fulfilment chip (পিকআপ/কুরিয়ার)
      actions: [নিশ্চিত করুন] placed · [প্রস্তুত]/[পাঠানো…] confirmed · [সম্পন্ন] ready/shipped · [বাতিল]
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| `OrderBoard` | Client (TanStack Query, poll 30 s) | Status columns (board ≥1024) / tabs (<1024); counts per column |
| `ShipDialog` | Client | courier name + tracking number (both required, zod); explains buyer sees the tracking number |
| `CancelDialog` | Client | Reason required ≥ 5 chars (vendor); shows restock consequence ("স্টক ফেরত যাবে / stock returns") |
| `OrderDetailDrawer`/page | Client | Snapshot items (as ordered — "যে দামে অর্ডার হয়েছিল / price at order time"), buyer contact, address or pickup note, commission row, status timeline |

**States** — `CONFLICT` (buyer cancelled meanwhile) → toast "অর্ডারটি ইতিমধ্যে বাতিল / Order was
already cancelled" + row refetch; empty column → "কোনো অর্ডার নেই / No orders"; auto-cancelled rows
show system reason.

### 2.6 Commission stub — `/admin/commission`

07 `StubRoute` pattern: icon + "কমিশন রিপোর্ট মডিউল ১২-এর সাথে আসছে / Commission report ships with
module 12" + the model note (ডিফল্ট ৫%, `brd.md` §7-এর ৫–১০% ব্যাপ্তি) — no invented figures. Nav
entry added to the Super Admin sidebar by this module (07 owns the shell).

## 3. Forms

| Field | Control | Zod rule | Default | Conditional on |
| --- | --- | --- | --- | --- |
| Storefront `nameBn`/`nameEn` | text inputs (tabs) | `validation.commerce.name_bn_required` · `name_length` | — | — |
| `schoolIds` | checkbox list | ≥ 1, ≤ 50 (`schools_required`) | none | — |
| `pickupAddress` / `deliveryNote` | textarea | 10–300 / ≤ 300 | — | — |
| Product `nameBn`/`nameEn`, `category`, `priceBdt` | inputs/select | `name_bn_required` · `category_invalid` · `price_range` | category=books | — |
| `imageMediaIds` | uploader | ≤ 5 confirmed (`images_invalid`) | [] | degraded-save allowed w/ warning |
| Variant `name` / `priceDelta` / `sku` | repeater inputs | `variant_name_invalid` · `price_delta_range` · `sku_invalid` | delta=0 | — |
| Inventory `qtyOnHand` / `reorderLevel` | inline numbers | `qty_invalid` (≥ reserved, ≥ 0) | current value | — |
| Ship `courierName` / `trackingNumber` | dialog inputs | `courier_required` · `tracking_required` | — | courier orders only |
| Cancel `cancelReason` | dialog textarea | 5–500 (`cancel_reason_required`) | — | vendor cancel |

Submission: same Zod schema on the server (Route Handler re-validation) · disable while pending ·
map `fields` errors to inputs · never lose input · unsaved-changes guard on all vendor forms.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Portal reads (dashboard/board/inventory/products) | Server Component first paint → TanStack Query hydration (board polls 30 s, inventory 60 s) via generated `openapi-fetch` → api |
| Browse-side reads (none in web this module) | N/A — buyer surfaces live in the app only |
| Mutation | Server Action / Route Handler → generated client → api → toast + query invalidation (board, inventory, storefront) |
| Product images | Client → `POST /media/upload-url` (05) → PUT R2 → `POST /media/{id}/confirm` → attach ids on product save |
| Vendor identity | 07 shell gate `GET /vendor/state`; portal-user link happens at first approved login (api-side) |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Board column advance | 200 ms fade/slide of the moved card | status action | progress through fulfilment | instant move |
| Order-placed/success toast | slide-in 150 ms, auto-dismiss 4 s | mutation result | feedback | fade only |
| Low-stock highlight | static amber tint + label | threshold crossed | urgency without motion | same |
| Dialog/sheet | scale-fade 150 ms | ship/cancel/pause | context switch | instant |
| Skeleton shimmer | 1.2 s loop | loading | data arriving | static grey blocks |

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 | ≥ 1024 |
| --- | --- | --- | --- |
| Vendor portal | degraded single column: sidebar → drawer, tables/boards → stacked cards + tabs | drawer nav, boards → tabs, tables scroll-x | fixed sidebar + board columns |
| Tables (products/inventory) | card-stack rows (label: value) | horizontal scroll, sticky first column | full table |
| Forms | single column | centred panel 560 px | two-column with live preview |
| Order detail | full-screen page | drawer | drawer |

## 7. Accessibility

- [ ] Landmarks, one `h1`, heading order per screen
- [ ] Keyboard path complete; focus visible and never lost; focus moved into dialogs, restored on close
- [ ] TanStack tables keyboard-complete (arrow navigation, row actions, aria-rowcount); inline stock edit reachable by keyboard
- [ ] Status/stock/low-stock never colour-only (icon + bn/en text)
- [ ] Labels, descriptions, error announcements (`aria-live` on form errors + toasts)
- [ ] `<html lang>` flips bn/en; Bengali never rendered in Inter; ৳ figures use tabular numerals
- [ ] Motion: reduced-motion variant verified per §5
- [ ] axe (Playwright) clean on `/vendor/*` and `/admin/commission`

## 8. Design-System Compliance

`docs/design-reference/README.md` usage rules hold: tokens only (no raw hex), deep-teal primary
CTAs, Hind Siliguri for all Bengali, Inter for Latin/numerals (tabular figures for prices/stock),
swoosh-gray never used as text colour. Every string verified in bn + en via the CI catalog parity
gate — namespaces `vendor.*` (extended with commerce keys) and `admin.*` added to module 02's
whitelist (additive, parity-gated); new namespace `commerce.*` for shared buyer/seller vocabulary.

## 9. Task Checklist

- [ ] `CMP-FE-001` `/vendor` role screens unlocked for approved vendors (07 shell integration, state cards kept for others)
- [ ] `CMP-FE-002` Vendor dashboard (counters, quick links, storefront status chip + pause/resume)
- [ ] `CMP-FE-003` Storefront create/settings (SchoolsPicker, pickup address, PauseDialog)
- [ ] `CMP-FE-004` Products list (TanStack Table, filters, stock column)
- [ ] `CMP-FE-005` Product create/edit (ProductForm, bn-first tabs, variants repeater, archived banner + restore)
- [ ] `CMP-FE-006` `ImageUploader` (05 presign → PUT → confirm) + degraded "save without images" warning path
- [ ] `CMP-FE-007` Inventory manager (inline edit, reserved column, low-stock highlight, digest note)
- [ ] `CMP-FE-008` Orders fulfilment board (columns/tabs, polls, action buttons)
- [ ] `CMP-FE-009` `ShipDialog` (courier + tracking, required-field validation)
- [ ] `CMP-FE-010` `CancelDialog` (reason, restock consequence copy) + `CONFLICT` refetch handling
- [ ] `CMP-FE-011` Order detail (snapshot items, buyer, fulfilment, commission row, timeline)
- [ ] `CMP-FE-012` `/admin/commission` stub (07 StubRoute pattern) + Super Admin nav entry
- [ ] `CMP-FE-013` Portal-user linking UX (first approved login → link confirmation state)
- [ ] `CMP-FE-014` Responsive pass per §6 (drawer nav, board→tabs, table→cards)
- [ ] `CMP-FE-015` Motion per §5 with reduced-motion variants
- [ ] `CMP-FE-016` bn/en catalog keys (`vendor.commerce.*`, `admin.commission.*`, `validation.commerce.*`) + parity gate green + axe suite

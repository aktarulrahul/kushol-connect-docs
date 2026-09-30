# Payments — App Tasks (Mobile)

**Module:** `12-payments` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` (palette, Hind Siliguri + Inter, logo rules) and
> `docs/tech-stack.md` (app table) are binding: tokens only, every user-facing string in Bengali +
> English, 360px-first layouts.

---

## 1. Screen Inventory

| # | Route (expo-router) | Screen | Access | Deep link source |
| --- | --- | --- | --- | --- |
| 1 | `/(tabs)/marketplace` → "ফি পরিশোধ / Pay fees" entry | Payments home entry | Verified (guardian/student) | none (tab) |
| 2 | `/payments` | Invoice list — due / paid, ৳ amounts | Verified | Marketplace entry |
| 3 | `/payments/[invoiceId]` | Pay screen — gateway chooser + amount breakdown | Verified (entitled payer) | fee-due push (`payments.feeDue`), list tap |
| 4 | `/payments/status/[txnId]` | Return/status screen — poll → success/failure | Verified (payer) | gateway callback 302, push |
| 5 | `/receipts/[txnId]` | Receipt view/share (PDF) | Verified (payer / school admin) | payment-result push (route frozen with 06 §2.4), status screen |

## 2. Screen Breakdown

### 2.1 Invoice List — `/payments`

**Layout**

```text
360px ─ bn first
┌──────────────────────────────┐
│ ফি পরিশোধ            ⚙ bn/en  │
│ [বকেয়া ▾] [পরিশোধিত ▾] tabs    │
│ ┌──────────────────────────┐ │
│ │ টিউশন ফি — সেপ্টেম্বর        │ │
│ │ শ্রেণি ৬ · কারণত: ৩০ সেপ্টেম্বর   │ │
│ │ ৳১,২৫০.০০      [পে করুন] │ │
│ ├──────────────────────────┤ │
│ │ পরীক্ষার ফি — ✓ পরিশোধিত    │ │
│ │ ৳৪৫০.০০        [রসিদ]    │ │
│ └──────────────────────────┘ │
└──────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `InvoiceCard` | Client (TanStack Query → generated client) | due badge (bn: "বকেয়া" / overdue: "মেয়াদ উত্তীর্ণ"), paid badge, ৳ via `Intl` bn digits |
| `PayButton` / `ReceiptLink` | Client | pay → `/payments/[invoiceId]`; receipt → `/receipts/[txnId]` |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton cards; no blocking spinners |
| Empty | "কোনো বকেয়া ফি নেই 🎉" / "No fees due 🎉" (paid tab: "এখনও কোনো পেমেন্ট নেই" / "No payments yet") |
| Error | Retry + support path; never a blank screen |
| Offline | Banner "আপনি অফলাইনে আছেন — পেমেন্টের জন্য ইন্টারনেট প্রয়োজন" / "You're offline — payments need connectivity"; list shows cached read; Pay disabled |

### 2.2 Pay Screen — `/payments/[invoiceId]`

**Layout**

```text
360px
┌──────────────────────────────┐
│ ← টিউশন ফি — সেপ্টেম্বর          │
│ পরিমাণ হিসাব / Amount breakdown │
│   ফি:            ৳১,২৫০.০০    │
│   সুবিধা ফি:        ৳১৫.০০     │
│   ──────────────────────      │
│   মোট:           ৳১,২৬৫.০০    │
│ পেমেন্ট মাধ্যম বাছুন / Choose:  │
│ ┌──────────────────────────┐ │
│ │ [SSLCommerz]  কার্ড/ব্যাংক │ │
│ │ [bKash]        মোবাইল ওয়ালেট│ │
│ │ [Nagad]        মোবাইল ওয়ালেট│ │
│ └──────────────────────────┘ │
│ (gateway names = logos-as-text placeholders) │
│ [ পেমেন্ট করুন / Pay now ]      │
│ সুরক্ষা: কার্ডের তথ্য আমরা দেখি না │
└──────────────────────────────┘
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| `AmountBreakdown` | Client | fee + convenience fee (BDT 15, `PAY-BR-008`) = total; bn/en labels |
| `GatewayChooser` | Client | radios; down gateway hidden (health flag from initiate errors); logos-as-text placeholders until brand assets exist |
| `PayNow` | Client | calls `POST /payments/initiate` → opens `redirectUrl` via `expo-web-browser` (in-app browser) |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton breakdown |
| Forbidden | bn: "এই ইনভয়েস পরিশোধের অনুমতি আপনার নেই" / en: "You're not allowed to pay this invoice" + support path |
| Paid/void already | bn: "এই ইনভয়েস ইতিমধ্যে পরিশোধিত/বাতিল" + receipt or office note (`PAY-US-012`) |
| Gateway error (`PAYMENT_FAILED`) | bn: "পেমেন্ট গেটওয়ে সাময়িকভাবে অচল — কিছুক্ষণ পর আবার চেষ্টা করুন" / en: "Payment gateway temporarily unavailable — please try again shortly"; other gateways remain |
| Offline | Payment requires connectivity — refused up front with the §2.1 banner copy; nothing queued |

### 2.3 Status Screen — `/payments/status/[txnId]`

```text
360px
┌──────────────────────────────┐
│        ◠◌◠ (spinner)          │
│ পেমেন্ট প্রসেসিং — আমরা জানাবো   │
│ Payment processing — we'll    │
│ notify you                    │
│ [হোমে ফিরুন / Back home]      │
└──────────────────────────────┘
→ success: ✓ পেমেন্ট সফল + [রসিদ দেখুন]
→ failure: ✗ পেমেন্ট ব্যর্থ + [আবার চেষ্টা করুন]
```

Poll `payments.InvoiceStatus` every 3 s ×20 → settle to the "we'll notify you" state (webhook + push is the guaranteed path, `PAY-US-005`). Success → receipt link (`/receipts/[txnId]`, share via system sheet + PDF). Failure → retry re-enters §2.2.

### 2.4 Receipt — `/receipts/[txnId]`

Summary card (school name, serial no, student, title, ৳ amount + fee, gateway, date) + "রসিদ (PDF)" / "Receipt (PDF)" button → immutable R2 URL (via api) → system viewer/share. bn: "ফি পরিশোধ রসিদ" / en: "Fee payment receipt". Receipt not yet generated → bn: "রসিদ তৈরি হচ্ছে…" with retry (`PAY-US-014`).

## 3. Forms & Input

| Field | Control | zod rule (from `packages/shared`) | Default | Conditional on |
| --- | --- | --- | --- | --- |
| Gateway | radio group | `validation.payments.gateway` | SSLCommerz (first) | — |
| (No amounts editable by payers — display only) | — | — | — | — |

Submission: initiate is a button, not a form; disable while pending; errors mapped from RFC-7807 codes (`CONFLICT` → already-paid state; `PAYMENT_FAILED` → gateway-unavailable state); never lose context on error; keyboard never covers the pay button (no text inputs on this flow — safe by construction).

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Invoice list / detail read | TanStack Query → generated OpenAPI client → api; cache key `payments:invoices:{userId}` (30 s TTL, refetch-on-focus) — declared in `06` §4 |
| Initiate (mutation) | No optimistic state — money: button → spinner → browser open; rollback = error state with retry |
| Status poll | TanStack Query `refetchInterval` 3 s ×20 on the status screen |
| Push | expo-notifications: fee-due → `/payments/[invoiceId]`; `payment_result` → `/receipts/{txnId}` (06 §2.4 map); tap = deep-link, content fetched after auth |
| Gateway redirect | `expo-web-browser` in-app session; return lands on the callback 302 → app link → `/payments/status/[txnId]` |
| Receipt PDF | api returns the immutable R2 URL → `expo-web-browser`/Sharing for view/share |

## 5. Motion Spec

| Element | Technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| Pay button press | scale 0.98, 120 ms | touch | tap registered | static |
| Status spinner | rotation | poll active | work in progress | static "processing" label + dot pulse |
| Success state | banner fade-in 200 ms | terminal success | done | instant |
| List refresh | native pull-to-refresh | user | freshness | same (platform behaviour) |

Keep motion purposeful and cheap (low-end Android): layout transitions and press feedback only, unless the module's `02` §7 says otherwise.

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| 360px width (primary) | Single column, thumb-reachable actions; wireframes above are the contract |
| ≥ 600px (tablet) | Centred column (max-w-md); no two-pane needed for a linear pay flow |
| Low-end Android / 3G | Polling stops after 20 tries; lists paginated 20/page; no image assets on the pay path (logos-as-text) |
| Bengali content | Hind Siliguri renders; ৳ amounts in bn digits via `Intl("bn")`; no clipped glyphs; `locale="bn"` default |

## 7. Accessibility

- [ ] Screen-reader labels on every interactive element (gateway radios announce fee+total); meaningful reading order
- [ ] Touch targets ≥ 44pt; visible focus/press states
- [ ] Contrast meets WCAG AA against the themed background (badges included)
- [ ] Motion: reduced-motion form verified (§5)
- [ ] Both languages verified on-device (bn default, en secondary)

## 8. Offline Behaviour

Payments require connectivity by design — money actions are never queued silently.

| Action offline | Queued? | Conflict rule on reconnect |
| --- | --- | --- |
| Open invoice list | n/a — cached read shown with offline banner | refetch on reconnect |
| Tap Pay / initiate | **No — refused up front** with bn/en connectivity message | user retries manually |
| Poll status | No | resumes when online; push is the backstop |
| View receipt (already cached URL) | n/a | — (PDF needs network to fetch if not cached) |

## 9. Task Checklist

- [ ] `PAY-AP-001` Marketplace "ফি পরিশোধ / Pay fees" entry + `/payments` invoice list (due/paid tabs, ৳ bn digits)
- [ ] `PAY-AP-002` `/payments/[invoiceId]` pay screen — amount breakdown (fee + BDT 15 convenience fee) + gateway chooser (logos-as-text)
- [ ] `PAY-AP-003` `expo-web-browser` redirect flow + return handling into `/payments/status/[txnId]`
- [ ] `PAY-AP-004` Status screen — poll ×20 → success/failure/pending states (bn+en copy above)
- [ ] `PAY-AP-005` `/receipts/[txnId]` — summary card + PDF view/share; "generating" state
- [ ] `PAY-AP-006` Push deep-link wiring: fee-due → pay screen; `payment_result` → receipt (06 map)
- [ ] `PAY-AP-007` Error states: `FORBIDDEN`, `CONFLICT` (already paid → receipt), `PAYMENT_FAILED` (gateway down, chooser hides it)
- [ ] `PAY-AP-008` Offline handling: banner + Pay refused (never queued)
- [ ] `PAY-AP-009` Own transactions entry point in Settings/Marketplace (`GET /payments/transactions`)
- [ ] `PAY-AP-010` 360px bn-first layout pass on all five screens (wireframes above)
- [ ] `PAY-AP-011` Reduced-motion + touch-target + contrast passes
- [ ] `PAY-AP-012` Maestro golden path: fee-due push tap → pay screen → gateway chooser → status screen states (sandbox gateway)

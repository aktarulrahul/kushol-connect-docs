# Payments — Technical Document

**Module:** `12-payments` · **Version:** 0.1 · **Status:** 📝 Draft 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Single engineer-facing reference compressing the six spec files in this folder (`01-user-stories.md` … `06-integration-tasks.md`). If this document drifts, the spec files win and this file gets corrected.

---

## 1. Overview

### 1.1 Purpose

Turns fee collection from cash-in-an-envelope into a trust-first digital flow: School Admins issue fee invoices (single or bulk to a section), guardians and students pay through SSLCommerz/bKash/Nagad from a push-notification deep link, and every successful payment lands as verified webhook → idempotent ledger entries → auto-generated PDF receipt. Serves `prd.md` **§5.4** (fee collection, deep links, receipts, ledger) and the **§7** FinTech revenue stream, and fills the `/school` ledger stub left by module 07.

### 1.2 Scope

**In:** `fee_invoices`, `payment_transactions`, `ledger_entries` (append-only), `payment_receipts`, `gateway_events` — defined and owned here · invoice issue (single + bulk-by-section, ≤200 per batch), void-before-payment, overdue sweep · payment initiation for invoices and online partner orders (11 seam) via SSLCommerz, bKash, Nagad (gateway-hosted pages) · webhook ingestion with signature verification + idempotency (`UNIQUE(gateway, gateway_txn_id)`); browser/app callback as UX-only return path · ledger entries per success (fee_payment + convenience_fee split; commission for orders), manual refunds as `adjustment` entries · PDF receipt generation (job) → R2 via 05 → deep-linked push · school ledger dashboard + reconciliation report data · bn/en catalogs `payments.*`.

**Out:** order/cart/fulfilment logic (11 owns orders; 12 only attaches `payment_transaction_id` per 11's seam) · recurring subscriptions (Kushol Pro billing — 08/13, priced later) · gateway wallet onboarding/KYC · automatic gateway refunds (manual adjustment entries at launch) · auto-debit/standing instructions · invoice line-item breakdowns (single amount per invoice) · settlement-file auto-fetch (manual CSV import at launch — `TODO: Confirm` format).

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 01 foundations | `jobs.Enqueue`/`Register` (receipt, reconcile, sweeps, notify fan-out), `audit.Record` (every money mutation — failure aborts the mutation), RFC-7807 envelope |
| consumes | 03 identity-access | Auth chain, roles, verification status, guardian↔student link (03 `guardians.IsGuardianOf` / `LinkedStudents`), `users.locale` |
| consumes | 04 organization-hierarchy | `hierarchy.ResolveUserNodes` (school scoping; section→student resolution for bulk invoices) |
| consumes | 05 communication-engine | `media.PutObject` (receipt PDFs → R2; declared in 05 `06` §2) |
| consumes | 06 notifications | `notify.SendToUser` — fee-due push w/ deep link; payment-result push → receipt |
| consumes | 07 command-center-web | The `/institution/ledger` nav stub (`WEB-FE-025`) this module fills |
| consumes | 11 campus-commerce | `commerce.OrderAmount(orderId)` + the `payment_transaction_id` attach seam (defined in 11's spec) |
| consumed by | 07 dashboards | `payments.InitiateInvoicePayment` / `InvoiceStatus` / `TransactionSummary` exports feed ledger cards, collect shortcuts and the transaction drawer — no new tables |
| consumed by | 11 checkout | `POST /payments/initiate {orderId}` + `payments.TransactionSummary` for order→payment display; fallback to COD when 12 is down |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| api | Go 1.24+ · chi · `PaymentGateway` interface + SSLCommerz/bKash/Nagad adapters · sqlc + pgx · PostgreSQL (Neon) · Redis (idempotency fast-path) · in-DB job table + 01 worker | Server-side HTTP to gateways — no SDKs in clients; webhook signature pipeline; append-only ledger | `tech-stack.md` Payments row: server-side HTTP integrations, webhook signature verification, idempotent ledger |
| contracts | OpenAPI 3.1 (`applications/api/openapi/`) | single source for Go server types + TS clients; webhook route flagged `security: []` + webhook marker | gateway payload shapes versioned **internally** per adapter (stable event model v1) |
| web | Next.js App Router · Server Components/Actions · TanStack Table + Query · RHF + zod | `/institution/ledger` + invoice forms + reconciliation — all money reads `no-store` | fills 07's stub |
| app | Expo · expo-router · TanStack Query · `expo-web-browser` (in-app gateway view) | invoice list, pay screen, status poll, receipt view/share | `expo-web-browser` is the only new dep — small, EAS-compatible |
| web + app (per app) | each app's `src/i18n` bn/en catalogs + zod schemas | `payments.*` / `validation.payments.*` keys ("বকেয়া ফি", "পেমেন্ট সফল", "ফি পরিশোধ রসিদ") | bn default |
| security stance | Gateway-hosted checkout only | **No card/wallet data ever touches our servers** — no PAN/CVV/token storage anywhere; SAQ-A-level scope (`02` §6/§10) | gateways own fraud/liability |

---

## 3. Architecture

### 3.1 Component diagram

```text
app payer (Expo) ──┐                                     ┌─► 03 auth chain (roles, verification, guardian link, locale)
web admin (Next.js)┴─► chi REST /api/v1/school·payments/* ─┼─► 04 hierarchy.ResolveUserNodes (school scope, section rosters)
                        │  ▲                                ├─► 05 media.PutObject (receipt PDFs → R2)
                        │  └─ POST /payments/callback/{gateway} (UX only — status check + 302) ► 06 notify.SendToUser (fee-due, payment-result)
                        ▼
       payments service (PAY-BE-001–014) ── 11 seam: commerce.OrderAmount + attach hook
                        │  sqlc + pgx → PostgreSQL/Neon
 fee_invoices · payment_transactions · ledger_entries (append-only) · payment_receipts · gateway_events
                        │
  PaymentGateway adapters (sslcommerz | bkash | nagad): Initiate / VerifyWebhook / FetchStatus (HTTPS, 15 s)
                        ▲                               └─► 01 jobs: receipt.generate · invoice.notify ·
  POST /webhooks/{gateway} (server-to-server — AUTHORITATIVE, signature-verified, idempotent)    payments.reconcile · overdue_sweep · expire
```

### 3.2 Boundary

**Owns (tables / services):** `fee_invoices`, `payment_transactions`, `ledger_entries`, `payment_receipts`, `gateway_events`; the `PaymentGateway` adapter registry; webhook verification middleware; jobs `receipt.generate`, `invoice.notify`, `payments.reconcile`, `payments.overdue_sweep`, `payments.expire`.

**Reads (via exported service functions only):** 03 auth/verification/locale (never re-checks credentials) · 04 tenant scope + rosters · 05 `media.PutObject` (additive) for receipts · 06 push fan-out · 11 `commerce.OrderAmount` (amounts never re-computed here; 11 owns attaching `payment_transaction_id`) · 01 job runtime + audit. Cache-tag contract in `06` §4.

### 3.3 Request / data flows

```text
1 · Initiate → gateway redirect
    payer taps fee-due deep link → POST /payments/initiate {invoiceId | orderId, gateway}
      (verified + entitled payer; gateway health-flagged up; amount = invoice row or commerce.OrderAmount)
      → txn created initiated→redirected → RedirectPayload{redirectUrl,…} → app opens it in expo-web-browser
2 · Webhook (AUTHORITATIVE) + callback (UX)
    gateway → POST /webhooks/{gateway} — the ONE unauthenticated-but-signature-verified route:
      rate limit (payments class, 120/min/gateway) → signature + timestamp replay-window verification
      → only then parse. Valid: gateway_events row (digest + summary) + one tx =
        txn→success + balanced ledger entries + invoice→paid / 11-attach + audit + receipt job enqueue
      duplicate replay → 200 {"processed":false,"reason":"DUPLICATE_WEBHOOK"}, zero side effects
      invalid/tampered/replayed-window → 403 + flagged gateway_events row + alert log (ids only)
    browser returns → POST /payments/callback/{gateway} — UX only: single FetchStatus check, apply terminal
      state if the webhook hasn't, then 302 → /payments/status/{txnId} (app polls InvoiceStatus 3 s ×20)
3 · Ledger + receipt
    fee success ⇒ ledger_entries: fee_payment (credit amount, school) + convenience_fee (credit fee, platform)
      — balanced in the same tx (INV-2); order success ⇒ commission entry
    receipt.generate job: PDF (bn/en per school locale) → 05 media.PutObject → R2 → serial {SCHOOL-YY}-{seq}
      (pg_advisory_xact_lock per school) → push "পেমেন্ট সফল / Payment successful" → /receipts/{txnId};
      R2 down ⇒ job retries with backoff — payment/ledger already final, receipt late, never lost
4 · Failure / expiry backstops
    payments.expire (every 10 min): stale initiated|redirected > 30 min → expired; push retry link; invoice stays issued
    payments.overdue_sweep (daily 00:05): issued ∧ due_date < today → overdue
    payments.reconcile (daily 06:00): ledger vs imported settlement CSV; invariant check
      sum(fee_payment credits) == sum(success txn amounts) per school; mismatch list flagged
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| invoice | draft · issued · paid · partially_paid · void · overdue | draft→issued (admin of same school; bulk issue same step; audit + notify job) · issued→paid (exactly one success txn; balanced ledger in tx) · issued→void (zero successful txns only, else `CONFLICT`; audit w/ reason) · issued→overdue (sweep: due date passed ∧ unpaid); amount/title/student immutable after issue (INV-5) |
| transaction | initiated · redirected · success · failed · expired · refunded | initiated→redirected (payer verified + entitled; gateway up) · redirected→success (signature-verified webhook/callback; idempotency key free — ledger + attach + receipt job + push) · redirected→failed/expired (gateway report or expire sweep; retry starts a fresh txn, no stale session reuse) · success→refunded (manual Super/School-Admin adjustment only, no gateway auto-refund); success is terminal — re-webhooks are no-ops |

---

## 4. Data Model (summary)

Mirror of `03-backend-tasks.md` §1 — column detail stays there.

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `fee_invoices` | School's money demand on one student: title, kind (tuition/exam/transport/other), `amount_bdt numeric(12,2)`, due date, status, issuer | **tenant column** `school_id` | `(school_id,status,due_date)` (ledger tab + overdue sweep) · `(school_id,student_id,status)` · `(student_id)` | CHECKs on kind/status/amount > 0; amount immutable after issue |
| `payment_transactions` | One gateway attempt: invoice xor order target, gateway + `gateway_txn_id`, amount + convenience fee, status, payer | `school_id` denormalized (from invoice/order); scoped transitively via payer/admin visibility | **UNIQUE `(gateway, gateway_txn_id)`** (idempotency core) · `(invoice_id)` · `(order_id)` · `(payer_id,created_at DESC)` · `(school_id,status,created_at DESC)` · partial stale for the expire sweep | CHECK exactly one of invoice_id/order_id; convenience_fee 0 for order payments |
| `ledger_entries` | Append-only double-side money journal: fee_payment, convenience_fee, commission, payout, adjustment | **tenant column** `school_id` (platform-side entries still record school context) | `(school_id,created_at DESC)` · `(school_id,type)` (summary aggregates) · `(txn_id)` | append-only via DB rule/trigger — no UPDATE/DELETE (INV-1); CHECK exactly one of debit/credit ≠ 0 |
| `payment_receipts` | One immutable PDF receipt per success: media ref (05/R2), per-school serial | **tenant column** `school_id` | UNIQUE `(txn_id)` · UNIQUE `(school_id, serial_no)` | serial `{SCHOOL-YY}-{seq:6}` via advisory lock; PDF object immutable in R2 |
| `gateway_events` | Webhook envelope audit: gateway, event id, `signature_valid`, sha256 `payload_digest`, ids/amounts `payload_summary` — **never the raw payload** (INV-6) | scoped transitively (gateway + txn); security-review visibility | UNIQUE `(gateway, event_id)` (envelope dedupe ahead of the txn index) · `(signature_valid,received_at)` · partial unprocessed | `signature_valid=false` rows are security flags (PAY-US-013) |

---

## 5. Contracts

### 5.1 REST endpoints

Summary of `03-backend-tasks.md` §2 (auth chain authenticate → role claims → tenant-scope on every protected route; rate class `default` for admin/reads, strict `payments` class for initiate/callback/webhook).

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | POST `/api/v1/school/invoices` | School Admin (own school) | Issue single invoice | `VALIDATION_FAILED`, `TENANT_MISMATCH` | PAY-US-001 |
| 2 | POST `/api/v1/school/invoices/bulk` | School Admin (own school) | Bulk issue to a section (1–200 students, one tx) | `VALIDATION_FAILED` (`bulkLimit`) | PAY-US-002 |
| 3 | GET `/api/v1/school/invoices` | School Admin (own school) | Invoice tab (status/class/month filters + totals) | — | PAY-US-009 |
| 4 | PATCH `/api/v1/school/invoices/{id}/void` | School Admin (own school) | Void before any payment (reason) | `CONFLICT` if ≥1 success | PAY-US-012 |
| 5 | GET `/api/v1/school/ledger` · `/api/v1/school/ledger/summary` | School Admin (own school) | Ledger tab + summary cards (server-computed totals, `no-store`) | — | PAY-US-009 |
| 6 | GET `/api/v1/school/payments/reconciliation?date=` | Super Admin + School Admin (own slice) | Per-gateway settled-vs-ledger + mismatch list | — | PAY-US-010 |
| 7 | POST `/api/v1/payments/initiate` | Verified entitled payer | Start payment (invoice xor order) → `RedirectPayload` | `FORBIDDEN`, `CONFLICT`, `PAYMENT_FAILED`, `VALIDATION_FAILED` | PAY-US-004/005/011 |
| 8 | **POST `/api/v1/webhooks/{gateway}`** | **None — the one unauthenticated-but-signature-verified exception** (flagged `security: []` in the OpenAPI spec; mounted outside the auth group) | Authoritative gateway confirmation; always 2xx for valid signatures | `403` invalid signature/replay window (+ flagged `gateway_events` + alert); `DUPLICATE_WEBHOOK` 200 on replay | PAY-US-006/007/013 |
| 9 | POST `/api/v1/payments/callback/{gateway}` | None (gateway browser return; txn token) | UX-only return path — status re-check vs gateway, 302 → `/payments/status/{txnId}` | surfaces in redirect state, not as an API error | PAY-US-005 |
| 10 | GET `/api/v1/payments/transactions` | Payer (claims-scoped) | Own payment history, newest first | — | PAY-US-014 |
| 11 | GET `/api/v1/payments/receipts/{txnId}` | Payer or txn's School Admin | `{receiptUrl, serialNo, issuedAt}` (immutable R2 URL) | `NOT_FOUND` (generating), `FORBIDDEN` | PAY-US-014 |

Refund adjustment (`POST /institution/refunds`) and settlement CSV import (`POST /institution/settlements/import`) are Super/School-Admin endpoints defined at build (PAY-BE-017/018) — same chain, audited (PAY-BR-011, PAY-US-010).

### 5.2 Realtime / jobs

No realtime channel; pushes are module 06's (`fee_due` → `/payments/{invoiceId}`, `payment_result` → `/receipts/{txnId}` — frozen with 06, `NTF-INT-007`). Jobs (`03` §5):

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| `receipt.generate` (PAY-JOB-001) | Enqueued in the success tx | PDF (bn/en per school locale) → 05 `media.PutObject` → serial → result push | payer, School Admin | UNIQUE(txn_id) guards double issue; worker retry/backoff; R2-down recovers late; sweep re-enqueues missing receipts |
| `invoice.notify` (PAY-JOB-002) | After issue commit (single + bulk fan-out) | Fee-due push "বকেয়া ফি / Fee due" + amount + deep link | guardians (or student) | degraded: invoice remains payable in-app; 06 owns retries |
| `payments.reconcile` (PAY-JOB-003) | Cron daily 06:00 Asia/Dhaka | Ledger vs imported settlement; invariant check per school; mismatch list; audit summary | Super Admin, ops | report regenerated from append-only ledger — rerun safe; failure → alert |
| `payments.overdue_sweep` (PAY-JOB-004) | Cron daily 00:05 Asia/Dhaka | `issued` past due → `overdue` | School Admin reporting | guarded status UPDATE; missed days self-heal (date-agnostic predicate) |
| `payments.expire` (PAY-JOB-005) | Cron every 10 min | Stale `initiated|redirected` > 30 min → `expired` (+ push) | payer | guarded status UPDATE; retry per worker policy |

### 5.3 Exported service functions

From `06-integration-tasks.md` §2 — DTOs only, domain errors, additive-first signatures.

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `payments.InitiateInvoicePayment(actor, invoiceID, gateway)` | 07 (dashboard "collect" shortcuts, server-side) · app/web via REST initiate (order payments use the same core with `orderId` — 11's seam, PAY-BR-015) | `RedirectPayload{txnId, gateway, redirectUrl, redirectMethod, params}` | `FORBIDDEN` (unverified/unentitled), `CONFLICT` (paid/void), `PAYMENT_FAILED`, `VALIDATION_FAILED` |
| `payments.InvoiceStatus(actor, invoiceID)` | 07 (ledger cards) · 11 (checkout pre-checks) · app status poll via REST | `InvoiceStatusDTO{invoiceId, status, amountBdt, paidTxnId?, lastTxnStatus?}` | `NOT_FOUND`, `TENANT_MISMATCH` |
| `payments.TransactionSummary(actor, txnID)` | 07 (transaction drawer) · 11 (order → payment display) | `TransactionSummaryDTO{txnId, kind: fee|order, refId, amountBdt, convenienceFeeBdt, gateway, status, completedAt?, receiptUrl?}` — no secrets | `NOT_FOUND`, `TENANT_MISMATCH`/`FORBIDDEN` (payer or school admin only) |

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

No public payment pages — payers pay in the app; the web callback route only 302-redirects to the app deep link.

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| `/institution/ledger` | Ledger dashboard — fills 07's stub (`WEB-FE-025`): summary cards (collected/outstanding ৳), Invoices · Transactions · Reconciliation tabs, server-side filters + totals row, CSV export, transaction detail drawer (ids/amounts/status only) | Server shell + Client tables (`no-store` — money screens never cached) | School Admin (own school) · Super Admin (read, all schools) |
| `/institution/invoices/new` | Issue single invoice — StudentPicker (04 roster), RHF + zod | Client (RHF) | School Admin |
| `/institution/invoices/bulk` | Issue bulk to a section — preview step with resolved student count ("১২৪ জন শিক্ষার্থী"); 200-cap guard | Client (RHF) | School Admin |

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| `/(tabs)/marketplace` → "ফি পরিশোধ / Pay fees" | Payments home entry | none (tab) | cached list + banner; Pay disabled |
| `/payments` | Invoice list — due/paid tabs, ৳ in bn digits via `Intl` | Marketplace entry | cached read + offline banner |
| `/payments/[invoiceId]` | Pay screen — amount breakdown (fee [+ convenience fee when enabled; default none] = total), gateway chooser (down gateway hidden via health flag), "কার্ডের তথ্য আমরা দেখি না" trust line | fee-due push (`payments.feeDue`), list tap | **payments require connectivity — refused up front, never queued** |
| `/payments/status/[txnId]` | Return/status screen — poll `InvoiceStatus` 3 s ×20 → success/failure/"processing — we'll notify you" | gateway callback 302, push | poll resumes when online; push is the backstop |
| `/receipts/[txnId]` | Receipt view/share — summary card + PDF via immutable R2 URL; "রসিদ তৈরি হচ্ছে…" while generating | payment-result push (`payment_result`), status screen | cached URL viewable; PDF fetch needs network |

---

## 7. External Integrations

From `06-integration-tasks.md` §5 — three gateways behind one `PaymentGateway` interface (`Initiate` / `VerifyWebhook` / `FetchStatus`; mock adapter for tests, ADR `02` §10).

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| SSLCommerz (first — cards + internet banking) | Hosted checkout for fees + orders | HTTPS hosted checkout + server-to-server webhook + status API | `SSLCOMMERZ_*` (store id + hash secret; envconfig-parsed; sandbox until module 15) | 15 s; webhooks idempotent (`UNIQUE(gateway, gateway_txn_id)`) + status-poll fallback + expiry-sweep backstop | Chooser hides it when health-flagged; fee invoices unaffected |
| bKash (wallet) | Hosted checkout (temp-token) + webhook + status API | HTTPS | `BKASH_*` (app key/secret, username/password — config module only) | 15 s; same | same |
| Nagad (wallet) | Hosted checkout + webhook + status API | HTTPS | `NAGAD_*` (merchant id + keys; config module only) | 15 s; same | same |
| (R2 via 05, FCM via 06) | Receipts, pushes | always through module services | none held here | — | see `06` §3/§8 — receipt retries late, pushes degraded |

All webhook payloads are signature-verified before parsing; **secrets and raw payloads are never logged or stored** — `gateway_events` keeps ids + amounts + digest only. Settlement reports are manual CSV imports at launch; per-gateway format `TODO: Confirm`.

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |
| `SSLCOMMERZ_STORE_ID` / `SSLCOMMERZ_HASH_SECRET` (+ base URL) | Yes (SSLCommerz enabled) | sandbox values until module 15 cutover | SSLCommerz adapter: initiate + signature verify |
| `BKASH_APP_KEY` / `BKASH_APP_SECRET` / `BKASH_USERNAME` / `BKASH_PASSWORD` (+ base URL) | Yes (bKash enabled) | sandbox values | bKash adapter (temp-token checkout) |
| `NAGAD_MERCHANT_ID` / `NAGAD_*` keys (+ base URL) | Yes (Nagad enabled) | sandbox values | Nagad adapter |
| — | — | — | Keys live only in the parsed config module, never admin-editable (`02` §5); never logged (`PAY-BR-007`) |

### 8.2 Runtime config — the two lists

From `02-solution-approach.md` §5.

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| Convenience fee amount (platform-wide, default **BDT 0 = off** — `brd.md` §7 removes transaction fees, superseding `prd.md` §7) | Ledger entry types + balance rule; invoice/transaction state machines (`02` §3) |
| Gateway enable/disable toggles (per gateway; down/holiday switches) | Signature schemes + replay windows per gateway adapter |
| Invoice kind presets (labels bn/en for tuition/exam/transport/other) | Txn expiry window (30 min); receipt serial format `{SCHOOL-YY}-{seq}` |
| Order commission rate (default 5% — owned with 11, `TODO: Confirm`) | Rate-limit class `payments` (strict); webhook route list |
| Bulk batch cap display (hard cap 200 is code; admins see the limit) | Sandbox vs production keys come from env only — never admin-editable |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | Every REST route: authenticate → load role claims → tenant-scope (03 chain). **`POST /api/v1/webhooks/{gateway}` is the one deliberate exception: no auth chain — instead rate limit → HMAC/signature + timestamp replay-window verification → allowlisted gateway source ranges → only then parse; flagged `security: []` + webhook marker in OpenAPI** (`02` §6, PAY-BR-006) |
| Role matrix | School Admin: issue/void own-school invoices, read own ledger/summary/reconciliation slice, receipts of own school's payers · Super Admin: reads platform revenue across schools, imports settlement CSVs, initiates manual refunds (adjustment entries) · Guardian/Student (verified, linked): view/pay entitled invoices, own transactions + receipts · Teacher: no surface |
| Tenant scope | `fee_invoices`, `ledger_entries`, `payment_receipts` carry `school_id` (all queries scoped); `payment_transactions`/`gateway_events` scoped transitively via invoice/order + payer with service visibility rules; cross-tenant probes → `TENANT_MISMATCH`/404 (PAY-IT-005, every owned table) |
| Rate limits | Class `payments` (strict): initiate 5/min/user · callback 30/min/IP · webhook 120/min/gateway (retries are legitimate); ledger reads use class `default`; repeated bad signatures trip the limiter and flag the IP for ops review |
| Audit events | **All money mutations audited in-transaction** (PAY-BR-010 / INV-8): issue (single + batch summary), void, initiate, every webhook terminal state change, refund adjustment, settlement import — ids + amounts only; `audit.Record` failure aborts the mutation (no un-audited commit) |
| Privacy / minors | PCI stance: **no card/wallet data ever reaches our servers** — gateways host the payment page; only gateway txn ids, amounts and statuses stored (SAQ-A scope; `02` §10 option G). Never log secrets or raw payloads — `gateway_events` stores digest-only + ids/amounts summary (PAY-BR-007 / INV-6, asserted by PAY-UT-005); transaction drawer shows ids/amounts/status only; unverified users can neither see nor pay an invoice |

---

## 10. Error Handling

All errors surface as RFC-7807 `application/problem+json`. User-visible messages resolve via each app's `src/i18n` catalogs — every message key ships in **bn + en** (Bengali default), e.g. "পেমেন্ট গেটওয়ে সাময়িকভাবে অচল / Payment gateway temporarily unavailable".

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `PAYMENT_FAILED` | Gateway refused / down / unreachable | Initiate against a health-flagged or refusing gateway; order initiate when 11 is unreachable | bn/en "temporarily unavailable — try again shortly"; chooser hides that gateway; other gateways remain |
| `DUPLICATE_WEBHOOK` | Idempotent replay (not an error) | Same gateway event/txn id re-processed → **200** `{"processed":false,"reason":"DUPLICATE_WEBHOOK"}`, zero side effects | n/a — gateway contract: always 2xx for valid signatures so gateways don't retry-storm |
| `INVALID_SIGNATURE` (403) | Forged / tampered / replayed-timestamp webhook | Signature verification failure or out-of-window replay | Refused before any parsing; flagged `gateway_events` row + alert-level log (event id + gateway only); rate limiter trips on repeats |
| `CONFLICT` | Target already paid/void/cancelled, second success attempt, attach guard | Pay on paid invoice (UI offers the receipt), void after a success, double order pay, already-attached txn | Show current state: receipt link / "ইনভয়েস বাতিল হয়েছে — স্কুল অফিসে যোগাযোগ করুন / invoice cancelled — contact the school office" |
| `TENANT_MISMATCH` / `NOT_FOUND` | Cross-tenant probe / invisible row | Foreign invoices/ledger/receipts; receipt not yet generated | 404 — no leak; "রসিদ তৈরি হচ্ছে / receipt is being generated" for the pending-receipt case |
| `FORBIDDEN` | Not entitled | Unverified payer, non-linked guardian, wrong-school admin, non-payer receipt request | Refusal + verify-first / support copy |
| `VALIDATION_FAILED` | Bad input | Invoice title/amount/due-date/kind, bulk > 200 (`validation.payments.bulkLimit`), gateway enum, malformed settlement CSV (names the row) | Field messages bn-first; split-the-batch guidance |
| `UNAUTHENTICATED` / `RATE_LIMITED` / `INTERNAL` | Standard envelope | Protected routes / limiter / infra | Re-auth; retry later; error boundary with `X-Request-Id` |

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | slog JSON; webhook/initiate paths log gateway, event id, txn id, amounts — **never signatures, payloads or keys** (redaction asserted by PAY-UT-005); bad-signature events fire an alert-level log (ids only) |
| Metrics / counters | Gateway success/failure rates, initiate→success conversion, webhook latency, `DUPLICATE_WEBHOOK` volume, flagged-signature count, receipt-generation lag, overdue ratio |
| Health contribution | No dedicated check — Postgres/Redis/worker health flows through the 01 base `/readyz`; gateway health flags (`payments:gateway-health`, TTL 60 s) drive chooser hiding |
| Jobs & retries | 5 jobs (`receipt.generate`, `invoice.notify`, `payments.reconcile`, `payments.overdue_sweep`, `payments.expire`) — idempotent; receipt retried with backoff + sweep re-enqueue; reconcile failure alerts; DB UNIQUE index is the real idempotency guard (Redis is only a fast-path) |
| Runbook pointers | Daily **reconciliation report** (settled vs ledger per gateway; mismatch list with txn id + expected vs settled ৳; per-school invariant flag) — investigate before any `adjustment` entry; **webhook replay detection alerting** (flagged `gateway_events` + IP flag on limiter trip); gateway-down drill; 01/15 runbooks for pool/worker alarms |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Ledger balance builder (fee split / order commission; unbalanced impossible), per-adapter signature verifier (valid/invalid/tampered/expired timestamp), serial generator under advisory lock, validation mirrors, log-redaction (no secrets/payloads) | `PAY-UT-001`–`005` | `go test` green |
| Integration | **Signature IT** (valid processes; invalid/tampered → 403 + flagged `gateway_events` + zero state change), **idempotent double-webhook** (one txn, one ledger pair, 200 `DUPLICATE_WEBHOOK`), **ledger balance** (fee_payment + convenience_fee in one tx; abort rolls back both), receipt job (+ rerun no-op), cross-tenant denial on every owned table, void-before-payment-only, overdue + expire sweeps, unauthenticated probes (webhook route rejects missing signature), 11 order seam (commission entry + attach once; double pay → `CONFLICT`) | `PAY-IT-001`–`009` | testcontainers Postgres green in CI |
| E2E | Playwright: issue invoice → ledger row with correct server totals → CSV export · Maestro: fee-due push tap → pay screen → gateway chooser → status screen (sandbox) → receipt link | `PAY-E2E-001`–`002` | CI smoke |
| CI | — | — | `go test/vet/lint` (api) + `pnpm lint/typecheck/test/build` (web/app). Mandatory everywhere: unauthenticated calls denied (webhook excepted **by design**, signature-enforced); validation rejects bad input; cross-tenant read/write → `TENANT_MISMATCH`/404 for every tenant-scoped table |

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | Pilot ≈ hundreds of invoices/institution/month; BRD-scale target ≈ 2.4 M transactions/year (`prd.md` §7); receipt generation is the only heavy work and is fully async |
| Hot paths + indexes | Webhook lookup by `UNIQUE(gateway, gateway_txn_id)` (the idempotency hot path); invoice lists `(school_id,status,due_date)`; payer history `(payer_id,created_at DESC)`; ledger `(school_id,created_at DESC)` + `(school_id,type)` aggregates; expiry sweep partial `(status,updated_at) WHERE status IN ('initiated','redirected')` |
| Latency targets | Initiate ≤ 800 ms p95 (excludes gateway page load); webhook processing ≤ 300 ms p95 (single tx + audit); ledger page ≤ 500 ms p95 with filters — always-fresh reads, so indexes do the work |
| Bundle / payload impact | Web adds no deps beyond 07's TanStack stack (CSV export is a small util); app adds `expo-web-browser` only; no image assets on the pay path (logos-as-text) |
| Caching | Money screens are **uncacheable by design** (`no-store`) — totals always server-computed; app invoice list `payments:invoices:{userId}` 30 s stale-while-revalidate; receipt PDFs immutable R2 objects cached forever (new receipt = new object); gateway health flag TTL 60 s |

---

## 14. Risks & Open Questions

Consolidated from `01` §9 and `02` §11 — the table to review in module readiness checks; unconfirmed items keep their `TODO: Confirm` marker.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| 1 | Gateway launch order & production accounts; sandbox behaviour ≈ production webhooks/signatures | Signature/format surprises at cutover (module 15) | Rahul | Open | SSLCommerz first (cards + internet banking), then bKash and Nagad wallets; sandbox keys until module 15; adapter + `VerifyWebhook` isolation, contract tests per gateway, sandbox-first rollout |
| 2 | Convenience fee amount (`prd.md` §7 allows 15–20) | Revenue stream underdelivers vs gateway MDR + margin | Rahul | Open (`TODO: Confirm`) | **BDT 0 (off)** per `brd.md` §7 (supersedes `prd.md` §7); enabling + MDR bearer is an owner decision `TODO: Confirm` |
| 3 | Settlement report file format per gateway | Reconciliation breaks per format drift | Rahul | Open (`TODO: Confirm`) | Manual CSV import at launch (one template per gateway); auto-fetch deferred |
| 4 | Refund mechanics | Ledger ≠ bank at audit if adjustments drift | Rahul | Open | Manual, Super/School-Admin initiated, `adjustment` ledger entry, **no gateway auto-refund at launch** |
| 5 | Partial payments (`partially_paid`) | Reconciliation corrections | Rahul | Open | Full-payment only at launch; `partially_paid` reserved for manual admin adjustments |
| 6 | Order commission rate (11 seam) | Commission rework | Rahul (with 11) | Open | 5% flat platform commission entry; rate change is config, not code |
| 7 | 11's order seam (`OrderAmount`, attach hook) must land before 12 order payments; 05 must ship the additive `media.PutObject` export | Order payments blocked (fees unaffected); receipt upload blocked | 11 / 05 / Rahul | Open | Ship fees first if 11 slips; `PutObject` flagged additive in `06` §3 — fallback: presign flow driven server-side (uglier, works) |
| 8 | Public webhook route as flood target | Noise/DoS on the money path | — | Mitigated in spec | `payments` rate-limit class, allowlisted ranges, cheap-verify-first ordering, alerting |

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| — (fee collection is a PRD stream, not a numbered BR) | §5.4 (fees, deep links, receipts, ledger) · §7 (convenience fee 15–20, revenue stream) · §4A/§4B surfaces | PAY-US-001–014 | PAY-BE-001–023 (+PAY-BE-031/032 schema) · PAY-JOB-001–005 · PAY-FE-001–012 · PAY-AP-001–012 · PAY-INT-001–010 | PAY-UT-001–005 · PAY-IT-001–009 · PAY-E2E-001–002 |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-10-03 | Build executed contract-first: 11 routes (incl. the `security: []` webhook exception with the verification order in-spec) + 24 schemas; webhook pipeline = signature+replay FIRST → envelope dedupe (UNIQUE gateway+event_id) → txn idempotency (UNIQUE gateway+gateway_txn_id) → server-to-server FetchStatus confirm → one tx (txn→success + balanced ledger + invoice→paid / 11-attach + receipt job); ledger append-only via trigger; convenience fee defaults 0/off (PAY-BR-008); `SandboxGateway` HMAC adapter exact + offline-testable, real adapters gated on merchant docs (ADR-1, G-2); receipts behind a `ReceiptRenderer` port (bn shaping spike = G-4); env `PAYMENTS_WEBHOOK_SECRET` added to config + tests; migrations `20270210090000–093000`. | Kilo |
| 2026-09-30 | Initial technical document drafted from spec set 01–06 | Kilo |
| 2026-09-30 | Consistency pass: migrations re-versioned `20270210…` (after 11); convenience fee default BDT 0 per `brd.md` §7; success requires server-to-server `FetchStatus` confirmation (gateway webhook schemes `TODO: Confirm`); route `/institution/payments/reconciliation` (was colliding with 14); guardian entitlement via 03 `guardians.IsGuardianOf`; `media.PutObject` now declared by 05 | Claude |

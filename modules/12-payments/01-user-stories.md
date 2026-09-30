# Payments — User Stories

**Module:** `12-payments` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

---

## 1. Purpose

Module 12 turns fee collection from cash-in-an-envelope into a trust-first digital flow: School Admins issue fee invoices (single or bulk to a section), guardians and students pay through SSLCommerz/bKash/Nagad from a push-notification deep link, and every successful payment lands as verified webhook → idempotent ledger entries → auto-generated PDF receipt. It serves `prd.md` §5.4 (fee collection, deep links, PDF receipts, ledger) and the FinTech revenue stream (`prd.md` §7), and fills the `/school` ledger stub left by module 07.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Unverified user (pending) | Cannot see invoices or pay until verified by their school (module 03) |
| Student | Pays their own issued invoices from the Marketplace tab; views own transactions and receipts |
| Guardian | Primary payer — receives the fee-due push ("বকেয়া ফি"), taps the deep link, pays, gets the receipt |
| Teacher | No payments surface in this module (read-only nothing) |
| School Admin | Issues/voids invoices (single + bulk), reads the school ledger dashboard, transaction details, reconciliation report |
| Super Admin | Reads platform revenue (convenience fees, commissions), imports gateway settlement CSVs, initiates manual refunds |
| Vendor / EdTech brand | Indirect — their online orders (module 11) are paid through this module's transaction + ledger path |
| System (jobs, webhooks) | Receives signed gateway webhooks; runs receipt-generation, daily reconciliation and overdue-sweep jobs |

The five roles are defined by module 03; verification gates every participatory action here (`prd.md` §5.1) — an unverified guardian can neither see nor pay an invoice.

## 3. Scope

**In scope**

- `fee_invoices`, `payment_transactions`, `ledger_entries` (append-only), `payment_receipts`, `gateway_events` — defined and owned here
- Invoice issue (single + bulk-by-section), void-before-payment, overdue sweep
- Payment initiation for invoices and online vendor orders (11 seam) via SSLCommerz, bKash, Nagad (gateway-hosted pages)
- Webhook ingestion with signature verification + idempotency (`UNIQUE(gateway, gateway_txn_id)`); browser/app callback as UX-only return path
- Ledger entries per success (fee_payment + convenience_fee split; commission for orders), manual refunds as adjustments
- PDF receipt generation (job) → R2 → deep-linked push
- School ledger dashboard + reconciliation report data (`GET /school/ledger*`, `GET /school/payments/reconciliation`)
- bn/en string catalogs `payments.*`, `validation.*` entries for this module

**Out of scope** (explicit — prevents scope drift)

- Order/cart/fulfilment logic (11 owns orders; 12 only attaches `payment_transaction_id` per 11's seam); recurring subscriptions (Kushol Pro billing — 08/13 surfaces, priced later); gateway-hosted wallet onboarding/KYC; automatic gateway refunds (manual adjustment entries at launch); auto-debit/standing instructions; invoice line-item breakdowns (single amount per invoice at launch); settlement-file auto-fetch (manual CSV import at launch — `TODO: Confirm` format)

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 07 command-center-web | The `/school/ledger` nav stub (WEB-FE-025) that this module fills |
| 11 campus-commerce | `commerce.OrderAmount(orderId)` + the `payment_transaction_id` attach seam (defined in 11's spec) |
| 03 identity-access | Auth chain, roles, verification status, guardian↔student link (03 `guardians.IsGuardianOf` / `LinkedStudents`), `users.locale` |
| 04 organization-hierarchy | `hierarchy.ResolveUserNodes` (school scoping; section→student resolution for bulk invoices) |
| 05 communication-engine | R2 storage service for generated receipt PDFs (`media.PutObject` — declared in 05 `06` §2) |
| 06 notifications | `notify.SendToUser` — fee-due push w/ deep link; payment-result push → receipt |
| 01 foundations | `jobs.Enqueue` (receipt generation, reconciliation, sweeps), `audit.Record` (every money mutation) |

---

## 4. User Stories

### `PAY-US-001` — School Admin issues a fee invoice to a student

**Priority:** P0 · **Traces:** prd.md §5.4 · prd.md §4A (fee payment links) · **Depends on:** 03, 04

**Story** — As a **School Admin**, I want to issue a fee invoice (title, kind, amount, due date) to one student in my school, so that the family receives a clear, trackable demand instead of a paper slip.

**Acceptance criteria**

- **Given** I am a verified School Admin of school S, **when** I POST a valid invoice for a student of S, **then** the invoice is created `issued` with a server-set `amount_bdt numeric(12,2)`, `due_date`, `kind ∈ tuition|exam|transport|other`, and my user id as `issued_by`.
- **Given** I target a student of another school, **when** the request lands, **then** it fails `TENANT_MISMATCH`/404 with no row created.
- **Given** the invoice is issued, **when** the transaction commits, **then** an audit entry records issuer, student, amount (ids + amounts only — no secrets) and a notification job is enqueued (`PAY-US-003`).

**Notes** — Amount is immutable after issue; corrections require void + reissue (`PAY-US-012`).

---

### `PAY-US-002` — School Admin issues bulk invoices to a section

**Priority:** P0 · **Traces:** prd.md §4A · **Depends on:** PAY-US-001, 04

**Story** — As a **School Admin**, I want to issue the same fee to every student of a section in one batch (CSV-lite: no file upload, just section + shared fields), so that monthly tuition takes one action, not two hundred.

**Acceptance criteria**

- **Given** I pick a section of my school, **when** I preview the batch, **then** the API returns the resolved student count from 04's section roster before anything is created.
- **Given** I confirm, **when** the bulk POST runs, **then** every student of the section gets an `issued` invoice; the response reports `created` count and per-student failures (if any) — never a partial silent batch.
- **Given** a section resolves to more than 200 students, **when** I submit, **then** it is refused `VALIDATION_FAILED` with `validation.payments.bulkLimit` and I am told to split the batch.

**Notes** — Batch is one transaction; per-invoice notification jobs fan out afterwards via `jobs.Enqueue` (no push storm inside the tx).

---

### `PAY-US-003` — Issued invoice pushes a fee-due notification with a deep link

**Priority:** P0 · **Traces:** prd.md §5.4 · **Depends on:** PAY-US-001/002, 06

**Story** — As a **guardian**, I want a push notification the moment my child's fee invoice is issued, so that I can pay from the lock screen without hunting through menus.

**Acceptance criteria**

- **Given** an invoice is issued for student X, **when** the notification job runs, **then** every guardian linked to X (03's guardian link; the student themself if none) receives a directed push (`notify.SendToUser`, class per 06) titled **bn: "বকেয়া ফি" · en: "Fee due"** with the amount — e.g. bn "বকেয়া ফি: ৳১,২৫০.০০" / en "Fee due: ৳1,250.00" — and `deepLink: /payments/{invoiceId}`.
- **Given** the recipient's locale is `bn` (default) or `en`, **when** the payload is built, **then** the string comes from `packages/shared` `payments.*` in that language (06 renders per device locale).
- **Given** the push fails, **when** 06 reports degradation, **then** the invoice remains payable in-app under Marketplace → "Pay fees" — the flow never depends on the push.

**Notes** — Payload carries key + ids + deep link only (`NTF-BR-003`); no amounts-in-URL, content fetched after auth.

---

### `PAY-US-004` — Guardian opens the pay screen and picks a gateway

**Priority:** P0 · **Traces:** prd.md §5.4 · prd.md §4B (Marketplace → Pay fees) · **Depends on:** PAY-US-001, 03

**Story** — As a **guardian**, I want a pay screen showing exactly what I owe — fee amount + any convenience fee (default BDT 0 = none, `brd.md` §7) — and a choice of SSLCommerz, bKash or Nagad, so that there are no surprises at the gateway.

**Acceptance criteria**

- **Given** I tap the fee-due deep link (or Marketplace → Pay fees), **when** the pay screen loads for an `issued` invoice of my child, **then** I see the invoice title, kind, due date, the amount breakdown (fee ৳X + convenience fee ৳15 = total ৳Y) and the gateway chooser.
- **Given** I am not the linked guardian/student of that invoice's school, **when** I open the link, **then** I get `FORBIDDEN` and the screen shows the bn/en refusal — no invoice data rendered.
- **Given** a gateway is down (health-flagged), **when** the chooser renders, **then** that gateway is hidden/disabled and the others remain selectable.

**Notes** — Convenience fee defaults to BDT 0 (off): `brd.md` §7 removes transaction fees and supersedes `prd.md` §7's BDT 15–20. When config > 0 the fee line is shown before any redirect; when 0 no fee line renders and no `convenience_fee` ledger row is written.

---

### `PAY-US-005` — Payment redirects to the gateway and returns to the app

**Priority:** P0 · **Traces:** prd.md §5.4 · prompt.txt §3 (deep links) · **Depends on:** PAY-US-004

**Story** — As a **guardian**, I want to complete payment on the gateway's own page and land back in the app automatically, so that the flow feels native even though the gateway hosts it.

**Acceptance criteria**

- **Given** I confirm a gateway, **when** `POST /payments/initiate` succeeds, **then** a transaction row `initiated` → `redirected` is created and the response returns the gateway's hosted-checkout redirect payload; the app opens it in the in-app browser.
- **Given** I finish (or abandon) on the gateway page, **when** the gateway returns to `POST /payments/callback/{gateway}`, **then** the server checks transaction status with the gateway, updates the row if terminal, and 302-redirects the browser to the app deep link `/payments/status/{txnId}`.
- **Given** I return before the webhook arrives, **when** the status screen polls `payments.InvoiceStatus`, **then** I see "processing" (bn: "পেমেন্ট প্রসেসিং — আমরা জানাবো" / en: "Payment processing — we'll notify you") rather than a wrong success/failure.

**Notes** — The callback is UX only; the webhook is the source of truth (`02` §3). No card/wallet data ever touches our servers.

---

### `PAY-US-006` — Webhook confirms payment (signed, idempotent)

**Priority:** P0 · **Traces:** prompt.txt §5/§9 · tech-stack.md (webhook signature verification, idempotent ledger) · **Depends on:** PAY-US-005

**Story** — As a **system**, I want gateway webhooks verified by signature and processed idempotently, so that exactly one ledger effect exists per real payment no matter how many times a gateway retries.

**Acceptance criteria**

- **Given** a webhook arrives at `POST /webhooks/{gateway}` (the one unauthenticated-but-signature-verified route), **when** the signature is valid, **then** a `gateway_events` row is written (event id, `signature_valid`, sha256 `payload_digest`, summary only) and the transaction advances.
- **Given** the same webhook replays (same gateway event/txn id), **when** it is processed again, **then** the response is **200 with `{"processed": false, "reason": "DUPLICATE_WEBHOOK"}`** and no second transaction/ledger entry (UNIQUE(gateway, gateway_txn_id)).
- **Given** a `success` webhook for a `success` transaction, **when** processed, **then** the handler is a no-op that still returns 200 (gateways retry on non-2xx; never let them storm).

**Notes** — Replay window + timestamp check per gateway scheme (`02` §6); secrets and raw payloads are never logged or stored (`PAY-BR-007`).

---

### `PAY-US-007` — Success writes balanced ledger entries and issues the PDF receipt

**Priority:** P0 · **Traces:** prd.md §5.4 (receipts + ledger) · prd.md §7 (convenience fee) · **Depends on:** PAY-US-006

**Story** — As a **School Admin**, I want every successful fee payment to appear in my ledger instantly and generate a numbered PDF receipt, so that my accounts reconcile without manual bookkeeping.

**Acceptance criteria**

- **Given** a fee-invoice transaction transitions to `success`, **when** the webhook transaction commits, **then** two `ledger_entries` rows are appended in the same transaction: `fee_payment` (credit `amount_bdt`, school) + `convenience_fee` (credit `convenience_fee_bdt`, platform) — debit/credit balanced against the charged total.
- **Given** the commit succeeds, **when** the receipt job runs, **then** a PDF (bn/en per school locale) is generated, stored to R2 via 05, a per-school serial (`{SCHOOL-YY}-{seq}`) is assigned, and the guardian gets a push **bn: "পেমেন্ট সফল" · en: "Payment successful"** deep-linking `/receipts/{txnId}`.
- **Given** R2 is down, **when** the receipt job fails, **then** it retries with backoff (01 worker); the payment and ledger are already final and the receipt appears late — never lost.

**Notes** — Invoice flips `issued → paid`; receipt title **bn: "ফি পরিশোধ রসিদ" · en: "Fee payment receipt"**.

---

### `PAY-US-008` — Failed or expired payments leave the invoice payable and retryable

**Priority:** P0 · **Traces:** prd.md §5.4 · **Depends on:** PAY-US-005

**Story** — As a **guardian**, I want a clear failure/success state and a working retry, so that a dropped gateway session never costs me money or blocks me from paying later.

**Acceptance criteria**

- **Given** the gateway reports failure or the transaction expires (no completion within the window), **when** the state lands, **then** the transaction is `failed`/`expired`, the invoice stays `issued` (unpaid), and I get a push **bn: "পেমেন্ট ব্যর্থ" · en: "Payment failed"** with a retry deep link.
- **Given** a failed transaction, **when** I tap pay again, **then** a fresh transaction starts — no reference to the failed one, no stale gateway session reuse.
- **Given** the invoice was paid between my attempt and my return, **when** I retry, **then** initiate refuses `CONFLICT` and the screen shows the receipt link instead.

**Notes** — Expiry sweep job marks stale `initiated|redirected` rows `expired` (window 30 min, fixed in code).

---

### `PAY-US-009` — School Admin ledger dashboard (invoices + transactions)

**Priority:** P0 · **Traces:** prd.md §5.4 (dashboard ledger) · **Depends on:** PAY-US-001, PAY-US-007, 07

**Story** — As a **School Admin**, I want a ledger dashboard at `/school/ledger` (filling 07's stub) with invoice and transaction tables, status/class/month filters and totals, so that fee collection status is one glance away.

**Acceptance criteria**

- **Given** I am a School Admin, **when** I open `/school/ledger`, **then** I see tabs **Invoices** and **Transactions** (TanStack Table), filterable by status, class and month, with a totals row (count + ৳ sums) computed server-side — never client-side math over money.
- **Given** another school's invoices exist, **when** any ledger query runs, **then** only my school's rows are returned (tenant scope in the repository layer; cross-tenant probe → `TENANT_MISMATCH`).
- **Given** I filter + export, **when** I click CSV export, **then** the current filtered view downloads with bn/en headers per my locale.

**Notes** — Ledger reads are always fresh (no caching); transaction detail shows ids, amounts, gateway status — no sensitive data (`04` §2).

---

### `PAY-US-010` — Daily reconciliation report flags mismatches

**Priority:** P1 · **Traces:** prd.md §5.4 (automated reconciliation) · **Depends on:** PAY-US-007

**Story** — As a **Super Admin**, I want a daily job that compares each gateway's settlement report against our ledger and flags mismatches, so that a lost webhook or wrong amount surfaces within a day, not at audit time.

**Acceptance criteria**

- **Given** the daily reconciliation job runs, **when** it compares settled amounts per gateway against `ledger_entries`, **then** it produces per-school totals, a match/mismatch flag list, and audit-logs the summary.
- **Given** a settlement CSV is imported (manual, per gateway — `TODO: Confirm` format), **when** rows disagree with the ledger (missing/extra/amount-delta), **then** each mismatch is listed with txn id, expected vs settled ৳ on the reconciliation screen (`GET /school/payments/reconciliation?date=`).
- **Given** `sum(ledger fee_payment credits) ≠ sum(success transactions)` for a school, **when** the invariant check runs, **then** the school is flagged in the report for investigation.

**Notes** — At launch the comparison runs per imported file; auto-fetch is out of scope (`03` §5 job table).

---

### `PAY-US-011` — Vendor order paid online through the same path (11 seam)

**Priority:** P0 · **Traces:** prd.md §4B/§5.4 (campus commerce) · brd.md §7 Stream 1 (commission) · **Depends on:** 11, PAY-US-006

**Story** — As a **student/guardian**, I want to pay for an online vendor order with the same gateways and get a receipt, so that marketplace checkout feels identical to fee payment.

**Acceptance criteria**

- **Given** an `11` order is payable, **when** checkout calls the payments path (order id instead of invoice id), **then** the amount comes from `commerce.OrderAmount(orderId)` — never re-computed here — and a transaction + redirect proceed exactly as fees do.
- **Given** the webhook marks the order transaction `success`, **when** the commit lands, **then** a `commission` ledger entry (platform commission per 11's rate) is appended and `payment_transaction_id` is attached to the 11 orders row (seam defined in 11's spec).
- **Given** the order was already paid/cancelled, **when** initiate runs, **then** it refuses `CONFLICT` — one paid transaction per order.

**Notes** — Same webhook, idempotency and receipt machinery; commission `TODO: Confirm` 5–10% rate owner (11/Rahul).

---

### `PAY-US-012` — Void an invoice before any payment

**Priority:** P1 · **Traces:** prd.md §5.4 · **Depends on:** PAY-US-001

**Story** — As a **School Admin**, I want to void a wrongly-issued invoice, but only if nobody has paid it, so that mistakes are correctable without ever unpicking money that moved.

**Acceptance criteria**

- **Given** an `issued` invoice with zero successful transactions, **when** I void it, **then** it becomes `void`, pending transactions are refused at initiate, and an audit entry records who/when/why (ids only).
- **Given** the invoice has ≥1 `success` transaction, **when** I attempt void, **then** it is refused `CONFLICT` — money is corrected by manual refund adjustment (`PAY-BR-011`), never by void.
- **Given** a voided invoice's deep link is tapped, **when** the pay screen loads, **then** it shows "invoice cancelled — contact the school office" (bn: "ইনভয়েস বাতিল হয়েছে — স্কুল অফিসে যোগাযোগ করুন").

**Notes** — A voided invoice can be superseded by reissuing a corrected one (new row, no edits to the old).

---

### `PAY-US-013` — Forged webhook replay is rejected and flagged

**Priority:** P0 · **Traces:** prompt.txt §9 · **Depends on:** PAY-US-006

**Story** — As a **system**, I want a webhook with a bad signature rejected before any processing and recorded as a security event, so that forged "payment success" floods cannot mint ledger entries.

**Acceptance criteria**

- **Given** a webhook whose signature fails verification, **when** it hits `POST /webhooks/{gateway}`, **then** it is refused **403**, a `gateway_events` row is written with `signature_valid=false`, an alert-level log fires (event id + gateway only — never the payload), and no transaction or ledger state changes.
- **Given** repeated bad signatures from one source, **when** the `payments` rate-limit class trips, **then** further requests get `RATE_LIMITED` and the IP is flagged for ops review.
- **Given** a validly-signed but out-of-window (replayed-timestamp) webhook, **when** checked, **then** it is treated as invalid (403) and flagged the same way.

**Notes** — Valid-signature-but-unknown-event-id is stored `processed=false` and alerted for ops triage, not 403 (could be a genuine new event type).

---

### `PAY-US-014` — Users see their own payment history and receipts

**Priority:** P1 · **Traces:** prd.md §5.4 (receipts) · **Depends on:** PAY-US-007

**Story** — As a **guardian or student**, I want a list of my own payments with downloadable receipts, so that I can prove I paid without calling the school office.

**Acceptance criteria**

- **Given** I call `GET /payments/transactions`, **when** the query runs, **then** I get only transactions I initiated (payer-scoped), newest first, with invoice/order title, ৳ amount + fee, gateway, status and receipt link.
- **Given** I request `GET /payments/receipts/{txnId}` for my own successful transaction, **when** the receipt exists, **then** I get the R2 URL (immutable object); School Admins of the paying student's school get it too — nobody else (`FORBIDDEN`).
- **Given** a transaction without a receipt yet (job still retrying), **when** I request it, **then** I get `NOT_FOUND` and the UI shows "receipt is being generated" (bn: "রসিদ তৈরি হচ্ছে") with the success state intact.

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `PAY-BR-001` | Every invoice, ledger and receipt row is tenant-scoped by `school_id`; no query without the scope (repository layer) | DB column + tenant-scoped repository |
| `PAY-BR-002` | Invoice lifecycle: `draft → issued → paid / partially_paid / void / overdue`; void only before any success; overdue only from `issued` past due date | DB CHECK + service state guards |
| `PAY-BR-003` | Only verified users (03) linked to the student — guardian(s) via the 03 guardian link, or the student — may view/pay that invoice; payer must be `VERIFIED` | Service (auth chain + link check) |
| `PAY-BR-004` | Every `success` transaction produces balanced ledger entries in the same DB transaction (fee: `fee_payment` [+ `convenience_fee` when config > 0]; order: `commission` [+ `payout` at settlement]); unbalanced commit is impossible | Service (single tx) + `PAY-IT` balance tests |
| `PAY-BR-005` | Webhook idempotency: `UNIQUE(gateway, gateway_txn_id)`; duplicate → 200 `DUPLICATE_WEBHOOK`, zero side effects | DB unique index + handler |
| `PAY-BR-006` | Webhooks are the one unauthenticated route — signature verified + replay window before any parsing beyond the envelope; invalid → 403 + flagged `gateway_events` row | Webhook middleware (module-owned) |
| `PAY-BR-007` | Never log or store secrets or raw webhook payloads — log/store ids + amounts only (payload digest, not payload) | `gateway_events` schema + slog redaction + `PAY-UT` |
| `PAY-BR-008` | Convenience fee: platform config, default **BDT 0 (off)** per `brd.md` §7 (supersedes `prd.md` §7 BDT 15–20); if enabled, flat per transaction, charged to the payer, shown before redirect; zero ⇒ no `convenience_fee` ledger row | Platform config (owner-changeable) |
| `PAY-BR-009` | One receipt per successful transaction, serial unique per school, issued once; PDF object immutable in R2 | UNIQUE(txn_id) + UNIQUE(school_id, serial_no) |
| `PAY-BR-010` | Every money mutation (issue, void, initiate, webhook state change, refund adjustment, settlement import) writes an `audit.Record` entry in the same transaction — ids + amounts only | Service + 01 `audit.Record` |
| `PAY-BR-011` | Refunds are manual (Super/School Admin), recorded as `adjustment` ledger entries; no gateway auto-refund at launch | Service (admin-only, audit-logged) |
| `PAY-BR-012` | `ledger_entries` is append-only — no UPDATE/DELETE path exists | DB rule/trigger (mirrors `audit_log`) |
| `PAY-BR-013` | Invoice `amount_bdt`, `title`, `student_id` are immutable after issue | Service (update path absent) |
| `PAY-BR-014` | A transaction can only succeed once; `success` is terminal (until `refunded` flag via manual adjustment) and re-webhooks are no-ops | State guard + idempotency index |
| `PAY-BR-015` | Order payments: order must be in a payable state per 11; amount from `commerce.OrderAmount`; one paid transaction per order; `payment_transaction_id` attached via 11's seam | Service + 11 contract |

Content accuracy (`prompt.txt` §12): no seeded invoices, amounts or gateway figures are presented as real — seed data is fictional ("Demo High School") and marked; gateway commission/fee values carry `TODO: Confirm` until Rahul confirms.

## 6. Validation Rules

| Field | Rule | Message key (`packages/shared` i18n catalog) |
| --- | --- | --- |
| invoice `title` | Required, 3–120 chars, trimmed | `validation.payments.title` |
| invoice `amount_bdt` | Required, numeric(12,2), > 0, ≤ 1,000,000 | `validation.payments.amount` |
| invoice `due_date` | Required, date ≥ today (issue date) | `validation.payments.dueDate` |
| invoice `kind` | ∈ tuition/exam/transport/other | `validation.payments.kind` |
| invoice `student_id` | Required uuid; student of the caller's school (04 scope) | `validation.payments.student` |
| bulk `section_id` | Required uuid; section of the caller's school; resolves 1–200 students | `validation.payments.section` / `validation.payments.bulkLimit` |
| initiate `gateway` | ∈ sslcommerz/bkash/nagad; gateway enabled | `validation.payments.gateway` |
| initiate target | Exactly one of `invoiceId` \| `orderId`; caller entitled to it; payable state | `validation.payments.target` |
| webhook envelope | Non-empty body; signature header present; timestamp within replay window | `validation.payments.webhook` (internal — never surfaced to end users) |
| ledger filters | `status ∈ …`, `month` = `YYYY-MM`, `classLevel` 1–12 (sections carry class level; no class entity), `date` = `YYYY-MM-DD` | `validation.payments.filter` |

Mirrored exactly by the OpenAPI contract (server validation) and the zod form schemas (web/app) generated from it. Both languages from day one — bn default (e.g. `validation.payments.amount` → bn: "পরিমাণ সঠিক পূর্ণসংখ্যা টাকায় লিখুন (১ থেকে ১০,০০,০০০)" / en: "Enter a valid amount in BDT (1 to 1,000,000)").

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to any protected endpoint | `UNAUTHENTICATED`, no side effect (webhook route excepted — signature instead, `PAY-BR-006`) |
| 2 | Cross-tenant invoice/ledger/receipt access | `TENANT_MISMATCH` / 404, no data leaked (tested per table) |
| 3 | Unverified (pending/suspended) payer hits initiate | Refused `FORBIDDEN` with verify-first message; invoice untouched |
| 4 | Webhook arrives before the browser callback | Webhook (authoritative) completes the txn; callback then finds terminal state and just redirects to status — no double effect |
| 5 | Callback arrives before the webhook | Callback polls gateway status, may mark terminal; if webhook later replays the same event → `DUPLICATE_WEBHOOK` no-op |
| 6 | Duplicate webhook replay with a forged signature | 403 + `gateway_events` flagged + alert (`PAY-US-013`) |
| 7 | All gateways down at initiate | Refused with bn/en "gateway unavailable" message; invoice unaffected; commerce COD unaffected (`06` §8) |
| 8 | R2 down during receipt generation | Job retries w/ backoff; payment/ledger final; receipt appears when R2 recovers |
| 9 | Pay tapped on already-paid invoice | `CONFLICT`; UI offers the existing receipt |
| 10 | Invoice voided while a redirect session is open | Initiate/check at callback refuses (`CONFLICT`/void state); no success possible on a voided invoice |
| 11 | Guardian taps expired push for a voided/paid invoice | Pay screen renders current state with bn/en explanation — never a stale pay button that 500s |
| 12 | Reduced motion enabled | Status spinner/ celebratory states render static (`05` §5) |
| 13 | Offline app pay attempt | Refused up front: payments require connectivity — clear bn/en message, nothing queued (money ≠ chat) |
| 14 | Settlement CSV malformed / wrong gateway file | Import refused `VALIDATION_FAILED` naming the offending row; ledger untouched |

## 8. Reporting Needs

- **School Admin (07 `/school/ledger`):** issued vs paid vs overdue counts; collected this month (৳); outstanding (৳); per-class collection rate — served by `GET /school/ledger/summary`.
- **Super Admin (07 revenue):** platform convenience-fee revenue (৳, per month), gateway success/failure rates, order commission totals — `ledger_entries` type-filtered aggregates.
- **Ops (reconciliation):** daily per-gateway settled vs ledger delta; mismatch list; invariant-check flag (`PAY-US-010`).
- Consumption shape: `payments.InvoiceStatus` / `payments.TransactionSummary` exports (06 §2) feed 07 dashboards without new tables.

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Gateway launch order & production accounts | Rahul | Open | SSLCommerz first (cards + internet banking), then bKash and Nagad wallets; sandbox keys until module 15 production cutover |
| 2 | Convenience fee amount (`prd.md` §7 allows 15–20) | Rahul | Open | **BDT 0 (off)** per `brd.md` §7 revised model; owner may enable via config — who bears gateway MDR `TODO: Confirm` |
| 3 | Settlement report file format per gateway | Rahul | Open | Manual CSV import at launch (one template per gateway); auto-fetch deferred; `TODO: Confirm` exact column specs |
| 4 | Refund mechanics | Rahul | Open | Manual, Super/School-Admin initiated, `adjustment` ledger entry, no gateway auto-refund at launch |
| 5 | Partial payments (`partially_paid` state) | Rahul | Open | Full-payment only at launch; `partially_paid` reserved for manual admin adjustments/reconciliation corrections |
| 6 | Order commission rate (11 seam) | Rahul (with 11) | Open | 5% flat platform commission entry at launch; rate change is config, not code |

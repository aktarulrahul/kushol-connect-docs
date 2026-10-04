# Payments — Backend Tasks & Database Design

**Module:** `12-payments` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `applications/api/openapi/openapi.yaml` · slog logging
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms · generated `openapi-fetch` client → api
**Last updated:** 2026-09-30

---

## 1. Database Design

### 1.1 Tables

#### `fee_invoices` (model `FeeInvoice`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | FK `schools.id` — **tenant scope column** |
| `student_id` | `uuid` | no | — | FK `users.id` (role=student, same school) |
| `title` | `text` | no | — | 3–120 chars, bn/en free text |
| `kind` | `text` | no | — | CHECK ∈ `tuition\|exam\|transport\|other` |
| `amount_bdt` | `numeric(12,2)` | no | — | CHECK `> 0` |
| `due_date` | `date` | no | — | ≥ issue date (service-checked) |
| `status` | `text` | no | `issued` | CHECK ∈ `draft\|issued\|paid\|partially_paid\|void\|overdue` |
| `issued_by` | `uuid` | no | — | FK `users.id` (school_admin actor) |
| `voided_by` | `uuid` | yes | null | FK `users.id`; set only on void |
| `voided_at` | `timestamptz` | yes | null | set only on void |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** CHECKs above; FK to `schools`/`users`. **Indexes:** `(school_id, status, due_date)` → ledger invoice tab + overdue sweep · `(school_id, student_id, status)` → per-student due list · `(student_id)` FK support.

#### `payment_transactions` (model `PaymentTransaction`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK — the public txn id (receipts, deep links) |
| `school_id` | `uuid` | no | — | FK `schools.id` — denormalized tenant scope (from invoice/order) |
| `invoice_id` | `uuid` | yes | null | FK `fee_invoices.id`; null for order payments |
| `order_id` | `uuid` | yes | null | 11 seam; null for fee payments; CHECK exactly one of invoice_id/order_id |
| `payer_id` | `uuid` | no | — | FK `users.id` (who tapped pay) |
| `gateway` | `text` | no | — | CHECK ∈ `sslcommerz\|bkash\|nagad` |
| `gateway_txn_id` | `text` | no | — | gateway's transaction reference |
| `amount_bdt` | `numeric(12,2)` | no | — | principal (fee amount or order amount) |
| `convenience_fee_bdt` | `numeric(12,2)` | no | `0` | payer-side fee (`PAY-BR-008`; 0 for order payments) |
| `status` | `text` | no | `initiated` | CHECK ∈ `initiated\|redirected\|success\|failed\|expired\|refunded` |
| `initiated_by` | `uuid` | no | — | FK `users.id` (= payer_id; kept for audit clarity) |
| `completed_at` | `timestamptz` | yes | null | set on success/failure/expiry |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** `UNIQUE(gateway, gateway_txn_id)` — the idempotency core (`PAY-INV-3`); CHECK `(invoice_id IS NULL) <> (order_id IS NULL)`. **Indexes:** the unique index → webhook lookup · `(invoice_id)` · `(order_id)` · `(payer_id, created_at DESC)` → own-transactions · `(school_id, status, created_at DESC)` → admin ledger tab · partial `(status, updated_at) WHERE status IN ('initiated','redirected')` → expiry sweep.

#### `ledger_entries` (model `LedgerEntry`) — append-only

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | FK `schools.id` — tenant scope (platform-side entries still record the school context) |
| `txn_id` | `uuid` | yes | null | FK `payment_transactions.id`; null for standalone adjustments |
| `type` | `text` | no | — | CHECK ∈ `fee_payment\|convenience_fee\|commission\|payout\|adjustment` |
| `debit_bdt` | `numeric(12,2)` | no | `0` | CHECK `>= 0` |
| `credit_bdt` | `numeric(12,2)` | no | `0` | CHECK `>= 0`; CHECK `(debit_bdt = 0) <> (credit_bdt = 0)` |
| `balance_note` | `text` | no | — | human/audit note: who benefits ("school", "platform", refund reason) + ids |
| `created_by` | `uuid` | yes | null | null = system (job/webhook) |
| `created_at` | `timestamptz` | no | `now()` | |

**Constraints:** append-only via DB rule/trigger (no UPDATE/DELETE) — mirrors 01's `audit_log` pattern (`PAY-INV-1`). **Indexes:** `(school_id, created_at DESC)` → ledger tab · `(school_id, type)` → summary aggregates · `(txn_id)` → per-transaction drill-down.

#### `payment_receipts` (model `PaymentReceipt`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | FK `schools.id` — tenant scope |
| `txn_id` | `uuid` | no | — | FK `payment_transactions.id`; `UNIQUE` — one receipt per success |
| `media_asset_id` | `uuid` | no | — | FK `media_assets.id` (05) — the PDF in R2 |
| `serial_no` | `text` | no | — | `{SCHOOL-YY}-{seq:6}`; `UNIQUE(school_id, serial_no)` |
| `issued_at` | `timestamptz` | no | `now()` | |

**Constraints:** UNIQUE(txn_id), UNIQUE(school_id, serial_no). **Indexes:** the two unique indexes (all access paths — lookups by txn, listing by school).

#### `gateway_events` (model `GatewayEvent`) — webhook envelope audit

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `gateway` | `text` | no | — | CHECK ∈ `sslcommerz\|bkash\|nagad` |
| `event_id` | `text` | no | — | gateway event/txn reference from the envelope |
| `signature_valid` | `boolean` | no | — | false rows are security flags (`PAY-US-013`) |
| `payload_digest` | `text` | no | — | sha256 hex of the raw body — proves what arrived **without storing it** |
| `payload_summary` | `jsonb` | no | — | ids + amounts only (`{txnRef, amount, status}`) — never secrets, never raw payload (`PAY-BR-007`) |
| `processed` | `boolean` | no | `false` | flipped by the handler in-tx |
| `processed_txn_id` | `uuid` | yes | null | FK `payment_transactions.id` when applied |
| `error_code` | `text` | yes | null | e.g. `DUPLICATE_WEBHOOK`, `UNKNOWN_EVENT` |
| `received_at` | `timestamptz` | no | `now()` | |

**Constraints:** UNIQUE(gateway, event_id) — envelope-level dedupe ahead of the txn unique index. **Indexes:** `(gateway, event_id)` · `(signature_valid, received_at)` → security review · partial `(processed) WHERE NOT processed` → triage.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `20270210090000_create_fee_invoices` | ✅ |
| 2 | `20270210091500_create_payment_transactions` | ✅ |
| 3 | `20270210092000_create_ledger_entries` (+ append-only rule/trigger) | ✅ (drop trigger + table) |
| 4 | `20270210092500_create_payment_receipts` | ✅ |
| 5 | `20270210093000_create_gateway_events` | ✅ |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| "Demo High School" tuition/exam invoices + one sandbox success txn + ledger entries + receipt (dev seeds only) | `DRAFT` (clearly fictional) | prd.md §5.4; amounts invented for dev, marked fictional (`prompt.txt` §12) |
| Gateway adapter config (sandbox base URLs) | `DRAFT` | `SSLCOMMERZ_*` / `BKASH_*` / `NAGAD_*` env, sandbox until module 15 `TODO: Confirm` |

---

## 2. Server Contracts

### Endpoint `POST /api/v1/school/invoices` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | middleware: authenticate → load role claims → tenant-scope (school_admin of own school; super_admin read-only elsewhere) |
| **Input** | contract-generated validator; `{studentId, title, kind, amountBdt, dueDate}`; zod-mirrored on web |
| **Result** | `{ "data": InvoiceDTO }` — 201; RFC-7807 `application/problem+json` on error |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` · `TENANT_MISMATCH` · `NOT_FOUND` |
| **Rate limit** | class `default` (admin action) |
| **Audit** | yes — issue (`PAY-BR-010`) |
| **Stories** | `PAY-US-001` |

### Endpoint `POST /api/v1/payments/initiate` (Go)

| | |
| --- | --- |
| **Auth** | full chain; payer must be VERIFIED and entitled (guardian/student of the invoice, or order buyer per 11) |
| **Input** | `{invoiceId \| orderId, gateway}` — exactly one target |
| **Result** | `{ "data": { txnId, gateway, redirectUrl, redirectMethod, params } }` — gateway-hosted checkout payload |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` (not entitled/unverified) · `VALIDATION_FAILED` · `NOT_FOUND` · `CONFLICT` (paid/void/cancelled target) · `PAYMENT_FAILED` (gateway refused/down — module code) · `RATE_LIMITED` |
| **Rate limit** | class `payments` (strict): 5/min/user |
| **Audit** | yes — initiate |
| **Stories** | `PAY-US-004`, `PAY-US-005`, `PAY-US-011` |

### Endpoint `POST /api/v1/webhooks/{gateway}` — ⚠️ the one unauthenticated-but-signature-verified route

| | |
| --- | --- |
| **Auth** | **NO auth chain — documented exception.** Order: rate limit (`payments` class, 120/min/gateway) → signature + timestamp replay-window verification → only then parse the payload. Flagged `security: []` + webhook marker in the OpenAPI spec; route mounted outside the auth middleware group |
| **Input** | raw body (bytes, for signature); gateway path param |
| **Result** | `200 {"processed": true\|false, "reason": "DUPLICATE_WEBHOOK"}` — always 2xx for valid signatures (gateway retries otherwise); state applied in one tx (txn transition + ledger + invoice/order + audit + `gateway_events.processed`) |
| **Errors** | `403` invalid signature/replay-window (with flagged `gateway_events` row + alert log) · `VALIDATION_FAILED` (well-signed, malformed) |
| **Rate limit** | class `payments` |
| **Audit** | yes — every terminal state change |
| **Stories** | `PAY-US-006`, `PAY-US-007`, `PAY-US-013` |

### Remaining endpoints (same table shape; abridged)

| Endpoint | Auth / scope | Result | Errors | Rate class | Audit | Stories |
| --- | --- | --- | --- | --- | --- | --- |
| `POST /api/v1/school/invoices/bulk` | school_admin own school; section of own school (04) | `{created, failed[]}` | standard + `VALIDATION_FAILED` (`bulkLimit`) | default | yes (batch summary) | `PAY-US-002` |
| `GET /api/v1/school/invoices` | school_admin own school; filters status/class/month + pagination | `InvoiceDTO[]` + totals | standard | default | no | `PAY-US-009` |
| `PATCH /api/v1/school/invoices/{id}/void` | school_admin own school; body `{reason}` | `{invoice}` voided | `CONFLICT` if ≥1 success | default | yes | `PAY-US-012` |
| `GET /api/v1/school/ledger` | school_admin own school; type/month filters + pagination | `LedgerEntryDTO[]` + totals (server-computed) | standard | default | no | `PAY-US-009` |
| `GET /api/v1/school/ledger/summary` | school_admin own school; `?month=` | counts + ৳ totals (issued/paid/overdue, collected, outstanding) | standard | default | no | `PAY-US-009`, §8 |
| `GET /api/v1/school/payments/reconciliation?date=` | super_admin + school_admin (own school slice); `?gateway=` optional | per-gateway settled-vs-ledger + mismatch list | standard | default | no (import is audited) | `PAY-US-010` |
| `POST /api/v1/payments/callback/{gateway}` | none (gateway browser return); txn token in payload; status re-check vs gateway | 302 → app deep link `/payments/status/{txnId}` (or web receipt) | `PAYMENT_FAILED` surfaces in redirect state, not as an API error to the browser | `payments` | yes (terminal changes only) | `PAY-US-005` |
| `GET /api/v1/payments/transactions` | authenticate; payer-scoped from claims | own `TransactionDTO[]` newest-first | standard | default | no | `PAY-US-014` |
| `GET /api/v1/payments/receipts/{txnId}` | payer themself OR school_admin of the txn's school | `{receiptUrl, serialNo, issuedAt}` (immutable R2 URL via 05) | `NOT_FOUND` (not yet generated) · `FORBIDDEN` | default | no | `PAY-US-014` |

Refund/settlement admin actions (`adjustment` entries, settlement CSV import) are Super/School Admin endpoints defined at build (`PAY-BE-017`/`PAY-BE-018`) — same chain, class `default`, audited (`PAY-BR-011`, `PAY-US-010`).

### Web Server Action / Route Handler (Next.js)

`/school/ledger`, invoice forms, reconciliation screen call the Go API through the generated `openapi-fetch` client — never the database directly. Same auth (school-admin session, 03) + zod mirrors of the contract shapes; money totals always come from api responses (no client-side arithmetic).

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `PAY-BE-001` | `payments.IssueInvoice(actor, in)` | school_admin of claims' school; student ∈ school (04); amount/due-date rules (`01` §6); status `issued` | invoice list tags | yes |
| `PAY-BE-002` | `payments.IssueInvoicesBulk(actor, in)` | section roster via 04 (1–200); single tx; returns per-student failures; enqueues notify jobs after commit | invoice list tags | yes (batch) |
| `PAY-BE-003` | `payments.VoidInvoice(actor, id, reason)` | zero successful txns (`PAY-INV-5`) else `CONFLICT`; sets voided_by/at | invoice + summary tags | yes |
| `PAY-BE-004` | `payments.Initiate(actor, target, gateway)` | verified payer + entitlement (`PAY-BR-003`/`PAY-BR-015`); amount: invoice row or `commerce.OrderAmount`; gateway up (health flag) else `PAYMENT_FAILED`; creates txn `initiated`→`redirected`; returns redirect payload | none (no-cache) | yes |
| `PAY-BE-005` | `payments.ProcessWebhook(gateway, rawBody)` | verify signature + window first (`PAY-BR-006`); write `gateway_events`; idempotent via `UNIQUE(gateway, gateway_txn_id)` (duplicate → `DUPLICATE_WEBHOOK` no-op, 200); success ⇒ **one tx:** txn→success + balanced ledger (`PAY-INV-2`) + invoice→paid / 11-attach + audit + receipt job enqueue | none | yes |
| `PAY-BE-006` | `payments.HandleCallback(gateway, payload)` | verify return token; single `FetchStatus` check; apply terminal state if webhook hasn't; always redirect to status screen | none | terminal only |
| `PAY-BE-007` | `payments.MarkExpired` (sweep core) | stale `initiated|redirected` > 30 min → `expired`; push via 06; invoice untouched | none | yes (batch) |
| `PAY-BE-008` | `payments.SweepOverdue` | `issued` + `due_date < today` → `overdue`; daily | invoice tags | yes (batch) |
| `PAY-BE-009` | `payments.GenerateReceipt(txnID)` (job handler) | exactly-once per success (`PAY-INV-4`); PDF bytes (bn/en per school locale) → 05 `media.PutObject` → serial via `pg_advisory_xact_lock(school)` + count; insert receipt; result push w/ `/receipts/{txnId}` | none | yes |
| `PAY-BE-010` | `payments.ReconcileDay(date, gateway?)` (job core) | ledger vs settlement import (`TODO: Confirm` format); invariant check `PAY-INV-7`; mismatch list; audit summary | none | yes |
| `PAY-BE-011` | `payments.ImportSettlement(actor, gateway, csv)` | super_admin; per-gateway template parser; malformed → `VALIDATION_FAILED` + row no; parsed rows cached (Redis 24 h) for reconciliation reads | none | yes |
| `PAY-BE-012` | `payments.RecordRefundAdjustment(actor, txnID, note)` | super/school_admin; `adjustment` entry (append-only); txn→`refunded`; **no gateway call at launch** (`PAY-BR-011`) | summary tags | yes |
| `PAY-BE-013` | `payments.ListInvoices(actor, filters)` / `ListLedger(actor, filters)` / `LedgerSummary(actor, month)` | tenant-scoped only (`PAY-BR-001`); totals computed in SQL; always-fresh reads | — | no |
| `PAY-BE-014` | `payments.ListOwnTransactions(payer)` / `GetReceipt(actor, txnID)` | payer-scoped; receipt visible to payer + txn's school admin | — | no |
| `PAY-BE-015` | `PaymentGateway` adapters (sslcommerz/bkash/nagad): `Initiate` / `VerifyWebhook` / `FetchStatus` | signature schemes + replay windows per gateway; timeouts 15 s; health flag feeds chooser hiding | — | no (adapter) |
| `PAY-BE-016` | Webhook middleware (signature-first pipeline) | the documented auth-chain exception (`02` §6); 403 path writes flagged `gateway_events` + alert log (ids only) | — | yes (rejects) |
| `PAY-BE-017` | `POST /school/refunds` endpoint wiring for `PAY-BE-012` | same chain; class `default` | summary tags | yes |
| `PAY-BE-018` | `POST /school/settlements/import` endpoint wiring for `PAY-BE-011` | super_admin; multipart CSV | none | yes |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `PAY-BE-019` | `Invoices.Create / CreateBatch / GetByID / ListBySchool / Void / MarkOverdue` | INSERT (batch = single stmt); SELECT scoped `WHERE school_id = $1 AND …` + filters; UPDATE status guarded `AND status = 'issued'` | `(school_id, status, due_date)` · `(school_id, student_id, status)` |
| `PAY-BE-020` | `Transactions.Create / GetByGatewayRef / TransitionStatus / ListByPayer / ListBySchool / FindStale / CountSuccessForInvoice` | INSERT (unique-violation → `DUPLICATE_WEBHOOK` path); guarded status transitions `UPDATE … WHERE id=$1 AND status=$2`; stale `WHERE status IN ('initiated','redirected') AND updated_at < now()-interval '30 min'` | UNIQUE(gateway, gateway_txn_id) · `(payer_id, created_at DESC)` · `(school_id, status, created_at DESC)` · partial stale |
| `PAY-BE-021` | `Ledger.Append / ListBySchool / SumByType / SumFeePaymentsForDay` | INSERT-only (trigger rejects UPDATE/DELETE); SUM/CASE aggregates `GROUP BY type` | `(school_id, created_at DESC)` · `(school_id, type)` · `(txn_id)` |
| `PAY-BE-022` | `Receipts.Create / GetByTxn / SerialNext(school)` | INSERT with `pg_advisory_xact_lock(hashtext($school))` + count→serial; SELECT by txn/school | UNIQUE(txn_id) · UNIQUE(school_id, serial_no) |
| `PAY-BE-023` | `GatewayEvents.Record / MarkProcessed / ListFlagged / ListUnprocessed` | INSERT (incl. `signature_valid=false` rejects); guarded flip `WHERE NOT processed` | `(gateway, event_id)` · `(signature_valid, received_at)` · partial unprocessed |

All queries sqlc-generated, tenant-scoped at the repository boundary; cross-tenant probes are tested per table (`06` §9).

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `PAY-JOB-001` | `receipt.generate` {txnID} | enqueued in the success tx (`PAY-BE-005`) | yes — UNIQUE(txn_id) guards double issue | 01 worker retry/backoff; R2-down recovers late; sweep re-enqueues missing receipts (`02` §8.7) |
| `PAY-JOB-002` | `invoice.notify` {invoiceID} | after issue commit (single + bulk) | yes — delivery dedupe is 06's | degraded: invoice still payable in-app |
| `PAY-JOB-003` | `payments.reconcile` {date} | cron daily 06:00 Asia/Dhaka | yes — report regenerated from append-only ledger + cached settlement | failure → alert; rerun safe |
| `PAY-JOB-004` | `payments.overdue_sweep` | cron daily 00:05 Asia/Dhaka | yes — guarded status UPDATE | retry per worker policy; missed days self-heal (date-agnostic predicate) |
| `PAY-JOB-005` | `payments.expire` | cron every 10 min | yes — guarded status UPDATE | retry per worker policy |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `PAY-UT-001` | Ledger balance builder: fee success → fee_payment + convenience_fee credits sum == charged total; order success → commission entry | Unit | `PAY-INV-2`, `PAY-BR-004` |
| `PAY-BE` redaction | slog output of webhook/initiate paths contains ids+amounts, never signatures/payloads/keys | Unit | `PAY-BR-007`, `PAY-INV-6` |
| `PAY-UT-003` | Serial generator under `pg_advisory_xact_lock` (concurrent goroutines, same school) — strictly increasing, per-school scoped | Unit (DB-backed) | `PAY-INV-4` |
| `PAY-UT-004` | Webhook signature verifier per adapter: valid / invalid / tampered body / expired timestamp | Unit | `PAY-BR-006`, `PAY-US-013` |
| `PAY-UT-005` | Validation mirrors: amount bounds, due-date, bulk cap 200, gateway enum | Unit | `01` §6 |
| `PAY-IT-001` | Signature verification end-to-end: valid processes; invalid/tampered → 403 + flagged `gateway_events` + no state change; replayed-timestamp → 403 | Integration | `PAY-US-006`, `PAY-US-013` |
| `PAY-IT-002` | Double-webhook idempotency: same gateway event twice → single txn, single ledger pair, second returns `DUPLICATE_WEBHOOK` 200 | Integration | `PAY-INV-3`, `PAY-BR-005` |
| `PAY-IT-003` | Convenience-fee split: success txn writes fee_payment(amount) + convenience_fee(15) rows in one tx; abort rolls back both | Integration | `PAY-INV-2`, `PAY-BR-008` |
| `PAY-IT-004` | Receipt generation job: success → PDF asset row via 05 + serial + push payload with `/receipts/{txnId}`; rerun is a no-op | Integration | `PAY-US-007`, `PAY-JOB-001` |
| `PAY-IT-005` | Cross-tenant: School Admin B reads/voids School A invoice/ledger/receipt → `TENANT_MISMATCH`/404, no rows leaked (every owned table) | Integration | `PAY-BR-001` |
| `PAY-IT-006` | Void-before-payment-only: void with 0 successes OK; void after success → `CONFLICT` | Integration | `PAY-INV-5`, `PAY-US-012` |
| `PAY-IT-007` | Overdue sweep + expire sweep: due invoices flip, stale txns expire, paid/void rows untouched | Integration | `PAY-JOB-004/005`, `PAY-US-008` |
| `PAY-IT-008` | Unauthenticated probes on every protected endpoint → `UNAUTHENTICATED`; webhook route with no signature → 403 | Integration | `02` §6 exception is signature-only |
| `PAY-IT-009` | Order seam: order payment success → commission entry + 11 attach hook invoked once; already-paid order initiate → `CONFLICT` | Integration | `PAY-US-011`, `PAY-BR-015` |

Always include: unauthenticated call denied for every protected entry point (webhook excepted by design, signature-enforced); validation rejects bad input; a cross-tenant read/write attempt returns `TENANT_MISMATCH`/404 for every tenant-scoped table.

## 7. Task Checklist

> Tick with a date: `[x] <ID> … — YYYY-MM-DD`.

### Schema

- [x] `PAY-BE-031` Migrations 1–5 (five tables, constraints, indexes, append-only trigger) — 2026-10-03 (5 migrations incl. append-only trigger; **owner SQL run pending — Gate 2**)
- [x] `PAY-BE-032` sqlc queries + models for all five tables — 2026-10-03 (5 query files; contracts no drift)

### Repository · Service · Entry points · Jobs · Seed · Tests

- [ ] `PAY-BE-019` … `PAY-BE-023` repositories (order as listed)
- [ ] `PAY-BE-001` … `PAY-BE-003` invoice service (single, bulk, void)
- [ ] `PAY-BE-015` `PaymentGateway` interface + SSLCommerz adapter (first), bKash, Nagad
- [ ] `PAY-BE-016` webhook middleware + `PAY-BE-005` `ProcessWebhook`
- [ ] `PAY-BE-004` `Initiate` + `PAY-BE-006` `HandleCallback`
- [ ] `PAY-BE-000` **Spike first:** Bengali PDF rendering (shaping of conjuncts/vowel signs) — sample bn+en receipt, chosen library recorded as an ADR in `07-progress.md`
- [ ] `PAY-BE-009` receipt job (with 05 `media.PutObject`) + `PAY-JOB-001/002`
- [ ] `PAY-JOB-003/004/005` cron jobs + `PAY-BE-007/008/010` cores
- [ ] `PAY-BE-011/017/018` settlement import + refund adjustment (launch-manual)
- [ ] `PAY-BE-013/014` read services behind the REST routes (`02` §2 table)
- [ ] `06` §2 exports: `payments.InitiateInvoicePayment` / `InvoiceStatus` / `TransactionSummary`
- [ ] Seed: Demo High School invoice set (fictional, marked)
- [ ] Tests: `PAY-UT-001…005`, `PAY-IT-001…009` green in CI

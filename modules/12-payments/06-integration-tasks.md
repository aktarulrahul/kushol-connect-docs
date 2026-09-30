# Payments — Integration Tasks

**Module:** `12-payments` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

> `02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
> **contract**. **No cross-module call, cache key or external dependency may exist in code unless
> it is declared here** (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `07-command-center-web` | they call us | REST `/school/invoices*`, `/school/ledger*`, `/school/payments/reconciliation` + exports (`06` §2) for dashboard cards | degraded — ledger screens show error states; payments unaffected |
| I-2 | `11-campus-commerce` | they call us | REST `POST /payments/initiate {orderId}` + export `payments.TransactionSummary` for checkout; 11 attaches `payment_transaction_id` on success (seam defined in 11's spec) | degraded — order checkout falls back to COD; fee payments unaffected |
| I-3 | `06-notifications` | we call them | `notify.SendToUser` — fee-due push (`/payments/{invoiceId}`) + payment-result push (`/receipts/{txnId}`) | degraded, never fatal — invoices remain payable in-app |
| I-4 | `05-communication-engine` | we call them | `media.PutObject` (receipt PDFs → R2; declared in 05 `06` §2) | degraded — receipt job retries; money state already final |
| I-5 | `03-identity-access` | we call them | auth chain (authenticate → role claims → tenant-scope); verification status; guardian↔student link (03 `guardians.IsGuardianOf` / `LinkedStudents`); `users.locale` | fatal to entry points by design (`UNAUTHENTICATED`/`FORBIDDEN`) |
| I-6 | `04-organization-hierarchy` | we call them | `hierarchy.ResolveUserNodes` + section rosters (school scoping, bulk-invoice targeting) | degraded — issue forms' pickers degrade; no cross-school fallback ever |
| I-7 | `01-foundations` | we call them | `jobs.Enqueue`/`Register` (receipt, reconcile, sweeps, notify fan-out), `audit.Record` (every money mutation), RFC-7807 envelope | receipt/recon jobs stay queued (retry); un-audited money mutation aborts by design |
| I-8 | SSLCommerz / bKash / Nagad (external) | bidirectional | HTTPS hosted-checkout initiate + server-to-server webhook + status API | degraded — chooser hides a down gateway; ledger core never trusts client-side claims |
| I-9 | app / web callback | they call us | `POST /payments/callback/{gateway}` (browser/app return) — UX only | degraded — webhook remains authoritative |

## 2. Exported Contract

```text
payments.InitiateInvoicePayment(ctx, actor ActorClaims, invoiceID uuid, gateway string) (RedirectPayload, error)
payments.InvoiceStatus(ctx, actor ActorClaims, invoiceID uuid) (InvoiceStatusDTO, error)
payments.TransactionSummary(ctx, actor ActorClaims, txnID uuid) (TransactionSummaryDTO, error)
```

```text
RedirectPayload{ txnId, gateway, redirectUrl, redirectMethod, params }   // opaque gateway checkout reference
InvoiceStatusDTO{ invoiceId, status, amountBdt, paidTxnId?, lastTxnStatus? }
TransactionSummaryDTO{ txnId, kind: fee|order, refId, amountBdt, convenienceFeeBdt,
                       gateway, status, completedAt?, receiptUrl? }
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `payments.InitiateInvoicePayment(invoiceID, gateway)` | 07 (dashboard "collect" shortcuts, server-side) · app/web via REST initiate | `RedirectPayload` | `FORBIDDEN` (unverified/unentitled) · `CONFLICT` (paid/void) · `PAYMENT_FAILED` · `VALIDATION_FAILED` | Same core as the REST route; order payments go through the same path with `orderId` (11's seam, `PAY-BR-015`) |
| `payments.InvoiceStatus(invoiceID)` | 07 (ledger cards) · 11 (checkout pre-checks) | `InvoiceStatusDTO` | `NOT_FOUND` · `TENANT_MISMATCH` | Read-only; the app status poll consumes this via REST |
| `payments.TransactionSummary(txnID)` | 07 (transaction drawer) · 11 (order → payment display) | `TransactionSummaryDTO` | `NOT_FOUND` · `TENANT_MISMATCH`/`FORBIDDEN` (payer or school admin only) | Contains no secrets — ids/amounts/status only |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the context; services return domain errors (mapped to the problem envelope at the handler), never raw HTTP; signature changes are additive first.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `notify.SendToUser(userID, PushPayload{type: payment_result \| fee_due, deepLink})` | 06 | Degraded — push lost, flow continues (invoice list + status screen carry the UX); 06 owns retries |
| `media.PutObject(ctx, in PutInput{bytes, kind: receipt_pdf, schoolId})` → `MediaAssetDTO` | 05 — declared in 05 `06` §2 (2026-09-30) | Receipt job retries w/ backoff (`PAY-JOB-001`); 05 today ships only `PresignUpload`/`ConfirmUpload` (client flow); api-generated PDFs need this small server-side put helper — flagged **additive**, agreed shape: same sniffer/allowlist rules, service-account path |
| `commerce.OrderAmount(orderID)` + success attach hook (`payment_transaction_id` → 11 orders row) | 11 (seam defined in 11's spec) | Order payment refused at initiate (`PAYMENT_FAILED`) if 11 unreachable; fee path unaffected; attach failure → refund path + reconciliation flag (`02` §8.9) |
| `hierarchy.ResolveUserNodes(userID)` / section roster reads | 04 | Bulk issue refuses (`VALIDATION_FAILED`) rather than guessing scope; single issue depends on student's school claim |
| Auth chain + `users` (locale, verification) | 03 | Chain failures propagate (`UNAUTHENTICATED`/`FORBIDDEN`); SUSPENDED payer refused |
| `jobs.Enqueue` / `jobs.Register`, `audit.Record` | 01 | Jobs stay QUEUED (retry/backoff); `audit.Record` failure aborts the money mutation — no un-audited commit |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| Issue (single/bulk) / void | `payments:invoices:{schoolId}` (web tag + app query invalidation); ledger is never cached |
| Webhook success / callback terminal change | ledger + summary are read fresh (`no-store`); app `payments:invoices:{userId}` invalidated on next focus |
| Refund adjustment / settlement import | `payments:invoices:{schoolId}` summary refetch |
| Receipt created | none (immutable object, fetched by URL) |

| Read | Tagged with |
| --- | --- |
| `GET /school/invoices*`, `/school/ledger*` | **never cached** — money screens are always fresh (`02` §4) |
| App invoice list | `payments:invoices:{userId}` (TanStack Query, 30 s TTL) |
| Receipt PDF | immutable R2 object — cache forever (new receipt = new object) |
| Gateway health flag (chooser hiding) | `payments:gateway-health` (Redis, TTL 60 s) |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| SSLCommerz (first — cards + internet banking) | HTTPS hosted checkout + server-to-server webhook + status API | `SSLCOMMERZ_*` (store id + hash secret; envconfig-parsed; sandbox until module 15) | 15 s | Webhooks idempotent (`UNIQUE(gateway, gateway_txn_id)`) + status-poll fallback; expiry sweep backstop | Gateway chooser hides it when health-flagged; fee invoices unaffected |
| bKash (wallet) | HTTPS hosted checkout (bKash temp-token checkout) + webhook + status API | `BKASH_*` (app key/secret, username/password — config module only) | 15 s | same | same |
| Nagad (wallet) | HTTPS hosted checkout + webhook + status API | `NAGAD_*` (merchant id + keys; config module only) | 15 s | same | same |
| (R2 via 05, FCM via 06) | n/a — always through module services | none held here | — | — | See I-3/I-4 |

All webhook payloads are signature-verified before parsing; **secrets and raw payloads are never logged or stored** — `gateway_events` keeps ids + amounts + digest only (`PAY-BR-007`). Settlement reports are manual CSV imports at launch; per-gateway file format `TODO: Confirm`.

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| Ledger tabs + filters (web) | `GET /school/invoices` · `GET /school/ledger` | Filtered, paginated rows + server-computed totals; `no-store` |
| Summary cards (web) | `GET /school/ledger/summary` | counts + ৳ totals for the month |
| Issue forms (web) | `POST /school/invoices` · `POST /school/invoices/bulk` | `InvoiceDTO` / `{created, failed[]}`; zod mirrors of `01` §6 |
| Void (web) | `PATCH /school/invoices/{id}/void` | `CONFLICT` surfaced when payments exist |
| Reconciliation (web) | `GET /school/payments/reconciliation?date=` | per-gateway totals + mismatch rows |
| Pay now (app) | `POST /payments/initiate` | `RedirectPayload` → in-app browser |
| Return/status (app) | callback 302 → `payments.InvoiceStatus` poll | success/failure/pending states |
| Receipt (app/web) | `GET /payments/receipts/{txnId}` | immutable R2 URL + serial no |
| Own history (app) | `GET /payments/transactions` | payer-scoped rows, newest first |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source — regenerate Go + TS contract code on every spec change. Gateway-specific webhook payload shapes are versioned **internally**: each adapter maps its gateway's external schema to our stable internal event model (v1), so a gateway format change touches one adapter, not the ledger. The `/receipts/{txnId}` deep-link route and the `payment_result` payload type are frozen jointly with module 06 (`NTF-INT-007`); new webhook event types arrive as adapter mappings flagged `UNKNOWN_EVENT` + alert until reviewed, never auto-applied.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| One gateway down (e.g. bKash) | Other gateways; all ledger/reads; COD orders (11 unaffected) | Chooser hides bKash; bn/en unavailable copy | Health flag clears → reappears |
| **All gateways down** | Invoicing, ledger, receipts (history), commerce COD | initiate refused: "পেমেন্ট গেটওয়ে সাময়িকভাবে অচল…" — invoices unaffected | Adapters' health flags clear; retry |
| Webhook endpoint down (api restart) | Payer checkout pages still work (gateway-hosted) | Status screen polls → "processing — we'll notify you" | Gateway retries per its policy + status-poll + expiry-sweep backstops complete the state |
| R2 down (receipts) | All money flows (payment/ledger final before receipt) | "রসিদ তৈরি হচ্ছে…" on receipt link | `receipt.generate` retries; late receipt, never lost |
| 06 (push) down | Entire payment flow | No push; invoice list + status screen carry UX | 06 queues + drains |
| 11 unreachable | Fee payments fully unaffected | Order initiate refused with clear message | Checkout retries; COD fallback |
| Redis down | DB UNIQUE index still guards idempotency | Slower webhook path (no fast-path dedupe) | Redis reconnect; no correctness impact |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `PAY-UT-001` | Ledger balance builder — balanced entries per success; unbalanced input impossible | Unit | `PAY-INV-2` |
| `PAY-UT-004` | Signature verification (per adapter): valid / invalid / tampered / replayed-timestamp | Unit | `PAY-BR-006` |
| `PAY-UT-005` | Log redaction — no secrets/payloads in webhook/initiate logs | Unit | `PAY-BR-007` |
| `PAY-IT-001` | Signature IT: valid → processed; invalid/tampered → 403 + flagged `gateway_events` + zero state change | Integration | `PAY-US-013` |
| `PAY-IT-002` | Idempotent double-webhook IT: replay same event → one txn, one ledger effect, 200 `DUPLICATE_WEBHOOK` | Integration | `PAY-INV-3`, `PAY-US-006` |
| `PAY-IT-003` | Convenience-fee split IT: `fee_payment` + `convenience_fee` rows in one tx; abort rolls back both | Integration | `PAY-BR-008`, `PAY-BE-005` |
| `PAY-IT-004` | Receipt generation job IT: success → 05-stored PDF + serial + result push payload (`/receipts/{txnId}`); rerun no-op | Integration | `PAY-US-007`, `PAY-JOB-001` |
| `PAY-IT-005` | Cross-tenant invoice/ledger/receipt access denied (`TENANT_MISMATCH`/404) for every owned table | Integration | `PAY-BR-001` |
| `PAY-IT-006` | Void-before-payment-only IT: 0 successes → void OK; ≥1 success → `CONFLICT` | Integration | `PAY-INV-5`, `PAY-US-012` |
| `PAY-IT-007` | Overdue sweep IT: issued past due → overdue; paid/void untouched | Integration | `PAY-US-008`, `PAY-JOB-004` |
| `PAY-IT-008` | Unauthenticated probes on all protected routes; webhook route rejects missing signature | Integration | `02` §6 exception boundary |
| `PAY-IT-009` | Order seam IT: order success → `commission` entry + 11 attach called once; double pay → `CONFLICT` | Integration | `PAY-US-011`, `PAY-BR-015` |
| `PAY-E2E-001` | Playwright (web): issue invoice → visible in ledger with correct server totals → CSV export | Playwright | `PAY-FE-001…004`, `PAY-US-009` |
| `PAY-E2E-002` | Maestro (app): fee-due push tap → pay screen → gateway chooser → status screen (sandbox) → receipt link | Maestro | `PAY-US-003…007` |

## 10. Task Checklist

- [ ] `PAY-INT-001` Publish exports `InitiateInvoicePayment` / `InvoiceStatus` / `TransactionSummary`; 07/11 consumer stubs compile
- [ ] `PAY-INT-002` Confirm 11's seam signatures (`commerce.OrderAmount` + attach hook) against 11's spec; adapt names if 11 finalizes differently — flag any drift in `08-gaps.md`
- [ ] `PAY-INT-003` Consume 05 `media.PutObject` (declared in 05 `06` §2, kind `receipt_pdf`); contract test against 05 fake
- [ ] `PAY-INT-004` Wire `notify.SendToUser` payloads: `fee_due` (`/payments/{invoiceId}`, bn "বকেয়া ফি" + amount) and `payment_result` (`/receipts/{txnId}`) — freeze with 06 (`NTF-INT-007`)
- [ ] `PAY-INT-005` Register jobs (`receipt.generate`, `invoice.notify`, `payments.reconcile`, `payments.overdue_sweep`, `payments.expire`) with the 01 worker + cron
- [ ] `PAY-INT-006` Webhook routes outside the auth group with signature middleware; OpenAPI spec annotated as the signature-verified exception
- [ ] `PAY-INT-007` Gateway adapters sandbox credentials via env (`SSLCOMMERZ_*`, `BKASH_*`, `NAGAD_*`); health flag + chooser hiding verified
- [ ] `PAY-INT-008` Cache-tag contract implemented (ledger never cached; invoice tags invalidated)
- [ ] `PAY-INT-009` Failure & degradation matrix drills: gateway-down, webhook-before-callback, callback-before-webhook, R2-down receipt retry
- [ ] `PAY-INT-010` Test plan (`06` §9) green in CI — signature, idempotency, split, receipt, tenant, void, sweep suites

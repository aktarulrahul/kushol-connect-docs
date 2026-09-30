# Payments — Solution Approach

**Module:** `12-payments` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `fee_invoices` | A school's money demand on one student: title, kind (tuition/exam/transport/other), `amount_bdt numeric(12,2)`, due date, status, issuer | Yes |
| `payment_transactions` | One gateway payment attempt: invoice or order target, gateway + `gateway_txn_id`, amount + convenience fee, status, payer, completion time | Yes |
| `ledger_entries` | Append-only double-side (debit/credit) money journal per school: fee_payment, convenience_fee, commission, payout, adjustment | Yes |
| `payment_receipts` | One immutable PDF receipt per successful transaction, serial-numbered per school, stored in R2 (via 05) | Yes |
| `gateway_events` | Webhook envelope audit: gateway, event id, `signature_valid`, sha256 payload digest, processed flag, **payload summary only — never the payload** | Yes |
| `users` (03) | Payers (guardian/student), issuers, admins; `locale` for bn/en rendering; guardian↔student link (03 `guardians.IsGuardianOf` / `LinkedStudents`) | No — read via 03 |
| `schools` / hierarchy (04) | Tenant root; section→student resolution for bulk invoices | No — read via 04 |
| `orders` (11) | Vendor order paid online; 12 only reads `commerce.OrderAmount` and 11 attaches `payment_transaction_id` | No — 11's seam |
| `media_assets` (05) | Row representing the stored receipt PDF in R2 | No — written via 05's service |
| `notification_deliveries` (06) | Push rows for fee-due / payment-result notifications | No — via `notify.SendToUser` |

### 1.2 Relationships

```text
schools (04) 1───* fee_invoices *───1 users(student, 03)
                      │
                      │ 1
                      └───* payment_transactions *───1 users(payer, 03)
                              │        │
                              │        └──* ledger_entries (fee_payment / convenience_fee
                              │              / commission / payout / adjustment)
                              ├──1 payment_receipts ───1 media_assets (05, R2)
                              └──* gateway_events (envelope audit, digest only)

orders (11) 1───* payment_transactions (order_id set, invoice_id null)
                   └── 11 attaches payment_transaction_id on success (11's seam)
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| `PAY-INV-1` | `ledger_entries` is append-only: no UPDATE/DELETE path; corrections are new `adjustment` rows | DB rule/trigger (mirrors 01 `audit_log`) |
| `PAY-INV-2` | Every `success` transaction produces balanced entries in the same tx: credits (fee_payment [+ convenience_fee when > 0], or commission) == charged amount | Service single-tx write + `PAY-IT` balance tests |
| `PAY-INV-3` | At most one transaction per (gateway, gateway_txn_id) — webhook idempotency | `UNIQUE(gateway, gateway_txn_id)` + handler no-op on duplicate |
| `PAY-INV-4` | At most one receipt per successful transaction; serial unique per school; receipt object immutable | UNIQUE(txn_id), UNIQUE(school_id, serial_no), R2 immutability discipline |
| `PAY-INV-5` | Invoice amount/title/student immutable after issue; void only with zero successful transactions | Service guards + `PAY-IT` |
| `PAY-INV-6` | `gateway_events` stores digest + ids/amounts summary only — never secrets, never the raw payload | Schema (no payload column) + `PAY-UT` redaction test |
| `PAY-INV-7` | `sum(ledger fee_payment credits) == sum(success txn amounts)` per school per day — the reconciliation check | Daily job + reconciliation report |
| `PAY-INV-8` | Money mutations are audit-logged in-transaction (issue, void, initiate, webhook transitions, refund, settlement import) | `audit.Record` in the same tx (01) |

## 2. Module Boundary

**Owns (writes):** `fee_invoices`, `payment_transactions`, `ledger_entries`, `payment_receipts`, `gateway_events`; the `PaymentGateway` adapter registry (SSLCommerz/bKash/Nagad); webhook verification middleware; the jobs `receipt.generate`, `payments.reconcile`, `payments.overdue_sweep`, `payments.expire`.

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 03 | `auth.*` chain, roles, verification status, guardian↔student link (03 `guardians.IsGuardianOf` / `LinkedStudents`), `users.locale` | Identity and verification are 03's; 12 never re-checks credentials |
| 04 | `hierarchy.ResolveUserNodes` (tenant scoping; section→student rosters for bulk) | The hierarchy is 04's data model; 12 has no school/section tables |
| 05 | `media.PutObject` (receipt PDFs → R2; **additive export** — 05 ships `PresignUpload`/`ConfirmUpload` for clients; api-generated files need a server-side put) | One storage path; 12 never holds R2 credentials |
| 06 | `notify.SendToUser` (fee-due push, payment-result push → `/receipts/{txnId}`) | All push fan-out, prefs, retries live in 06 |
| 11 | `commerce.OrderAmount(orderId)`; 11 owns attaching `payment_transaction_id` to its orders row | Order state machine is 11's; 12 is order-agnostic apart from the amount + attach hook |
| 01 | `jobs.Enqueue`/`Register`, `audit.Record` | No new queue/audit machinery |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4.

## 3. Lifecycle

```text
invoice:   draft ──issue──▶ issued ──webhook success──▶ paid
                 (bulk issue same step)   │──void (0 successes)──▶ void
                                          └──due date passes, unpaid──▶ overdue (sweep)

transaction: initiated ──redirect──▶ redirected ──webhook/callback success──▶ success ──manual refund──▶ refunded
                  └──expire sweep / gateway failure──▶ expired | failed

payment flow (authoritative vs UX):
  payer → POST /payments/initiate → gateway hosted checkout
        → gateway calls POST /webhooks/{gateway}  (SERVER-TO-SERVER — AUTHORITATIVE)
        → browser/app returns via POST /payments/callback/{gateway} (UX ONLY — status check + redirect)
        → app polls payments.InvoiceStatus until webhook lands
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| invoice draft | issue (single/bulk) | issued | admin of same school; valid student/section; amount > 0 | audit; notify job (fee-due push) |
| invoice issued | webhook success | paid | exactly one success txn; balanced ledger entries in tx | ledger ×2; receipt job; result push |
| invoice issued | void | void | zero successful txns; admin; audit with reason | pending txns refuse at initiate |
| invoice issued | overdue sweep | overdue | `due_date < today` AND unpaid | daily job; reportable |
| txn initiated | redirect issued | redirected | payer verified + entitled; gateway up | — |
| txn redirected | webhook/callback success | success | signature verified where the gateway signs; **server-to-server `FetchStatus` confirms status + amount + currency + our txn id**; idempotency key free | **ledger entries; attach to 11 order (if order); invoice→paid; receipt job; push** |
| txn redirected | failure/expire | failed / expired | gateway report or sweep | result push (retry link); invoice stays issued |
| txn success | manual refund | refunded | Super/School Admin; adjustment entry | audit; no gateway auto-refund |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| `/school/ledger` (web) | Server shell + client TanStack Table; `no-store` — money screens are always fresh | None (uncacheable by design) | — |
| Ledger summary cards | Server Component → `GET /school/ledger/summary` | None | invalidated by revalidation on any ledger mutation (06 §4) |
| Invoice forms | Client (RHF + zod) | Student/section pickers reuse 04's cached lists | consumes `hierarchy:*` tags |
| App invoice list / pay screen | TanStack Query, short TTL (30 s) | `payments:invoices:{userId}` (stale-while-revalidate; refetch on focus) | — |
| Receipt PDFs | Immutable R2 objects served directly (via 05 URL) | Cache-forever (content never changes; new receipt = new object) | — |
| Gateway status polls (app) | Poll `/payments/status` every 3 s ×20, then settle to "we'll notify you" | None | — |

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| Convenience fee amount (platform-wide, default **BDT 0 = off** per `brd.md` §7 revised model — transaction fees removed; enabling is an owner decision) | Ledger entry types + balance rule; state machines (`02` §3) |
| Gateway enable/disable toggles (per gateway; down/holiday switches) | Signature schemes + replay windows per gateway adapter |
| Invoice kind presets (labels bn/en for tuition/exam/transport/other) | Txn expiry window (30 min); receipt serial format `{SCHOOL-YY}-{seq}` |
| Order commission rate (default 5% — owned with 11, `TODO: Confirm`) | Rate-limit class `payments` (strict); webhook route list |
| Bulk batch cap display (hard cap 200 is code; admins see the limit) | Sandbox vs production keys come from env only (`SSLCOMMERZ_*`, `BKASH_*`, `NAGAD_*`) — never admin-editable |

## 6. Security

- **Entry points & auth chain:** every REST route runs authenticate → load role claims → tenant-scope (03 chain). School-scoped reads/writes require `school_admin` of the claims' school (Super Admin may read across, write refunds only); payer routes are self-scoped by claims. **`POST /api/v1/webhooks/{gateway}` is the one deliberate exception: no auth chain — instead, HMAC/signature verification + timestamp replay window + allowlisted gateway source ranges, then the same validation pipeline.** This exception is documented here and in `03-backend-tasks.md` §2; it is flagged in the OpenAPI spec (security: [] with a webhook marker).
- **Rate limits:** class `payments` (strict) — initiate 5/min/user; callback 30/min/IP; webhook 120/min per gateway (generous, retries are legitimate); ledger reads use the `default` class.
- **Validation:** contract-generated validators on every field (`01` §6); webhook bodies parsed only after signature verification (envelope first, then payload).
- **Never trust the callback alone (binding, 2026-09-30):** a redirect/IPN/webhook only *triggers*
  processing; `success` is written only after the adapter's server-to-server `FetchStatus` confirms the
  payment (SSLCommerz order-validation API, bKash execute/query-payment, Nagad verify — exact
  endpoints, signing and whether each gateway pushes webhooks at all are `TODO: Confirm` against the
  current merchant docs before building each adapter; do not assume a signed-webhook scheme). Where a
  gateway sends no webhook, a `payments.status_poll` job confirms redirected transactions.
- **PCI stance:** **no card or wallet credentials ever reach our servers** — gateways host the payment page; we store only gateway transaction ids, amounts and statuses. There is no PAN/CVV/token storage anywhere in this module, which keeps the integration at SAQ-A-level scope. Redirect payloads are opaque gateway references; nothing sensitive is displayed in the UI (transaction drawer shows ids/amounts/status only).
- **Secrets & logging:** gateway keys live only in the parsed config module; `PAY-BR-007` forbids logging secrets or raw payloads — log gateway, event id, txn id, amounts. `PAY-UT` asserts redaction.
- **Tenant scope rule for every table:** `fee_invoices`, `ledger_entries`, `payment_receipts` carry `school_id` (all queries scoped); `payment_transactions`/`gateway_events` are scoped transitively via invoice/order + payer, with payer/admin visibility rules in the service; cross-tenant probes return `TENANT_MISMATCH`/404 (`PAY-IT` per table).
- **Money-mutation audit:** every state-changing call writes `audit.Record` in-transaction (`PAY-INV-8`).

## 7. Accessibility & Motion

Motion is minimal and functional: the pay-screen gateway chooser uses press feedback only; the status screen's spinner is announced via `aria-live`/accessible RN equivalents ("payment processing") and collapses to a static state under reduced motion. Receipt success uses a single non-animated confirmation banner (no confetti — trust product). Web tables keep full keyboard paths (filter controls, row focus, drawer focus trap, `Esc` close); the CSV export button is a real button with a label, not an icon-only control. Details in `04` §5 and `05` §5.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | Webhook arrives before callback (normal race) | Idempotency key | None | Webhook wins (authoritative); callback sees terminal state, redirects |
| 2 | Callback before webhook (gateway slow) | Callback polls gateway status API | User sees "processing" | Poll `InvoiceStatus`; webhook backfills; push notifies |
| 3 | Gateway down / timeouts at initiate | Adapter error / 15 s timeout | Cannot start that payment | Chooser hides the gateway (health flag); bn/en message; invoice unaffected; COD commerce unaffected |
| 4 | R2 down at receipt generation | Receipt job failure | Receipt missing (money already safe) | 01 worker retries w/ backoff; receipt appears on recovery; UI shows "receipt is being generated" |
| 5 | Bad-signature webhook (forged/replay) | Verification fails | None on state | 403 + flagged `gateway_events` + alert log + rate-limit trip (`PAY-US-013`) |
| 6 | Duplicate webhook (legit retry) | UNIQUE(gateway, gateway_txn_id) | None | 200 `DUPLICATE_WEBHOOK`, zero side effects |
| 7 | Worker crash between ledger commit and receipt enqueue | Job absent after success | Receipt delayed | Receipt job is enqueued in the same tx as the success transition — tx commit is atomic; if the row exists, the sweep re-enqueues missing receipts |
| 8 | Settlement CSV ≠ ledger (missing/delta) | Daily reconciliation job | Report-only | Mismatch rows flagged on the reconciliation screen; `adjustment` entries only after human review |
| 9 | 11 order cancelled mid-payment | `commerce.OrderAmount`/attach hook state check at callback | Tx succeeds but order can't attach | Refund path (`PAY-BR-011`) + reconciliation note; flagged to ops |
| 10 | Redis unavailable (idempotency cache) | Cache errors | Slower webhook path | DB UNIQUE index is the real guard — Redis is only a fast-path |

## 9. Performance

- **Volumes:** pilot ≈ hundreds of invoices/school/month; BRD-scale target ≈ 2.4 M transactions/year (`prd.md` §7). Receipt generation is the only heavy work and is fully async (`receipt.generate` job).
- **Hot queries & indexes:** webhook lookup by `UNIQUE(gateway, gateway_txn_id)` (the idempotency hot path); invoice lists by `(school_id, status, due_date)`; payer history by `(payer_id, created_at DESC)`; ledger by `(school_id, created_at DESC)` + `(school_id, type)` for summary aggregates; expiry sweep by partial `(status, updated_at) WHERE status IN ('initiated','redirected')`.
- **Latency budgets:** initiate ≤ 800 ms p95 (excludes gateway page load); webhook processing ≤ 300 ms p95 (single tx + audit); ledger page ≤ 500 ms p95 with filters (always-fresh reads, so indexes do the work — no cache to absorb).
- **Bundle impact:** web adds no new deps beyond 07's TanStack stack (CSV export is a small util); app adds `expo-web-browser` for the in-app gateway view — small, already-EAS-compatible.

## 10. Alternatives Considered

### Option A — three bespoke gateway integrations · Option B — `PaymentGateway` interface + adapters (SSLCommerz / bKash / Nagad)

| | A | B |
| --- | --- | --- |
| Advantages | Each integration maximally tailored; no abstraction indirection | One initiate/verify/status contract; adding a gateway (or Nagad later) is a new adapter; webhook handlers share the idempotency + ledger core; mock adapter for tests |
| Disadvantages | Triplicated idempotency/ledger/webhook logic — three places to get money wrong; tests ×3 | Adapter boundary must be kept thin; per-gateway quirks live in mapping code |
| Complexity / weight | High recurring (every fix lands thrice) | One interface + 3 small adapters (~each maps initiate/verify/status) |

**Recommendation:** **B — the interface** (chosen). `PaymentGateway` with `Initiate`, `VerifyWebhook`, `FetchStatus`; the service owns state, idempotency, ledger and receipts. **ADR** recorded in `07-progress.md` at build.

### Option C — poll-for-status only · Option D — webhook-only · Option E — webhook (authoritative) + on-return status check (chosen)

| | C poll-only | D webhook-only | E webhook + on-return check |
| --- | --- | --- | --- |
| Advantages | No public endpoint to secure | Instant confirmation; no polling load | Instant + resilient to webhook loss; return UX can resolve early |
| Disadvantages | Slow/laggy UX; wasted polls; harder reconciliation | A lost webhook stalls the txn until sweep; user staring at "processing" | Slightly more code (two confirmation paths) |
| Complexity / weight | Low but operationally noisy | Lowest code, highest support burden | Moderate — justified for money |

**Recommendation:** **E** — webhook is the source of truth; the callback route runs a single on-return status check for UX; the expiry sweep is the backstop.

### Option F — store cards/wallet tokens for one-tap repeat pay · Option G — gateway-hosted pages only (chosen)

| | F | G |
| --- | --- | --- |
| Advantages | Fastest repeat checkout | No sensitive data on our servers; SAQ-A scope; gateways own fraud/liability |
| Disadvantages | PCI DSS burden, token lifecycle, breach blast radius — unacceptable at this stage | Each payment re-enters the gateway page (~2 taps) |
| Complexity / weight | High + regulatory | Low; matches BD gateway norms (bKash/Nagad wallet PINs stay in their apps) |

**Recommendation:** **G** — never store card data; revisit only with an ADR and a real compliance budget.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | Sandbox gateway behaviour ≈ production webhooks/signatures | Signature/format surprises at cutover (module 15) | Adapter + VerifyWebhook isolation; contract tests per gateway; sandbox-first rollout |
| 2 | Settlement CSV formats stay stable enough for manual import | Reconciliation breaks per format drift | `TODO: Confirm` per-gateway templates; parser per adapter; mismatches fail loud, not silent |
| 3 | Guardians pay within due dates; volume of overdue is manageable | Push fatigue / reconciliation backlog | Overdue sweep + ledger filters; bulk re-issue is one action |
| 4 | Fee stays off (BDT 0, `brd.md` §7) — gateway MDR is absorbed by the platform/school | MDR cost unfunded | Fee is config, not code; owner decides MDR bearer (`TODO: Confirm` — Rahul) before production cutover |
| 5 | 11's order seam (`OrderAmount`, attach hook) lands before 12 builds | Order payments blocked (fees unaffected) | Order path is a separate initiatable target; ship fees first if 11 slips |
| 6 | 05's `media.PutObject` server-side export (declared in 05 `06` §2) | Receipt upload blocked | Contract test against 05's fake; fallback: 05's presign flow driven server-side (uglier, works) |
| 7 | Webhook route exposed publicly becomes a flood target | Noise/DoS on the money path | `payments` rate-limit class, allowlisted ranges, cheap-verify-first ordering, alerting |
| 8 | Refund ledger adjustments drift from gateway realities | Ledger ≠ bank at audit | Manual refunds require Super/School Admin + audit; reconciliation flags deltas |
| 9 | Go PDF tooling renders Bengali (conjuncts, vowel signs) correctly in receipts | Garbled bn receipts — a trust failure with guardians | **Spike before build (`PAY-BE-000`)**: render a bn+en sample receipt with (a) a Go text-shaping library (HarfBuzz-class shaping) + PDF writer, (b) a renderer bundled in the api image; pick the one that renders correctly within the api's 512 MB cap; en-only receipt fallback is **not** acceptable (bn is the default language) |

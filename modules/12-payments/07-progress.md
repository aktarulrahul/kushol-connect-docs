# 12-payments — Build Progress

Module: payments · Surfaces: api + web (school ledger) + app (payer) · **Last updated:** 2026-10-03

> Owner instruction: "go next" after the 11 build — same through-stages precedent (06/10/11);
> gates 1–3 stay owner-manual.

## Stage / gate status

| Stage | Status | Evidence |
| --- | --- | --- |
| 1 Plan | ✅ 2026-10-03 | plan in-session; defaults OQ-1…6; deps 07/11 🚧 accepted per owner instruction |
| 2 UI (web + app, mock-driven) | ✅ 2026-10-03 | contract-first: 11 REST routes + 24 `Payments*` schemas landed FIRST (incl. the `security: []` webhook exception with the full verification order documented in the spec); both clients generated |
| Gate 1 | ⏳ pending owner | |
| 3 Docs sync | ✅ 2026-10-03 | this file, 08-gaps, README → 🚧, checklist ticks, change log |
| 4 Backend | ✅ code-complete 2026-10-03 | 5 migrations (+ append-only trigger), 5 sqlc files, `internal/payments` (service, orders/webhook pipeline, money helpers, sandbox adapter, renderer, jobs, handler, dto) + config env + cmd/httpapi wiring |
| Gate 2 (SQL on Neon) | ⏳ pending owner | SQL hand-off below |
| 5 Integration | ✅ code-complete 2026-10-03 | app: live client + session-token selector, hooks re-pointed; deep links additive; web: fixture seam until 07's console glue (G-3) |
| Gate 3 | ⏳ pending | — |

## Decisions (ADR)

1. **ADR-1 (adapter interface — 02 §10 B):** `GatewayPort` (Initiate/VerifyWebhook/FetchStatus) +
   `SandboxGateway` HMAC adapter (exact, offline-testable). **No real gateway adapter was built**:
   per prompt.txt §6 / 02 §6 the signing + endpoints are `TODO: Confirm` against current merchant
   docs — inventing them is forbidden. Cutover = one file per gateway.
2. **ADR-2 (webhook authoritative + FetchStatus confirm):** `success` is written only after the
   adapter's server-to-server `FetchStatus` confirms status+amount+ref — the callback/redirect is
   UX-only; duplicate/replayed webhooks → 200 `DUPLICATE_WEBHOOK` with zero effects
   (UNIQUE(gateway, gateway_txn_id) + envelope dedupe UNIQUE(gateway, event_id)).
3. **ADR-3 (payload privacy — PAY-BR-007/INV-6):** `gateway_events` stores sha256 digest +
   ids/amounts summary only; unit-proven that payloads/secrets never appear in the summary.
4. **ADR-4 (balanced ledger in the success tx — PAY-INV-2):** fee → `fee_payment` [+`convenience_fee`
   only when config > 0, default 0]; order → `commission` (5%, owned with 11) + 11 attach in-tx.
5. **ADR-5 (renderer port — PAY-BE-000):** receipts render through a `ReceiptRenderer` port; the
   sandbox renderer emits unshaped Latin text only — **the bn shaping verdict is an owner-run
   spike (G-7)**; en-only receipts are unacceptable, so the port keeps the library choice open.

## Evidence (2026-10-03)

| Repo | Check | Result |
| --- | --- | --- |
| api | build/vet/fmt repo-wide | clean |
| api | golangci-lint `./internal/payments/...` | **0 issues** |
| api | `go test -race ./internal/payments/...` | UT-001 (balance), UT-004 (signature: valid/invalid/tampered/incomplete), UT-005 (validation ×5), redaction, privacy, config defaults — green |
| api | `go test ./...` | repo-wide green (config env tests extended for the new `PAYMENTS_WEBHOOK_SECRET`) |
| api | `make contracts-check` | `contracts: no drift` |
| api | wiring | 3 jobs registered (`receipt.generate`, `payments.expire`, `payments.overdue_sweep`); notify + commerce adapters; webhook route OUTSIDE the auth group (not in `AuthRequired`) |
| web | typecheck ✓ · lint ✓ · tests **178/178** | ledger dashboard + issue form on the fixture seam |
| app | typecheck ✓ · scoped lint ✓ · payments tests **10/10** (18/18 with i18n) | pay screen/status/receipt/deep links |
| app | full suite | 273 total — the 1 red is `index.test.tsx` (pre-existing, 05 stream) |
| both clients | sync + generate | spec copies match the api |

## Gate 2 SQL hand-off (owner)

```text
db/migrations/20270210090000_create_fee_invoices.up.sql           -- fee_invoices (tenant school_id, immutability by omission)
db/migrations/20270210091500_create_payment_transactions.up.sql   -- txns (UNIQUE(gateway, gateway_txn_id) idempotency core)
db/migrations/20270210092000_create_ledger_entries.up.sql         -- ledger + append-only trigger (PAY-INV-1)
db/migrations/20270210092500_create_payment_receipts.up.sql       -- receipts (UNIQUE(txn_id), per-school serial)
db/migrations/20270210093000_create_gateway_events.up.sql         -- webhook envelope audit (digest + summary only)
```
Run in order against Neon; each has a `.down` reverse. New env: `PAYMENTS_WEBHOOK_SECRET`
(server-side sandbox HMAC — registered in the config module + its tests).

## Gate 1 review hand-off

Web (`pnpm dev`, school-admin fixture): `/institution/ledger` (summary cards, invoices tab + void
dialog, ledger tab) → `/institution/invoices/new`. App (fixture): Marketplace → ফি পরিশোধ → invoice →
pay (gateway chooser) → status (settles in sandbox) → receipt. Fixture modes:
`success/offline/forbidden/conflict/gateway_down`. 360px bn+en.

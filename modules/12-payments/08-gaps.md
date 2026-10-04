# 12-payments — Remaining Gaps

| # | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | Playwright + Maestro + IT runs pending owner | Standing rule: agent never runs the app/containers | E2E + signature/idempotency ITs unexecuted | `make test-integration`, `pnpm test:e2e`, `maestro test .maestro/payments-golden-path.yaml` |
| G-2 | Real gateway adapters not built | prompt.txt §6 forbids inventing third-party signing/endpoints; merchant docs are `TODO: Confirm` | Only the SandboxGateway adapter exists; initiate returns sandbox URLs | Module 15 cutover: build SSLCommerz → bKash → Nagad adapters per verified docs (one file each behind GatewayPort) |
| G-3 | Web seam stays on fixtures | 07's console session glue is still fixture-level (10-G-8/11-G-3 same boundary) | Ledger screens can't hit the live api yet | One-file swap of `src/fixtures/payments.ts` when 07 lands |
| G-4 | PAY-BE-000 bn-PDF shaping spike unexecuted | Rendering can't be visually verified by the agent; en-only fallback is unacceptable per spec | Sandbox renderer emits Latin-only text; receipts would garble bn conjuncts | Owner-run spike: render a bn+en sample via a shaping library vs a bundled renderer; pick one within 512 MB; implement behind the existing `ReceiptRenderer` port |
| G-5 | Reconcile/settlement-import/refund endpoints (`PAY-BE-010/011/012/017/018`) deferred | Launch-manual ops; settlement CSV format `TODO: Confirm` (OQ-3); refund mechanics OQ-4 | Reconciliation screen + import/refund endpoints absent | Land after Rahul confirms the CSV templates; ledger append-only core already supports `adjustment` entries |
| G-6 | Seed deferred | No seed vehicle (10-G-7/11-G-6 same decision) | Fresh envs lack demo invoices | Owner decides CLI vs dev migration |
| G-7 | Guardian fan-out for fee-due pushes simplified | 03's guardian→user resolution rides the caller claims; the job fans to the student row | Both guardians receive the push only via the linked-student path (03 `LinkedStudents` wired in the claims layer, not the job) | Extend the notify fan-out to `LinkedStudents` guardians when the claims export is available |

# 14-lms-erp-sync — Remaining Gaps

| # | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | E2E + IT runs pending owner | Standing rule: agent never runs the app/containers | `LMS-E2E-001` (specs in `e2e/lms.spec.ts`) + IT-001–012 unexecuted | `pnpm test:e2e`; `make test-integration` |
| G-2 | `it_lms_test.go` not written | Context budget: IT-001–012 specs exist (03 §6) but the testcontainers harness didn't land this session (same as 13 G-2) | HMAC/replay/hash-no-op/resumability ITs unproven | Write the file mirroring `it_commerce_test.go` |
| G-3 | Web seam stays on fixtures | 07's console session glue is still fixture-level (same boundary as 10/11/12/13) | Admin screens can't hit the live api yet | One-file swap of `src/fixtures/lms.ts` when 07 lands; template + error CSV become server streams then |
| G-4 | Sync-licence management UI not built | The flag (`schools.sync_licence_enabled`) is additive to 04's tenant table; its Super Admin control belongs in 07's tenants screen | Flag defaults OFF — enable per pilot via SQL (`UPDATE schools SET sync_licence_enabled = true WHERE …`) before Gate 3 | 07 pass: licence toggle on the tenants screen (OQ-7) |
| G-5 | Withdrawal (`active=false`) not applied | 04 has no exported end-enrollment path yet | Webhook/pull withdrawal events record `error` (redrive-able), never silently dropped | 04 pass: additive `EndEnrollment` export; redrive picks them up |
| G-6 | Reconciliation 5-min Redis memo not implemented | Reads are no-store fresh by design (ADR-6); the memo is a cheap re-read optimisation | Recomputes per request (trivial at pilot volume) | Land with the cache-tag pass when 07's glue makes admin reads cached |
| G-7 | Private-range SSRF allowlist for vendor base URLs | HTTPS-only is enforced at create/update/test; private-CIDR blocking is an operator hardening | A misconfigured institution URL could point at internal hosts | Add CIDR deny-list at connection create (one function) |
| G-8 | Notices pull (`/notices`, `sync_notices`) stored but not applied | Applying to 05's boards needs a 05 notice-write export | The field is inert; sections/people/membership sync fully | 05 pass: additive notice upsert export, then flip the pull step |
| G-9 | XLSX parsing (P1) | Spec 02 §10 Option B — CSV P0 | xlsx uploads rejected `sync.import.format_invalid` | Add a streaming sheet reader behind the same `format` column |

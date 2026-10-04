# 11-campus-commerce — Remaining Gaps

Genuine gaps only — reason · impact · next action. Created 2026-10-03.

| # | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | Playwright + Maestro + axe runs pending owner | Standing rule: the agent never runs the app/dev stack (workspace `AGENTS.md`) | E2E/a11y unproven in browser/on device | `pnpm test:e2e` (web), `maestro test .maestro/commerce-golden-path.yaml` (app); axe during the Gate-1 browser pass |
| G-2 | Integration tests (IT-001–010) pending owner | Testcontainers suites are owner-run (`make test-integration`) | Oversell/cross-school/vendor-scope proofs unexecuted | Owner runs the suite after Gate 2; results recorded in 07-progress |
| G-3 | Web product-image upload rides 07's console glue | 05's presign→PUT→confirm flow needs the live session layer; 07's vendor shell is still fixture-driven | Products save without images in live mode (degraded path per US-002) | Wire `ImageUploader` when 07 lands its live console session (one component) |
| G-4 | App offline placement queue is in-memory | Persisted store belongs with the live wiring (10-G-4 precedent) | A queued order survives only the session | Swap to a persisted store with the live client; replay logic already tested |
| G-5 | Degradation drills + integration runs | Same owner-run constraint as G-2 | 06-down/05-down/07-down proofs unexecuted | Covered by fakes in `it_commerce_test.go`; owner runs with `make test-integration` |
| G-6 | Demo Store seed deferred (`03` §1.3 DRAFT) | No seed mechanism exists (same vehicle decision as 10-G-7 / 03 `IDT-BE-032`) | Fresh environments have no demo storefront/orders | Owner decides CLI vs dev migration; then seed the fictional "ডেমো স্টোর / Demo Traders" dataset per §1.3 |
| G-7 | Vendor placement push + per-vendor low-stock digest fan-out | Need a 07 export resolving the portal user for a vendor account (`portal_user_id`); 07 has user→account only | Placement/digest notices reach the buyer path only; vendors see the board (DB-first, §8) | Ask 07 to export `vendorPortalUserID(vendorAccountID)`; then wire both sends (06 seam already in place) |
| G-8 | Portal-user linking (`CMP-BE-001`) + linking UX (`CMP-FE-013`) | The one-time phone-match bind happens at first approved login — 07's live portal login is still fixture-level | First approved login does not bind `portal_user_id` yet | Land with 07's live portal login; schema column + audit contract ready |
| G-9 | Browse read-through caches not populated | Read paths are DB-direct; the invalidation side (tags) is implemented and unit-proven | Cache TTLs from `06` §4 are inert until the reads opt in | Add redis reads on `GET /commerce/stores` etc. when traffic warrants; invalidation already correct |

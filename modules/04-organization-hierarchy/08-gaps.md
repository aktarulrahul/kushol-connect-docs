# 04-organization-hierarchy — Remaining Gaps

Genuine gaps only — reason · impact · next action. Created 2026-10-02.

| # | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | Chat join/archive against the real module 05 is not provable yet | 05-communication-engine is unbuilt; 04 calls it behind the interface-first port with a no-op binding | `ORG-IT-001`/`ORG-IT-007` assert join calls on the port fake only; real membership is proven in 05's build (`COM-INT-001`, `COM-IT-011`) | 05 binds the port and re-runs the seam tests; no 04 change expected |
| G-2 | Promotion rules remain the recorded default | OQ-2 open — `TODO: Confirm` with Rahul (graduation classes, RETAINED handling, repeating students, section re-mapping) | Year-end behaviour could differ from school expectations | Confirm before the first real migration window (Dec–Jan); rules live in one tested config constant |
| G-3 | AudienceCount small-count suppression threshold (20) unconfirmed | `TODO: Confirm` noted in `06` §2 | Ad targeting could single out very small segments of minors | Rahul confirms threshold; constant in one place |
| G-4 | 5/hour rate caps key on client IP, not principal/per-school | Rate classifier runs before authentication in the router chain | A shared office NAT could exhaust the school-creation budget | Revisit with module 07 (principal-aware limiting), or accept as-is for Phase 1 |
| G-5 | Maestro/e2e for this module | None — the "onboarding → verified → auto-join section group → receive notice" golden path is owned by modules 03/05/06 app specs; 04 is API-only | None directly | Asserted end-to-end by those modules' builds |
| G-6 | Integration suite **pending owner run** (owner rule 2026-10-02: the agent never starts the app/Docker) | `ORG-IT-001…009` need Docker (testcontainers); 5 of 7 executed runs fixed their found defects (user FK seeding, upsert-return-row, apply-count) but the final green run must be owner-executed | No automated proof yet — everything else (build · vet · lint 0 issues · `go test -race` 20 pkgs · contracts no drift · fmt) is green | Owner: `cd applications/api && make test-integration` (Docker required); share output; agent fixes any red test |

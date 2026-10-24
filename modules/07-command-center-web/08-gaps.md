# Command Center Web — Gaps

Genuine remaining gaps only (reason · impact · next action).

| ID | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | `WEB-FE-008` SEO suite (Metadata, OG, JSON-LD, sitemap, robots) | Not finished in Stage 2 | Landing SEO incomplete | Stage 5 polish / next UI pass |
| G-2 | `WEB-FE-021` real `AttachmentUploader` (05 R2) | Fixture stub only | Composer cannot attach yet | Stage 5 after 05 media confirmed |
| G-3 | `WEB-FE-027` full DataTable keyboard/aria pass | Partial admin tables | A11y debt on dense tables | Stage 5 polish |
| G-4 | `WEB-FE-030` axe Playwright + Lighthouse CI | Specs not written / e2e pending owner stack | No CWV/axe gate evidence | Write specs; owner runs e2e |
| G-5 | `WEB-BE-014` seed loader | Not shipped | No DB demo rows until seeded | Add idempotent seed after Gate 2 |
| G-6 | `WEB-IT-001`–`006` integration tests | Containers / live DB — owner-run only | No IT evidence yet | Owner: `make test-integration` (or module IT package) after migrate |
| G-7 | `leads` rate limit burst 3/min | Limiter is single fixed-window (10/h/IP wired) | Burst rule soft | Documented TODO; enhance limiter later |
| G-8 | Stage 5 fixture→OpenAPI client swap | Waiting Gate 2 + live handlers | UI still on fixtures | After owner confirms migrate |
| G-9 | App Maestro | N/A — module is web+api only | — | None |

---

## Gaps from the 2026-10-04 console additions (all fixture-seam by design)

| # | Gap | Next action |
| --- | --- | --- |
| G-13 | Console personas/chat/access-logs/lead-decisions/partner-store/school-details/tenant-LMS/product-approvals run on fixtures | One-file swaps when this module's glue lands; contracts listed in 07-progress "Console additions" |
| G-14 | Role switcher is a fixture store (localStorage) | Replace with real claims from 03 identity once 07's session glue exists (api re-checks stay authoritative) |
| G-15 | Access log has no writer yet (01 httpx) | 01 pass: request-log table + middleware; then the access tab reads live |
| G-16 | Product approvals live in the commerce fixture | 11 pass: `products.status` CHECK + kushol-admin approve/reject routes; partner stock guard server-side |
| G-17 | Migration `20270312092000_partner_module_refinement` | Pending owner run against shared DB (Owner Rule 1) | Live DB unapplied until owner runs | Owner: `cd applications/api && go run ./cmd/api migrate up --confirm` |
| G-18 | Public registration (`/register`) still lists fixture cities/institutions, and its submit is a fixture | Out of the 2026-10-23 directory scope (owner asked for console institutions/partners) | A real user registering on web sees fixture institutions | Swap `fixtures/auth` hierarchy calls to `/api/v1/hierarchy/*` together with the live registration submit |
| G-19 | Cities: "Add city" is fixture-only (no create-city api); the list is live since 2026-10-23 | No 04 create-city endpoint | An added city vanishes on reload | 04: `POST /admin/cities`, then swap the form |
| G-20 | Still on fixtures after 2026-10-23: dashboard notices widget, leads (pilot registrations) queue, audit/access logs fallback, institution-admin pages (`/institution/*` except the directory and details) | Not institutions/partners | Mixed live + fixture data on those screens | Swap per screen as 07's glue lands (G-13) |
| G-21 | `admin-portal-layout.tsx` has 10 pre-existing lint errors (unused `Building2`/`initials`, needless `as Route` casts) | Pre-existing at HEAD (checked 2026-10-23) | `pnpm lint` fails on this file | Remove the dead code and casts |
| G-22 | Partner human ids can't be edited in the console | Generated once from the company name (stable URLs) | A partner renamed later keeps its old slug | Add an admin "rename id" with a redirect from the old one |
| G-23 | Partner Logs reads `audit_log` by `entity_id`, which has no index | Pilot volume is small | The Logs tab slows as the audit log grows | Index `audit_log (entity_id, created_at DESC)` |
| G-24 | Dev-DB schema_migrations marker sat at `20270313090004` while `20270313090001`–`090003` never executed (marker ran ahead of content — a sequential run is impossible: 090003 seeds `human_id`, which only 09001 adds, yet the marker was clean at 090004 without the column) | Broken local schema state; applied migration files are never edited, so the fix is a new version | `/admin/partners` + `/admin/institutions` 500 (`human_id` missing, SQLSTATE 42703); dev-start's migrate step prints "local schema up to date" because only the version marker is compared | Owner: `cd applications/api && go run ./cmd/api migrate up --confirm` (or restart `dev-start.sh`) to apply the idempotent repair `20270313090005_partner_human_id_repair` — re-applies 090001–090003's effects under the renamed schema, no-op on a fully-migrated DB |
| G-25 | Historical audit rows written before the rename keep `vendor.*` actions / `vendor_account` entity types | The rename switched writers to `partner.*` in the same change | Old console rows render their raw action string in the audit tab | Acceptable for a dev-stage DB; if needed, add a display-mapping case or a one-off `UPDATE` |
| G-26 | Integration suites (`make test-integration`, testcontainers) not re-run after the rename | Owner Rule 1 | Compile-level checks and unit tests only | Owner: `cd applications/api && make test-integration` after the G-24 repair run |

## BRD/PRD completeness pass (2026-10-04) — pages implemented, stubs retired

| Page | Was | Now |
| --- | --- | --- |
| `/admin/campaigns` | StubRoute (13) | Real campaigns list from the ads fixture (status, spend/budget, schedule, reject reasons); moderation actions stay in `/admin/moderation` |
| `/admin/commission` | StubRoute (12/13) | Platform revenue report: ledger summary cards + commission entries (12 payments seam; tuition/commerce/ads revenue kinds) |
| `/institution/invoices` | Missing (nav pointed nowhere) | Real invoices view from the payments fixture (title, student, amount, due, status) next to Ledger |
| `/institution/webhooks` | StubRoute (14) | ERP webhook endpoints + delivery log from the lms fixture; configuration remains on Integrations |
| `/institution/ai-matrix` | StubRoute (09) | **Intentionally left as stub — AI excluded by owner instruction** (phase 2, with module 08/09) |

**Remaining BRD/PRD notes:** everything else in the admin/institution/partner panels is implemented on
fixture seams (see G-13, narrowed by the 2026-10-23 live directory — G-18…G-20); AI surfaces (08/09) are phase 2 per owner instruction.
| G-27 | Migration `20270313090006_partner_member_details` (partner_members designation/notes/module_permissions + permission CHECK) not yet applied | Owner Rule 1 — agent never touches the database | Access-tab add-member fails until it runs | Owner: `cd applications/api && go run ./cmd/api migrate up --confirm` (after the G-24 repair), then verify: add a member on /admin/partners/ejonaki → Access, both emails arrive, permission badges + audit row show |
| G-28 | Migration `20270313090007_school_human_id` (schools.human_id + trigger + backfill) not yet applied; `GET /admin/institutions/{institutionId}` and the new chat endpoints accept uuids meanwhile, and the console falls back to uuid URLs | Owner Rule 1 — agent never touches the database | /institution/<human-id> 404s (uuid still works) until it runs | Owner: `cd applications/api && go run ./cmd/api migrate up --confirm`, then open /institution and click an institution — the URL should switch to its readable id and the Chat tab should list its groups |
| G-29 | Migration `20270313090010_partner_capabilities` (partner plans + capabilities) not yet applied | Owner Rule 1 — agent never touches the database | Plan badge + Manage Capabilities dialog work against live columns only after it runs | Owner: `cd applications/api && go run ./cmd/api migrate up --confirm`, then open /admin/partners/ejonaki → Manage Capabilities, flip to pro, verify the badge and the bill estimate |

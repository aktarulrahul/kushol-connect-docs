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
| G-13 | Console personas/chat/access-logs/lead-decisions/vendor-store/school-details/tenant-LMS/product-approvals run on fixtures | One-file swaps when this module's glue lands; contracts listed in 07-progress "Console additions" |
| G-14 | Role switcher is a fixture store (localStorage) | Replace with real claims from 03 identity once 07's session glue exists (api re-checks stay authoritative) |
| G-15 | Access log has no writer yet (01 httpx) | 01 pass: request-log table + middleware; then the access tab reads live |
| G-16 | Product approvals live in the commerce fixture | 11 pass: `products.status` CHECK + kushol-admin approve/reject routes; vendor stock guard server-side |

## BRD/PRD completeness pass (2026-10-04) — pages implemented, stubs retired

| Page | Was | Now |
| --- | --- | --- |
| `/admin/campaigns` | StubRoute (13) | Real campaigns list from the ads fixture (status, spend/budget, schedule, reject reasons); moderation actions stay in `/admin/moderation` |
| `/admin/commission` | StubRoute (12/13) | Platform revenue report: ledger summary cards + commission entries (12 payments seam; tuition/commerce/ads revenue kinds) |
| `/institution/invoices` | Missing (nav pointed nowhere) | Real invoices view from the payments fixture (title, student, amount, due, status) next to Ledger |
| `/institution/webhooks` | StubRoute (14) | ERP webhook endpoints + delivery log from the lms fixture; configuration remains on Integrations |
| `/institution/ai-matrix` | StubRoute (09) | **Intentionally left as stub — AI excluded by owner instruction** (phase 2, with module 08/09) |

**Remaining BRD/PRD notes:** everything else in the admin/institution/vendor panels is implemented on
fixture seams (see G-13); AI surfaces (08/09) are phase 2 per owner instruction.

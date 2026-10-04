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

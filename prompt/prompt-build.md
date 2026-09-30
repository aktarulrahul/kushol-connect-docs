# Build prompt — implement one Kushol Connect module

One prompt for every module. Set the parameters, then run it with an AI coding agent (or follow it
by hand).

```text
MODULE   = 01-foundations          # folder name under docs/modules/
APP      = api                     # api · web · app — which application(s) this module touches
TODAY    = 2026-09-29              # used when ticking checklist items
APPROVAL = required                # required → stop after the plan · pre-approved → implement after planning
```

**Set all four before starting.** Everything below refers to `<MODULE>`.

---

## 1. What to read (paths relative to the workspace root)

Read the named sections, not whole documents, unless the ✅ column says "all".

| ✅ | Document | Read |
| --- | --- | --- |
| always | `prompt.txt` (workspace root) | all — the binding brief |
| always | `docs/persona.md` | all (short) |
| always | `docs/brd.md` | §4 (scope) · §5 (business requirements BR-01…BR-05) · §8 (phasing) |
| always | `docs/prd.md` | the sections your module implements |
| always | `docs/modules/<MODULE>/01…06` | **all** — this is the work |
| always | `docs/modules/README.md` | the module's row, dependencies, blocked-before-build defaults |
| always | `docs/tech-stack.md` | the rows for the app(s) `<APP>` you touch |
| UI work | `docs/design-reference/README.md` | all — palette, typography (Hind Siliguri + Inter), logo rules |
| schema / data | the module's `03-backend-tasks.md` §2 plus `docs/brd.md` §6 (isolation) | tenant scoping is mandatory for every table |
| payments / AI | `docs/prd.md` §5.2 / §5.4 | quota + webhook rules |
| module 15 | `docs/tech-stack.md` §Infrastructure | all |

**If a file this prompt names is missing or a section is empty, writing that specification is the
task — stop and say so. Do not infer requirements.**

## 2. Preconditions (Step 0)

- [ ] Every dependency listed for `<MODULE>` in `docs/modules/README.md` is `🟢 Delivered` (or the
      owner explicitly accepts building against a stub).
- [ ] The module's open questions are answered, or you use the default stated in its `01` §9 — list
      which defaults you are relying on.
- [ ] For UI modules: brand assets exist in `docs/design-reference/brand/` — otherwise use a
      typographic fallback ("কুশল CONNECT" in Hind Siliguri + Inter) and record it as a gap.

## 3. Objective

Complete **every unticked checklist item** of `<MODULE>`, in this **UI-first** order:

1. `04-frontend-tasks.md` + `05-app-tasks.md` — **UI first, mock-driven** (web screens → states →
   data flow → motion → responsive → a11y; app screens → states incl. offline → media flow →
   device behaviour). **No real API calls**: every screen runs on in-repo fixtures/mocks that
   mirror the contract shapes from `03-backend-tasks.md` §2, so swapping to the generated client
   later is a one-file change per surface.
2. `03-backend-tasks.md` — **backend** (schema → SQL migration script → tenant-scoped
   repositories → services → entry points → jobs → tests). Migrations ship as plain-SQL files
   that the **owner runs manually** against the shared database (Neon) — see Gate 2.
3. `06-integration-tasks.md` — **integration** (replace mocks with the generated OpenAPI client,
   cache invalidation, externals, E2E).

**Exceptions:**

- Write the module's exported contract (`06` §2) first if another module will call it.
- Modules with no web/app surfaces (e.g. 01-foundations): Stage 2 is "N/A — <reason>" and the
  build starts at Stage 4 (Gate 1 is skipped and recorded as such in `07-progress.md`).

## 4. How to work — six stages, three manual gates

**Stage 1 — Read & plan.** Go through all documents listed in §1 plus the module's `01`–`06`
spec files and `technical-document.md`. Restate the objective; list assumptions and defaults
used; list the exact files to create/change across `applications/api`, `applications/web`,
`applications/app` and `packages/shared`; note tenant-isolation, security, bilingual (bn/en),
quota/cost, accessibility and performance impact.
- `APPROVAL = required` → **stop here and wait for approval.**
- `APPROVAL = pre-approved` → continue.

**Stage 2 — UI build (`04` + `05`, mock-driven).** Implement every web and app screen against
in-repo mock data (fixtures or MSW-style handlers matching the contract shapes — never hand-rolled
types). Tokens only, bn/en for every string, purposeful motion with reduced-motion forms,
360px-first app layouts. Run the touched apps' checks (`pnpm lint`, `pnpm typecheck`,
`pnpm test`) after each item. Finish with review instructions: how to run web + app and what to
look at (with screenshots).
🚦 **GATE 1 — manual UI approval.** Stop. The owner reviews the UI in the browser/on device and
approves or requests changes. **Do not start the backend before this approval.**

**Stage 3 — Docs sync (after approval).** Tick the completed `04`/`05` checklist items with
`— <TODAY>`; record UI decisions and screenshots in `07-progress.md`; set the module to
`🚧 In development` in `docs/modules/README.md`.

**Stage 4 — Backend build (`03`).** Schema first: write the plain-SQL migration files, then
**deliver the script path and ask the owner to run it manually** against the shared database.
🚦 **GATE 2 — owner runs the SQL and confirms.** While waiting, work that does not need the
live database may proceed: sqlc codegen against the migration files, tenant-scoped repositories,
services, unit tests — testcontainers integration tests apply migrations themselves, so they do
not depend on this gate. After confirmation: entry points, jobs, seeds, api checks
(`gofmt`/`golangci-lint`, `go vet`, `go test`).

**Stage 5 — Integration (`06`).** Replace the Stage-2 mocks with the generated OpenAPI client
(`openapi-fetch` / typed WS), wire cache invalidation (`06` §4) and externals, run E2E (Playwright
/ Maestro). Regenerate contract code after any `contracts/openapi/` change. Run the full check
suite across api + web + app.
🚦 **GATE 3 — manual approval of the integrated flows.** Stop and let the owner click through
the module's golden paths end-to-end on real data.

**Stage 6 — Gaps & verification.** Run the §5 definition-of-done checks; write `08-gaps.md`
(genuine gaps only — reason · impact · next action); update `docs/modules/README.md`; **ask the
owner for final verification** before marking the module `🟢 Delivered`.

**Working rules (every stage):**

1. **Respect the layers:** handler (REST/WS, generated from `contracts/openapi`) → service →
   tenant-scoped repository → sqlc queries. SQL only in repositories/migrations. Contract
   validation on every input. Authenticate + tenant-scope before any business logic.
2. **Respect the design:** tokens only; Hind Siliguri / Inter; deep-teal brand palette; both
   languages for every user-facing string; purposeful motion with a reduced-motion form.
3. **Respect the truth:** seed with clearly fictional data (e.g. "Demo High School") marked as
   such; unknowns are `TODO: Confirm …`; never invent schools, partners, prices or figures.
4. **Invalidate only the caches declared** in the module's `06` §4.
5. **Commit in small conventional commits** (`feat(api): …` / `feat(web): …` / `feat(app): …`),
   docs updated in the same commit as the behaviour.

## 5. Definition of done

- [ ] All checklist items ticked with `— <TODAY>` or deferred in `08-gaps.md` with a reason
- [ ] **Gate 1 passed** — UI approved by the owner (recorded in `07-progress.md`)
- [ ] **Gate 2 passed** — migration script executed manually by the owner against the shared
      database (version + date recorded in `07-progress.md`)
- [ ] **Gate 3 passed** — integrated flows approved by the owner
- [ ] No mock/fixture data paths remain — every screen talks to the real API through the
      generated client (mocks deleted or moved behind test-only flags)
- [ ] Unit, integration and E2E tests pass; **cross-tenant isolation tests pass** for any data
      module
- [ ] axe: 0 serious/critical on web screens touched
- [ ] Mobile screens verified at 360px width and with Bengali content
- [ ] DeepSeek calls (if any) quota-guarded and cost-noted in `07-progress.md`
- [ ] `docs/modules/<MODULE>/07-progress.md` written (what, decisions, evidence: test counts,
      screenshots, bundle/API latency numbers)
- [ ] `docs/modules/<MODULE>/08-gaps.md` lists only genuine remaining gaps (reason · impact · next
      action)
- [ ] `docs/modules/README.md` build status updated; `docs/tech-stack.md` updated if versions
      changed

## 6. Never

- Invent schools, partner brands, tutor credentials, prices, user counts or revenue figures.
- Write a database query without tenant scoping.
- Import another module's repository or write another module's tables.
- Add a cache key, cross-module call or external dependency not declared in `05`.
- Put a secret in code, a log, an image or a `NEXT_PUBLIC_*` / client-visible variable
  (`DEEPSEEK_API_KEY` and gateway credentials are server-side only).
- Call DeepSeek without a per-user quota check and a validated structured output.
- Process a payment webhook without signature verification and idempotency.
- Ship the logo PNG as a production asset once SVGs are available (see
  `docs/design-reference/brand/README.md`).

## 7. Final report (reply format)

```text
Module: <MODULE> (<APP>)            Date: <TODAY>
Stage:     1 plan · 2 UI · 3 docs · 4 backend · 5 integration · 6 gaps   → <current stage>
Gates:     1 UI ✓/pending · 2 SQL run ✓/pending · 3 integration ✓/pending · final ✓/pending
Done:      <ticked IDs>
Verified:  go vet/lint ✓ (api) · typecheck ✓ (web/app) · unit N/N · integration N/N · e2e N/N · axe ✓ · tenant-isolation ✓
Defaults relied on: <open-question defaults>
Gaps:      <IDs in 08-gaps.md, one line each>
Next:      <next module or item>
```

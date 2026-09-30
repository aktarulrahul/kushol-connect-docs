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
| always | `docs/modules/<MODULE>/01…05` | **all** — this is the work |
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

Complete **every unticked checklist item** of `<MODULE>`, in this order:

1. `03-backend-tasks.md` (schema → tenant-scoped repositories → services → entry points → jobs →
   tests)
2. `04-frontend-tasks.md` (screens → states → data flow → motion → responsive → a11y → tests)
3. `05-integration-tasks.md` (exported/consumed contracts, cache invalidation, externals, E2E)

**Exception:** write the module's exported contract (`05` §2) first if another module will call it.

## 4. How to work

1. **Plan.** Restate the objective; list assumptions and defaults used; list the exact files to
   create/change across `applications/api`, `applications/web`, `applications/app` and
   `packages/shared`; note tenant-isolation, security, bilingual (bn/en), quota/cost, accessibility
   and performance impact.
   - `APPROVAL = required` → **stop here and wait for approval.**
   - `APPROVAL = pre-approved` → continue.
2. **Implement one checklist item at a time.** After each item run the touched app's checks:
   api → `gofmt`/`golangci-lint`, `go vet`, `go test` (+ testcontainers integration); web/app →
   `pnpm lint`, `pnpm typecheck`, `pnpm test` (+ `pnpm test:e2e` / Maestro where coverage exists).
   Regenerate contract code after changing `contracts/openapi/`. Fix before moving on.
3. **Respect the layers:** handler (REST/WS, generated from `contracts/openapi`) → service →
   tenant-scoped repository → sqlc queries. SQL only in repositories. Contract validation on every
   input. Authenticate + tenant-scope before any business logic.
4. **Respect the design:** tokens only; Hind Siliguri / Inter; deep-teal brand palette; both
   languages for every user-facing string; purposeful motion with a reduced-motion form.
5. **Respect the truth:** seed with clearly fictional data (e.g. "Demo High School") marked as
   such; unknowns are `TODO: Confirm …`; never invent schools, partners, prices or figures.
6. **Invalidate only the caches declared** in the module's `05` §4.
7. **Commit in small conventional commits** (`feat(api): …` / `feat(web): …` / `feat(app): …`),
   docs updated in the same commit as the behaviour.

## 5. Definition of done

- [ ] All checklist items ticked with `— <TODAY>` or deferred in `07-gaps.md` with a reason
- [ ] Unit, integration and E2E tests pass; **cross-tenant isolation tests pass** for any data
      module
- [ ] axe: 0 serious/critical on web screens touched
- [ ] Mobile screens verified at 360px width and with Bengali content
- [ ] DeepSeek calls (if any) quota-guarded and cost-noted in `06-progress.md`
- [ ] `docs/modules/<MODULE>/06-progress.md` written (what, decisions, evidence: test counts,
      screenshots, bundle/API latency numbers)
- [ ] `docs/modules/<MODULE>/07-gaps.md` lists only genuine remaining gaps (reason · impact · next
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
Done:      <ticked IDs>
Verified:  go vet/lint ✓ (api) · typecheck ✓ (web/app) · unit N/N · integration N/N · e2e N/N · axe ✓ · tenant-isolation ✓
Defaults relied on: <open-question defaults>
Gaps:      <IDs in 07-gaps.md, one line each>
Next:      <next module or item>
```

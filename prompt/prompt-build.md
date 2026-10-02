# Build prompt — implement one Kushol Connect module

One prompt for every module. Set the parameters, then run it with an AI coding agent (or follow it
by hand).

```text
MODULE   = 05-communication-engine         # folder name under docs/modules/
TODAY    = 2026-10-01              # ISO date used when ticking checklist items and in progress notes
APPROVAL = required                # required → stop after the Stage 1 plan · pre-approved → continue after planning
```

**Set all three before starting.** `APP` no longer exists: every module is built for **api, web,
app and integration** — the module's own `03`/`04`/`05`/`06` checklists decide which surfaces
apply, and a surface with no checklist items is recorded as "N/A — <reason>" in `07-progress.md`.
Everything below refers to `<MODULE>`. Gates 1–3 are **always** manual, whatever `APPROVAL` says —
`pre-approved` only skips the stop after Stage 1.

---

## 0. Resume or start?

1. Open `docs/modules/<MODULE>/07-progress.md`. If it exists, find the last completed stage and
   gate, re-read only what that stage needs, and **continue from the next unfinished step** —
   never redo approved work. If it does not exist, start at Stage 1.
2. `07-progress.md` and `08-gaps.md` are created by the build (they are not part of the spec set).
   Create them on first use with the headings in §5.

## 1. What to read (paths relative to the workspace root)

Read the named sections, not whole documents, unless the ✅ column says "all".

| ✅            | Document                                                | Read                                                                                                                                                                         |
| ------------- | ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| always        | `prompt.txt` (workspace root)                           | all — the binding brief                                                                                                                                                      |
| always        | `docs/persona.md`                                       | all (short)                                                                                                                                                                  |
| always        | `docs/brd.md`                                           | §4 (scope) · §5 (BR-01…BR-05) · §6 (isolation) · §7 (business model) · §8 (phasing)                                                                                          |
| always        | `docs/prd.md`                                           | the sections your module implements (note the "Superseded" call-outs in §3 and §7)                                                                                           |
| always        | `docs/modules/<MODULE>/01…06` + `technical-document.md` | **all** — this is the work                                                                                                                                                   |
| always        | `docs/modules/README.md`                                | the module's row, dependencies, blocked-before-build defaults, **Cross-module registries**                                                                                   |
| always        | `docs/tech-stack.md`                                    | the api, web and app rows — plus §Infrastructure when building module 15                                                                                                     |
| always        | every dependency's `06-integration-tasks.md` §2         | the exact export signatures you will call                                                                                                                                    |
| UI work       | `docs/design-reference/README.md`                       | all — palette, typography, logo rules, **§6 mobile (CircleUp + WhatsApp)**, **§7 web (professional)**; look at `docs/design-reference/mobile-circleup/*.png` for app screens |
| schema / data | the module's `03-backend-tasks.md` §1 (Database Design) | tenant scoping is mandatory for every table                                                                                                                                  |
| payments / AI | `docs/prd.md` §5.2 / §5.4 + the module's `02` §6        | quota, cost and payment-confirmation rules                                                                                                                                   |
| module 15     | `docs/tech-stack.md` §Infrastructure                    | all                                                                                                                                                                          |

**If a file this prompt names is missing or a section is empty, writing that specification is the
task — stop and say so. Do not infer requirements.**

### 1.1 When documents disagree

Precedence, highest first:

1. The owner's instruction in the current conversation.
2. `docs/brd.md` (business decisions; §7 is the revised business model).
3. `prompt.txt`.
4. `docs/modules/README.md` (build order, cross-module registries, resolved decisions).
5. `docs/design-reference/README.md` (UI) and `docs/tech-stack.md` (tooling).
6. The module's own spec files (`technical-document.md` summarises `01`–`06`; if they differ, `01`–`06` win).
7. `docs/prd.md` (original pitch — kept for context).

A conflict you can resolve by this order: follow the higher source and note it in `07-progress.md`.
A conflict that changes scope, money, privacy or another module's contract: **stop and ask** —
never pick silently. A gap you discover in another module's spec goes in your `08-gaps.md` and is
reported; do not edit another module's code.

## 2. Preconditions (Step 0)

- [ ] Every dependency listed for `<MODULE>` in `docs/modules/README.md` is `🟢 Delivered` (or the
      owner explicitly accepts building against the interface fakes declared in `06` §3).
- [ ] The module's open questions are answered, or you use the default stated in its `01` §9 /
      the README "Blocked before build" table — list which defaults you are relying on.
- [ ] Every name you will introduce is checked against the README **Cross-module registries**:
      migration version block, error codes, i18n namespaces, Go export packages, web routes,
      API paths, env variables. Anything new is added to the registry in Stage 3.
- [ ] Repository state is known **for every repo the module touches**: each of
      `applications/api`, `applications/web`, `applications/app` (and `applications/ai` when the
      module's checklist names it) is its **own git repository** — no root repo, no shared
      package, nothing imported across app folders. In each touched repo: current branch, clean
      working tree, work on a branch `module/<MODULE>`; never commit to `main` directly.
      (Commit only when the owner has asked for commits in this session.)
- [ ] For UI modules: brand assets exist in `docs/design-reference/brand/` — otherwise use a
      typographic fallback ("কুশল CONNECT" in Hind Siliguri + Inter) and record it as a gap.
- [ ] Library versions marked `latest verify` in `docs/tech-stack.md` are checked against the
      library's current docs before pinning; pin exact versions and record them.

## 3. Objective

Complete **every unticked checklist item** of `<MODULE>`, in this **UI-first** order:

1. `04-frontend-tasks.md` + `05-app-tasks.md` — **UI first, mock-driven** (web screens → states →
   data flow → motion → responsive → a11y; app screens → states incl. offline → media flow →
   device behaviour). **No real API calls**: every screen runs on in-repo fixtures that mirror the
   contract shapes from `03-backend-tasks.md` §2, typed from the OpenAPI spec (add the paths to
   `applications/api/openapi/openapi.yaml` first, sync the spec copy into web/app
   (`pnpm sync:api-spec`) and generate each app's `src/api` types — never hand-roll DTO types).
   Keep fixtures in one place per surface (`src/fixtures/`) so swapping to the generated client is
   a one-file change.
2. `03-backend-tasks.md` — **backend** (schema → SQL migration files → tenant-scoped
   repositories → services → entry points → jobs → tests). Migrations ship as plain-SQL
   `up`/`down` files that the **owner runs manually** against the shared database (Neon) — Gate 2.
3. `06-integration-tasks.md` — **integration** (replace fixtures with the generated OpenAPI
   client, cache invalidation, externals, E2E).

**Exceptions:**

- Write the module's exported contract (`06` §2) — Go interface + DTOs + a fake — first if
  another module will call it.
- Modules with no web/app surfaces (e.g. 01-foundations): Stage 2 is "N/A — <reason>" and the
  build starts at Stage 4 (Gate 1 is skipped and recorded as such in `07-progress.md`).
- Stay inside the module: routes owned by later modules are stubs only; do not build features
  from another module's checklist, and nothing from `docs/modules/README.md` "Out of scope".

## 4. How to work — six stages, three manual gates

**Stage 1 — Read & plan.** Read everything in §1. Reply with a plan in this shape:

```text
Objective      one paragraph in your own words
Defaults used  open-question defaults + any precedence decisions (§1.1)
Conflicts      anything you must ask the owner about (or "none")
Files          create/change list per repo: applications/api (incl. openapi/openapi.yaml) ·
               applications/web · applications/app (+ applications/ai when the module owns it) —
               nothing outside the app folders; "N/A — reason" for untouched surfaces
Contracts      exports you implement (06 §2) · exports you consume (with the owner module)
Data           tables + migration file names/versions (from the README registry)
Impact         tenant isolation · security · bn/en · quota/cost · a11y · performance
Checks         the exact commands you will run per stage
Risks          top 3 with mitigation
```

- `APPROVAL = required` → **stop here and wait for approval.**
- `APPROVAL = pre-approved` → continue.

**Stage 2 — UI build (`04` + `05`, mock-driven).** Implement every web and app screen against
fixtures. Rules:

- Tokens only (no raw hex, spacing or font values in components); 02 primitives before new
  components; every string via `t()` in bn + en.
- **App:** CircleUp layout + WhatsApp chat behaviour in Kushol teal
  (`docs/design-reference/README.md` §6), 360px-first, low-end Android profile, offline states.
- **Web:** professional SaaS landing / admin console (§7), desktop-first down to 768px,
  keyboard-complete.
- Every screen has loading (skeleton), empty, error and success states; motion has a
  reduced-motion form.
- Run the touched apps' checks (`pnpm lint`, `pnpm typecheck`, `pnpm test`) after each item.

Finish with review instructions: exact commands to run web + app, the routes/screens to open,
the states to toggle (fixture switches), and screenshots — app at 360px in bn and en, web at
1280px and 768px.
🚦 **GATE 1 — manual UI approval.** Stop. The owner reviews the UI in the browser/on device and
approves or requests changes. Apply requested changes and re-submit. **Do not start the backend
before this approval.**

**Stage 3 — Docs sync (after approval).** Tick the completed `04`/`05` checklist items with
`— <TODAY>`; record UI decisions, owner feedback and screenshot paths in `07-progress.md`; add any
new names to the README registries; update the module's `technical-document.md` change log if a
decision changed the spec; set the module to `🚧 In development` in `docs/modules/README.md`.

**Stage 4 — Backend build (`03`).** Schema first:

1. Write the plain-SQL migration files using the version block reserved for the module in the
   README registry (versions must be **higher than every already-applied version** — golang-migrate
   silently skips lower ones). Each has an `up` and a `down`; `down` must actually reverse `up`.
2. Deliver the file paths, the exact command to run them, and a one-line description of each, and
   **ask the owner to run them manually** against the shared database.

🚦 **GATE 2 — owner runs the SQL and confirms.** While waiting, work that does not need the live
database may proceed: sqlc codegen against the migration files, tenant-scoped repositories,
services, unit tests — testcontainers integration tests apply migrations themselves, so they do
not depend on this gate. After confirmation: entry points, jobs, seeds, and the api checks
(`gofmt`, `golangci-lint`, `go vet`, `go test ./...`, integration tests incl. cross-tenant
isolation). Every api service lands with its unit tests (§4.1) in the same commit as the code.

**Stage 5 — Integration (`06`).** Replace the Stage-2 fixtures with the generated OpenAPI client
(`openapi-fetch` / typed WS), wire cache invalidation (`06` §4) and externals, run E2E
(Playwright / Maestro — §4.1: golden-path specs written in Stage 2 now run against the local
stack; no stack without the owner's say-so). Regenerate contract code after any
`applications/api/openapi/` change and confirm zero drift: api `make contracts-check`; in web
and app `pnpm sync:api-spec && pnpm generate:api` then `git diff --exit-code` (each client's
spec copy must match the api's). Run the full check suite in each touched repo
(api + web + app): lint · typecheck · **unit tests** · contracts drift · build.
🚦 **GATE 3 — manual approval of the integrated flows.** Stop and give the owner a numbered list
of the module's golden paths (from `01` user stories) to click through end-to-end on real data,
with the seed accounts to use.

**Stage 6 — Gaps & verification.** Run the §5 definition-of-done checks; write `08-gaps.md`
(genuine gaps only — reason · impact · next action); update `docs/modules/README.md`; **ask the
owner for final verification** before marking the module `🟢 Delivered`.

**Working rules (every stage):**

1. **Respect the layers:** handler (REST/WS, generated from `applications/api/openapi/openapi.yaml`) → service →
   tenant-scoped repository → sqlc queries. SQL only in repositories/migrations. Contract
   validation on every input. Authenticate + tenant-scope before any business logic.
2. **Respect module boundaries:** call other modules only through the exports in their `06` §2;
   never import another module's repository or write its tables. If an export you need is
   missing, stop and report it — do not add it to the other module yourself.
3. **Respect the design:** tokens only; Hind Siliguri / Inter; deep-teal brand palette; the
   §6/§7 UI direction; both languages for every user-facing string; purposeful motion with a
   reduced-motion form.
4. **Respect the truth:** seed with clearly fictional data (e.g. "Demo High School") marked as
   such; unknowns are `TODO: Confirm …` with an owner; never invent schools, partners, prices,
   figures, or third-party API behaviour (payment gateways, SMS, FCM — check their current docs).
5. **Invalidate only the caches declared** in the module's `06` §4.
6. **Small conventional commits** (`feat(api): …` / `feat(web): …` / `feat(app): …` /
   `docs(<module>): …`), docs updated in the same commit as the behaviour, only when the owner
   has asked for commits.
7. **Evidence over claims:** every "done" is backed by a command output, test count or
   screenshot recorded in `07-progress.md`. If a check fails, say so with the output.

### 4.1 Testing — unit and e2e (mandatory in every module)

Every module ships its own tests. Writing the feature without its tests is an unfinished
checklist item.

**Unit tests — written in the same stage as the code they cover:**

| Repo | Command     | What must be covered                                                                                                                                                                                   |
| ---- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| api  | `make test` | Table-driven unit tests per service: validators/normalizers, token/OTP/HMAC logic and expiry, rotation + reuse, role/verified guard matrices, problem mapping, cursor paging, CSRF. `-race` must pass. |
| web  | `pnpm test` | Vitest per touched unit: forms/state machines (happy + invalid + rate-limited + delayed), problem+json mapping, phone/validation utils, i18n parity, fixture seam behaviour.                           |
| app  | `pnpm test` | jest per touched unit: stores/reducers and guards, validation schemas, OTP state machine, token store + single-flight refresh, navigation gating, i18n parity.                                         |

Rules: colocate tests with the code (`*.test.ts(x)` / `_test.go`); no network in unit tests
(clocks, gateways and providers are injected fakes); a bug fix ships with the test that would
have caught it; `make test` / `pnpm test` green is checked after every stage, not only at the
end.

**E2E tests — written in Stage 2 (specs, against fixtures) and run for real in Stage 5
(against the local stack):**

| Repo | Runner                       | Scope                                                                                                                                                                                   |
| ---- | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| web  | Playwright (`pnpm test:e2e`) | One spec per module golden path (from `01` user stories): public + authenticated routes, bn default + language toggle, one error path per critical form; axe checks on touched pages.   |
| app  | Maestro (`.maestro/*.yaml`)  | One flow per golden path with fixture mode ON. If the Maestro CLI or a device is unavailable, the spec is still written and the run is recorded as a gap with the exact command to run. |

E2E runs need the local dev stack (`applications/dev-start.sh`). The agent does **not** start
servers on its own: either the owner has approved running the stack in this session, or the
agent writes the specs and hands the owner the exact commands, recording "e2e pending owner run"
in `07-progress.md` and `08-gaps.md`.

**Triage rule:** a red test is never skipped, deleted or `fixme`-d to get green — fix the code,
or (when the test is wrong) change the test with a written reason in `07-progress.md`.

## 5. Definition of done

- [ ] All checklist items ticked with `— <TODAY>` or deferred in `08-gaps.md` with a reason
- [ ] **Gate 1 passed** — UI approved by the owner (recorded in `07-progress.md`)
- [ ] **Gate 2 passed** — migration files executed manually by the owner against the shared
      database (versions + date recorded in `07-progress.md`)
- [ ] **Gate 3 passed** — integrated flows approved by the owner
- [ ] No fixture data paths remain — every screen talks to the real API through the generated
      client (fixtures deleted or moved behind test-only flags)
- [ ] Contract drift check clean (api's generated Go matches `applications/api/openapi/openapi.yaml`; each client's spec copy and generated TS client match it)
- [ ] **Unit tests** for every new service/util/store (api `make test`, web `pnpm test`, app
      `pnpm test`) pass with `-race`/strict flags — counts recorded in `07-progress.md`
- [ ] **E2E specs exist for every module golden path** (web Playwright, app Maestro) and pass
      against the local stack — or the run is recorded as a pending-owner gap with the exact
      commands (§4.1)
- [ ] Unit, integration and E2E tests pass; **cross-tenant isolation tests pass** for any data
      module
- [ ] i18n parity check passes (identical bn/en key sets; namespaces from the 02 registry)
- [ ] axe: 0 serious/critical on web screens touched
- [ ] Mobile screens verified at 360px width, bn + en, on a low-end Android profile
- [ ] DeepSeek calls (if any) quota-guarded and cost-noted in `07-progress.md`
- [ ] README cross-module registries updated for every new migration, error code, namespace,
      export package, route and env variable
- [ ] `docs/modules/<MODULE>/07-progress.md` written: stages + gates with dates, decisions (ADRs),
      defaults relied on, evidence (test counts, screenshots, bundle/API latency numbers)
- [ ] `docs/modules/<MODULE>/08-gaps.md` lists only genuine remaining gaps (reason · impact · next
      action)
- [ ] `docs/modules/README.md` build status updated; `docs/tech-stack.md` updated if versions
      changed

## 6. Never

- Invent schools, partner brands, tutor credentials, prices, user counts or revenue figures.
- Write a database query without tenant scoping.
- Import another module's repository or write another module's tables.
- Add a cache key, cross-module call or external dependency not declared in `06`.
- Reuse or lower a migration version, or edit a migration the owner has already run
  (fix forward with a new file).
- Put a secret in code, a log, an image or a `NEXT_PUBLIC_*` / `EXPO_PUBLIC_*` / client-visible
  variable (`DEEPSEEK_API_KEY`, `FCM_SERVER_KEY` and gateway credentials are server-side only);
  read env only through the config module.
- Call DeepSeek without a per-user quota check and a validated structured output.
- Mark a payment successful from a callback or webhook alone — verify the signature where the
  gateway provides one, **confirm server-to-server** (status + amount + our txn id), and apply
  idempotency.
- Start a stage past a gate that has not been passed.
- Ship the logo PNG as a production asset once SVGs are available (see
  `docs/design-reference/brand/README.md`), or ship the CircleUp kit's own illustrations, photos
  or icons.

## 7. Final report (reply format)

```text
Module: <MODULE>                     Date: <TODAY>
Stage:     1 plan · 2 UI · 3 docs · 4 backend · 5 integration · 6 gaps   → <current stage>
Gates:     1 UI ✓/pending/N/A · 2 SQL run ✓/pending · 3 integration ✓/pending · final ✓/pending
Done:      <ticked IDs>
Verified:  api: vet/lint ✓ · unit N/N · integration N/N · contracts ✓
           web: typecheck/lint ✓ · unit N/N · e2e N/N (or pending owner run) · axe ✓
           app: typecheck/lint ✓ · unit N/N · e2e N/N (or pending owner run / gap)
           tenant-isolation ✓ · i18n parity ✓
Defaults relied on: <open-question defaults + §1.1 precedence decisions>
Waiting on owner:   <gate / question, or "nothing">
Gaps:      <IDs in 08-gaps.md, one line each>
Next:      <next stage, item or module>
```

# 10-tuition-marketplace — Build Progress

Module: tuition-marketplace · Surfaces: api + app + web (07's `/institution/tutors` stub filled) ·
Repos: `applications/api`, `applications/app`, `applications/web` · **Last updated:** 2026-10-03

> Owner instruction (this session): "complete the 10-tuition-marketplace module" — building
> continues through the stages on that instruction (precedent: the module-06 run); gates 1–3 stay
> owner-manual.

## Stage / gate status

| Stage | Status | Evidence (dated) |
| --- | --- | --- |
| 1 Plan | ✅ 2026-10-03 | plan delivered in-session (defaults OQ-1…7 + blocked-before-build verification standard; deps 05 🚧-code-complete accepted per owner instruction) |
| 2 UI (web + app, mock-driven) | ✅ 2026-10-03 | web: queue/detail/oversight on `fixtures/tuition.ts`; app: 11 marketplace routes on `fixtures/tuition.ts`; OpenAPI paths #1–#15 landed FIRST and both clients generated from them (no hand-rolled DTO types) |
| Gate 1 (UI approval) | ⏳ pending owner — build continued on the owner's "complete the pending tasks" instruction (2026-10-03) | |
| 3 Docs sync | ✅ 2026-10-03, refreshed after Stage 4/5 | this file, `08-gaps.md`, README → 🚧, checklist ticks (`03` §7, `04` §9, `05` §9, `06` §10), change log |
| 4 Backend | ✅ code-complete 2026-10-03 | 4 migrations + 4 sqlc query files + `internal/tuition` (service, matching, payload, jobs, handler, dto, cache) + cmd/api + httpapi wiring; `go build ./...` + `go vet ./...` clean repo-wide; golangci-lint 0 issues in `internal/tuition`; UT green `-race`; **SQL hand-off below — Gate 2 pending owner** |
| Gate 2 (SQL on Neon) | ⏳ pending owner | run `db/migrations/2026112009000{0,1,2,3}_tut_*.up.sql` (with their `.down` reverses) in order |
| 5 Integration | ✅ code-complete 2026-10-03 | app: live `openapi-fetch` client (`live.ts`) behind the session-token selector (`backend.ts`), hooks re-pointed; live-client tests 14/14; web: stays on the fixture seam until 07's console session glue (G-8) — contract + E2E specs ready; IT + Maestro written, runs pending owner |
| Gate 3 | ⏳ pending | — |

## Decisions (ADR)

1. **ADR-1 (spec-order):** the 15 tuition endpoints were added to `applications/api/openapi.yaml`
   before any UI code so fixtures/DTO types come from the generated clients (build-prompt Stage-2
   rule). Drift checks pass (`contracts: no drift` api; both clients re-synced 2026-10-03).
2. **ADR-2 (INV-4 in the contract):** `contact`/`chat` on tutor-detail and both match shapes are
   `oneOf: [schema, null]` — staged contact reveal is enforced by the contract, not convention.
   `interestedCount` is required (list chips render it unconditionally).
3. **ADR-3 (app seam):** screens/lib import only `src/fixtures/tuition.ts` (one-file swap story);
   the wizard offline queue is in-memory in Stage 2 (`replayPendingPosts` pure + tested) and gets
   its persisted store in Stage 5. Tab bar untouched (owner freeze precedent) — the marketplace
   route tree ships standalone; Market-tab wiring (`/shop` vs `/marketplace`) is an owner
   question (G-5).
4. **ADR-4 (deep links additive):** `tuition_match`/`tuition_interest`/`tuition_verification`
   routes added to 06's `deepLinkFor` map (additive per 06 §7); unknown targets still fall back
   home. Covered by `tuition.test.ts`.
5. **ADR-5 (web forms):** the repo's admin convention is controlled inputs + zod (RHF is not a
   web dependency today); forms validate with the shared `validation.tuition.*` keys and never
   lose input. Deviation from 04 §3's "RHF + zod" noted — 07's pages set the convention.
6. **ADR-6 (platform queue tab):** Super-Admin-only platform tab renders behind a fixture review
   flag in Stage 2; the real role gate lands with Stage 5's auth seam — the api enforces scoping
   regardless (`school_id IS NULL` rows never leave the platform queue).

## Evidence (2026-10-03)

| Repo | Check | Result |
| --- | --- | --- |
| api | `make contracts` + `make contracts-check` | tuition paths #1–#15 + 25 schemas generate; `contracts: no drift` |
| web | `pnpm typecheck` | green (`next typegen` re-ran to clear the 07 stream's stale `.next/dev` validators) |
| web | scoped eslint (`--max-warnings=0`) on tuition files | clean |
| web | `pnpm test` | 168/168 (5 new tuition-seam tests) |
| web | `pnpm test:e2e` | `e2e/tuition.spec.ts` written (queue→detail→approve; reject-note guard; oversight close) — **run pending owner** |
| app | `pnpm typecheck` | green (`expo customize tsconfig.json` regenerated `.expo/types/router.d.ts` incl. marketplace routes) |
| app | scoped eslint on tuition files | clean |
| app | `pnpm test src/lib/tuition src/fixtures/tuition` | **18/18** (wizard state machine, schemas, offline queue replay, contact-null INV-4, verified gates, single-winner accept, deep-link map) |
| app | `pnpm test` (full) | 254/255 — the 1 red is `src/__tests__/index.test.tsx` (pre-existing, 05 stream, module-06 G-3) |
| app | Maestro | `.maestro/tuition-golden-path.yaml` written — **run pending owner** |
| both clients | `sync:api-spec && generate:api` | spec copies + `schema.gen.ts` carry the tuition contract (133 type refs each) |

## Stage 4/5 evidence (2026-10-03)

| Repo | Check | Result |
| --- | --- | --- |
| api | `go build ./...` + `go vet ./...` | clean repo-wide (the earlier 04-stream `hierarchy.GetCity` breakage was fixed by its owning stream in the meantime) |
| api | `make fmt-check` | clean (incl. the additive 06 payload-map edit) |
| api | `go test -race ./internal/tuition/...` | **UT-001/002/005/006/010/011 + state guards green** (ranker coverage→distance→stable-id, Dhaka bbox ≈0.0449°, catalogs, contact-regex, tag set, privacy-shape payload) |
| api | `go test ./...` | repo-wide green, no FAIL |
| api | golangci-lint `./internal/tuition/...` | 0 issues |
| api | `make contracts-check` | `contracts: no drift` (incl. `GET /tuition/tutor-profile` added after the app tracker needed it) |
| api | IT `it_tuition_test.go` | IT-001/002/003/004/005/009 written (testcontainers + fakes) — **pending owner** `make test-integration` |
| api | cmd/api wiring | `tuition.match` / `tuition.expiry` / `tuition.verification-reminder` registered; notify + chat adapters + shared tag cache wired |
| app | `pnpm typecheck` | green (`.expo/types` regenerated via `expo customize tsconfig.json`) |
| app | scoped eslint on tuition files | clean |
| app | `pnpm test src/lib/tuition src/fixtures/tuition` | **32/32** (wizard 3, queue 3, deep-links/schemas 5, fixtures 8, live client 4, notifications regression 9) |
| app | `pnpm test` (full) | 253/254 — the 1 red is `src/__tests__/index.test.tsx` (pre-existing, 05 stream) |
| app | Maestro | `.maestro/tuition-golden-path.yaml` — **run pending owner** |
| web | `pnpm typecheck` + `pnpm test` | green · 20 files (incl. 5 tuition-seam tests) |
| web | `e2e/tuition.spec.ts` | written — **run pending owner** |
| both | `sync:api-spec && generate:api` | both clients carry the full tuition contract; spec copies match the api |

## Independent verification + web seam (2026-10-03, second stream)

The owner ran a second agent session on this module after the 06-notifications run; it verified
the Stage 4/5 evidence above independently and landed the web half of the Stage-5 seam:

| Repo | Check | Result |
| --- | --- | --- |
| api | `go build ./...` + `go vet ./...` | clean (repo-wide, 2026-10-03) |
| api | `go test -race -count=1 ./internal/tuition/...` | green |
| api | golangci-lint `./internal/tuition/...` | 0 issues |
| api | `make contracts-check` | `contracts: no drift` |
| app | `pnpm typecheck` + `pnpm test src/lib/tuition src/fixtures/tuition` | green · 18/18 (verified mid-flight; the owning stream's later 32/32 run supersedes) |
| web | `src/lib/tuition/api.ts` + `api.test.ts` **landed** | live admin seam for endpoints #2/#3/#8/#9/#10, typed from the generated schema (`TuitionRequirementPage`, `TuitionVerificationPage`, `*Result` envelopes unwrapped; problem codes → `TuitionApiError`; transport injectable) |
| web | `pnpm test src/lib/tuition` | 6/6 (envelopes, problem mapping, OFFLINE transport, approve-note optional / reject-note required) |
| web | `pnpm typecheck` + `pnpm test` | green · 174/174 |
| web | `src/i18n/catalog.test.ts` allowlist | fixed: `landing.mkt.wordmark` ("kushol", brand Latin wordmark) added to the proper-name allowlist — unblocked the bn-catalog guard after the 07 stream added the key |

The web screens stay on the fixture seam until module 07's session middleware (`WEB-INT-005`,
cookie + CSRF transport) lands — flipping `/institution/tutors*` + `/institution/tuitions` to
`lib/tuition/api.ts` is then a one-import change (`08-gaps.md` G-7).

## Gate 2 SQL hand-off (owner)

```text
applications/api/db/migrations/20261120090000_tut_requirements.up.sql          -- requirements + indexes (GIN subjects, partial expiry)
applications/api/db/migrations/20261120091000_tut_tutor_profiles.up.sql        -- profiles (verified partial, geo, GIN)
applications/api/db/migrations/20261120092000_tut_tutor_verifications.up.sql   -- one-pending partial unique + reject-note CHECK
applications/api/db/migrations/20261120093000_tut_matches.up.sql               -- UNIQUE pair + single-accept partial unique
```
Run in order against the shared Neon database (each has a `.down` reverse). golang-migrate records
the highest version — do not run lower-versioned files afterwards.

## UI review hand-off (Gate 1)

- **Web** (`pnpm dev`, school-admin fixture login): `/institution/tutors` (queue + SLA chips; platform
  tab via `tuitionFixtureFlags.platformScope`), `/institution/tutors/ver_demo_1` (evidence viewer,
  approve/reject note rules), `/institution/tuitions` (oversight + confirm-guarded close). Fixture
  modes: `success/offline/forbidden/conflict` (`tuitionFixtureFlags`). Desktop 1280 + 768.
- **App** (fixture session): home → wizard (4 steps, offline banner via
  `tuitionFixtureFlags.mode = "offline"`) → my requirements → detail accept; matches interest
  (optimistic); tutor setup + evidence tracker; premium upsell (disabled CTA). 360px bn + en.

---

## Scope correction + marketplace build (2026-10-04, owner instruction)

**Tuitions are now independent of schools/colleges.** The P0 admin verification/oversight screens
(`tuition.admin.*`, `/institution/tuitions` for the institution view) stay as built; the marketplace
itself moved to standalone public routes with a new fixture seam (`fixtures/tuition-market.ts`):

| Surface | What exists |
| --- | --- |
| `/tuition` | Browse open requirements (subject/class/area/sessions/budget) + interview-call log; Kushol ops **Arrange interview** per requirement |
| `/tuition/post` | Guardian/student posts a requirement (no institution binding) |
| `/tuition/register` | Any Kushol user registers as a tutor → **auto-match** (subject + class levels + area) → **matched tutors are notified** (count shown on success) |
| Interviews | **Physical meet or online** — mode toggle; online takes a meeting link, in-person takes a venue; calls logged with mode badge |
| Ratings | **Registered tutors are rated 1–5** (`rateTutor`): running average + count shown; unrated tutors render "unrated" explicitly |

**Additive api contracts for the integration pass (10):** tuition requirements (no school FK —
poster name/phone/subject/class/area/budget), tutor registrations (user-linked, subject/class/
area), requirement–tutor matching + tutor notifications (06 push type `tuition.match` already
exists), interview calls (mode in_person/online, slot, venue/meeting link), `tutor_ratings`
(tutor, rater, stars 1–5, unique per rater per session).

**Verified:** fixture tests for post → register → match/notify → arrange (both modes) and the
rating bounds; web typecheck/lint green; 205/205 tests.

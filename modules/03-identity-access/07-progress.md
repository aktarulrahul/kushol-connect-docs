# 03-identity-access — Build Progress

Module: identity-access · Surfaces: api · web · app · integration ·
Repos: `applications/api`, `applications/web`, `applications/app` (each its own git repo,
branch `module/03-identity-access`, nothing committed yet) · **Last updated:** 2026-10-17

## Stage / gate status

| Stage | Status | Evidence (dated) |
| --- | --- | --- |
| 1 Plan | ✅ approved (earlier session) | built per 01–06 spec set |
| 2 UI (mock-driven) | ✅ built (earlier session) | web /login /register /verification-pending /auth/sso/return; app onboarding + login; fixtures seam |
| Gate 1 (UI approval) | ✅ owner | 2026-10-15 — owner approved in session ("complete all from Gate 1"), including the Email OTP tab |
| 3 Docs sync | ✅ | 2026-10-15 — checklists ticked: `IDT-FE-001…008` (FE-003 superseded by the passwordless pivot), `IDT-AP-001…011/013`, `IDT-INT-001…011`. Open: `IDT-FE-009/010`, `IDT-AP-012` (G-8), `IDT-AP-014` + `IDT-INT-012` (E2E runs — G-4) |
| 4 Backend | ✅ (api) | full gate green 2026-10-02: fmt · contracts · vet · lint · `-race` unit (18 pkgs) · testcontainers integration incl. cross-tenant isolation; 2026-10-09 `make test-integration` fully green (32 pkgs) |
| Gate 2 (SQL on Neon) | ◐ core done · 1 straggler | 2026-10-09 — owner applied all migrations to Neon via 15's first deploy (`v0 → 20270302090001 dirty=false`, covers the 01+03 blocks); still pending on Neon: `20270303090001_seed_demo_tenant_users` + `bootstrap-super-admin` (applied to the local `kc`/dev DB only); 2026-10-17: new data migration `20270307090000_set_kushol_admin_phone`; 2026-10-18 owner ran `migrate up --confirm` on Neon → `database_version=20270307090000 expected_version=20270307090000 dirty=false` (the starting version was not captured, so it may also have applied the earlier pending files, incl. `20270303090001`); local `kc` applies it on the next `dev-start.sh` |
| 5 Integration | 🚧 live for the auth calls the spec already has; some reads still fixtures | 2026-10-02: phone OTP, register, GET /me, logout (web + app), web SSO return → generated client. See the integration note below |
| Gate 3 (integrated flows) | ⏳ pending owner | — |
| 6 Gaps & verification | 🚧 | 08-gaps.md created 2026-10-02 |

## Owner decisions (2026-10-02) — ADR

1. **Seed the platform Super Admin:** `contact.aktarul@gmail.com` (password held only as the
   bootstrap credential, never shown in any UI). Executed against the local `kc` database
   (`applications/api`: `go run ./cmd/api bootstrap-super-admin`) → "super admin created".
   Neon gets the same command after Gate 2.
2. **Passwordless login:** "I don't want password in email — after input email, 6 digit OTP will
   be sent to the mail address." Implemented same day:
   - Contract: `POST /api/v1/auth/login/password` **removed** (+ `PasswordLoginInput/Result`);
     `OtpVerifyResult.status` gains `unknown_email`.
   - Api: `otp.UserFinder.StatusByEmail`; login suspend-check runs on the email channel;
     `IDT-IT-002` re-logs in via email OTP; new `TestITEmailOtpLogin` (email login ✓,
     unknown_email ✓, removed endpoint answers 404 ✓); `IDT-IT-010` covers the email cooldown.
   - Web: Email OTP tab is now the default login (two-step email → code); password form deleted;
     `useCountdown` shared; i18n bn/en updated (parity holds).
   - App: password tab → Email OTP tab; `OtpVerify` accepts an email target (also fixes a latent
     double-send: login now passes `autoSend=false`).
   - Passwords survive only as provisioned credentials: bootstrap super admin, teacher
     registration, `/auth/password/forgot` + `/reset` (07 vendor first-password set).

## Bugfix (2026-10-02) — login email never arrived

The app email tab called the in-memory fixture, so nothing was handed to SMTP. The jobs worker
also crashed on boot (`jobs.Default` had a nil database connection — `SetConn` was never called),
so a queued `auth.otp_email` could not be delivered. Fixed: `jobs.SetConn(pool)` at boot; enqueue
returns an error instead of panicking when the pool is missing; the email body is quoted-printable
UTF-8; the app/web email login uses `POST /auth/otp/request` and `/auth/otp/verify`. Web local
dev rewrites `/api/v1/*` onto the api (`next.config.ts`) so the browser avoids CORS (api does not
send CORS headers). Phone login was still on the fixture at this point (wired later the same day —
see Integration below). Confirmed: worker log `otp email delivered` for the seeded super admin
address after `POST /api/v1/auth/otp/request` returned 202.

The same mail is now a bilingual letter (`smsout.RenderOTPEmail`): plain text plus
HTML, deep-teal wordmark, the six digits as separate figures, purpose-specific
subject for login / register / link / reset. SMS stays the one-line text.

## Integration (2026-10-02) — remaining auth seams

Wired to the generated client (no new endpoints):

- **Phone OTP** — web `/login` and app login + onboarding call `POST /auth/otp/request`, `/resend`, and `/verify`. Email OTP is unchanged.
- **Register** — web wizard and app onboarding call `POST /auth/register`. The app sends the verified `otpCode` with the phone proof.
- **GET /me** — web pending screen and `/auth/sso/return` (cookie). App live sessions already used it; `PATCH /me` now does too for a real access token (language switch).
- **Logout** — web `POST /auth/logout` echoes the `kushol_csrf` cookie as `X-CSRF-Token`. App `signOut` revokes the refresh family; settings "everywhere" calls `POST /auth/logout-all` when the token is a JWT.
- **Web SSO return** — the callback already sets the session cookie and redirects with `?sso=`. `ok` and `linked` read `GET /me` and route; any other marker goes to `/login?sso=failed`.

Still on fixtures, or with no contract to call (08-gaps): hierarchy pickers, school-request, the caller's own verification request (rejection reason), the app device list, and app SSO (no mobile token handoff). Fixture helpers stay for unit tests and for sessions whose access token is still the demo `access_demo_` pair.

## Evidence

| Repo | Check | Result |
| --- | --- | --- |
| api | `make gate` (fmt · contracts · vet · lint · test -race · test-integration) | exit 0, 2026-10-02 |
| api | local DB `migrate-status` | `20261001090035 dirty=false`, matches binary |
| web | `pnpm lint && pnpm typecheck && pnpm contracts:check && pnpm test && pnpm build` | ✓ · ✓ · no drift · **147/147** (17 files) · build ✓ (2026-10-02, pre-integration) |
| web | `pnpm exec tsc --noEmit` · eslint on touched auth files · `pnpm test` | ✓ · ✓ · **160/160** (18 files) (2026-10-02, after wiring) |
| app | `pnpm lint && pnpm typecheck && pnpm contracts:check && pnpm test` | ✓ · ✓ · no drift · **152/152** (23 suites) (2026-10-02, pre-integration) |
| app | `pnpm exec tsc --noEmit` · eslint on touched auth files · `pnpm test` | ✓ · ✓ · **180/180** (27 suites) (2026-10-02, after wiring) |

## Defaults relied on

- Teacher registration keeps email+password (spec as written) — flagged in 08-gaps G-1 for the
  owner to confirm or make registration passwordless too.
- `/auth/password/forgot` + `/reset` kept (07 vendor flow + recovery) although login no longer
  uses passwords — G-2.

## Standing rule (2026-10-02) — agent never starts the stack

Owner rule (also `.cursor/rules/no-dev-server.mdc` + `AGENTS.md`): the agent must not start
Docker, `dev-start.sh` / `dev-stop.sh`, api/web/app binaries, Metro, or open direct DB sessions.
Owner runs the local stack and Gate 2/3 / e2e / testcontainers manually; agent records results
as pending until the owner shares output. Agent-side checks stay container-free (`go build` /
`vet` / lint / fmt / `make contracts-check` / `go test -race` / `pnpm test`).

## App session restore (2026-10-02)

- `AuthProvider` mounts above the navigator; hydrate + single-flight refresh use Secure Store
  token pairs; a rejected refresh clears the session; foreground retries a renew that failed
  offline.
- `/` and `/login` wait until restore finishes (`idle`/`checking` → blank / boot skeleton). A
  restored session redirects to `/chat` or `/verification-pending` — no welcome / login flash
  before redirect.

## Session wrap (2026-10-02) — what shipped (no gate pass)

Order within the day (append-only; does not invent Gate ✓):

1. **Email OTP delivery** — app/web left the in-memory fixture for email; `jobs.SetConn(pool)` so
   `auth.otp_email` can send; bilingual letter templates (`smsout.RenderOTPEmail`).
2. **Web email OTP live** — Next.js `/api/v1/*` rewrite onto the api in local (api does not speak
   CORS). Phone login stayed on fixtures until the Stage 5 wiring pass later the same day.
3. **Stage 5 partial** — phone OTP, register, `GET /me`, logout, web SSO return on the generated
   client (see Integration above). Hierarchy pickers / school-request / device list / app SSO
   still fixtures or missing contract (`08-gaps` G-3, G-6–G-8).
4. **App AuthProvider + refresh session** — above.
5. **Gates** — Gate 1 (UI, now includes Email OTP tab), Gate 2 (Neon SQL), Gate 3 (integrated
   flows) all still ⏳ owner. Module stays 🚧 — **not Delivered**.

Related app chrome (WhatsApp-dense chat list, bottom tabs, reactions, etc.) is Stage-2 fixture
UI under **05-communication-engine** `07-progress.md` — not an identity deliverable.

## Fix log — 2026-10-09 (owner `make test-integration` run 1 failure)

**IDT-IT-006 (TestIT006Register)** returned 500: register inserts the verification request with
`requested_section_id`, and migration 04's FK (`verification_requests_requested_section_id_fkey`)
needs the section row in the DB — but the IT world seeded only cities + schools, while placement
re-validation runs against the in-memory demo. Fix: `newWorldWith` now also seeds the demo
sections (both schools, levels 6–10, A/B, session 2026) so the deterministic demo ids exist as
rows. The wrong-hierarchy CONFLICT case still fails first on placement (memory), before any FK.
Agent-side checks green (build · vet · lint 0 · unit ok · `-tags=integration` compiles); suite
re-run **pending owner**.

## Fix log — 2026-10-09 (evening owner run: `migrate up` aborts everywhere)

The new seed migration `20270303090000_seed_kushol_admins_and_chat` failed on every
testcontainer suite (httpapi/jobs/notify/tuition/platform-db) with 42P10 — `ON CONFLICT (email)`
cannot target `users_email_key` because that index is PARTIAL (`WHERE email IS NOT NULL`). Fix:
the conflict target now repeats the index predicate (`ON CONFLICT (email) WHERE email IS NOT
NULL DO UPDATE …`). Verified the other conflict targets are full-index/PK-backed
(`auth_identities_provider_account_key`, `chat_group_members_unique_key`, `chat_groups` PK) and
the seeded values pass the role/plan/locale CHECKs. `go build` · `go vet` (+`-tags=integration`)
· golangci-lint 0 issues; suite re-run **pending owner**.

## Demo tenant seed — 2026-10-09 (owner request: "seed the new users")

New migration `20270303090001_seed_demo_tenant_users` (+down) seeds the shared demo tenant:

- **Hierarchy**: launch cities (ঢাকা, চট্টগ্রাম) + the two demo schools + sections 6–10 A/B —
  ids are the frozen `hierarchytest` constants / v5 `SectionID` grammar, so Gate 2's DB matches
  every test world.
- **Staff**: `rahul.aktarul@gmail.com` (school_admin, Demo HS), `aktarul.rahul@gmail.com`
  (school_admin, Demo CTG).
- **Vendor**: `aktarul.i1708@gmail.com` (`vendor`, platform-scoped) + an approved
  `vendor_accounts` row portal-linked to it.
- **Students + guardians**: 2 VERIFIED students (enrolled, HS 6A/6B) + 2 guardians
  (`guardian_links` father/mother, ROSTER source).
- **Auth (owner decision)**: passwordless — email OTP (web + app) via `users.email`, phone OTP
  (app) via `users.phone_e164`; NO `auth_identities` rows, NO password hashes (OTP login resolves
  the account straight off the users table, 03 §2).

Fallout fixed in the IT worlds that previously seeded their own copies of the shared demo rows:
httpapi world now relies on the migration for the demo hierarchy; hierarchy + notify worlds give
their test cities distinct names (`cities_name_en_key` is unique). Exact-list assertions in
hierarchy IT005/IT009 became presence-based (the shared tenant legitimately contributes rows).

**Verified**: migration up/down/up green; `make test-integration` fully green — 32 packages ok;
vet + golangci-lint 0 issues; unit `-race` 31 ok.

## SMS OTP — app only, SAS Bulk SMS gateway (2026-10-17)

Owner request: wire the owner's SMS provider (SAS Bulk SMS) behind phone OTP; "Mobile OTP will
only work for the mobile app"; give Aktarul Islam (`aktarul.islam@kusholconnect.com`) the phone
`+8801776300013`. Nothing committed (owner commits on request).

**api**

- `internal/smsout/gateway.go` (new, replaces the JSON-POST placeholder): `HTTPGateway` sends
  one GET per message,
  `{SMS_GATEWAY_URL}?apikey&secretkey&callerID={SMS_GATEWAY_SENDER}&toUser=8801XXXXXXXXX&messageContent`.
  A send fails on a transport error, a non-2xx status (redirects are not followed), or a reply
  carrying an error marker (08-gaps G-11). Errors name the endpoint without its query and redact
  any echo of the key, the secret or the number. A transport error used to print the full
  credentialed URL into the worker log and `jobs.last_error` (G-10). A nil gateway answers
  `ErrNotConfigured` instead of panicking on the typed-nil `*HTTPGateway` that `main` wires when
  the URL is unset. Handler logs mask the number (`+8801XXXXXX678`).
- `internal/config`: the real key/secret/callerID `envDefault`s are gone (G-10).
  `SMS_GATEWAY_SECRET_KEY` added. `SMS_GATEWAY_SENDER` is the callerID; the stray
  `SMS_GATEWAY_CALLER_ID` was dropped. A set `SMS_GATEWAY_URL` without key, secret or sender now
  fails startup and names each missing variable. Unset still means degraded.
- `internal/auth`: `refuseWebPhoneOTP` is the one gate for phone OTP request/resend/verify from
  web clients (`Origin` or `X-Kushol-Client: web`; `X-Kushol-Client: mobile` wins). It answers
  `VALIDATION_FAILED` with the new bilingual `errors.phone_otp_app_only` key and a `phone` field
  error. The refusal existed already as an inline check with no copy and no tests. It is a
  product rule, not a security boundary (G-13).
- Migration `20270307090000_set_kushol_admin_phone` (+down): sets the phone on the account with
  that email. Idempotent. If another account already holds the number, it stops with a message
  naming that account (`users_phone_e164_key` is unique). The value is already the
  `phone.NormalizeBD` E.164 form. **Pending owner (Gate 2).**
- Env: real values only in the gitignored `applications/api/.env`. Placeholders in
  `applications/api/.env.example` and `docs/infra/deploy/env/api.env.example` (commented,
  module 15's template).

**app**: `createApiClient` sends `X-Kushol-Client: mobile` on iOS/Android. Login: the send
button's result now seeds `OtpVerify` (`initialSend`). Before, a code sent from the login button
left the resend button live at once and never showed the 15 s delayed-SMS notice. The send
button shows loading and ignores double taps. "Use a different number/email" returns to entry,
and switching tabs drops the sent code. New bn/en keys `auth.otp.change_phone` and
`auth.otp.change_email`.

**web**: the login card was already email OTP + SSO only. The unused `PhoneOtpForm` and its test
are deleted, and `login-island.test.tsx` pins "no phone field on web login". Web *registration*
still asks consumers for phone OTP, which the api now refuses: G-12, owner decision.

**Evidence (agent-side, 2026-10-17; no app, no containers)**

| Repo | Check | Result |
| --- | --- | --- |
| api | `go build ./...` · `go vet ./...` · `go vet -tags=integration` (httpapi, auth, smsout, cmd) | ✓ |
| api | `go test ./...` (no `-race`: no cgo on this host) | all packages ok; new `TestGateway*` (fake `RoundTripper`, no network), `TestSMSHandlerMasksPhoneAndDegrades`, `TestLoadSMSGateway` + 3 config cases, `TestWebRequestClassification`, `TestPhoneOTPRefusedForWebClients`, `TestRefuseWebPhoneOTPLeavesAppAndEmailAlone` |
| api | golangci-lint (smsout, config, auth, i18n, cmd) | only `gofmt` on 3 CRLF working-tree files (two untouched); `gofmt -l` on CR-stripped copies of every touched file is clean (host CRLF false positive) |
| app | `tsc --noEmit` · eslint + prettier on touched files | ✓ · ✓ · ✓ |
| app | `jest --ci` | 361/362. New phone-login tests pass (`login.test.tsx` 6/6, `client.test.ts`). The 1 failure is pre-existing: `src/__tests__/index.test.tsx` (DSN-IT-002) expects the holding screen while the auth store is still `idle`, and `/` renders nothing until restore finishes. Untouched files |
| web | `tsc --noEmit` · eslint + prettier on touched files · `vitest run` | ✓ · ✓ · **253/253** (33 files) |
| contracts | OpenAPI unchanged | no regeneration needed |

**Pending owner**

1. Rotate the SAS key/secret (they are in pushed history, G-10), then update `applications/api/.env`.
2. Restart the stack with `applications/dev-start.sh`. It reloads `.env` and runs
   `migrate up --confirm` on the local `kc` database, which applies `20270307090000`.
   Neon: ✅ done 2026-10-18 (`database_version=20270307090000 dirty=false`). It ran through the
   pooled endpoint; use the direct (non-`-pooler`) host next time.
3. Gate 3: on a phone, sign in with `01776300013` and confirm the SMS arrives and is legible
   (Bengali text), and that the code signs Aktarul Islam in. 2026-10-18: two tries, and SAS accepted
   both (`Status "0"`, `Text "ACCEPTD"`, `Message_ID` 4117517 for the second), but no SMS arrived.
   The api side works. Delivery past SAS is open (G-11: delivery report, English-only test, Unicode).
   The check is now pinned to `Status "0"`, and the reply logs at info.
4. `make test-integration`: no new integration test, but every testcontainer suite now applies
   the new migration.

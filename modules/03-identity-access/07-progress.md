# 03-identity-access — Build Progress

Module: identity-access · Surfaces: api · web · app · integration ·
Repos: `applications/api`, `applications/web`, `applications/app` (each its own git repo,
branch `module/03-identity-access`, nothing committed yet) · **Last updated:** 2026-10-02

## Stage / gate status

| Stage | Status | Evidence (dated) |
| --- | --- | --- |
| 1 Plan | ✅ approved (earlier session) | built per 01–06 spec set |
| 2 UI (mock-driven) | ✅ built (earlier session) | web /login /register /verification-pending /auth/sso/return; app onboarding + login; fixtures seam |
| Gate 1 (UI approval) | ⏳ pending owner — now includes the new Email OTP tab | — |
| 3 Docs sync | 🚧 partial | this file + technical-document change log updated 2026-10-02; checklist ticks pending |
| 4 Backend | ✅ (api) | full gate green 2026-10-02: fmt · contracts · vet · lint · `-race` unit (18 pkgs) · testcontainers integration incl. cross-tenant isolation |
| Gate 2 (SQL on Neon) | ⏳ pending owner (01's G-1 covers both modules' blocks) | — |
| 5 Integration | 🚧 fixtures still in place; clients regenerated | web+app `schema.gen.ts` synced from api spec 2026-10-02, `contracts: no drift` |
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
UTF-8; the app email login uses `POST /auth/otp/request` and `/auth/otp/verify`. Phone login stays
on the fixture. Confirmed: worker log `otp email delivered` for the seeded super admin address
after `POST /api/v1/auth/otp/request` returned 202.

The same mail is now a bilingual letter (`smsout.RenderOTPEmail`): plain text plus
HTML, deep-teal wordmark, the six digits as separate figures, purpose-specific
subject for login / register / link / reset. SMS stays the one-line text.

## Evidence

| Repo | Check | Result |
| --- | --- | --- |
| api | `make gate` (fmt · contracts · vet · lint · test -race · test-integration) | exit 0, 2026-10-02 |
| api | local DB `migrate-status` | `20261001090035 dirty=false`, matches binary |
| web | `pnpm lint && pnpm typecheck && pnpm contracts:check && pnpm test && pnpm build` | ✓ · ✓ · no drift · **147/147** (17 files) · build ✓ |
| app | `pnpm lint && pnpm typecheck && pnpm contracts:check && pnpm test` | ✓ · ✓ · no drift · **152/152** (23 suites) |

## Defaults relied on

- Teacher registration keeps email+password (spec as written) — flagged in 08-gaps G-1 for the
  owner to confirm or make registration passwordless too.
- `/auth/password/forgot` + `/reset` kept (07 vendor flow + recovery) although login no longer
  uses passwords — G-2.

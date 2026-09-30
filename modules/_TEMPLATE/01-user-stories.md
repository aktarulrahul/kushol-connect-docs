# <Module Name> — User Stories

> Copy this folder to `docs/modules/NN-<module-name>/` and fill every section. Delete guidance
> blockquotes as you go. Never leave a section empty — write "None" or "N/A — <reason>".

**Module:** `NN-<module-name>`
**Status:** 📝 Spec drafted YYYY-MM-DD
**Owner:** Rahul (product owner)
**Last updated:** YYYY-MM-DD

---

## 1. Purpose

> 2–3 sentences: what this module provides and which business objective (`brd.md` §2) it serves.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Unverified user (pending) | Has an account but cannot participate until verified (module 03) |
| Student | |
| Guardian | |
| Teacher | |
| School Admin | Governs only their own school (tenant) |
| Super Admin | Governs the whole platform (tenants, vendors, campaigns) |
| Vendor / EdTech brand | |
| System (jobs, webhooks) | |

> The five roles (Super Admin / School Admin / Teacher / Student / Guardian) plus Vendors are
> defined by module 03 (`03-identity-access`). Verification gates every participatory action
> (`prd.md` §5.1).

## 3. Scope

**In scope**

-

**Out of scope** (explicit — prevents scope drift)

-

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| | |

---

## 4. User Stories

### `<PREFIX>-US-001` — <Short title>

**Priority:** P0 | P1 | P2 · **Traces:** BR-… (`brd.md` §5) / PRD §… · **Depends on:** —

**Story** — As a **<actor>**, I want **<capability>**, so that **<outcome>**.

**Acceptance criteria**

- **Given** <precondition>, **when** <action>, **then** <observable result>.

**Notes**

-

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `<PREFIX>-BR-001` | | DB constraint / service / both |

> Content-accuracy rules (`prompt.txt` §12) apply to every seeded or publishable entity — state
> how this module enforces them (fictional seed data marked as such, `TODO: Confirm …` blocks
> publishing).

## 6. Validation Rules

| Field | Rule | Message key (per-app `src/i18n` catalog) |
| --- | --- | --- |
| | | |

> Mirrored exactly by the OpenAPI contract (server validation) and the zod form schemas
> (web/app) generated from it. Both languages from day one.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to a protected action | `UNAUTHENTICATED`, no side effect |
| 2 | Cross-tenant read/write attempt | `TENANT_MISMATCH` / 404, no data leaked |
| 3 | Unverified (pending) user tries to participate | Refused with `NOT_VERIFIED` + how to get verified |
| 4 | Referenced media deleted / R2 object missing | Degraded placeholder, never a crash |
| 5 | Reduced motion enabled | Static / instant form of every animation |
| 6 | Offline action (app) | Queued or refused with a message — never silently lost |

## 8. Reporting Needs

> Dashboard figures this module contributes (consumed by modules 07/09 dashboards), or "None".

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | | Rahul | Open | |

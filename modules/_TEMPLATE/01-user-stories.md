# <Module Name> — User Stories

> Copy this folder to `docs/modules/NN-<module-name>/` and fill every section. Delete guidance
> blockquotes as you go. Never leave a section empty — write "None" or "N/A — <reason>".

**Module:** `NN-<module-name>`
**Status:** 📝 Spec drafted YYYY-MM-DD
**Owner:** Rahul (product owner)
**Last updated:** YYYY-MM-DD

---

## 1. Purpose

> 2–3 sentences: what this module provides and which business objective (`brd.md` §3) it serves.

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Visitor | |
| Admin (owner) | |
| Scheduler / Crawler | |

> Actors are defined in `access-matrix.md` §1. There is one authenticated role.

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

**Priority:** P0 | P1 | P2 · **Traces:** FR-… · **Depends on:** —

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

> Content-accuracy rules (`brd.md` §9) apply to every publishable entity — state how this module
> enforces them.

## 6. Validation Rules

| Field | Rule | Message (from `glossary.md` §6 where one exists) |
| --- | --- | --- |
| | | |

> Mirrored exactly by the Zod schema shared by the client form and the server entry point.

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Content contains `TODO:` at publish | Refused with `PUBLISH_BLOCKED_TODO` |
| 2 | Unauthenticated call to an admin action | `UNAUTHENTICATED`, no side effect |
| 3 | Slug collision | |
| 4 | Referenced media deleted / missing | |
| 5 | Reduced motion enabled | |
| 6 | JavaScript unavailable | |

## 8. Reporting Needs

> Dashboard figures this module contributes (FR-CMS-005), or "None".

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | | Rahul | Open | |

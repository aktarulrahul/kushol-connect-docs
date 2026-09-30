# <Module Name> — Technical Document

> Copy into `docs/modules/NN-<module-name>/` next to the six spec files (`01`–`06`). This is the
> single engineer-facing reference for the module: it compresses the spec set into one place so
> nobody has to open five files to understand how the module works. It must agree with the spec
> files — when it drifts, the spec files win and this file gets corrected. Delete guidance
> blockquotes as you go. Never leave a section empty — write "None" or "N/A — <reason>".

**Module:** `NN-<module-name>`
**Version:** 0.1
**Status:** 📝 Draft YYYY-MM-DD
**Owner:** Rahul (product owner)
**Last updated:** YYYY-MM-DD

---

## 1. Overview

### 1.1 Purpose

> 2–3 sentences: what this module provides and which business objective (`brd.md` §2 / BR-xx) it serves.

### 1.2 Scope

**In:** …

**Out:** …

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | | |
| consumed by | | |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |

> Only what this module actually touches (`docs/tech-stack.md` is the pinned source). State
> "None — <reason>" if a layer (e.g. web) is not part of this module.

---

## 3. Architecture

### 3.1 Component diagram

```text
<ASCII: apps → handlers → services → repositories → tables; externals; other modules>
```

### 3.2 Boundary

**Owns (tables / services):** …

**Reads (via exported service functions only):** …

### 3.3 Request / data flows

```text
<numbered happy-path flows: UI → handler → service → repo → sqlc → PostgreSQL;
realtime paths (WS/pub-sub); job paths. One flow per major capability.>
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |

---

## 4. Data Model (summary)

> One row per table — a mirror of `03-backend-tasks.md` §1. Column-level detail stays in `03`.

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |

---

## 5. Contracts

### 5.1 REST endpoints

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |

### 5.2 Realtime / jobs

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |

### 5.3 Exported service functions

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |

> Backend-only modules: write "N/A — <reason>" per subsection instead of deleting it. If the
> module ships no screens at all, keep both subsections with their N/A reasons.

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |

---

## 8. Configuration

### 8.1 Environment variables

| Variable | Required | Example / default | Used by |
| --- | --- | --- | --- |

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | authenticate → load role claims → tenant-scope (adjust if this module differs) |
| Role matrix | <which roles may do what on this module's endpoints> |
| Tenant scope | <per-table scoping rule; cross-tenant attempts → `TENANT_MISMATCH`/404> |
| Rate limits | <route classes> |
| Audit events | <what gets written to `audit_log`> |
| Privacy / minors | <data-minimisation, aggregation-only rules, contact-reveal gates, …> |

---

## 10. Error Handling

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |

> All errors surface as RFC-7807 `application/problem+json`. User-visible messages resolve via
> `packages/shared` catalogs — every message key ships in **bn + en** (Bengali default).

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | <structured fields this module adds; redaction rules> |
| Metrics / counters | <what to watch> |
| Health contribution | <what `/readyz` checks for this module, if anything> |
| Jobs & retries | <jobs owned, retry policy, dead-letter> |
| Runbook pointers | <deploy/rollback/backup notes specific to this module> |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | | `<PREFIX>-UT-…` | |
| Integration | | `<PREFIX>-IT-…` | |
| E2E | | `<PREFIX>-E2E-…` | |
| CI | | — | <quality gate for the touched apps> |

> Mandatory everywhere: unauthenticated calls denied; validation rejects bad input; cross-tenant
> attempts return `TENANT_MISMATCH`/404; publish guard blocks `TODO:`; public reads never return
> drafts.

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | |
| Hot paths + indexes | |
| Latency targets | |
| Bundle / payload impact | |
| Caching | |

---

## 14. Risks & Open Questions

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |

> Consolidated from `01` §9 and `02` §11 — this table is the one to review in module readiness
> checks. Anything unconfirmed keeps its `TODO: Confirm …` marker.

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |

---

## 16. Change Log

| Date | Change | Author |
| --- | --- | --- |

# <Module Name> — Solution Approach

**Module:** `NN-<module-name>` · **Last updated:** YYYY-MM-DD

> Written **before** any task list and any code (`docs/prompt/prompt-build.md` §4 step 1).

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| | | |

### 1.2 Relationships

```text
<ASCII sketch — must match this module's 03 §1 tables, which are the data model>
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| | | |

## 2. Module Boundary

**Owns (writes):** …

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| | | |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4.

## 3. Lifecycle

```text
<entity states relevant to this module — e.g. user: PENDING ──verify──▶ VERIFIED ──suspend──▶ SUSPENDED;
order: CREATED ──paid──▶ PAID ──fulfilled──▶ DONE. Or "None — this module has no state machine.">
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| | | | | |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| | | | |

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| | |

## 6. Security

Entry points, auth middleware placement (authenticate → role claims → tenant-scope), validation,
sanitisation, rate limits, privacy. Every table here must state its tenant-scope rule.

## 7. Accessibility & Motion

What is animated and why (details in `04` §5); keyboard and screen-reader behaviour.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| | | | | |

## 9. Performance

Expected volumes, hot queries and their indexes, bundle impact (gzip) of new dependencies.

## 10. Alternatives Considered

### Option A — <name> · Option B — <name>

| | A | B |
| --- | --- | --- |
| Advantages | | |
| Disadvantages | | |
| Complexity / weight | | |

**Recommendation:** … **ADR:** record non-trivial decisions in this module's `07-progress.md`
(or a new `docs/decisions/NNN-<slug>.md` if it affects other modules).

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| | | | |

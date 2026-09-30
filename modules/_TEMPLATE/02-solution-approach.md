# <Module Name> — Solution Approach

**Module:** `NN-<module-name>` · **Last updated:** YYYY-MM-DD

> Written **before** any task list and any code (`instruction.md` §4).

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| | | |

### 1.2 Relationships

```text
<ASCII sketch — must match data-model.md>
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

**Cache tags revalidated / consumed:** see `05-integration-tasks.md` §4.

## 3. Lifecycle

```text
DRAFT ──publish (guards)──▶ PUBLISHED ──unpublish──▶ DRAFT
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

Entry points, `requireAdmin()` placement, validation, sanitisation, rate limits, privacy.

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

**Recommendation:** … **ADR:** `docs/decisions/NNN-<slug>.md` if non-trivial.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| | | | |

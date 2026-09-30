# <Module Name> — Integration Tasks

**Module:** `NN-<module-name>` · **Last updated:** YYYY-MM-DD

> `02-solution-approach.md` §2 says *what* crosses this module's boundary; this file is the
> **contract**. **No cross-module call, cache key or external dependency may exist in code unless
> it is declared here** (`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | `<NN-module>` | we call them | exported Go service function | fatal / degraded |
| I-2 | `<NN-module>` | they call us | exported Go service function | |
| I-3 | api → app/web pushes | we notify | FCM topic / WS event / generated client refresh | degraded, never fatal |
| I-4 | `<external>` (FCM, R2, DeepSeek, gateways, SMS) | outbound | HTTPS SDK | degraded, never fatal (except payments ledger, which retries) |

## 2. Exported Contract

```text
<service>.<fn>(args): Promise<DTO>
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| | | | | |

Rules: exports return DTOs (never sqlc row structs); admin-only exports require role claims in the
context; services return domain errors (mapped to the problem envelope at the handler), never raw
HTTP; signature changes are additive first.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| | | |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| | |

| Read | Tagged with |
| --- | --- |
| | |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| | | |

## 7. Contract Stability

Schema changes expand/contract; JSON shapes versioned; the OpenAPI spec is the single source —
regenerate Go + TS contract code on every spec change.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| | | | |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `<PREFIX>-UT-…` | | Unit | |
| `<PREFIX>-IT-…` | | Integration | |
| `<PREFIX>-E2E-…` | | Playwright | |

## 10. Task Checklist

- [ ] `<PREFIX>-INT-001`

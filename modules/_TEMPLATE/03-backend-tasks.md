# <Module Name> — Backend Tasks & Database Design

**Module:** `NN-<module-name>`
**Stack (api):** Go · chi REST handlers + gorilla/websocket gateway · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration) · contracts generated from `applications/api/openapi/openapi.yaml` · slog logging
**Stack (web):** Next.js Route Handlers / Server Actions · zod forms · generated `openapi-fetch` client → api
**Last updated:** YYYY-MM-DD

> Schema first. Nothing below it is designed until the schema is settled. Every table states its
> tenant-scope column/rule — unscoped tables are a defect (`prompt.txt` §9).

---

## 1. Database Design

### 1.1 Tables

#### `<table_name>` (model `<Model>`)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| | | | | |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | |

**Constraints:** … **Indexes:** column(s) → query served.

### 1.2 Migrations

| # | Migration | Reversible? |
| --- | --- | --- |
| 1 | `YYYYMMDDHHMMSS_<slug>` | ✅ |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| | `DRAFT` (clearly fictional, e.g. "Demo High School") | brd/prd § / `TODO:` |

---

## 2. Server Contracts

### Endpoint `<METHOD> /api/v1/…` (Go, generated from the OpenAPI spec)

| | |
| --- | --- |
| **Auth** | middleware: authenticate → load role claims → tenant-scope |
| **Input** | contract-generated validator; request struct from `oapi-codegen` |
| **Result** | `{ "data": … }` / RFC-7807 `application/problem+json` error envelope |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `VALIDATION_FAILED` · `TENANT_MISMATCH` · … |
| **Rate limit** | per route class (auth / AI / payments / default) |
| **Audit** | audit-log entry if destructive or financial |
| **Stories** | `<PREFIX>-US-…` |

### Web Server Action / Route Handler (Next.js)

Calls the Go API through the generated `openapi-fetch` client — never the database directly.
Same auth + input (zod) + result rows as above.

---

## 3. Service Layer Tasks

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `<PREFIX>-BE-0xx` | | | | |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| | | | |

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| | | | | |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `<PREFIX>-UT-0xx` | | Unit | |
| `<PREFIX>-IT-0xx` | | Integration (testcontainers Postgres) | |

Always include: unauthenticated call denied for every protected entry point; validation rejects bad
input; a cross-tenant read/write attempt returns `TENANT_MISMATCH`/404 for every tenant-scoped table;
publish guard blocks `TODO:`; public reads never return drafts.

## 7. Task Checklist

> Tick with a date: `[x] <ID> … — YYYY-MM-DD`.

### Schema

- [ ] `<PREFIX>-BE-001`

### Repository · Service · Entry points · Seed · Tests

- [ ] …

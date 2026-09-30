# Design System — Backend Tasks & Database Design

**Module:** `02-design-system`
**Stack (api):** N/A — no server code in this module (the Go/chi/sqlc stack of `docs/tech-stack.md` is untouched here)
**Stack (web):** N/A — no routes or Server Actions; this module's web work is tokens/components (`04-frontend-tasks.md`)
**Last updated:** 2026-09-30

---

## 1. Database Design

**N/A — no database.** Module 02 owns **zero tables**: design tokens, string catalogs and UI primitives are code/config in `packages/shared` and per-app folders. Data-model ownership stays with: `01-foundations` (audit_log, jobs) · `03-identity-access` (users, auth_identities, otp_codes, sessions, refresh_tokens, verification_requests) · `04-organization-hierarchy` (cities, schools, sections, enrollments, fcm_topic_bindings, migration_runs, migration_run_items) · `05-communication-engine` (chat_groups, chat_group_members, chat_messages, message_requests, notices, media_assets) · `06-notifications` (device_tokens, notification_deliveries, notification_preferences). Nothing here migrates, seeds or queries.

### 1.1 Tables

N/A — no database.

### 1.2 Migrations

N/A — no database.

### 1.3 Seed

N/A — no rows. The closest equivalent — catalog seed strings — is code in `packages/shared/i18n/bn.json` / `en.json`, specified in §2 below; illustrative copy stays clearly fictional (`prompt.txt` §12).

---

## 2. Server Contracts

No endpoints exist (`DSN-BE` items: none). The module's real contract is the **catalog JSON schema** consumed by `t()` — written here because it is the cross-module interface every other module codes against.

### Catalog shape (`packages/shared/i18n/bn.json` / `en.json`)

```json
{
  "common.appName":      { "bn": "কুশল কানেক্ট", "en": "Kushol Connect" },
  "common.actions.save": { "bn": "সংরক্ষণ", "en": "Save" },
  "validation.required": { "bn": "এই ঘরটি পূরণ করুন", "en": "This field is required" },
  "chat.send.failed":    { "bn": "মেসেজ পাঠানো যায়নি", "en": "Message failed to send" }
}
```

| Rule | Value |
| --- | --- |
| Shape | flat map: `key → { bn: string, en: string }` — no nesting, no extra locale fields |
| Keys | dot-namespaced under `common · validation · auth · chat · notices · ai · marketplace · admin` |
| Parity | identical key sets in both files; non-empty values; identical `{param}` placeholders |
| Params | `{name}` placeholders, interpolated by `t(key, params)` |
| Helper | `t(key: CatalogKey, params?: Record<string, string \| number>): string` — `CatalogKey` typed from the catalog; fallback requested locale → `bn` → key literal (dev warning); never throws |
| Consumers | every web/app module (`03-identity-access` … `14-lms-erp-sync`) |

### CI key-parity gate (this module's enforced "contract")

| Check | Fails when | Test |
| --- | --- | --- |
| JSON parse + schema | malformed entry or unknown locale field | `DSN-UT-001` |
| Key parity | bn/en key sets differ | `DSN-UT-001` |
| Placeholder parity | `{params}` differ between locales | `DSN-UT-001` |
| Namespace whitelist | key outside the eight namespaces | `DSN-UT-001` |
| Fallback safety | `t()` throws or returns an empty string | `DSN-UT-002` |

### Web Server Action / Route Handler (Next.js)

N/A — no actions or handlers in this module.

---

## 3. Service Layer Tasks

None — no server code in this module.

## 4. Repository Tasks

None — no database.

## 5. Jobs

None — no backend jobs. Catalog/token checks run as CI steps (§6/§7), never as scheduled jobs.

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `DSN-UT-001` | Catalog parity: schema, identical bn/en key sets, non-empty values, identical placeholders, namespace whitelist | Unit (CI) | `DSN-BR-001` — a missing bn or en key fails CI |
| `DSN-UT-002` | `t()` fallback chain (requested locale → bn → key literal) never throws or returns empty | Unit | `DSN-US-004`; `01-user-stories §7` edge 1 |

The generic server-test requirements (unauthenticated denied, cross-tenant `TENANT_MISMATCH`, publish guards) are N/A — no entry points exist; the parity + fallback gates above are this module's mandatory gates.

## 7. Task Checklist

### Schema

- [ ] N/A — no database; **no `DSN-BE` items exist in this module**

### Catalog contract · CI gate · Tests

- [ ] `DSN-INT-001` — catalog schema + validator wired into CI (detail: `06-integration-tasks §2`/`§9`)
- [ ] `DSN-UT-001` — parity gate green in CI
- [ ] `DSN-UT-002` — fallback chain green in CI
- [ ] `DSN-FE-001`…`DSN-FE-018` — owned by `04-frontend-tasks §9` (tokens wiring, web primitives, locale provider)
- [ ] `DSN-AP-001`…`DSN-AP-017` — owned by `05-app-tasks §9` (NativeWind, fonts, RN primitives, icon/splash)

# LMS Pull Integration Plan — Kushol side

**Module:** `14-lms-erp-sync`  
**Status:** Plan drafted 2026-10-03 (not yet in build queue)  
**Owner:** Rahul (product owner)  
**Vendor contract:** [`vendor-lms-api-spec.md`](./vendor-lms-api-spec.md) · [`docs/contracts/lms-vendor-api.yaml`](../../contracts/lms-vendor-api.yaml)  
**Terminology:** [`terminology-institution.md`](./terminology-institution.md) (**binding**)

How Kushol **consumes** an educational institution’s LMS that implements the vendor API. Complements
CSV upload and inbound HMAC webhooks. Pull sync is in-scope for Phase 3.

---

## 1. Placement

| Decision | Choice |
| --- | --- |
| Module folder | **`docs/modules/14-lms-erp-sync/`** — do **not** create `07-lms-integration` (07 is command-center-web) |
| Prefix | `LMS` |
| Spec / build | Spec `📝`; build `⬜ Not started` until Phase 3 |
| Web surface | Extends integrations UI (today `/school/integrations` — **deferred rename** to `/institution/integrations`) with an **LMS connection** panel |
| Apps | `api` + `web` only |

Product noun everywhere in this plan: **educational institution** / UI **Institution** /
**প্রতিষ্ঠান**. Admin actor: **Institution Admin** (legacy claim may still be `SCHOOL_ADMIN` until rename).

---

## 2. Product behaviour (Institution Admin)

### 2.1 Config UI — Integrations → “LMS connection”

Licence-gated (same sync licence as CSV/webhooks). Fields:

| Field | Notes |
| --- | --- |
| Enabled | Toggle |
| Display name | e.g. “Institution ERP”, “Moodle” |
| Base URL | HTTPS + path prefix (`https://…/api/kushol/v1`) |
| Auth type | `bearer` \| `api_key` |
| Credential | Write-only; never returned on GET (mask `••••`) |
| API key header name | Default `X-Api-Key` |
| Mode | `rest_lists` (only mode for simplified vendor API v1) |
| Resource overrides | Optional per-resource path (`teachers`, `students`, `sections`, `notices`) |
| Sync schedule | Off · Hourly · Daily 02:00 Asia/Dhaka · Weekly Sunday 02:00 |
| Sync now | Enqueues immediate job |
| Test connection | Probes `GET /teachers?limit=1` (auth + pagination sanity) |
| Last run | Status, counts, errors |
| `expected_institution_type` | Set in Kushol (tenant); not pulled from LMS in simplified v1 |

Tenant `institution_type` is configured in Kushol (04), not required from the LMS pull surface.

**Gate 1:** Owner approves this UI (mock-driven) before backend build.

### 2.2 Sync outcomes

1. Classes + nested sections created/updated for the institution.
2. Teachers/students upserted as **PENDING** if new — **never auto-verified**.
3. Section membership applied from `teacher_ids` / `student_ids`.
4. Section chat groups: **`class_teacher_id` = group admin**, enrolled **students = members**.
5. Transfers / inactive membership soft-removed from groups; teacher changes update admin.
6. Notices upserted onto institution/section boards when `/notices` is enabled.

---

## 3. Internal sync job flow

```text
Institution Admin: Sync now / cron
        │
        ▼
POST …/lms/connections/{id}/sync   (± institutions-scoped alt — §6)
        │
        ▼
jobs.Enqueue(lms.pull.sync)
        │
        ├─ 1. Load connection (decrypt credential in-memory only)
        ├─ 2. GET /teachers + GET /students
        ├─ 3. GET /sections (classes with nested sections)
        ├─ 4. For each section external_id → GET /sections/{sectionId}
        ├─ 5. Optional GET /notices
        ├─ 6. Validate (phones, class_level, external_ids, id references)
        ├─ 7. Map → upsert:
        │      classes+sections → sections (04)
        │      teachers/students (03)
        │      teacher_ids / student_ids → enrollments + group membership (04/05)
        │      notices → notice boards (05) when enabled
        ├─ 8. VERIFIED users: 04→05→06 group/topic chain
        ├─ 9. Persist sync run + audit
        └─ 10. Update last_success_at / last_error_key
```

**Concurrency:** One `running` pull sync per institution. Second Sync-now → `409 CONFLICT`.  
**Idempotency:** Upsert by `(institution_id, external_id)` per entity type (DB column may still be
`school_id` until rename).

---

## 4. Mapping to Kushol concepts

| LMS vendor field | Kushol target | Module | Gap / note |
| --- | --- | --- | --- |
| `institution_type` (Kushol tenant) | Tenant institution | 04 | Not on LMS pull API in simplified v1 — set in Kushol |
| Class (`GET /sections` outer) + nested section | Section row (class on section) | 04 | External id via `lms_external_ids` map |
| Teacher / Student | Users TEACHER / STUDENT PENDING | 03 | Phone match + external_id map |
| `class_teacher_id` | Section teacher / group admin | 04/05 | Fallback: lex-smallest `teacher_ids` |
| `teacher_ids` / `student_ids` | Enrollments + membership | 04/05 | IDs missing from people lists → warn + skip |
| Notice (`scope` institution/section) | Notice board | 05 | Text only v1; attachments out of scope |

### 4.1 Known gaps

| Gap | Impact | Next action |
| --- | --- | --- |
| Hierarchy APIs may still be fixtures | Cannot prove live groups until 04+05 Gate 3 | Pending owner run |
| No `external_id` columns yet | Need `lms_external_ids` in 14 | Prefer map table in 14 |
| Product still uses `schools` / `schoolId` / `/school/*` | Copy vs wire mismatch | Deferred rename (§7) |
| FCM topic `school-{id}` | Institution wording + future `institution-{id}` | **Follow-up gap for module 06** — devices must resubscribe; do not silently rename in pull sync |

---

## 5. Conflict rules

| LMS event | Kushol rule |
| --- | --- |
| New person | Upsert; PENDING if new |
| Name change | Update display name only |
| Phone conflict on same `external_id` | Error row; no silent merge |
| Transfer / withdraw | End old enrollment; remove from section group |
| Class teacher change | Demote old; promote new; update 05 ownership |
| Section inactive | Archive when safe; else warn |
| Missing from full pull | MVP: do **not** auto-deactivate unless policy `missing=deactivate` |
| Institution-only local section | Untouched (no external_id) |
| CSV vs pull | Last writer wins; reconciliation flags drift |

---

## 6. Kushol admin API sketch (internal — later build)

Prefer claim-scoped routes. Legacy path prefix `/school/` remains until terminology migration;
**product docs** say Institution.

### 6.1 Preferred (Institution Admin)

| Method | Path (current / target) | Purpose |
| --- | --- | --- |
| `POST` | `/api/v1/school/lms/connections` → later `/api/v1/institution/lms/connections` | Create |
| `GET` | same family | List (secrets redacted) |
| `PATCH` / `DELETE` | `…/connections/{id}` | Update / revoke |
| `POST` | `…/connections/{id}/test` | Probe `GET /teachers?limit=1` (auth sanity) |
| `POST` | `…/connections/{id}/sync` | Sync now → `202` + `sync_run_id` |
| `GET` | `…/lms/sync-runs` · `…/sync-runs/{runId}` | History / detail |

### 6.2 Alternate

`/api/v1/institutions/{institutionId}/lms-connections` (+ `/sync`, sync-runs). Enforce
`institutionId == claim` (today `schoolId`).

### 6.3 Example create body

```json
{
  "name": "Institution Moodle",
  "base_url": "https://lms.demo-institution.edu.bd/api/kushol/v1",
  "auth_type": "bearer",
  "credential": "replace-me",
  "api_key_header": "X-Api-Key",
  "mode": "rest_lists",
  "schedule_cron": "0 2 * * *",
  "timezone": "Asia/Dhaka",
  "sync_notices": true,
  "session_year_override": null,
  "resource_overrides": {
    "teachers": { "path": "/teachers" },
    "students": { "path": "/students" },
    "sections": { "path": "/sections" },
    "notices": { "path": "/notices" }
  }
}
```

`institution_type` stays on the Kushol tenant (04). Optional `sync_notices` toggles `/notices` pull.

### 6.4 Tables / jobs (at build)

| Table | Purpose |
| --- | --- |
| `lms_connections` | Per-institution pull config; encrypted credential; cached `institution_type` |
| `lms_sync_runs` / `lms_sync_run_items` | Run history |
| `lms_external_ids` | `(institution_id, entity_type, external_id) → kushol_id` |

Jobs: `lms.pull.sync`, `lms.pull.test`, schedule tick.

---

## 7. Deferred renames (owner follow-up — not part of vendor brief)

| Current | Target | Owner module |
| --- | --- | --- |
| DB `schools` | `institutions` (or API alias) | 04 |
| Claim `schoolId` / role `SCHOOL_ADMIN` | `institutionId` / `INSTITUTION_ADMIN` | 03 |
| Routes `/school/*`, `/admin/schools` | `/institution/*`, `/admin/institutions` | 07 / 04 |
| FCM topic `school-{id}` | `institution-{id}` | **06** — **explicit follow-up gap**; rename requires device resubscribe / backfill job |
| Cache `school:{id}:*` | `institution:{id}:*` | 01 / 14 |
| Web `/school/integrations` | `/institution/integrations` | 07 |

Vendor-facing docs already use Institution + `institution_type`. Internal renames must not block
sending the vendor brief.

---

## 8. Security

| Concern | Rule |
| --- | --- |
| Credentials at rest | AES-256-GCM; never in clients or GET bodies |
| SSRF | HTTPS only; block private/link-local unless allowlisted |
| Audit | Connection CRUD, test, sync start/finish |
| Licence | Same sync licence gate |
| Tenancy | Connection rows scoped to institution tenant |

---

## 9. CSV · webhook · pull

| Path | Direction | When |
| --- | --- | --- |
| CSV/Excel | Admin → Kushol | No LMS API |
| Inbound HMAC webhook | LMS → Kushol | Event-driven ERP |
| **Pull (this plan)** | Kushol → LMS | **Recommended v1 for partners** |

---

## 10. Owner approvals vs deferred implementation

**Approve now**

1. Vendor API + terminology (`institution_type` + Bangla labels).
2. Pull as default for new LMS partners.
3. Module placement = 14 (not a new 07 folder).

**Gate 1 later:** Institution LMS config UI mocks.  
**Deferred to implementation module run:** Go/React, OpenAPI in `applications/api`, migrations,
Gate 2/3, FCM topic rename, full `/school` → `/institution` path migration.

Story outline to fold into `01` at build: `LMS-US-013`–`019` (configure, test, sync now, groups,
cron, conflicts, sync-run history) — actor = Institution Admin.

---

## 11. Change log

| Date | Change |
| --- | --- |
| 2026-10-03 | Initial pull plan |
| 2026-10-03 | Institution terminology + `institution_type`; FCM `school-*` rename listed as 06 follow-up |

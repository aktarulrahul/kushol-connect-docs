# Kushol Connect — Partner LMS / Institution ERP API Specification

| | |
| --- | --- |
| **Audience** | LMS / educational-institution ERP engineering teams (Moodle-like, custom SIS) |
| **Purpose** | Define the read API that Kushol Connect pulls to sync teachers, students, classes/sections, section membership, and notices for an **educational institution** |
| **Version** | `2026-10-03` · API version header `Kushol-LMS-API: 1` |
| **Status** | Draft for partner review — sendable as an integration brief |
| **Companion OpenAPI** | [`docs/contracts/lms-partner-api.yaml`](../../contracts/lms-partner-api.yaml) |
| **Response examples** | [`partner-lms-api-response-examples.md`](./partner-lms-api-response-examples.md) — shareable GET + full JSON samples for LMS partners |
| **Terminology** | [`terminology-institution.md`](./terminology-institution.md) (**binding**) |
| **Kushol module** | `14-lms-erp-sync` |

---

## 0. Terminology (binding — read first)

Kushol’s org entity is an **educational institution** (UI: **Institution** / **প্রতিষ্ঠান**). Do **not** treat “school” or “college” as the generic product noun.

Every institution has **`institution_type`** (configured in Kushol for the tenant; not required on this pull API):

| `institution_type` | English | Bangla (primary) | Bangla alternate |
| --- | --- | --- | --- |
| `primary_school` | Primary School | প্রাইমারি স্কুল | প্রাথমিক বিদ্যালয় |
| `high_school` | High School | হাই স্কুল | মাধ্যমিক বিদ্যালয় |
| `college` | College | কলেজ | — |

Optional Bangla labels on resources use `*_bn` / `display_name_bn` fields. Full note: `terminology-institution.md`.

---

## 1. Why this exists

Kushol Connect (কুশল) is a Bangladesh community platform for educational institutions. When an
**Institution Admin** connects their LMS/ERP, Kushol **pulls** roster + notice data on a schedule
(or on “Sync now”) and:

1. Upserts teachers and students into the institution tenant.
2. Maps classes and nested sections to Kushol’s hierarchy.
3. Creates or updates **section chat groups** using section teacher/student IDs.
4. Imports institution/section notices onto Kushol notice boards (when `/notices` is implemented).

This document is the contract **your system exposes**. Kushol is the HTTPS client. You do **not**
need to call Kushol for v1 sync (pull-only).

**Bangladesh context:** English field names on the wire; optional Bangla in `*_bn` fields. Phone
numbers SHOULD use BD mobile form `01[3-9]XXXXXXXX` when available.

---

## 2. Design principles (normative language)

| Keyword | Meaning |
| --- | --- |
| **MUST** | Required for MVP compliance |
| **SHOULD** | Strongly recommended; required for Full compliance |
| **MAY** | Optional |

1. **Pull-only for v1** — Kushol GETs your endpoints. You MUST NOT require Kushol to open inbound
   ports for roster sync.
2. **Stable external IDs** — Every entity MUST carry an opaque, immutable `external_id` (string,
   ≤ 128 chars). Kushol stores it for idempotent upserts. Never reuse an `external_id` for a
   different person, section, or notice.
3. **REST + JSON** — `application/json; charset=utf-8`. Prefer `GET` collection resources.
4. **Pagination** — List endpoints MUST support cursor or page pagination (see §6).
5. **Soft delete** — Prefer `active: false` over hard DELETE of roster/notice rows.
6. **Idempotency** — Identical responses for the same snapshot MUST be safe to re-ingest.

---

## 3. Base URL and versioning

| Item | Requirement |
| --- | --- |
| Base URL | Institution-configured HTTPS origin, e.g. `https://lms.example-institution.edu.bd/api/kushol/v1` |
| Path prefix | SHOULD be `/api/kushol/v1` (or equivalent versioned prefix you document) |
| Version | API major version in path (`v1`) **and** response header `Kushol-LMS-API: 1` |
| Breaking changes | New major path (`v2`) or negotiated version; additive fields are non-breaking |
| TLS | HTTPS MUST; TLS 1.2+ |

Institution Admin pastes this base URL into Kushol. Kushol appends the resource paths below.

---

## 4. Authentication

Kushol supports two auth modes (configured per institution). Your LMS MUST implement **at least one**.

### 4.1 Bearer token (preferred)

```http
Authorization: Bearer <token>
```

Token is a long-lived integration credential. Scope SHOULD be read-only roster + notices.

### 4.2 API key header

```http
X-Api-Key: <key>
```

Alternate header name MAY be agreed per partner (e.g. `X-LMS-Key`); Kushol stores the header name
in the connection config. Default assumption: `X-Api-Key`.

### 4.3 Auth failures

| HTTP | When |
| --- | --- |
| `401` | Missing / invalid credentials |
| `403` | Valid credentials but insufficient scope |

Body SHOULD use the error format in §8.

**MUST NOT** require interactive OAuth browser flows for v1 institution integrations. OAuth2
client-credentials MAY be added later as Full compliance.

---

## 5. Resources and endpoints (MVP surface)

All timestamps MUST be ISO-8601 UTC (`2026-10-02T18:30:00Z`). Booleans JSON `true`/`false`.

**Response examples →** full curl + 200 JSON samples: [`partner-lms-api-response-examples.md`](./partner-lms-api-response-examples.md).

| # | Method | Path | Purpose |
| --- | --- | --- | --- |
| 0 | `GET` | `/institutions` | **Multi-institution LMS only** — institutions this LMS serves (§5.0) |
| 1 | `GET` | `/teachers` | Teachers list with teacher details |
| 2 | `GET` | `/students` | Students list with student details |
| 3 | `GET` | `/sections` | Classes list **with nested sections** |
| 4 | `GET` | `/sections/{sectionId}` | Section membership — teacher IDs + student IDs |
| 5 | `GET` | `/notices` | Notices (institution-wide and/or section-scoped) |

`{sectionId}` is the section’s stable `external_id` (URL-encoded).

**Request styles (2026-10-23).** Kushol calls either `{base}/teachers` (path style) or
`{base}?path=teachers` (query style, for a single entry point such as `index.php`; the parameter
name is configurable). `sections/{sectionId}` becomes `?path=sections/{sectionId}` in query style.
Kushol sends `Kushol-LMS-API: <version>` and the API key header on every request.

---

### 5.0 Institutions (MUST for a multi-institution LMS — added 2026-10-23)

One LMS deployment may serve many institutions (e.g. e-jonaki). Kushol syncs the list, and a
Kushol admin chooses which institutions join Kushol — each becomes a Kushol institution (or links
to an existing one) and is then synced on its own.

```http
GET /institutions?cursor=&limit=100
```

```json
{
  "data": [
    {
      "external_id": "101",
      "name": "Mirpur Model High School",
      "name_bn": "মিরপুর মডেল উচ্চ বিদ্যালয়",
      "institution_type": "high_school",
      "eiin": "108255",
      "district": "Dhaka",
      "active": true,
      "updated_at": "2026-10-01T00:00:00Z"
    }
  ],
  "next_cursor": null
}
```

| Rule | Requirement |
| --- | --- |
| Scope parameter | Every other endpoint (§5.1–§5.5) MUST accept `institution_id={external_id}` and return only that institution's rows. |
| Rows name their institution | Every teacher, student, class and section-membership row MUST carry `institution_id`. Kushol never applies a row whose `institution_id` differs from the one it asked for. |
| Ids | `external_id` / `institution_id` MAY be numbers; Kushol treats them as strings. |
| Single-institution LMS | MAY answer `404` here; Kushol then treats the whole LMS as one institution and sends no scope parameter. |
| No `/institutions` but rows carry `institution_id` | Kushol groups rows by `institution_id` (and `institution_name` when present) to build the list — slower; implement `/institutions` when possible. |

---

### 5.1 Teachers (MUST — MVP)

```http
GET /teachers?cursor=&limit=100&updated_since=
```

```json
{
  "data": [
    {
      "external_id": "tch-1001",
      "full_name": "Rahim Uddin",
      "full_name_bn": "রহিম উদ্দিন",
      "phone": "01712345678",
      "email": "rahim@example-institution.edu.bd",
      "employee_code": "T-1001",
      "roles": ["teacher"],
      "active": true,
      "updated_at": "2026-03-01T10:00:00Z"
    }
  ],
  "next_cursor": "eyJvZmZzZXQiOjEwMH0"
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `external_id` | string | MUST |
| `full_name` | string | MUST |
| `full_name_bn` | string | SHOULD |
| `phone` | string | SHOULD (MVP); MUST (Full). BD mobile preferred |
| `email` | string \| null | SHOULD |
| `employee_code` | string | SHOULD |
| `roles` | string[] | MUST include at least `"teacher"`; MAY include `"class_teacher"`, `"admin"` |
| `active` | boolean | MUST — `false` means soft-deactivated |
| `updated_at` | string | SHOULD |

---

### 5.2 Students (MUST — MVP)

```http
GET /students?cursor=&limit=100&updated_since=
```

```json
{
  "data": [
    {
      "external_id": "stu-9001",
      "full_name": "Nusrat Jahan",
      "full_name_bn": "নুসরাত জাহান",
      "phone": "01898765432",
      "email": null,
      "student_code": "2025-10A-042",
      "guardian_phone": "01911112222",
      "active": true,
      "updated_at": "2026-03-02T08:00:00Z"
    }
  ],
  "next_cursor": null
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `external_id` | string | MUST |
| `full_name` | string | MUST |
| `full_name_bn` | string | SHOULD |
| `phone` | string | SHOULD (MVP); MUST (Full) — primary identity key in Kushol when present |
| `email` | string \| null | MAY |
| `student_code` | string | SHOULD — roll / admission number |
| `guardian_phone` | string \| null | MAY |
| `active` | boolean | MUST |
| `updated_at` | string | SHOULD |

---

### 5.3 Classes with sections (MUST — MVP)

“Class” = grade level (Class 6, Class 10, HSC 1st year). Each class nests its **sections**.

```http
GET /sections?cursor=&limit=100&updated_since=
```

```json
{
  "data": [
    {
      "external_id": "cls-10",
      "class_level": 10,
      "name": "Class 10",
      "name_bn": "দশম শ্রেণি",
      "stream": null,
      "active": true,
      "updated_at": "2026-01-15T00:00:00Z",
      "sections": [
        {
          "external_id": "sec-10-a",
          "name": "A",
          "name_bn": "ক",
          "display_name": "Class 10 — A",
          "display_name_bn": "দশম শ্রেণি — ক",
          "active": true,
          "updated_at": "2026-02-01T00:00:00Z"
        },
        {
          "external_id": "sec-10-b",
          "name": "B",
          "name_bn": "খ",
          "display_name": "Class 10 — B",
          "display_name_bn": "দশম শ্রেণি — খ",
          "active": true,
          "updated_at": "2026-02-01T00:00:00Z"
        }
      ]
    },
    {
      "external_id": "cls-11-sci",
      "class_level": 11,
      "name": "Class 11 Science",
      "name_bn": "একাদশ বিজ্ঞান",
      "stream": "science",
      "active": true,
      "updated_at": "2026-01-15T00:00:00Z",
      "sections": [
        {
          "external_id": "sec-11sci-a",
          "name": "A",
          "name_bn": "ক",
          "display_name": "Class 11 Science — A",
          "display_name_bn": "একাদশ বিজ্ঞান — ক",
          "active": true,
          "updated_at": "2026-02-01T00:00:00Z"
        }
      ]
    }
  ],
  "next_cursor": null
}
```

| Field (class) | Rule |
| --- | --- |
| `external_id` | MUST — stable class/grade id |
| `class_level` | MUST — integer 1–12 for `primary_school` / `high_school`; `college` MAY use 11–12 or levels documented in `name` |
| `name` / `name_bn` | MUST / SHOULD |
| `stream` | SHOULD when applicable: `science` \| `business_studies` \| `humanities` \| `null` |
| `sections` | MUST — array (MAY be empty); each section MUST have its own `external_id` |
| `active` | MUST |

| Field (section) | Rule |
| --- | --- |
| `external_id` | MUST — used as `{sectionId}` in §5.4 |
| `name` | MUST — short label (`A`, `B`, `Morning`) |
| `display_name` / `display_name_bn` | SHOULD |
| `active` | MUST |

Kushol maps one LMS section → one Kushol section row (+ one official section chat group).

Pagination `cursor`/`limit` applies to the **outer class list**. Include all sections for each
returned class on that page.

---

### 5.4 Section teachers and students (MUST — MVP)

Returns membership for one section: **teacher IDs** and **student IDs** only (people details come
from `/teachers` and `/students`).

```http
GET /sections/{sectionId}
```

Example: `GET /sections/sec-10-a`

```json
{
  "external_id": "sec-10-a",
  "teacher_ids": ["tch-1001", "tch-1002"],
  "student_ids": ["stu-9001", "stu-9002", "stu-9003"],
  "class_teacher_id": "tch-1001",
  "active": true,
  "updated_at": "2026-02-15T00:00:00Z"
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `external_id` | string | MUST — same as `{sectionId}` |
| `teacher_ids` | string[] | MUST — `external_id` values from `/teachers` (MAY be empty) |
| `student_ids` | string[] | MUST — `external_id` values from `/students` (MAY be empty) |
| `class_teacher_id` | string \| null | SHOULD — primary class teacher; becomes section chat **group admin**. MUST be one of `teacher_ids` when set |
| `active` | boolean | MUST |
| `updated_at` | string | SHOULD |

| HTTP | When |
| --- | --- |
| `200` | Section found |
| `404` | Unknown `{sectionId}` |

If `class_teacher_id` is omitted and `teacher_ids` is non-empty, Kushol picks the
lexicographically smallest id as primary admin and SHOULD log a warning (partner SHOULD set
`class_teacher_id`).

IDs listed here but missing from `/teachers` or `/students` are skipped with a sync warning.

---

### 5.5 Notices (MUST — MVP when notice sync is enabled; SHOULD otherwise)

```http
GET /notices?cursor=&limit=100&updated_since=&scope=&section_external_id=
```

```json
{
  "data": [
    {
      "external_id": "ntc-1001",
      "scope": "institution",
      "section_external_id": null,
      "title": "Annual sports day",
      "title_bn": "বার্ষিক ক্রীড়া দিবস",
      "body": "Sports day will be held on 15 October. All students must attend.",
      "body_bn": "১৫ অক্টোবর ক্রীড়া দিবস অনুষ্ঠিত হবে। সকল শিক্ষার্থীর উপস্থিতি বাধ্যতামূলক।",
      "pinned": true,
      "published_at": "2026-09-20T09:00:00Z",
      "active": true,
      "updated_at": "2026-09-20T09:00:00Z"
    },
    {
      "external_id": "ntc-1002",
      "scope": "section",
      "section_external_id": "sec-10-a",
      "title": "Class test — Mathematics",
      "title_bn": null,
      "body": "Class test on Monday covering chapters 1–3.",
      "body_bn": null,
      "pinned": false,
      "published_at": "2026-09-25T08:00:00Z",
      "active": true,
      "updated_at": "2026-09-25T08:00:00Z"
    }
  ],
  "next_cursor": null
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `external_id` | string | MUST |
| `scope` | `institution` \| `section` | MUST |
| `section_external_id` | string \| null | MUST when `scope=section`; MUST be `null` when `scope=institution` |
| `title` | string | MUST (≤ 120 chars) |
| `title_bn` | string \| null | SHOULD |
| `body` | string | MUST (≤ 5000 chars) |
| `body_bn` | string \| null | SHOULD |
| `pinned` | boolean | SHOULD — default `false` |
| `published_at` | string | MUST |
| `active` | boolean | MUST — `false` soft-removes from Kushol board |
| `updated_at` | string | SHOULD |

| Query | Rule |
| --- | --- |
| `scope` | MAY filter `institution` or `section` |
| `section_external_id` | MAY filter section-scoped notices |
| `updated_since` | SHOULD — incremental sync |

Kushol maps `scope=institution` → institution notice board; `scope=section` → that section’s
notice board. Attachment sync is **out of scope** for v1 (text title/body only).

---

## 6. Pagination, filtering, concurrency

### 6.1 Cursor pagination (preferred)

| Query | Rule |
| --- | --- |
| `limit` | MUST accept 1–200; default 100 |
| `cursor` | Opaque string from previous `next_cursor`; omit on first page |
| `next_cursor` | `null` or absent when done |

### 6.2 Page pagination (allowed)

| Query | Rule |
| --- | --- |
| `page` | 1-based |
| `page_size` | 1–200 |
| Response | `{ "data": [...], "page": 1, "page_size": 100, "total": 412 }` — `total` SHOULD |

### 6.3 Incremental sync (SHOULD — Full)

| Query | Rule |
| --- | --- |
| `updated_since` | ISO-8601; return entities with `updated_at >= updated_since` including soft-deactivated |

### 6.4 Concurrency

Kushol MAY run one sync job per institution at a time. Partners SHOULD tolerate parallel GETs across
different resources (e.g. `/teachers` + `/students` + N × `/sections/{id}`).

---

## 7. Optional webhooks (NOT required for v1)

| Mode | Recommendation |
| --- | --- |
| **Pull (this spec)** | **Recommended for v1** |
| Push webhooks to Kushol | Optional later; Kushol inbound HMAC webhooks exist for event-driven ERPs |

---

## 8. Errors

```json
{
  "error": {
    "code": "unauthorized",
    "message": "Invalid API key",
    "request_id": "req_abc123"
  }
}
```

| HTTP | `code` (suggested) | When |
| --- | --- | --- |
| 400 | `validation_failed` | Bad query |
| 401 | `unauthorized` | Auth failed |
| 403 | `forbidden` | Scope denied |
| 404 | `not_found` | Unknown path / `{sectionId}` |
| 429 | `rate_limited` | Too many requests — include `Retry-After` |
| 500 / 503 | `internal` / `unavailable` | Server fault — Kushol retries with backoff |

---

## 9. Rate limits

| Guidance | Value |
| --- | --- |
| Sustained | SHOULD allow ≥ 60 requests/minute per integration token |
| Burst | SHOULD allow short bursts of 10 req/s |
| Response | On limit: `429` + `Retry-After` (seconds) |

---

## 10. Compliance levels

### MVP

| # | Requirement |
| --- | --- |
| 1 | HTTPS base URL + Bearer **or** API key auth |
| 2 | `GET /teachers` with stable `external_id` + details |
| 3 | `GET /students` with stable `external_id` + details |
| 4 | `GET /sections` returning classes **with nested** `sections[]` |
| 5 | `GET /sections/{sectionId}` returning `teacher_ids` + `student_ids` |
| 6 | Pagination on every list |
| 7 | Soft-deactivate via `active: false` |
| 8 | At least one teacher id (or `class_teacher_id`) per active section preferred |
| 9 | Phones present for ≥ 80% of teachers/students **or** accepted risk of pending unmatched users |

### Full

Everything in MVP, plus: `GET /notices`, `updated_since`, `*_bn` fields, phone MUST on all active
people, documented rate limits + `request_id`, `class_teacher_id` on every active section.

---

## 11. Mapping cheat-sheet (for LMS developers)

| Your concept | Kushol concept |
| --- | --- |
| Educational institution | Tenant institution (`institution_type` set in Kushol) |
| Grade / class / batch | Outer object on `GET /sections` |
| Section / group / room | Nested `sections[]` + `GET /sections/{id}` |
| Class teacher | `class_teacher_id` → section chat group admin |
| Teacher / student records | Users (students created **PENDING** until Kushol verification) |
| Section membership | `teacher_ids` / `student_ids` on section detail |
| LMS notice / circular | Kushol notice board (`scope` institution or section) |

**Note:** Kushol does **not** auto-verify students from LMS sync.

---

## 12. Example minimal Moodle-style adapter

Thin adapter / plugin:

1. Map course or class+section tables → nested payload on `GET /sections`.
2. Map users + roles → `GET /teachers` + `GET /students`.
3. Map cohort/group membership → `GET /sections/{sectionId}` (`teacher_ids`, `student_ids`).
4. Map news/announcements → `GET /notices` (optional Full).
5. Issue one API key per Kushol connection.

---

## 13. Security expectations for partners

- Issue per-institution credentials; revoke on request.
- Prefer read-only DB roles behind the API.
- Do not put PII in URLs (IDs only in `{sectionId}`).
- Log access with `request_id`; retain ≥ 30 days.
- Rotate keys at least annually (Institution Admin can update the stored secret in Kushol).

---

## 14. Contact / change control

| Item | Value |
| --- | --- |
| Spec owner | Kushol Connect — Rahul (product) |
| Machine contract | `docs/contracts/lms-partner-api.yaml` |
| GET response examples (shareable) | `partner-lms-api-response-examples.md` |
| Kushol consumption plan | `lms-pull-integration-plan.md` |
| Terminology | `terminology-institution.md` |

---

## 15. Change log

| Date | Change |
| --- | --- |
| 2026-10-03 | Initial partner-facing pull API spec (v1) |
| 2026-10-03 | Binding terminology: Institution + required `institution_type` enum |
| 2026-10-03 | Link to shareable GET response examples (`partner-lms-api-response-examples.md`) |
| 2026-10-03 | **Simplified MVP surface:** `GET /teachers`, `/students`, `/sections` (classes nested), `/sections/{sectionId}` (teacher/student ids), `/notices`. Dropped separate `/classes`, `/section-teachers`, `/enrollments`, `/export`, `/institution`, `/terms`, `/capabilities` |
| 2026-10-23 | **Multi-institution LMS:** `GET /institutions`, the `institution_id` scope parameter on every roster endpoint, `institution_id` on every roster row; query-style routing (`?path=teachers`); numeric ids accepted. First partner: e-jonaki |

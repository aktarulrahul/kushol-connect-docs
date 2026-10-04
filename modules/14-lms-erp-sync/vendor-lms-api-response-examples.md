# Kushol Connect — LMS / Institution ERP GET API Response Examples

| | |
| --- | --- |
| **Audience** | LMS / educational-institution ERP engineering teams |
| **Purpose** | Copy-pasteable **GET** request + full JSON **200** response examples for Kushol Connect roster + notice sync v1 |
| **API version** | Path `v1` · response header `Kushol-LMS-API: 1` |
| **Normative contract** | [`vendor-lms-api-spec.md`](./vendor-lms-api-spec.md) · OpenAPI [`lms-vendor-api.yaml`](../../contracts/lms-vendor-api.yaml) |
| **Terminology** | [`terminology-institution.md`](./terminology-institution.md) (**binding**) |
| **Date** | 2026-10-03 |

> **Share this file alone.** It is standalone: base URL, auth, pagination, and complete sample payloads. Field rules and MVP compliance live in the normative spec above.

---

## 1. Quick start

### GET only (v1)

Kushol Connect **pulls** roster + notice data with **HTTPS GET**. For Kushol sync **v1**, the LMS team implements **read endpoints only**.

### MVP endpoint list

| # | Method | Path | Returns |
| --- | --- | --- | --- |
| 1 | `GET` | `/teachers` | Teachers with details |
| 2 | `GET` | `/students` | Students with details |
| 3 | `GET` | `/sections` | Classes with nested sections |
| 4 | `GET` | `/sections/{sectionId}` | `teacher_ids` + `student_ids` |
| 5 | `GET` | `/notices` | Notices |

### Base URL

Institution Admin pastes an HTTPS origin into Kushol. Kushol appends the resource paths.

```text
https://lms.udaharon-uccha.edu.bd/api/kushol/v1
```

Path prefix SHOULD be `/api/kushol/v1` (or an equivalent versioned prefix you document).

### Required headers

| Header | Value |
| --- | --- |
| `Accept` | `application/json` |
| `Authorization` **or** `X-Api-Key` | See auth below |
| Response (your LMS) | `Content-Type: application/json; charset=utf-8` |
| Response (your LMS) | `Kushol-LMS-API: 1` |

### Authentication (implement at least one)

**Bearer (preferred):**

```http
Authorization: Bearer FAKESECRET_c3d4e5f6g7h8i9j0k1l2
```

**API key:**

```http
X-Api-Key: kc_live_8f3a2b1c9d0e4f5a6b7c8d9e0f1a2b3c
```

### Pagination (every list)

**Cursor (preferred):**

| Query | Rule |
| --- | --- |
| `limit` | 1–200; default `100` |
| `cursor` | Opaque string from previous `next_cursor`; omit on first page |

List responses:

```json
{ "data": [ /* … */ ], "next_cursor": null }
```

### Sample institution used below

| Field | Sample |
| --- | --- |
| Name | উদাহরণ উচ্চ বিদ্যালয় / Udaharon Uccha Bidyalaya |
| City | Dhaka |
| EIIN | `134567` |

`institution_type` is configured on the Kushol tenant (not pulled via these endpoints).

Every entity MUST include a stable `external_id` (string, ≤ 128 chars).

---

## 2. Common errors

Use this shape for failures:

```json
{
  "error": {
    "code": "unauthorized",
    "message": "Invalid API key",
    "request_id": "req_abc123"
  }
}
```

| HTTP | `code` | When |
| --- | --- | --- |
| 400 | `validation_failed` | Bad query |
| 401 | `unauthorized` | Auth failed |
| 403 | `forbidden` | Scope denied |
| 404 | `not_found` | Unknown `{sectionId}` |
| 429 | `rate_limited` | Too many requests — include `Retry-After` |
| 500 / 503 | `internal` / `unavailable` | Server fault |

---

## 3. GET `/teachers` (MUST — MVP)

Teachers list with teacher details.

```http
GET /api/kushol/v1/teachers?limit=100 HTTP/1.1
Host: lms.udaharon-uccha.edu.bd
Accept: application/json
Authorization: Bearer FAKESECRET_c3d4e5f6g7h8i9j0k1l2
```

```json
{
  "data": [
    {
      "external_id": "tch-1001",
      "full_name": "Rahim Uddin",
      "full_name_bn": "রহিম উদ্দিন",
      "phone": "01712345678",
      "email": "rahim@udaharon-uccha.edu.bd",
      "employee_code": "T-1001",
      "roles": ["teacher", "class_teacher"],
      "active": true,
      "updated_at": "2026-03-01T10:00:00Z"
    },
    {
      "external_id": "tch-1002",
      "full_name": "Salma Akter",
      "full_name_bn": "সালমা আক্তার",
      "phone": "01611223344",
      "email": "salma@udaharon-uccha.edu.bd",
      "employee_code": "T-1002",
      "roles": ["teacher"],
      "active": true,
      "updated_at": "2026-03-01T10:00:00Z"
    }
  ],
  "next_cursor": null
}
```

---

## 4. GET `/students` (MUST — MVP)

Students list with student details.

```http
GET /api/kushol/v1/students?limit=100 HTTP/1.1
Host: lms.udaharon-uccha.edu.bd
Accept: application/json
Authorization: Bearer FAKESECRET_c3d4e5f6g7h8i9j0k1l2
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
    },
    {
      "external_id": "stu-9002",
      "full_name": "Karim Hossain",
      "full_name_bn": "করিম হোসেন",
      "phone": "01555667788",
      "email": null,
      "student_code": "2025-10A-043",
      "guardian_phone": "01700001111",
      "active": true,
      "updated_at": "2026-03-02T08:00:00Z"
    },
    {
      "external_id": "stu-9003",
      "full_name": "Farzana Islam",
      "full_name_bn": "ফারজানা ইসলাম",
      "phone": "01399887766",
      "email": null,
      "student_code": "2025-10A-044",
      "guardian_phone": null,
      "active": true,
      "updated_at": "2026-03-02T08:00:00Z"
    }
  ],
  "next_cursor": null
}
```

---

## 5. GET `/sections` (MUST — MVP)

Classes list **with nested sections**.

```http
GET /api/kushol/v1/sections?limit=100 HTTP/1.1
Host: lms.udaharon-uccha.edu.bd
Accept: application/json
Authorization: Bearer FAKESECRET_c3d4e5f6g7h8i9j0k1l2
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

---

## 6. GET `/sections/{sectionId}` (MUST — MVP)

Section’s teachers and students — **IDs only** (details from `/teachers` and `/students`).

```http
GET /api/kushol/v1/sections/sec-10-a HTTP/1.1
Host: lms.udaharon-uccha.edu.bd
Accept: application/json
Authorization: Bearer FAKESECRET_c3d4e5f6g7h8i9j0k1l2
```

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

**404** when `{sectionId}` is unknown:

```json
{
  "error": {
    "code": "not_found",
    "message": "Section not found",
    "request_id": "req_sec404"
  }
}
```

---

## 7. GET `/notices` (SHOULD — Full; MUST when notice sync enabled)

```http
GET /api/kushol/v1/notices?limit=100 HTTP/1.1
Host: lms.udaharon-uccha.edu.bd
Accept: application/json
Authorization: Bearer FAKESECRET_c3d4e5f6g7h8i9j0k1l2
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

Optional filters: `?scope=institution`, `?scope=section&section_external_id=sec-10-a`, `?updated_since=2026-09-01T00:00:00Z`.

---

## 8. MVP checklist (GET)

- [ ] HTTPS + Bearer **or** `X-Api-Key`
- [ ] `GET /teachers` — details + stable `external_id`
- [ ] `GET /students` — details + stable `external_id`
- [ ] `GET /sections` — classes with nested `sections[]`
- [ ] `GET /sections/{sectionId}` — `teacher_ids` + `student_ids` (+ optional `class_teacher_id`)
- [ ] Pagination on list endpoints (`next_cursor` or page style)
- [ ] Soft-deactivate via `active: false`
- [ ] (Full / notice sync) `GET /notices`

---

## 9. Related docs

| Doc | Role |
| --- | --- |
| [`vendor-lms-api-spec.md`](./vendor-lms-api-spec.md) | Normative field rules + compliance |
| [`lms-vendor-api.yaml`](../../contracts/lms-vendor-api.yaml) | OpenAPI machine contract |
| [`lms-pull-integration-plan.md`](./lms-pull-integration-plan.md) | How Kushol consumes this API |
| [`terminology-institution.md`](./terminology-institution.md) | Institution / প্রতিষ্ঠান wording |

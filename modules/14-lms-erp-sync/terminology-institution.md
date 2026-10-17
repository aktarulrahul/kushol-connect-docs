# Terminology — Educational Institution (binding 2026-10-03)

**Status:** Binding for new LMS / integration copy and APIs.  
**Applies to:** App, API, web product language; module 14 LMS vendor + pull docs.  
**Owner:** Rahul

---

## 1. Product noun (org entity)

| Do **not** use (as the generic org noun) | Use instead |
| --- | --- |
| school, college (when meaning “the tenant org”) | **educational institution** |
| UI short label | **Institution** |
| Bangla UI short | **প্রতিষ্ঠান** |
| Bangla long (optional) | **শিক্ষা প্রতিষ্ঠান** |

Examples:

- ✅ “Select your educational institution” / “প্রতিষ্ঠান নির্বাচন করুন”
- ✅ “Institution Admin configures LMS”
- ❌ “Select your school” (generic) · ❌ “School settings” as the tenant settings title

**Allowed:** “High School”, “Primary School”, “College” only as **type display labels** (below), or in proper names (e.g. “Demo High School”).

---

## 2. `institution_type` enum (API)

Wire field name: **`institution_type`** (prefer over `type` / `school_type`).

| API value | English display | Bangla display (primary) | Bangla alternate (acceptable) |
| --- | --- | --- | --- |
| `primary_school` | Primary School | প্রাইমারি স্কুল | প্রাথমিক বিদ্যালয় |
| `high_school` | High School | হাই স্কুল | মাধ্যমিক বিদ্যালয় |
| `college` | College | কলেজ | — |

**i18n catalog keys (suggested):**

| Key | en | bn |
| --- | --- | --- |
| `institution.type.primary_school` | Primary School | প্রাইমারি স্কুল |
| `institution.type.high_school` | High School | হাই স্কুল |
| `institution.type.college` | College | কলেজ |
| `institution.noun` | Institution | প্রতিষ্ঠান |
| `institution.noun_long` | Educational institution | শিক্ষা প্রতিষ্ঠান |

Default Bangla for types: use the **primary** column (প্রাইমারি স্কুল / হাই স্কুল / কলেজ). Alternates may appear in help text.

---

## 3. Roles (product language in LMS docs)

| Legacy (existing modules) | Prefer in new LMS / Institution UI copy |
| --- | --- |
| School Admin | **Institution Admin** |
| Super Admin | Super Admin (unchanged) |

Full role-string migration across 03/04/07 (`SCHOOL_ADMIN`, `/institution/*` routes) is a **deferred rename** — see §5.

---

## 4. LMS / mapping language

| Concept | Wording |
| --- | --- |
| Tenant root | Educational institution (`institutions` product noun; DB may still be `schools` until rename) |
| LMS counterparty | “the institution’s LMS / ERP” |
| Admin config | Institution Admin pastes LMS base URL + credential |
| Vendor metadata | `institution_type` set on Kushol tenant; LMS pull uses `/teachers`, `/students`, `/sections`, `/sections/{id}`, `/notices` |

---

## 5. Deferred renames (follow-up gaps — do not block LMS vendor brief)

| Area | Current | Target | Notes |
| --- | --- | --- | --- |
| DB table | `schools` | `institutions` (or keep table, expose API as institution) | Module 04 migration — owner ADR |
| JWT claim | `schoolId` | `institutionId` | Breaking for clients |
| REST paths | `/api/v1/school/…`, `/admin/schools` | `/api/v1/institutions/…` or `/institution/…` | Module 07 + 04 |
| Role claim | `SCHOOL_ADMIN` | `INSTITUTION_ADMIN` | Module 03 |
| FCM topics | `school-{id}` | `institution-{id}` | **Module 06** — rename is a follow-up gap; devices must resubscribe; record in 06 `08-gaps` when scheduled |
| Cache tags | `school:{id}:roster`, `hierarchy:school:{id}` | `institution:{id}:…` | 01/04/14 |
| Web routes | `/institution/roster`, `/institution/integrations` | `/institution/…` | 07 shell |
| CSV / webhook docs in 14 | “school”, `school_id` | Align when 04 renames land | Pull plan uses Institution wording; columns may stay `school_id` until migration |

LMS vendor-facing docs (**this pack**) use Institution + `institution_type` **now**. Kushol internal path/column renames wait for a dedicated terminology migration.

---

## 6. Change log

| Date | Change |
| --- | --- |
| 2026-10-03 | Binding terminology rule recorded; Bangla type strings fixed |

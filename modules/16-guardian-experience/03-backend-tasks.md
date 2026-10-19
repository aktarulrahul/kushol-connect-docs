# Guardian Experience — Backend Tasks & Database Design

**Module:** `16-guardian-experience`
**Stack (api):** Go · chi REST handlers (oapi-codegen `api.ServerInterface`) · services · tenant-scoped repositories · sqlc + pgx · PostgreSQL (testcontainers-go for integration, run by the owner only) · contracts generated from `applications/api/openapi/openapi.yaml` · slog logging
**Stack (web):** no server code of its own. The console calls the Go API through the generated `openapi-fetch` client (07 pattern).
**Last updated:** 2026-10-19

> **Status: planned, not built.** Nothing below exists yet unless it is marked *(exists)*.
>
> The schema comes first, and every table states its tenant scope. Migration versions shown are
> provisional. At build time they are stamped after the highest applied version (README
> migration registry rule). The highest version in the tree on 2026-10-19 is `20270309090000`.

---

## 1. Database Design

### 1.1 Tables

#### `guardian_links` (model `GuardianLink`) — 03 table *(exists)*, extended by 16 (v2)

Tenant scope: `school_id`. Every query filters on it. Guardian, student and link share the school
(`GRD-BR-003`).

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK *(exists)* |
| `school_id` | `uuid` | no | — | FK `schools` *(exists, FK from `20261002090007`)* |
| `guardian_user_id` | `uuid` | no | — | FK `users` ON DELETE CASCADE *(exists)* |
| `student_user_id` | `uuid` | no | — | FK `users` *(exists)* |
| `relation` | `text` | no | — | CHECK widened to `father, mother, grandfather, grandmother, brother, sister, uncle, aunt, legal_guardian, other`. The old values stay valid. |
| `status` | `text` | no | `'ACTIVE'` | CHECK `ACTIVE, REVOKED` *(exists)* |
| `source` | `text` | no | — | CHECK widened to `VERIFICATION, ROSTER, ADMIN, INVITE, LINK_REQUEST, LMS` |
| `verified_by` | `uuid` | yes | — | The admin (or system) that created it *(exists)* |
| `is_primary` | `boolean` | no | `false` | **new** |
| `request_id` | `uuid` | yes | — | **new**. FK `guardian_link_requests` (added in migration 3) |
| `invite_id` | `uuid` | yes | — | **new (G2)**. FK `guardian_invites` (added in migration 5) |
| `revoked_by` | `uuid` | yes | — | **new**. FK `users`. NULL means system. |
| `revoke_reason` | `text` | yes | — | **new**. Admin free text, or a system key (`guardian_self_unlink`, `student_removed`) |
| `revoked_at` | `timestamptz` | yes | — | *(exists)* |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | `kushol_set_updated_at` trigger *(exists)* |

**Constraints:**

- *(exists)* CHECK `guardian_user_id <> student_user_id`
- **new** CHECK `status <> 'REVOKED' OR (revoked_at IS NOT NULL AND revoke_reason IS NOT NULL)`
- **new** CHECK `revoke_reason IS NULL OR char_length(btrim(revoke_reason)) BETWEEN 10 AND 500`

**Indexes:**

- *(exists)* partial unique `(guardian_user_id, student_user_id) WHERE status='ACTIVE'`
- *(exists)* `(guardian_user_id, status)`: children of a guardian
- *(exists)* `(student_user_id, status)`: `GuardiansOf` and the batched fan-out
- *(exists)* `(school_id, status)`
- **new** partial unique `guardian_links_one_primary_key (student_user_id) WHERE status='ACTIVE' AND is_primary`
- **new** `(school_id, created_at DESC, id DESC)`: cursor for the admin links list

#### `guardian_link_requests` (model `GuardianLinkRequest`) — new (G1)

Tenant scope: `school_id` (the school the guardian claims the child is in; equal to the
guardian's own school in single-school mode).

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | FK `schools` |
| `guardian_user_id` | `uuid` | no | — | FK `users` ON DELETE CASCADE |
| `student_code` | `text` | no | — | CHECK trimmed length 3–20 |
| `claimed_student_name` | `text` | yes | — | CHECK length 2–80 |
| `requested_section_id` | `uuid` | yes | — | FK `sections` |
| `relation` | `text` | no | — | Same CHECK as links |
| `matched_student_user_id` | `uuid` | yes | — | FK `users`. Set on approve. |
| `status` | `text` | no | `'PENDING'` | CHECK `PENDING, APPROVED, REJECTED, CANCELLED` |
| `origin` | `text` | no | `'SELF'` | CHECK `SELF, INVITE` |
| `decided_by` | `uuid` | yes | — | FK `users` |
| `decision_reason` | `text` | yes | — | Required when REJECTED (see constraints) |
| `decided_at` | `timestamptz` | yes | — | |
| `reminder_count` | `int` | no | `0` | SLA reminders sent |
| `last_reminder_at` | `timestamptz` | yes | — | |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | trigger |

**Constraints:**

- CHECK `status <> 'APPROVED' OR matched_student_user_id IS NOT NULL`
- CHECK `(status IN ('APPROVED','REJECTED')) = (decided_by IS NOT NULL AND decided_at IS NOT NULL)`
- CHECK `status <> 'REJECTED' OR char_length(btrim(decision_reason)) BETWEEN 10 AND 500`

**Indexes:**

- partial unique `(guardian_user_id, school_id, lower(student_code)) WHERE status='PENDING'`:
  no duplicate claim
- `(school_id, status, created_at)`: the admin queue and the SLA job
- `(guardian_user_id, status)`: "my requests"

#### `guardian_consents` (model `GuardianConsent`) — new (G1), append-only

Tenant scope: `school_id` (the guardian's school at acceptance time).

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | FK `schools` |
| `guardian_user_id` | `uuid` | no | — | FK `users` ON DELETE CASCADE |
| `notice_version` | `text` | no | — | CHECK length 1–32, e.g. `2026-10-v1` |
| `locale` | `text` | no | — | CHECK `bn, en`: the language shown |
| `source` | `text` | no | `'APP'` | CHECK `APP, INVITE_CLAIM` |
| `accepted_at` | `timestamptz` | no | `now()` | |
| `created_at` | `timestamptz` | no | `now()` | No `updated_at`; rows never change. |

**Indexes:** unique `(guardian_user_id, notice_version)`.

#### `guardian_invites` (model `GuardianInvite`) — new (G2)

Tenant scope: `school_id`.

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | uuid v7 | PK |
| `school_id` | `uuid` | no | — | FK `schools` |
| `student_user_id` | `uuid` | no | — | FK `users` |
| `phone_e164` | `text` | no | — | Normalised BD mobile. Never returned unmasked after create. |
| `guardian_name` | `text` | yes | — | CHECK length 2–80 |
| `relation` | `text` | yes | — | Same CHECK as links |
| `source` | `text` | no | — | CHECK `ADMIN, ROSTER, LMS` |
| `status` | `text` | no | `'PENDING'` | CHECK `PENDING, CLAIMED, EXPIRED, REVOKED` |
| `sms_sent_at` | `timestamptz` | yes | — | |
| `sms_send_count` | `int` | no | `0` | Resend cap |
| `expires_at` | `timestamptz` | no | — | The service sets now() + 30 d |
| `claimed_by` / `claimed_at` | `uuid` / `timestamptz` | yes | — | FK `users` |
| `created_by` | `uuid` | yes | — | NULL for roster or LMS |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | trigger |

**Indexes:**

- partial unique `(student_user_id, phone_e164) WHERE status='PENDING'`
- `(phone_e164, status)`: claim lookup after OTP
- `(school_id, status, created_at)`: admin list and the expiry job

#### `users.student_code` — 03 table, amendment shipped by 16 (G1)

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `student_code` | `text` | yes | — | CHECK `student_code IS NULL OR (role='student' AND char_length(btrim(student_code)) BETWEEN 3 AND 20)` |

**Indexes:** partial unique `users_school_student_code_key (school_id, lower(student_code)) WHERE student_code IS NOT NULL`.
It is written by 14 roster/LMS and by the admin (03 users edit).

#### G2 amendments to other modules' tables (one 16 migration, recorded in 04/05 docs)

- `notices.audience text NOT NULL DEFAULT 'all'`, CHECK `all, students, guardians` (05).
- `fcm_topic_bindings.node_type` CHECK adds `SECTION_GUARDIANS` and `SCHOOL_GUARDIANS` (04/06).
  Topic names come from `hierarchy.TopicName`, under 80 characters.
- `chat_groups.post_policy text NOT NULL DEFAULT 'all'`, CHECK `all, moderators` (05).
  Guardian groups reuse `kind='official'` with `system_key='section_guardians:{sectionId}'`;
  no shape change is needed.

### 1.2 Migrations

Every file starts with a header comment: `-- 16-guardian-experience · <purpose> · owner 2026-10-19`.
Up and down are idempotent (`IF EXISTS` / `IF NOT EXISTS`, `DROP CONSTRAINT IF EXISTS` before
`ADD`). The owner runs them (Gate 2).

| # | Migration (provisional version) | Phase | Reversible? |
| --- | --- | --- | --- |
| 1 | `20270320090000_grd_student_codes` | G1 | ✅ (down drops the index and column) |
| 2 | `20270320091000_grd_guardian_links_v2` | G1 | ✅ lossy. Down maps new relations to `other`, `ADMIN`/`INVITE`/`LINK_REQUEST` to `VERIFICATION`, and `LMS` to `ROSTER`, before restoring the narrow CHECKs. Documented in the file header. |
| 3 | `20270320092000_grd_guardian_link_requests` (+ FK `guardian_links.request_id`) | G1 | ✅ |
| 4 | `20270320093000_grd_guardian_consents` | G1 | ✅ |
| 5 | `20270320094000_grd_guardian_invites` (+ FK `guardian_links.invite_id`) | G2 | ✅ |
| 6 | `20270405090000_grd_audiences` (notices audience, topic node types, chat post policy) | G2 | ✅ lossy. Down deletes `*_GUARDIANS` topic bindings first. |

### 1.3 Seed

| Dataset | Status | Source |
| --- | --- | --- |
| Demo student codes for the seeded students (`ডেমো-0001…`) | `DRAFT`, clearly fictional. Only if the owner wants demo data (no seed vehicle decision yet; 12 G-6 precedent). | `20270303090001_seed_demo_tenant_users` pattern |
| Existing demo guardians (করিম, সুমি) | *(exists)*: links with source ROSTER. Unchanged. Primary flag left false. | 03/04 seed |
| One PENDING link request and one PENDING invite for the demo school | `DRAFT`, only if the owner wants it | new seed migration stamped at build |

---

## 2. Server Contracts

The full request and response shapes are in `technical-document.md` §5.1. They are added to
`applications/api/openapi/openapi.yaml` under tag `guardians` first (OpenAPI-first), then
`make contracts` runs in api, and `pnpm sync:api-spec` plus `pnpm generate:api` run in web and
app.

These rules apply to every endpoint below:

| | |
| --- | --- |
| **Auth** | `bearerJWT` or `sessionCookie` → role claims → tenant scope. Console mutations also go through `consoleCSRF`. |
| **Input** | Request structs generated by `oapi-codegen`; service-level rules from `01` §6 |
| **Result** | `{ "data": … }` (plus `nextCursor` for pages), always `writeNoStore`. Errors use RFC-7807 via `problem.Write`. |
| **Errors** | `UNAUTHENTICATED` · `FORBIDDEN` · `NOT_VERIFIED` · `VALIDATION_FAILED` · `TENANT_MISMATCH` (404) · `NOT_FOUND` · `CONFLICT`, plus the new `GUARDIAN_LINK_LIMIT` (409) and `CONSENT_REQUIRED` (403), both to be registered in 01 `technical-document.md` §10 |
| **Rate limit** | Default class. Link-request create, invite create and invite resend have extra caps (`02` §5). |
| **Audit** | Every POST and PATCH (`GRD-BR-013`) |

| # | Method · Path | Roles | Stories | Phase |
| --- | --- | --- | --- | --- |
| 1 | `GET /api/v1/guardian/children` | guardian (VERIFIED) | US-001, US-002, US-005, US-009 | G1 |
| 2 | `GET /api/v1/guardian/children/{studentId}` | guardian + IsGuardianOf + consent | US-002 | G1 |
| 3 | `POST /api/v1/guardian/consent` | guardian | US-005 | G1 |
| 4 | `POST /api/v1/guardian/link-requests` | guardian (VERIFIED) | US-003 | G1 |
| 5 | `GET /api/v1/guardian/link-requests` | guardian | US-004 | G1 |
| 6 | `POST /api/v1/guardian/link-requests/{id}/cancel` | guardian (owner of the request) | US-004 | G1 |
| 7 | `POST /api/v1/guardian/links/{linkId}/unlink` | guardian (owner of the link) | US-016 | G1 |
| 8 | `GET /api/v1/me/guardians` | student (VERIFIED) | US-017 | G1 |
| 9 | `GET /api/v1/school/guardian-links` | school_admin, super_admin (`?schoolId=`) | US-007 | G1 |
| 10 | `POST /api/v1/school/guardian-links` | school_admin, super_admin | US-007, US-008 | G1 (G2 for the invite branch) |
| 11 | `PATCH /api/v1/school/guardian-links/{id}` | school_admin, super_admin | US-007 | G1 |
| 12 | `POST /api/v1/school/guardian-links/{id}/revoke` | school_admin, super_admin | US-007 | G1 |
| 13 | `GET /api/v1/school/guardian-link-requests` | school_admin, super_admin | US-006 | G1 |
| 14 | `POST /api/v1/school/guardian-link-requests/{id}/approve` | school_admin, super_admin | US-006 | G1 |
| 15 | `POST /api/v1/school/guardian-link-requests/{id}/reject` | school_admin, super_admin | US-006 | G1 |
| 16 | `GET /api/v1/school/guardian-invites` | school_admin, super_admin | US-008 | G2 |
| 17 | `POST /api/v1/school/guardian-invites` | school_admin, super_admin | US-008 | G2 |
| 18 | `POST /api/v1/school/guardian-invites/{id}/revoke` | school_admin, super_admin | US-008 | G2 |
| 19 | `POST /api/v1/school/guardian-invites/{id}/resend` | school_admin, super_admin | US-008 | G2 |
| 20 | `POST /api/v1/guardian/invites/{inviteId}/claim` | guardian (phone equals the invite phone) | US-009 | G2 |

Changes to existing contracts are owned by the other modules and tracked as `GRD-INT` tasks:

- `ApproveInput`: unchanged (`studentUserId` is still required for guardians).
- `VerificationRequestItem.guardianCandidates[]` (03).
- `SchoolUser.studentCode` and `sectionLabel` (03).
- `RegisterInput.relation` widened, plus an optional `inviteId` (03).
- `GET /api/v1/payments/invoices` payer list, and the role gate on `GET /school/invoices` (12).
- `notices.audience` (05).
- `forStudentId` on tuition requirements (10).

### Web Server Action / Route Handler (Next.js)

None of its own. The `/institution/guardians` client components call the API through the
generated client once 07's console session glue is live. Until then they use the fixture seam
`src/fixtures/guardians.ts` (`04` §4).

---

## 3. Service Layer Tasks

The package is `applications/api/internal/guardians`, split into `service.go`, `children.go`,
`requests.go`, `links_admin.go`, `invites.go`, `consent.go`, `match.go` (pure), `ports.go`,
`dto.go`, `handler.go`, `jobs.go` and `exports.go`. It must never import `hierarchy`, `chat`,
`notify` or `payments`.

| ID | Method | Rules / guards | Revalidates | Audit |
| --- | --- | --- | --- | --- |
| `GRD-BE-020` | `ports.go`: define `EnrollmentPort`, `GroupPort`, `NoticesPort`, `DuesPort`, `Notifier` and `SMSSender`, with nil-safe no-op defaults | Ports only, no imports of consumers | — | — |
| `GRD-BE-021` | `ListMyChildren(ctx)` | RequireRole(guardian) + VERIFIED. Reads ACTIVE links, then batch-fetches section, class teacher, dues and unread counts through ports, with a 500 ms port timeout and degrade to null. Before consent, returns names only plus `consentRequired`. Also returns pending invites matching the caller's phone (G2). | app `['guardian','children']` | — |
| `GRD-BE-022` | `GetChild(ctx, studentID)` | IsGuardianOf, else FORBIDDEN (same school) or 404 (other school). Needs consent. Returns ≤5 recent notices, open invoices, and co-guardians by name only. | `['guardian','child',id]` | — |
| `GRD-BE-023` | `AcceptConsent(ctx, version, locale)` | version equals `GUARDIAN_NOTICE_VERSION`. Idempotent (unique). | children | `guardian_consent.accepted` |
| `GRD-BE-024` | `CreateLinkRequest(ctx, in)` | VERIFIED guardian; same school; section belongs to the school; caps; no ACTIVE link to a student with that code (CONFLICT); no duplicate PENDING (CONFLICT); rate limit 10/day | link-requests | `guardian_link_request.created` |
| `GRD-BE-025` | `CancelLinkRequest(ctx, id)` | Owner of the request; status is PENDING (`UPDATE … WHERE status='PENDING'`) | link-requests | `guardian_link_request.cancelled` |
| `GRD-BE-026` | `DecideLinkRequest(ctx, id, approve, studentUserID, reason)` | school_admin or super_admin of the school (no ambassadors, no teachers). On approve: student VERIFIED, role student, same school; caps under lock (`SELECT … FOR UPDATE` on the student's ACTIVE links); insert link (source LINK_REQUEST, `request_id`, `verified_by`). On reject: reason 10–500. Status guard gives CONFLICT. | school requests, links | `guardian_link_request.approved/rejected` + `guardian_link.created` |
| `GRD-BE-027` | `AdminCreateLink(ctx, in)` | Admin. An existing VERIFIED same-school guardian gets a direct link (source ADMIN). An unknown phone creates an invite (G2; 202). A phone owned by another role gives CONFLICT. Caps apply. Optional `isPrimary`. | links | `guardian_link.created` / `guardian_invite.created` |
| `GRD-BE-028` | `UpdateLink(ctx, id, relation?, isPrimary?)` | Admin of the link's school; ACTIVE only. Primary switch clears the old primary in the same tx. | links, children | `guardian_link.updated` |
| `GRD-BE-029` | `RevokeLink(ctx, id, reason)` / `Unlink(ctx, linkID, reason?)` / `RevokeAllForStudent(ctx, studentID, key)` | Admin needs a reason 10–500. Self-unlink by the link's guardian stores `guardian_self_unlink` when no text is given. System use on student removal. All in `db.InTx`, then enqueue `guardians.sync_enrollments` and the push. | links, children | `guardian_link.revoked` |
| `GRD-BE-030` | `match.go` `RankCandidates(claim, students)` (pure) | Exact `student_code` (case-insensitive) first, then name similarity within the claimed section, then name within the school. Max 5. `matchedBy` is `student_code` or `name`. | — | — |
| `GRD-BE-031` | `CandidatesFor(ctx, schoolID, code, name, sectionID)` export | Used by 16's queue and by 03's verification decorate (`guardianCandidates`) | — | — |
| `GRD-BE-032` | Invites (G2): `CreateInvite`, `RevokeInvite`, `ResendInvite`, `ClaimInvite`, `InvitesForPhone` | Admin for create, revoke and resend. Resend allowed 3 times per day and only when the school's SMS opt-in is on. Claim requires the caller's OTP-proven phone to equal the invite phone, the invite PENDING and not expired, and the caps. Claim creates the link (source INVITE, `invite_id`). | invites, children | `guardian_invite.created/revoked/resent/claimed` |
| `GRD-BE-033` | `MyGuardians(ctx)` | Student VERIFIED. Returns names, relations and primary only. | — | — |
| `GRD-BE-034` | `ListLinks(ctx, filter)` / `ListRequests(ctx, filter)` / `ListInvites(ctx, filter)` | Admin of the school. Cursor pagination, limit ≤ 100, masked phones. | — | — |
| `GRD-BE-035` | `handler.go` (thin: decode, call service, `problem.Write` / `writeData` / `writeNoStore`), plus the `guardiansOps struct{ *guardians.Handler }` wrapper in `internal/httpapi/server.go`, plus a `Guardians` field in `httpapi.Deps`, plus wiring in `cmd/api/main.go` (ports and `registerHandlers` for jobs) | Shared files are edited with small anchored changes only | — | — |
| `GRD-BE-036` | api-side bn/en copy in `internal/i18n`: problems `GUARDIAN_LINK_LIMIT` and `CONSENT_REQUIRED`, push titles and bodies, SMS invite template (`TODO: Confirm` copy) | bn default | — | — |
| `GRD-BE-037` | `exports.go`: keep `LinkedStudents`, `GuardiansOf` and `IsGuardianOf` byte-identical. Add `ChildrenOf`, `ListGuardiansOfStudents`, `IsLinked` and `CandidatesFor` (`06` §2). | Additive only | — | — |

## 4. Repository Tasks

| ID | Method | Query shape | Index used |
| --- | --- | --- | --- |
| `GRD-BE-010` | `guardian_links.sql`: `RevokeGuardianLink`, `UpdateGuardianLinkRelation`, `ClearPrimaryForStudent`, `SetPrimary`, `GetGuardianLinkByIDForSchool`, `ListGuardianLinksBySchool` (filters plus cursor), `CountActiveLinksByStudent`, `CountActiveLinksByGuardian`, `LockActiveLinksByStudent` (`FOR UPDATE`), `ListGuardiansOfStudents(student_ids uuid[])`. The four existing queries stay unchanged. | `UPDATE … WHERE id=$1 AND school_id=$2 AND status='ACTIVE' RETURNING *` | `(school_id, created_at, id)`, `(student_user_id, status)`, primary partial unique |
| `GRD-BE-011` | New `guardian_link_requests.sql`: `Insert`, `GetForSchool`, `GetForGuardian`, `ListBySchoolStatus` (cursor), `ListByGuardian`, `Decide` (status guard), `Cancel` (status guard), `ListDueForReminder`, `BumpReminder` | Status-guarded `UPDATE … WHERE status='PENDING'` | `(school_id, status, created_at)`, `(guardian_user_id, status)` |
| `GRD-BE-012` | New `guardian_invites.sql` (G2): `Insert`, `GetForSchool`, `ListBySchool`, `ListPendingByPhone`, `Claim` (status plus expiry guard), `Revoke`, `MarkSmsSent`, `ExpireDue` | | `(phone_e164, status)`, `(school_id, status, created_at)` |
| `GRD-BE-013` | New `guardian_consents.sql`: `InsertConsent` (`ON CONFLICT DO NOTHING`), `HasConsent(guardian, version)` | | unique `(guardian_user_id, notice_version)` |
| `GRD-BE-014` | `users.sql` (03 file, small additive edit): `SetStudentCode`, `FindStudentsByCode(school_id, lower(code))`, `SearchSchoolStudents(school_id, q, section_id?)` | | `users_school_student_code_key`, `(school_id, role, status)` |

## 5. Jobs

| ID | Job | Trigger | Idempotent? | Failure handling |
| --- | --- | --- | --- | --- |
| `GRD-BE-040` | `guardians.sync_enrollments` {guardianID, studentID?, reason} | After any link create or revoke commit, and from the nightly reconcile | Yes. 04's `EnsureGuardianEnrollments` and `EndGuardianEnrollment` are idempotent. | Retry ×5 with backoff (01 jobs). The reconcile pass catches leftovers. |
| `GRD-BE-041` | `guardians.request_reminder` | Hourly. PENDING requests older than 48 h, then every 24 h, max 3 | Yes (`reminder_count` guard) | Skip on 06 failure. The next run retries. |
| `GRD-BE-042` | `guardians.invite_expiry` (G2) | Hourly | Yes (`UPDATE … WHERE status='PENDING' AND expires_at < now()`) | Next run |
| `GRD-BE-043` | `guardians.invite_sms` {inviteID} (G2) | After invite create or resend when SMS is on | Yes (`sms_sent_at` and `sms_send_count` guard) | Retry ×5. Admin sees "SMS not sent". |
| `GRD-BE-044` | `guardians.reconcile_enrollments` | Nightly | Yes | Logs counts. Alert if more than 0 links lack an enrollment for a placed child. |

## 6. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `GRD-UT-001` | `RankCandidates`: exact code beats name; case-insensitive; max 5; other-school students excluded | Unit | Matching never surfaces the wrong school; code first |
| `GRD-UT-002` | Caps evaluator (4 guardians per student, 8 children per guardian) | Unit | `GRD-BR-004` |
| `GRD-UT-003` | Same-school rule plus TENANT_MISMATCH mapping | Unit | `GRD-BR-003` |
| `GRD-UT-004` | Relation, source and status enum validation, and reason length rules (admin vs self) | Unit | `01` §6, `GRD-BR-006` |
| `GRD-UT-005` | DTO mapping masks phones; co-guardian DTO has no phone field | Unit | `GRD-BR-007` |
| `GRD-UT-006` | Consent gate: an old version gives `CONSENT_REQUIRED`; the current version passes | Unit | `GRD-BR-015` |
| `GRD-UT-007` | Invite claim guard (phone equality, expiry, status) | Unit | `GRD-BR-010` |
| `GRD-UT-008` | SMS invite render contains the school name and link only, never the child's name or code | Unit | `GRD-BR-011` |
| `GRD-UT-009` | Push payload builder for `guardian_link_decided` and `guardian_link_revoked` emits ids and keys only | Unit | `GRD-BR-011` |
| `GRD-UT-010` | Enrollment-follow decision (pure): end the old section only when no sibling remains | Unit | `GRD-INV-8` |
| `GRD-IT-001` | Unauthenticated calls denied on all 20 operations | Integration (testcontainers Postgres), **pending owner run** | auth chain |
| `GRD-IT-002` | PENDING guardian gets `NOT_VERIFIED` on `/guardian/*`; student gets `FORBIDDEN` on `/guardian/*` | Integration, pending owner run | role gates |
| `GRD-IT-003` | Cross-tenant: an admin of A reading or revoking B's link gets 404; a guardian reading a child of another school gets 404 | Integration, pending owner run | tenant scope on every table |
| `GRD-IT-004` | Approve tx: link + request APPROVED + audit commit together; cap breach rolls everything back | Integration, pending owner run | `GRD-BR-004`, `GRD-BR-013` |
| `GRD-IT-005` | Two concurrent approvals: one wins, one gets `CONFLICT` | Integration, pending owner run | status guard |
| `GRD-IT-006` | Two concurrent primaries: partial unique gives `CONFLICT` | Integration, pending owner run | `GRD-INV-2` |
| `GRD-IT-007` | Revoke ends the guardian enrollment unless a sibling is in the section; push enqueued | Integration, pending owner run | `GRD-US-007`, `GRD-INV-8` |
| `GRD-IT-008` | Invite claim: link + CLAIMED; expired gives `NOT_FOUND`; phone mismatch gives `FORBIDDEN` | Integration, pending owner run | `GRD-US-009` |
| `GRD-IT-009` | Children list returns ACTIVE links only and gates details on consent | Integration, pending owner run | `GRD-BR-001`, `GRD-BR-015` |
| `GRD-IT-010` | Migrations: up → down → up is clean on a DB with demo seed rows | Integration, pending owner run | idempotent pairs |

There is no publish guard or public read in this module (no public surface). Seed copy is
checked for the `TODO:` and ডেমো markers in review.

## 7. Task Checklist

> Status on 2026-10-19: planned, not built. Nothing is ticked.

### Schema

- [ ] `GRD-BE-001` Migration `grd_student_codes` (03 amendment; record it in 03 `03` §1.1)
- [ ] `GRD-BE-002` Migration `grd_guardian_links_v2`
- [ ] `GRD-BE-003` Migration `grd_guardian_link_requests`
- [ ] `GRD-BE-004` Migration `grd_guardian_consents`
- [ ] `GRD-BE-005` Migration `grd_guardian_invites` (G2)
- [ ] `GRD-BE-006` Migration `grd_audiences` (G2; record it in 04/05 docs)

### Repository

- [ ] `GRD-BE-010` … `GRD-BE-014`, then `make contracts` (sqlc + oapi) and `make contracts-check`

### Service · Entry points

- [ ] `GRD-BE-020` … `GRD-BE-037`
- [ ] OpenAPI paths 1–15 (G1) and 16–20 (G2), plus schemas, under tag `guardians`; web and app spec sync and generate

### Jobs

- [ ] `GRD-BE-040` … `GRD-BE-044`

### Seed

- [ ] Demo student codes, request and invite (only if the owner asks)

### Tests

- [ ] `GRD-UT-001` … `GRD-UT-010` (agent-run, `go test`)
- [ ] `GRD-IT-001` … `GRD-IT-010` written (`-tags integration` compile-checked with `go vet`), **run by the owner**

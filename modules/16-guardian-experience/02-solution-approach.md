# Guardian Experience — Solution Approach

**Module:** `16-guardian-experience` · **Last updated:** 2026-10-19

> This is a plan only (owner, 2026-10-19). Nothing is built. It was written from a read-only map
> of the current code and docs. Where it describes current behaviour, the file and line evidence
> is in `technical-document.md` §3 and §14.

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| Guardian account | A `users` row with `role='guardian'`. It has one `school_id` (required by `users_platform_scope_chk`), a globally unique `phone_e164`, and moves PENDING → VERIFIED through the 03 verification queue. | No (03). Read only. |
| Guardian link | A `guardian_links` row: guardian ↔ student, many-to-many, with relation, status ACTIVE/REVOKED, source, and `verified_by`. Today it is written only by 03's approve transaction and the demo seed. | Table stays registered to 03. **16 owns all new writes** (v2 columns, revoke, update, admin create) through the `guardians` package. |
| Link request | `guardian_link_requests`: a VERIFIED guardian's claim to a 2nd or later child (student code + relation), decided by the school admin. | Yes (new) |
| Guardian invite | `guardian_invites`: a school-vouched phone for a given student (from admin, roster or LMS), claimable once the phone is OTP-proven. | Yes (new, G2) |
| Guardian consent | `guardian_consents`: the guardian's acceptance of a versioned guardian privacy notice. Append-only. | Yes (new) |
| Student code | `users.student_code`: the institution's student ID, unique per school. It makes code claims matchable. | Amendment to 03's `users` (migration shipped by 16, recorded in 03 docs) |
| Guardian enrollment | An `enrollments` row with `role='GUARDIAN'` in a linked child's ACTIVE section. It drives FCM topics and notice visibility. | No (04). Driven through the EnrollmentPort. |
| Guardian section group | A 05 official `chat_groups` row with `system_key='section_guardians:{sectionId}'` (G2). | No (05). Driven through the GroupPort. |
| Notice audience | `notices.audience` = `all` / `students` / `guardians` (G2) | No (05) |

### 1.2 Relationships

```text
schools 1───* users(role=guardian)            users(role=student) *───1 schools
                    │ 1                            1 │  (student_code, unique per school)
                    │                                │
                    *──── guardian_links (M:N) ──────*
                    │      relation · is_primary · status ACTIVE|REVOKED · source
                    │      verified_by · revoked_by · revoke_reason · request_id
                    │
                    ├──* guardian_link_requests ──(approve)──▶ guardian_links (source LINK_REQUEST)
                    │      student_code claim · matched_student_user_id · status
                    │
                    ├──* guardian_consents (append-only, per notice_version)
                    │
   phone_e164 ◀─────┴── guardian_invites *───1 users(role=student)
   (match on OTP)        source ADMIN|ROSTER|LMS ──(claim)──▶ guardian_links (source INVITE)

guardian_links ACTIVE + child's ACTIVE STUDENT enrollment
   ──(04 EnsureGuardianEnrollments)──▶ enrollments(role=GUARDIAN, section of child)
        ──▶ fcm topics section-{id}/school-{id}/city-{id}  ──▶ 05 notices (via enrollments)
        ──▶ 05 group membership (student group now; section_guardians:{id} in G2)
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| GRD-INV-1 | At most one ACTIVE link per (guardian, student) | DB partial unique `(guardian_user_id, student_user_id) WHERE status='ACTIVE'` (exists) |
| GRD-INV-2 | At most one ACTIVE primary per student | DB partial unique `guardian_links_one_primary_key` (new) |
| GRD-INV-3 | A guardian never links to themselves | DB CHECK guardian <> student (exists) |
| GRD-INV-4 | Guardian, student and link share the same `school_id` (single-school mode) | service + `GRD-UT-003`/`GRD-IT-003` |
| GRD-INV-5 | A REVOKED link always has `revoked_at` and `revoke_reason` | DB CHECK (new) |
| GRD-INV-6 | At most one PENDING request per (guardian, school, lower(student_code)) | DB partial unique (new) |
| GRD-INV-7 | At most one PENDING invite per (student, phone) | DB partial unique (new) |
| GRD-INV-8 | A guardian has a GUARDIAN enrollment in section S if and only if they have an ACTIVE link to a child with an ACTIVE STUDENT enrollment in S (for the current session) | 04 `EnsureGuardianEnrollments` / `EndGuardianEnrollment` (idempotent), reconciled by the `guardians.sync_enrollments` job |
| GRD-INV-9 | Consent rows are never updated or deleted | No UPDATE or DELETE query exists. Review rule. |
| GRD-INV-10 | `users.student_code` is set only on `role='student'` rows and is unique per school, case-insensitive | DB CHECK + partial unique index (new) |

## 2. Module Boundary

**Owns (writes):** `guardian_links` (all writes after 03's existing approve insert, which keeps
calling `guardians.Link`), `guardian_link_requests`, `guardian_invites`, `guardian_consents`. It
also ships the `users.student_code` migration, but the column is 03's. The Go package is the
existing `applications/api/internal/guardians` (03 created it; 16 extends it). The README Go
export line becomes "`guardians` (03, extended by 16)".

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 03 | User display data (name, avatar, status, role), OTP proof check (invite claim), verification queue decoration (guardian candidates) | 03 owns identity |
| 04 | A child's ACTIVE section (class level, name, session), class teacher, `EnsureGuardianEnrollments` / `EndGuardianEnrollment` (new exports) | 04 owns placement and topics |
| 05 | Recent notices for a section or school plus the unread count, guardian group join/leave (G2), the `GuardianPolicy` it consumes from us | 05 owns notices and chat |
| 06 | `SendToUser` for decision and revocation pushes, SMS sender for invites | 06 owns delivery |
| 12 | Dues summary per student (count, total BDT), open invoices for a student | 12 owns money |

**Import-cycle rule:** `hierarchy` already imports `guardians` (hierarchy/service.go), so
`guardians` must never import `hierarchy`, `chat`, `notify` or `payments`. Everything it needs
from them is injected from `cmd/api/main.go` as ports: `EnrollmentPort`, `GroupPort`, `NoticesPort`,
`DuesPort`, `Notifier` and `SMSSender`. Consumers (`chat`, `payments`, `hierarchy`) keep calling
the `guardians` exports directly.

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4.

## 3. Lifecycle

```text
guardian_links:          (none) ──create──▶ ACTIVE ──revoke/unlink/student_removed──▶ REVOKED
                         (create = verification approve | link-request approve | invite claim |
                          admin create | roster/LMS vouched phone; a REVOKED pair may be linked again
                          as a NEW row)
guardian_link_requests:  PENDING ──approve──▶ APPROVED
                         PENDING ──reject(reason)──▶ REJECTED
                         PENDING ──cancel(guardian)──▶ CANCELLED
guardian_invites:        PENDING ──claim(OTP phone match)──▶ CLAIMED
                         PENDING ──expiry job (30 d)──▶ EXPIRED
                         PENDING ──admin revoke──▶ REVOKED
guardian_consents:       append-only rows; "current" = row for the server's current notice version
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| — | verification approve (03, guardian row) | link ACTIVE (source VERIFICATION) | actor is school_admin or super_admin of the school (ambassadors excluded, OQ-1); `studentUserId` is a VERIFIED same-school student | user → VERIFIED, `auth.provision_user`, audit `verification.approved`, `guardian_link.created` |
| request PENDING | approve | request APPROVED + link ACTIVE (source LINK_REQUEST, `request_id`) | admin of the school; student VERIFIED and same school; caps; no ACTIVE duplicate | audit, `guardians.sync_enrollments`, push `guardian_link_decided` |
| request PENDING | reject | REJECTED | admin; reason 10–500 | audit, push `guardian_link_decided` (rejected) |
| request PENDING | cancel | CANCELLED | caller is the requesting guardian | audit |
| — | admin create (existing guardian) | link ACTIVE (source ADMIN) | admin; guardian VERIFIED and same school; caps | audit, sync job, push `guardian_link_decided` |
| — | admin create (unknown phone) | invite PENDING | admin; phone not used by another role | audit, optional `guardians.invite_sms` |
| invite PENDING | claim | invite CLAIMED + link ACTIVE (source INVITE) | caller's OTP-proven phone equals the invite phone; not expired; caps | audit, sync job; new guardian → VERIFIED (only if OQ-2 is approved) |
| link ACTIVE | edit relation or primary | ACTIVE | admin; one primary per student | audit `guardian_link.updated` |
| link ACTIVE | revoke (admin) / unlink (guardian) / student removed (system) | REVOKED | reason rules (`GRD-BR-006`) | audit, `EndGuardianEnrollment` (unless a sibling is in the section), group leave, push `guardian_link_revoked` |
| invite PENDING | expiry | EXPIRED | `expires_at < now()` | none |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| App guardian home and child hub | Client (expo-router), TanStack Query | Query cache, persisted for offline display of the last children list | `['guardian','children']`, `['guardian','child',id]` |
| App link requests | Client | Query cache | `['guardian','link-requests']` |
| Web `/institution/guardians` | Client component under the console shell (07 pattern), TanStack Query on the fixture seam, then the generated client | Query cache | `['school','guardian-links',filters]`, `['school','guardian-link-requests',status]`, `['school','guardian-invites',status]` |
| api responses | `writeNoStore` on every `/guardian/*` and `/school/guardian-*` response (personal data of minors) | none server-side | — |

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| Per school (later, via 07): SMS invites on or off (default off) | Caps: 4 guardians per student, 8 children per guardian |
| Per school (G2): default post policy of guardian groups (`all` / `moderators`) | Invite expiry 30 days. Link-request SLA 48 h with a reminder, then every 24 h, max 3 |
| Platform (later): academic-records flag (default off) | Relation enum, source enum, status enums |
| | Guardian notice version (`GUARDIAN_NOTICE_VERSION` constant) plus bn/en copy (`TODO: Confirm`) |
| | Masking rule for phones; push payload keys |
| | Rate limits: link requests 10/day per guardian; invite resend 3/day per invite; invite create 200/day per school |

## 6. Security

- **Entry points:** about 20 REST operations under tag `guardians` (`technical-document.md`
  §5.1). There is no WebSocket surface of our own; chat stays 05's.
- **Auth chain:** `authenticate → load role claims → tenant scope`, with services authorising at
  entry:
  - `/guardian/*`: `principal.RequireRole(guardian)` plus VERIFIED, then a per-child
    `IsGuardianOf` check.
  - `/school/guardian-*`: `principal.RequireRole(school_admin, super_admin)` plus
    `RequireSchool(schoolId)`.
  - `/me/guardians`: role student plus VERIFIED.
  - Console mutations go through `consoleCSRF` (07 pattern).
- **Tenant scope:** every table carries `school_id`. Every query filters on it, using the caller's
  claim, or `?schoolId=` for super_admin with the tenant check. A cross-tenant id returns 404
  (`TENANT_MISMATCH` semantics).
- **Validation:** the OpenAPI contract plus service rules (§6 of `01`). Free text (reason, names)
  is trimmed and length-checked, and shown with plain-text rendering only.
- **Privacy:**
  - Phones are masked in all responses; the full invite phone is never returned after create.
  - Co-guardians are shown by name only.
  - Child data needs consent (`GRD-BR-015`).
  - Guardians get no chat, AI or analytics access (`GRD-BR-008`).
  - Push payloads carry ids only.
  - Logs carry ids, never phones or names (slog redaction list).
- **Child safety:** the DM policy (`GRD-BR-009`) and contact search scoping (G0) are
  prerequisites for any guardian rollout beyond the pilot. Link decisions are adults-only
  (`GRD-BR-002`).
- **Rate limits:** default class for reads. Link requests, invite create and invite resend use
  the caps in §5.
- **Abuse:**
  - A wrong link exposes another family's fees and notices. Mitigations: candidates ranked by an
    exact code match, the admin must pick explicitly, every decision is audited, and a revoke is
    effective at once.

## 7. Accessibility & Motion

- **Motion (app):** the child switcher bottom sheet slide, card press feedback, and a pending
  badge pulse. Each has an instant reduced-motion form.
- **Motion (web):** dialog fade and scale only.
- **Screen readers:** each child card reads as "{name}, {class} {section}, dues {amount}".
  The switcher announces the selected child.
- **Keyboard (web):** table row actions are reachable by keyboard. Dialogs trap focus and return
  it to the row action.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | EnrollmentPort fails after a link commits | Job error, retry count | Guardian lacks topics and notices for that child | `guardians.sync_enrollments` retries ×5 with backoff. A nightly reconcile pass re-runs for links missing enrollments. |
| 2 | Child not placed when the guardian is verified (today: provision fails ×5, `NOT_FOUND`) | — | Silent loss of notices | G0: `enrollGuardian` returns success. Student placement calls `EnsureGuardianEnrollments` for `GuardiansOf(student)`. |
| 3 | Year-end migration ignores guardians (today) | Count of GUARDIAN enrollments in archived sections | Guardians follow the old class | G0: the migration commit loop moves or ends GUARDIAN enrollments |
| 4 | 06 push down | 06 delivery tracking | Decision push missing | The in-app Requests list is the source of truth. Pushes are best-effort. |
| 5 | SMS gateway down or capped | `sms_sent_at` NULL plus job failures | Invite not received | Retry ×5; "SMS not sent" badge plus manual resend |
| 6 | Wrong child linked | Guardian or school report | Privacy exposure | Admin revoke (immediate). Audit trail shows who approved. Then re-link. |
| 7 | 12 dues lookup slow or down | Port timeout (500 ms) | Home without dues badges | Degrade: `dues: null` and the card shows "—". Never fail the children list. |
| 8 | Concurrent decisions | `CONFLICT` | One admin sees a stale row | Refetch the row and show the winner's decision |

## 9. Performance

- **Volumes (pilot):** 2–3 schools × about 1,500 students × about 1.6 guardians gives about
  2,400 links per school. Per year, about 200 link requests and about 1,000 invites per school.
- **Hot queries:**
  - children by guardian (`guardian_links (guardian_user_id, status)`, exists)
  - links by school with cursor (`(school_id, status)`, exists; add `(school_id, created_at, id)`
    for the cursor)
  - requests by school and status (`(school_id, status, created_at)`, new)
  - `GuardiansOf` for bulk invoices: a new batched `ListGuardiansOfStudents(student_ids[])` on
    `(student_user_id, status)` avoids N+1 when 12 issues a section-wide bulk
- **Children list latency:** under 300 ms p95. It makes at most 3 port calls per child, batched
  per guardian (sections by student ids, dues by student ids, notice counts by section ids).
- **Bundle:**
  - app: no new dependencies (existing bottom-sheet and query primitives)
  - web: no new dependencies (existing data-table and dialog)
- **Push volume:** fee-due fan-out multiplies pushes by about 2.6 (student plus guardians).
  This fits within the FCM free tier. The SMS budget is OQ-14.

## 10. Alternatives Considered

### Option A — new module 16 owning the guardian experience · Option B — amendments spread over 03/04/05/12

| | A | B |
| --- | --- | --- |
| Advantages | One owner for end-to-end flows, privacy matrix and rollout. Clear IDs (`GRD-*`). G0 fixes stay in their owning packages but are tracked in one list. | No new module or README row. Each change sits next to its code. |
| Disadvantages | One more module. Cross-module INT tasks must be coordinated. | Guardian behaviour stays scattered (today's state, which produced the gaps found while planning). No single privacy owner. |
| Complexity / weight | Medium | Low per change, high overall |

**Recommendation:** A. **ADR:** to be recorded in `07-progress.md` at build.

### Guardian chat placement — A: stay in the students' group · B: separate guardian group (G2)

| | A (stay) | B (`section_guardians:{id}`) |
| --- | --- | --- |
| Advantages | No migration. Today's behaviour. | Adults and minors are separated. Teachers moderate. A post policy is possible. |
| Disadvantages | Adults share a group with minors | `ListNotices` must read enrollments first (`GRD-INT-010`), plus a data migration of memberships |

**Recommendation:** A until the G0 DM policy lands, then B in G2 (OQ-3).

### Student code storage — A: `users.student_code` · B: separate `student_codes` table

**Recommendation:** A. It is one nullable column with a CHECK and a partial unique index; 14
roster/LMS and the 03 users list read it directly. B is kept as the fallback if 03 refuses to
widen `users` (OQ-6).

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | The existing school-wide invoice list exposure (`GET /school/invoices` has no role gate; the app uses it as "my invoices") is fixed before guardians scale | Every family's fees are visible to any school member | `GRD-INT-001` is G0 and P0, and blocks every other guardian rollout step |
| 2 | Guardians sharing groups with minors and instant DM to any same-school student is unacceptable at scale | Child-safety incident, schools lose trust | `GRD-INT-005` (G0) before onboarding beyond the pilot |
| 3 | One school per user stays true through G2 | Families with children in two schools cannot use one account | Clear `CONFLICT` copy; G3 design (`technical-document.md` §4.4) |
| 4 | Admins will match by student code once codes exist | Name-only matching links the wrong child | `users.student_code` via roster/LMS (G1/G2), candidate ranking, audit |
| 5 | The relation enum change is sequenced as one contract change | Clients reject unknown relations, or the api rejects new ones | `GRD-INT-007`: api accepts first, clients update, then `contracts-check` in all three repos |
| 6 | Attendance and results are not promised | Scope creep with heavy privacy weight | Out of scope. Flag-hidden slot only (OQ-11). |
| 7 | 07's console still runs on fixtures | Gate 3 for web flows waits on the live-seam swap | Fixture seam first (`GRD-FE-001`). Swap with 07's glue. |
| 8 | Import cycle (hierarchy → guardians) | Build break | Ports from `main.go` only. `go build ./...` guard in every change. |

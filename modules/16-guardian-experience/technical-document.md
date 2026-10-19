# Guardian Experience — Technical Document

**Module:** `16-guardian-experience`
**Version:** 0.1
**Status:** 📝 Draft 2026-10-19 — **planned, not built** (owner asked "also plan for student's guardian")
**Owner:** Rahul (product owner)
**Last updated:** 2026-10-19

> This is the single engineer-facing reference for the module. It must agree with `01`–`06`; if
> they drift, the spec files win. It was written from a read-only survey of the code on
> 2026-10-19. Nothing was built or run.

---

## 1. Overview

### 1.1 Purpose

This module gives guardians (অভিভাবক) one child-centred experience. A guardian is linked by the
institution to one or more children. They see each child's class, class teacher, notices and fees,
pay fees, and message school staff safely. Institution admins verify, manage and revoke those
links. It serves `brd.md` §3 (Guardians/Parents B2C) and BR-01, and `prd.md` §2, §4B and §5.4.

### 1.2 Scope

**In:**

- Guardian self-service: children list and hub, child switcher, link requests, unlink, consent.
- Institution link management: links, link requests with student matching, invites (G2).
- The `guardian_links` v2 data model and the new request, invite and consent tables.
- Guardian views of 04/05/12 data through their exports.
- Guardian pushes.
- G0 hardening, done inside 03/04/05/07/12 and tracked as `GRD-INT-001…006`.

**Out:**

- Attendance and results data (future `17-academic-records`, owner decision).
- Guardian access to chats, AI or analytics. This is never allowed.
- A web portal for guardians.
- Multi-school guardians, staff who are also parents, and phone-less students (G3 design only).
- Payment mechanics (12) and ad targeting (13).

### 1.3 Dependencies

| Direction | Module | What is exchanged |
| --- | --- | --- |
| consumes | 03 identity-access | users, verification approve path, OTP proof, register contract, `guardian_links` table |
| consumes | 04 organization-hierarchy | GUARDIAN enrollments, child placements, migration, topics |
| consumes | 05 communication-engine | notices, groups, DM/contacts policy hook |
| consumes | 06 notifications | directed pushes, SMS sender |
| consumes | 07 command-center-web | console shell, nav, verification queue page |
| consumes | 12 payments | dues summary, open invoices, payer list |
| consumes | 14 lms-erp-sync | roster/LMS guardian columns (G2) |
| consumed by | 03, 04, 05, 10, 12, 14 | `LinkedStudents`, `GuardiansOf`, `IsGuardianOf` (frozen), `ChildrenOf`, `ListGuardiansOfStudents`, `IsLinked`, `CandidatesFor`, `CreateInvitesFromRoster`, `RevokeAllForStudent` |

---

## 2. Tech Stack (this module)

| Layer | Technology | Why | Notes |
| --- | --- | --- | --- |
| API | Go, chi, oapi-codegen (`api.ServerInterface`), sqlc + pgx, golang-migrate | Project standard (01) | Existing package `internal/guardians`, extended |
| Jobs | `internal/jobs` (`jobs.NewType[Payload]`, `registerHandlers` in `main.go`) | Existing queue | 5 jobs (`03` §5) |
| DB | PostgreSQL (Neon) | Project standard | 4 new or changed tables plus 1 column (G1); 1 invite table plus 3 column/CHECK amendments (G2) |
| Web | Next.js 16 App Router, TanStack Query, shadcn-style `src/components/ui`, `useT()` | 07 console | Institution admin only |
| App | Expo Router, TanStack Query, zustand, `expo-secure-store` (active child id), NativeWind | Project standard | Guardian and student screens |
| Push / SMS | FCM via 06; `internal/smsout` | Existing | No new env variables |

---

## 3. Architecture

### 3.1 Component diagram

```text
 app (guardian/student)            web (/institution/guardians, /institution/users)
        │  openapi-fetch                     │  openapi-fetch (fixture seam until 07 glue)
        ▼                                    ▼
 ┌──────────────────────── api (chi) ─────────────────────────────────────────────┐
 │ httpapi.server  ──► guardiansOps{*guardians.Handler}  (problem.Write/writeNoStore)│
 │                         │                                                        │
 │                         ▼                                                        │
 │   guardians.Service  (children · requests · links_admin · invites · consent ·   │
 │                       match(pure) · jobs · exports)                              │
 │      │ sqlc (dbgen)            │ ports (injected in cmd/api/main.go)             │
 │      ▼                         ├─ EnrollmentPort ──► hierarchy (04)              │
 │  guardian_links                ├─ GroupPort ───────► chat (05, G2)               │
 │  guardian_link_requests        ├─ NoticesPort ─────► chat notices (05)           │
 │  guardian_invites (G2)         ├─ DuesPort ────────► payments (12)               │
 │  guardian_consents             ├─ Notifier ────────► notify (06) ──► FCM         │
 │  users.student_code (03)       └─ SMSSender ───────► smsout (06) ──► SMS gateway │
 │                                                                                  │
 │  callers of guardians exports: verification(03) · hierarchy(04) · chat(05)       │
 │                                payments(12) · tuition(10) · sync(14)             │
 └──────────────────────────────────────────────────────────────────────────────────┘
 import rule: hierarchy → guardians already exists, so guardians never imports
 hierarchy/chat/notify/payments
```

### 3.2 Boundary

**Owns (tables / services):**

- `guardian_links` writes (v2). The table stays registered to 03, and 03's approve keeps calling
  `guardians.Link`.
- `guardian_link_requests`, `guardian_invites` and `guardian_consents`.
- The `users.student_code` migration (the column is 03's).
- The Go package `guardians` (03 origin, extended by 16).

**Reads (via exported service functions only):** 03 users and OTP proof; 04 placements and
enrollment ensure/end; 05 notices and groups; 06 push and SMS; 12 dues and invoices.

### 3.3 Request / data flows

```text
F1  Guardian registration (exists, 03) — first child
    app onboarding → POST /auth/register {role:guardian, schoolId, sectionId, studentCode, relation}
    → verification_requests(PENDING, evidence{studentCode,relation})
    → admin (web /institution/users) opens row → guardianCandidates (16 CandidatesFor, G0)
    → POST /verification-requests/{id}/approve {studentUserId}
    → tx: request APPROVED · user VERIFIED · guardians.Link(source VERIFICATION) · audit
    → jobs auth.provision_user → hierarchy.enrollGuardian (G0: success when no child placed)
    → GUARDIAN enrollment(s) + topics + chat join

F2  Add another child (G1)
    app /children/add → POST /guardian/link-requests → guardian_link_requests(PENDING) + audit
    → web Requests tab → GET /school/guardian-link-requests (candidates ranked: code > name)
    → POST /school/guardian-link-requests/{id}/approve {studentUserId}
    → tx: lock student's ACTIVE links · caps · insert link(LINK_REQUEST, request_id) · request
      APPROVED · audit → enqueue guardians.sync_enrollments + push guardian_link_decided

F3  Guardian home (G1)
    app feeds → GET /guardian/children → ACTIVE links → consent check
    → batch: EnrollmentPort.ChildPlacements(ids) · DuesPort.DuesSummary(ids)
      · NoticesPort.UnreadCounts(sectionIds)  (each ≤500 ms, degrade to null)
    → [{studentId, fullName, relation, isPrimary, school, section?, classTeacher?, dues?,
        unreadNotices}] + consentRequired + pendingInvites(G2)

F4  Revoke (G1)
    web → POST /school/guardian-links/{id}/revoke {reason}
    → tx: link REVOKED (revoked_by, revoke_reason, revoked_at) · audit
    → job guardians.sync_enrollments → EnrollmentPort.EndGuardianEnrollment (unless sibling)
      → GroupPort.LeaveGuardianGroups (G2) → Notifier guardian_link_revoked

F5  Fee due (G0, owned by 12)
    payments invoice.notify → recipients = student ∪ guardians.ListGuardiansOfStudents
    → notify.SendToUser(payments_fee_due) each → app /payments?studentId=

F6  Invite (G2)
    web → POST /school/guardian-invites {studentUserId, phone, relation?, sendSms}
    → invite PENDING (+ guardians.invite_sms) → guardian installs app → OTP-proven phone
    → (new) register with inviteId / (existing) POST /guardian/invites/{id}/claim
    → tx: invite CLAIMED · link(INVITE, invite_id) · [user VERIFIED if OQ-2 approved] · audit
    → sync_enrollments
```

### 3.4 State machines

| Entity | States | Transitions (from → to, guard) |
| --- | --- | --- |
| `guardian_links` | ACTIVE, REVOKED | — → ACTIVE (verification approve / request approve / invite claim / admin create / roster-LMS vouched; caps, same school) · ACTIVE → REVOKED (admin with reason 10–500, guardian self-unlink, system `student_removed`). REVOKED is final; re-linking creates a new row. |
| `guardian_link_requests` | PENDING, APPROVED, REJECTED, CANCELLED | PENDING → APPROVED (admin, VERIFIED same-school student, caps) · → REJECTED (admin, reason) · → CANCELLED (requesting guardian). The status guard on `UPDATE` makes concurrent deciders `CONFLICT`. |
| `guardian_invites` | PENDING, CLAIMED, EXPIRED, REVOKED | PENDING → CLAIMED (OTP phone match, not expired) · → EXPIRED (hourly job) · → REVOKED (admin) |
| `guardian_consents` | (append-only) | Insert per (guardian, notice_version) |
| Guardian `users.status` (03) | PENDING, VERIFIED, SUSPENDED | Unchanged. Only the registration request (F1) or an approved invite claim (OQ-2) verifies a guardian. Link requests never change account status. A VERIFIED guardian with zero ACTIVE links stays VERIFIED with an empty home. |

---

## 4. Data Model (summary)

Column-level detail is in `03-backend-tasks.md` §1.

| Table | Purpose | Tenant scope | Key indexes | Notes |
| --- | --- | --- | --- | --- |
| `guardian_links` *(exists, v2)* | M:N guardian ↔ student with relation, primary, status, source, verifier, revocation | `school_id` | partial unique active pair; one primary per student; `(guardian,status)`; `(student,status)`; `(school_id,created_at,id)` | 03 table; 16 owns the new writes |
| `guardian_link_requests` (new, G1) | Claim to a 2nd or later child, decided by the institution | `school_id` | partial unique pending claim; `(school_id,status,created_at)` | — |
| `guardian_consents` (new, G1) | Versioned privacy-notice acceptance | `school_id` | unique `(guardian, notice_version)` | append-only |
| `guardian_invites` (new, G2) | School-vouched phone for a student | `school_id` | partial unique pending `(student, phone)`; `(phone,status)` | phone never returned unmasked |
| `users.student_code` (03 amendment, G1) | Institution student ID | `school_id` (unique per school) | `(school_id, lower(student_code))` partial unique | Written by 14 and the admin |
| `notices.audience`, `chat_groups.post_policy`, `fcm_topic_bindings.node_type` (G2 amendments) | Guardian-only notices, topics and groups | inherit | — | 05/04 tables |

### 4.1 Guardian accounts (current model, unchanged by G1/G2)

- A guardian is a `users` row with `role='guardian'`, exactly one `school_id` (required by
  `users_platform_scope_chk`), and a globally unique `phone_e164`. There is no password; login
  is by phone OTP (03).
- Self-registration is app-only. Phone OTP is refused for web clients (03 G-12).
- The account becomes VERIFIED only through the institution: the 03 verification queue (F1), or
  an invite claim (G2, if OQ-2 is approved).
- `principal.Principal` carries a single `SchoolID`. All guardian reads are therefore scoped to
  that school.
- The demo seed has two VERIFIED guardians (করিম, সুমি) linked with source ROSTER
  (`20270303090001_seed_demo_tenant_users`).

### 4.2 Guardian ↔ student links (many-to-many, verified by the institution)

- `guardian_links` is the join table. One student may have up to 4 ACTIVE guardians; one
  guardian may have up to 8 ACTIVE children. The partial unique index allows one ACTIVE row per
  pair.
- **Relation:** `father`, `mother`, `grandfather`, `grandmother`, `brother`, `sister`, `uncle`,
  `aunt`, `legal_guardian`, `other` (G1 widening; OQ-7).
- **Primary:** optional, at most one per student. Used for future SMS fallback and as a display
  hint. It never grants extra rights.
- **Verification by the institution:** every link has an accountable creator. `verified_by` is
  the deciding admin. `source` records the path: VERIFICATION, LINK_REQUEST, ADMIN, INVITE,
  ROSTER or LMS. A studentCode match is only a ranking hint (IDT-US-002: a mismatch stays in the
  queue, and nothing is auto-approved from a code). Only school_admin or super_admin decide
  (OQ-1).
- **Revocation** is a status change, never a delete. It is audited, takes effect immediately,
  and ends the guardian's enrollments where no sibling remains.

### 4.3 Invites (G2)

- An invite records that the institution vouches that phone P belongs to a guardian of student
  S. Sources are an admin, a roster row, or an LMS `guardian_phone`.
- **Claim** requires that P is OTP-proven by the claimer: during registration (03 OTP proof plus
  `inviteId`) or by a VERIFIED guardian (`/guardian/invites/{id}/claim`).
- **Enumeration safety:** invites are found only after OTP proof of the phone. There is no
  unauthenticated "is this phone invited" lookup.
- **SMS** is per-school opt-in. The template carries the school name and the download link only.

### 4.4 Future model (G3, design direction only)

- **Multi-school guardians.** Either (a) relax `users_platform_scope_chk` for guardians and
  derive tenancy per link (`Principal.SchoolIDs` from ACTIVE links, plus an active-child context
  header), or (b) one account per school. (a) is recommended. It touches `principal`, the tenant
  checks in every module, and 12's `callerEntitledForInvoice` (which compares the caller's single
  `SchoolID` to the invoice school). It needs an ADR (`GRD-INT-019`).
- **Staff who are also parents.** Allow `guardian_links` for teacher or school_admin users of the
  same school. The guardian capability then derives from having links, not from `users.role`.
- **Phone-less managed students.** Roster or admin-created student profiles without a phone, so
  guardians of primary-class children can link (`GRD-INT-022`).

### 4.5 Consent & privacy

- **Consent:** one `guardian_consents` row per guardian per notice version. Child details beyond
  names need the current version (`CONSENT_REQUIRED`). The notice is bn/en legal copy
  (`TODO: Confirm`, which blocks release). Withdrawing consent means self-unlinking (OQ-18).
- **Data minimisation:** guardians see their own child's name, avatar, class, section, class
  teacher name, school notices, the child's invoices and receipts, and co-guardian names. They
  never see the child's chats, DMs, AI scans (08), analytics (09) or other students' data.
- **Transparency for students:** `GET /me/guardians` shows linked guardians (names and
  relations).
- **Masking:** phones are masked in every admin response. Co-guardian phones are never exposed.
  Logs carry ids only.
- **Retention:** revoked links, decided requests and expired invites are kept for audit (no hard
  deletes). The retention period is `TODO: Confirm` with the owner. Deleting a guardian account
  cascades links (existing FK `ON DELETE CASCADE`) after audit.
- **Legal basis:** the applicable Bangladeshi data-protection requirements for minors' data are
  `TODO: Confirm`. Nothing in this plan claims compliance.

---

## 5. Contracts

### 5.1 REST endpoints

All endpoints use tag `guardians`, security `bearerJWT` or `sessionCookie`, responses
`{data: …}` (plus `nextCursor` for pages), `Cache-Control: no-store`, and RFC-7807 errors.

| # | Method · Path | Roles | Purpose | Key errors | Stories |
| --- | --- | --- | --- | --- | --- |
| 1 | `GET /api/v1/guardian/children` | guardian VERIFIED | Children list plus `consentRequired`, `noticeVersion`, `pendingInvites` (G2) | NOT_VERIFIED | US-001/002/005 |
| 2 | `GET /api/v1/guardian/children/{studentId}` | guardian + IsGuardianOf + consent | Child detail | FORBIDDEN, NOT_FOUND, CONSENT_REQUIRED | US-002 |
| 3 | `POST /api/v1/guardian/consent` | guardian | Accept the notice version | VALIDATION_FAILED (stale version) | US-005 |
| 4 | `POST /api/v1/guardian/link-requests` | guardian VERIFIED | Claim another child | CONFLICT, GUARDIAN_LINK_LIMIT, VALIDATION_FAILED, RATE_LIMITED | US-003 |
| 5 | `GET /api/v1/guardian/link-requests` | guardian | My requests | — | US-004 |
| 6 | `POST /api/v1/guardian/link-requests/{id}/cancel` | requesting guardian | Cancel | CONFLICT, NOT_FOUND | US-004 |
| 7 | `POST /api/v1/guardian/links/{linkId}/unlink` | the link's guardian | Self-unlink | NOT_FOUND, CONFLICT | US-016 |
| 8 | `GET /api/v1/me/guardians` | student VERIFIED | My guardians (names only) | — | US-017 |
| 9 | `GET /api/v1/school/guardian-links` | school_admin, super_admin | Links list (filters `studentId`, `guardianId`, `sectionId`, `relation`, `source`, `status`, `q`, cursor, limit ≤ 100) | TENANT_MISMATCH | US-007 |
| 10 | `POST /api/v1/school/guardian-links` | school_admin, super_admin | Link an existing guardian (201) or invite a phone (202, G2) | CONFLICT, GUARDIAN_LINK_LIMIT, VALIDATION_FAILED | US-007/008 |
| 11 | `PATCH /api/v1/school/guardian-links/{id}` | school_admin, super_admin | Relation and/or primary | CONFLICT, NOT_FOUND | US-007 |
| 12 | `POST /api/v1/school/guardian-links/{id}/revoke` | school_admin, super_admin | Revoke with a reason | VALIDATION_FAILED, CONFLICT | US-007 |
| 13 | `GET /api/v1/school/guardian-link-requests` | school_admin, super_admin | Queue with candidates | — | US-006 |
| 14 | `POST /api/v1/school/guardian-link-requests/{id}/approve` | school_admin, super_admin | Approve with `studentUserId` | CONFLICT, VALIDATION_FAILED, GUARDIAN_LINK_LIMIT, TENANT_MISMATCH | US-006 |
| 15 | `POST /api/v1/school/guardian-link-requests/{id}/reject` | school_admin, super_admin | Reject with a reason | CONFLICT, VALIDATION_FAILED | US-006 |
| 16 | `GET /api/v1/school/guardian-invites` | school_admin, super_admin | Invites list (G2) | — | US-008 |
| 17 | `POST /api/v1/school/guardian-invites` | school_admin, super_admin | Create an invite (G2) | CONFLICT, VALIDATION_FAILED, RATE_LIMITED | US-008 |
| 18 | `POST /api/v1/school/guardian-invites/{id}/revoke` | school_admin, super_admin | Revoke an invite (G2) | CONFLICT | US-008 |
| 19 | `POST /api/v1/school/guardian-invites/{id}/resend` | school_admin, super_admin | Resend the SMS (G2) | RATE_LIMITED, CONFLICT | US-008 |
| 20 | `POST /api/v1/guardian/invites/{inviteId}/claim` | guardian whose phone equals the invite phone | Claim an invite (G2) | FORBIDDEN, NOT_FOUND, GUARDIAN_LINK_LIMIT | US-009 |

**Schemas** (new, in `components/schemas`):

- `GuardianRelation` (enum, 10 values) and `GuardianLinkSource` (enum).
- `GuardianChild` = {studentId, fullName, avatarUrl?, relation, isPrimary, linkId,
  school{id,name}, section{id,classLevel,name,sessionYear}|null,
  classTeacher{userId,fullName}|null, dues{count,totalBdt}|null, unreadNotices}.
- `GuardianChildrenResult` = {children: GuardianChild[], consentRequired: boolean,
  noticeVersion: string, pendingInvites: GuardianInviteSummary[]}.
  - Before consent is accepted, `children` carry only studentId, fullName, linkId and relation.
- `GuardianChildDetail` = GuardianChild + {recentNotices: NoticeSummary[≤5],
  openInvoices: PaymentsInvoice[], coGuardians: [{fullName, relation, isPrimary}]}.
- `GuardianConsentInput` = {noticeVersion, locale}.
- `GuardianLinkRequestInput` = {schoolId, sectionId?, studentCode, relation, studentName?}.
- `GuardianLinkRequest` = {id, studentCode, claimedStudentName?, relation, section?, status,
  decisionReason?, createdAt, decidedAt?, studentId?}.
- `GuardianUnlinkInput` = {reason?}.
- `MyGuardian` = {fullName, relation, isPrimary}.
- `GuardianLinkRow` = {id, relation, isPrimary, source, status, createdAt, verifiedByName?,
  revokeReason?, guardian{userId, fullName, maskedPhone, status},
  student{userId, fullName, studentCode?, section{id,classLevel,name}?}}.
- `GuardianLinkCreateInput` = {studentUserId, relation, isPrimary?, guardianUserId? |
  (guardianPhone, guardianName?)}.
- `GuardianLinkPatch` = {relation?, isPrimary?}. `GuardianRevokeInput` = {reason}.
- `GuardianLinkRequestRow` = {id, guardian{userId, fullName, maskedPhone}, studentCode,
  claimedStudentName?, relation, section?, createdAt, reminderCount, candidates: GuardianCandidate[]}.
- `GuardianCandidate` = {studentUserId, fullName, studentCode?, section?,
  matchedBy: student_code|name}.
- `GuardianApproveInput` = {studentUserId}. `GuardianRejectInput` = {reason}.
- `GuardianInvite` = {id, student{userId, fullName}, maskedPhone, guardianName?, relation?,
  source, status, smsSentAt?, expiresAt, createdAt}.
- `GuardianInviteInput` = {studentUserId, phone, guardianName?, relation?, sendSms?}.

**Amended (owned elsewhere):**

- `VerificationRequestItem.guardianCandidates[]` (03).
- `SchoolUser.studentCode?` and `sectionLabel?` (03).
- `RegisterInput.relation` widened, plus `inviteId?` (03).
- `GET /api/v1/payments/invoices` (12).
- `Notice.audience` (05).
- `TuitionRequirementInput.forStudentId?` (10).

### 5.2 Realtime / jobs

| Channel / Job | Trigger | Payload / Work | Consumers | Failure handling |
| --- | --- | --- | --- | --- |
| `guardians.sync_enrollments` | Link create or revoke commit | {guardianId, studentId?, reason} → EnrollmentPort ensure/end, GroupPort (G2), push `guardian_child_placed` when a new enrollment appears | 04, 05 | ×5 retry; nightly reconcile |
| `guardians.request_reminder` | Hourly | Remind the school admins of PENDING requests older than 48 h (max 3) | 06 | Next run |
| `guardians.invite_expiry` (G2) | Hourly | PENDING → EXPIRED | — | Next run |
| `guardians.invite_sms` (G2) | Invite create or resend | Send the SMS template via smsout | 06 smsout | ×5 retry; admin resend |
| `guardians.reconcile_enrollments` | Nightly | Find ACTIVE links of placed children without a GUARDIAN enrollment and fix them | 04 | Log and alert |
| Push `guardian_link_decided` | Approve or reject | {requestId, studentId?, outcome} | app | best-effort |
| Push `guardian_link_revoked` | Revoke | {studentId} | app | best-effort |
| Push `guardian_child_placed` | Enrollment created | {studentId, sectionId} | app | best-effort |

There is no WebSocket channel of our own.

### 5.3 Exported service functions

| Export | Callers | Returns | Throws |
| --- | --- | --- | --- |
| `LinkedStudents` *(frozen)* | 04, 12 | `[]StudentRef` | db |
| `GuardiansOf` *(frozen)* | 04, 05, 12 | `[]uuid.UUID` | db |
| `IsGuardianOf` *(frozen)* | 05, 10, 12 | `bool` | db |
| `ChildrenOf` | 05, 16 | `[]ChildRef` | db |
| `ListGuardiansOfStudents` | 12 | `map[student][]guardian` | db |
| `IsLinked` | 05 policy | `bool` | db (callers fail closed) |
| `CandidatesFor` | 03, 16 | `[]Candidate` | problem |
| `CreateInvitesFromRoster` (G2) | 14 | result counts | problem |
| `RevokeAllForStudent` | 03 | — | db |

---

## 6. Client Surfaces

### 6.1 Web (detail in `04-frontend-tasks.md`)

| Route | Screen | Rendering | Access |
| --- | --- | --- | --- |
| `/institution/guardians` (`?tab=links\|requests\|invites`) | Links, link-request queue, invites (G2) | Client component in the 07 shell | School Admin, Super Admin |
| `/institution/users` | Guardian evidence plus `MatchStudentDialog` on approve (G0) | Client | School Admin, Super Admin |
| `/institution/sections/[sectionId]` | Guardian count plus a link (optional) | Client | School Admin, Super Admin |

### 6.2 Mobile (detail in `05-app-tasks.md`)

| Route | Screen | Deep link | Offline behaviour |
| --- | --- | --- | --- |
| `/(tabs)/feeds` (guardian) | Guardian home plus child switcher | — | In-memory cache with a banner |
| `/children` | My children, requests, invites | `guardian_link_decided` | Same |
| `/children/[studentId]` | Child hub: Overview, Notices, Fees, Chat (attendance and results flag-hidden) | `guardian_link_decided`, `guardian_child_placed` | Cached detail; actions disabled |
| `/children/add` | Link request form | — | Submit refused offline |
| `/children/requests` | Request statuses, cancel | `guardian_link_decided` (rejected) | Read cache |
| `/(modals)/guardian-consent` | Privacy notice | opened by `CONSENT_REQUIRED` | Refused offline |
| `/payments?studentId=` | Fees with a child filter (payer-scoped list) | `payments_fee_due` | 12 rules |
| `/me/guardians` (student) | My guardians | — | Read cache |

---

## 7. External Integrations

| System | Purpose | Protocol | Secret | Timeout / retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| FCM (through 06) | Decision, revocation and placement pushes; fee-due fan-out (12) | HTTPS | 06's `FCM_SERVICE_ACCOUNT_JSON` | 06 policy | In-app state stays correct |
| SMS gateway (through `internal/smsout`) | Guardian invite SMS (G2, opt-in) | HTTPS | existing smsout env | ×5 job retry | Invite without SMS; manual resend |

---

## 8. Configuration

### 8.1 Environment variables

None new. FCM and SMS use the existing 06/03 variables.

### 8.2 Runtime config — the two lists

| Admin-changeable (later) | Fixed in code |
| --- | --- |
| Per school: SMS invites on/off (default off) | Caps 4 guardians per student and 8 children per guardian; invite expiry 30 d; request SLA 48 h, reminders every 24 h, max 3 |
| Per school (G2): guardian group post policy default | Relation, source and status enums; masking rule; push payload keys |
| Platform: `guardian.academic_records` flag (default off) | `GUARDIAN_NOTICE_VERSION` plus bn/en notice copy (`TODO: Confirm`) |
| | Rate limits: link requests 10/day per guardian; invite resend 3/day; invites 200/day per school |

---

## 9. Security & Tenancy

| Concern | Rule |
| --- | --- |
| Auth chain | authenticate → load role claims → tenant scope. Services authorise at entry (`principal.RequireRole`, `RequireSchool`, VERIFIED). Console mutations use `consoleCSRF`. |
| Role matrix | Guardian (VERIFIED): own children, own requests, own links, consent, claim own-phone invites. Student (VERIFIED): `/me/guardians` read-only. school_admin: all `/school/guardian-*` for own school. super_admin: same with `?schoolId=`. Teacher and ambassador: no link decisions (OQ-1). Pending: nothing. |
| Tenant scope | Every table has `school_id`, and every query filters by the claim school. Cross-tenant ids give 404 (`TENANT_MISMATCH` semantics). Guardian, student and link must share the school. |
| Rate limits | Default class for reads, plus the caps in §8.2 |
| Audit events | `guardian_link.created`, `.updated`, `.revoked`; `guardian_link_request.created`, `.approved`, `.rejected`, `.cancelled`; `guardian_invite.created`, `.revoked`, `.resent`, `.claimed`; `guardian_consent.accepted`. Each is written in the same tx (`audit.Record`). |
| Privacy / minors | Privacy matrix below. Consent gate. Masked phones. Push payloads carry ids only. SMS without child PII. Guardians never reach non-linked minors (DM policy). |

**Privacy matrix**

| A VERIFIED guardian with an ACTIVE link **may** | A guardian **may never** |
| --- | --- |
| Read the child's name, avatar, class, section and session, the class teacher's name, and co-guardian names and relations | Read the child's chats, DMs, AI scans (08) or analytics (09) |
| Read school notices and the child's section notices (audience `all` or `guardians`) | See other students' data or other families' invoices |
| View, pay and get receipts for the child's invoices | See co-guardian phones (always masked) |
| Post tuition requirements (optionally for a child, G2); buy in commerce | DM or message-request non-linked students |
| DM same-school staff and their own children; read the guardian group (G2; posting per post policy) | See links, guardians or students of another school |

**Child safety:** the G0 policy (`GRD-INT-005`) and adult-only link decisions (`GRD-INT-006`)
must ship before guardian onboarding grows beyond the pilot schools.

---

## 10. Error Handling

| Code | Meaning | When this module returns it | Client handling |
| --- | --- | --- | --- |
| `UNAUTHENTICATED` | No or invalid session | Any endpoint | Re-login |
| `NOT_VERIFIED` | Account is PENDING | `/guardian/*`, `/me/guardians` | Pending screen |
| `FORBIDDEN` | Wrong role, not linked, or ambassador or teacher deciding | Child detail of a non-linked child; admin endpoints for non-admins; claim with a phone mismatch | Message, then back |
| `TENANT_MISMATCH` (404) | Cross-school id | Admin or guardian on another school's rows | Generic not-found |
| `NOT_FOUND` | Missing, expired or revoked resource | Request, link or invite ids | Refresh the list |
| `VALIDATION_FAILED` | Bad input, stale notice version, or another school while single-school | All writes | Field errors |
| `CONFLICT` | Duplicate pending request, already linked, already decided, concurrent primary, phone used by another role | Writes | Refetch and explain |
| `RATE_LIMITED` | Caps in §8.2 | Link request, invite create and resend | Countdown |
| `GUARDIAN_LINK_LIMIT` (409, **new**, register in 01 §10) | 4 guardians per student or 8 children per guardian reached | Request create, approve, admin link, claim | Limit copy |
| `CONSENT_REQUIRED` (403, **new**, register in 01 §10) | Current guardian notice not accepted | Child detail | Open the consent modal |

Messages resolve through the app and web `src/i18n` catalogs (bn default, en). Server-rendered
copy for pushes and SMS lives in `internal/i18n`.

---

## 11. Observability & Operations

| Concern | Detail |
| --- | --- |
| Logging | slog fields `guardian_id`, `student_id`, `link_id`, `request_id`, `invite_id`, `school_id`. Never phones or names. Add `phone_e164` to the redaction list for this package. |
| Metrics / counters | Pending requests and the oldest age per school; links created by source; revocations per week; invites claimed vs expired; `sync_enrollments` failures; reconcile fixes per night (should trend to 0) |
| Health contribution | None (no new `/readyz` dependency) |
| Jobs & retries | 5 jobs (§5.2). Retry ×5 with backoff (01 jobs). Failed jobs stay in `jobs` for inspection. |
| Runbook pointers | Gate 2: the owner runs the `grd_*` migrations in version order. Rollback order: G2 then G1 down files (lossy notes in `03` §1.2). Wrong-link incident: revoke via the console, then check `audit_log` for the approver. |

---

## 12. Testing

| Layer | Coverage | IDs | Gate |
| --- | --- | --- | --- |
| Unit | Matching, caps, same-school, enums and reasons, masking, consent, invite guard, SMS template, push payloads, enrollment-follow plan, DM policy matrix, fee fan-out recipients, migration planner | `GRD-UT-001…013` | Agent-run (`go test`, `npx vitest run`, `npx jest`) |
| Integration | Auth, roles, cross-tenant, approve tx, concurrency, revoke and enrollment, invite claim, consent gating, migrations up/down, invoice role gate, late placement, ambassador refusal, notices via enrollments | `GRD-IT-001…014` | Written by the agent, **run by the owner** (testcontainers) |
| E2E | Web approve and revoke; app add child → approve → pay | `GRD-E2E-001…002` | Run by the owner (Playwright, Maestro) |
| CI | `make lint`, `go vet` (plus `-tags integration`), `make contracts-check`, web `tsc` (agentcheck config), eslint, vitest, app `tsc`, eslint, jest | — | Each touched repo |

Mandatory: unauthenticated calls denied; validation rejects bad input; cross-tenant attempts
return 404. There is no publish guard or public read in this module.

---

## 13. Performance

| Concern | Budget / detail |
| --- | --- |
| Expected volumes | Pilot: about 2,400 links per school; about 200 requests and about 1,000 invites per school per year |
| Hot paths + indexes | Children by guardian `(guardian_user_id,status)`; admin list cursor `(school_id,created_at,id)`; queue `(school_id,status,created_at)`; fan-out batch `(student_user_id,status)` |
| Latency targets | `GET /guardian/children` p95 < 300 ms (batched ports, 500 ms port timeout with degrade); admin lists p95 < 250 ms |
| Bundle / payload impact | No new dependencies in web or app. The children payload is about 1 KB per child. |
| Caching | None server-side (`no-store`, personal data). Client query cache only. |

---

## 14. Risks & Open Questions

**Findings in current code** (read-only survey, 2026-10-19). Each one drives a G0 task.

| # | Item | Impact | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- | --- |
| R-1 | `GET /api/v1/school/invoices` has no role gate (`internal/payments/handler.go` `ListSchoolInvoices` checks only `caller.SchoolID`). The app uses it as "my invoices" (`applications/app/src/lib/payments/live.ts`). | Any school member, including students and guardians, can read every family's invoices | Rahul / 12 | Open | Fix first (`GRD-INT-001`, P0) |
| R-2 | `chat.DirectAllowed` (`internal/chat/dm.go`) allows instant DM between any verified users of the same school. Guardians are plain members of the students' section group (`chat/exports.go` `JoinSectionGroups`). Contact search lists the whole school. | Adults can reach any minor directly | Rahul / 05 | Open | `GRD-INT-005` before scaling |
| R-3 | Student Ambassadors (minors) may approve guardian requests (`internal/verification/verification.go`, the ambassador branch allows `guardian`) | Minors create durable adult–child links | Rahul / 03 | Open (OQ-1) | Exclude (`GRD-INT-006`) |
| R-4 | A guardian verified before the child is placed: `enrollGuardian` returns `NOT_FOUND`, provisioning fails ×5, and nothing re-triggers. The year-end migration moves STUDENT enrollments only. | Guardians silently miss notices and topics | 04 | Open | `GRD-INT-004` |
| R-5 | Fee-due push goes to the student only (12 G-7) | The primary payer is never told | 12 | Open | `GRD-INT-002` |
| R-6 | Web guardian approval sends no `studentUserId`, and there is no student code anywhere to match | Guardian approvals fail once live; name matching risks wrong links | 07 / 03 | Open | `GRD-INT-003`, `GRD-INT-008` |
| R-7 | `chat.JoinSectionGroups` compares `enrollment.Role == "teacher"` while hierarchy roles are uppercase (`TEACHER`/`CLASS_TEACHER`) | Teachers may join as plain members (unverified) | 05 | Open | Verify and fix in `GRD-INT-005` |
| R-8 | One school and one role per user, plus globally unique phones | Families across two schools, or staff who are parents, get `CONFLICT` | Rahul / 03 | Open (OQ-5) | G3 ADR |
| R-9 | Relation enum change ripples across three repos | Contract drift | 16 | Open | `GRD-INT-007` sequencing |
| R-10 | SMS and push volume increase (fan-out about ×2.6) | Cost | Rahul | Open (OQ-14) | SMS opt-in, off |
| R-11 | Attendance and results expectations | Scope creep with minors' academic data | Rahul | Open (OQ-11) | Out of scope |
| R-12 | Import cycle (hierarchy → guardians) | Build break | 16 | Mitigated by design | Ports only |
| R-13 | Web console still on fixtures | Gate 3 for web flows waits on 07 glue | 07 | Open | Fixture seam first |

**Open questions:** OQ-1 … OQ-18 in `01-user-stories.md` §9 (link deciders, invite auto-verify,
guardian groups, DM details, multi-school, student code storage, relations and primary, phone-less
students, caps, unlink rights, attendance and results, Auto-CT sharing, ad audience, SMS cost,
notice audiences, tuition per child, web sign-up, consent copy). Each has a stated default.

---

## 15. Traceability

| BR (`brd.md` §5) | PRD § | Stories | Tasks | Tests |
| --- | --- | --- | --- | --- |
| BR-01 Community (auto-grouping and year-end migration) | §2, §4B, §5.1 | US-001, 002, 012, 014, 015 | BE-021/022/040/044, AP-003…006/011, INT-004/010/014 | UT-010/013, IT-007/012/014 |
| BR-01 (verified participation), brd §3 Guardians | §5.1 | US-003, 004, 006, 007, 008, 009, 010, 016, 017 | BE-001…005, 024…034, FE-001…010, AP-007/008/013/015, INT-003/006/008/015/017 | UT-001…004/007, IT-003…006/008/013, E2E-001 |
| brd §3 (fees), PRD §5.4 | §2, §5.4 | US-011 | AP-010, INT-001/002/011 | UT-012, IT-011, E2E-002 |
| brd §4 role-based access; privacy (`prompt.txt` §12) | §5.1 | US-005, 013 | BE-023/036, AP-009, INT-005/009 | UT-005/006/008/009/011, IT-009 |
| BR-03 Tuition | §5.3 | US-018 | INT-018 | — |
| — (needs owner decision) | — | US-019 | INT-020 | — |

---

## 16. Phased Rollout

| Phase | Content | Owner modules | New tables | Exit criteria |
| --- | --- | --- | --- | --- |
| **G0 — hardening** (before any wider guardian rollout) | (a) invoice role gate plus payer list; (b) fee-due fan-out; (c) web guardian approve with the student picker; (d) guardian enrollment follows the child; (e) guardian DM and contacts policy; (f) no ambassador guardian decisions (OQ-1) | 12, 12, 03+07, 04, 05, 03 (`GRD-INT-001…006`) | none | A guardian sees only their children's invoices and gets the fee-due push; cannot DM a non-linked student; keeps notices after the child's promotion |
| **G1 — core guardian experience** (module 16 build) | `student_code`; links v2; link requests; consent; guardian children APIs; admin links console and request queue; app home, switcher, hub, add-child, requests; student "My guardians"; decision pushes; relation widening | 16 (+03/04/05/06/07/12 ports) | `guardian_link_requests`, `guardian_consents`; `guardian_links` v2; `users.student_code` | A guardian links a 2nd child via request → admin approves with a code-matched candidate → the child appears with notices and fees |
| **G2 — community and onboarding at scale** | Guardian section groups and post policy; notice audiences and guardian topics; invites (admin, roster, LMS) with OTP auto-link; SMS invites; tuition `forStudentId` | 16, 05, 06, 04, 14, 10 | `guardian_invites`; audience, post-policy and topic amendments | A roster upload invites guardians who join pre-linked; a parents'-meeting notice reaches guardians only |
| **G3 — later** | Multi-school guardians; staff who are parents; phone-less managed students; academic records module (attendance and results); Auto-CT sharing (08); SMS fallback for critical alerts | 03, new 17, 14, 08 | per ADR | Owner decisions first |

---

## 17. Change Log

| Date | Change | Author |
| --- | --- | --- |
| 2026-10-19 | Module planned (owner: "also plan for student's guardian"): spec set from `_TEMPLATE`, ID prefix `GRD`, README row added as planned. Docs only; no code, migrations or runs. | Agent (planning run) |

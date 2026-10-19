# Guardian Experience — Integration Tasks

**Module:** `16-guardian-experience` · **Last updated:** 2026-10-19

> **Status: planned, not built.** This file is the contract. No cross-module call, cache key or
> external dependency may exist in code unless it is declared here (`docs/prompt/prompt-build.md`
> §6).
>
> Phase G0 is mostly amendments **inside other modules' packages** (03/04/05/07/12). They are
> tracked here (`GRD-INT-001…006`) so that one list owns the guardian rollout. Each is built in
> the owning module's run, and that module's `03`/`06` docs are updated in the same change.

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | 03 identity-access | they call us | `guardians.Link` inside the verification approve tx *(exists)*; `guardians.CandidatesFor` for `guardianCandidates` in the queue decorate (new) | fatal for the approve tx (same tx) |
| I-2 | 03 identity-access | we call them | User display reads (sqlc joins inside `guardians`, a 03 package), the OTP-proof check for invite claims (G2), `RegisterInput.inviteId` handling (G2) | fatal (request fails) |
| I-3 | 04 organization-hierarchy | we call them | `EnrollmentPort` injected from `main.go`: `EnsureGuardianEnrollments`, `EndGuardianEnrollment`, `ChildPlacements(studentIDs)` (new 04 exports) | degraded. The job retries and the nightly reconcile catches the rest. |
| I-4 | 04 organization-hierarchy | they call us | `hierarchy` calls `guardians.LinkedStudents` *(exists)* and `guardians.GuardiansOf` (new use: on student verify/place and during migration) | fatal for that 04 job run (retried) |
| I-5 | 05 communication-engine | we call them | `GroupPort` (`JoinGuardianGroups` / `LeaveGuardianGroups`, G2), `NoticesPort` (`RecentNotices(sectionIDs, schoolID, limit)`, `UnreadCounts`) | degraded (hub shows no notices section) |
| I-6 | 05 communication-engine | they call us | `GuardianPolicy` used by `DirectAllowed` and `SearchContacts`: `guardians.IsLinked(guardianID, studentID)` and `guardians.ChildrenOf(guardianID)` | fatal for that DM attempt. **Fail closed:** deny when the lookup errors. |
| I-7 | 06 notifications | we call them | `Notifier.SendToUser(userID, type, data)` for `guardian_link_decided`, `guardian_link_revoked`, `guardian_child_placed`; `SMSSender.Send` (smsout) for invites (G2) | degraded, never fatal |
| I-8 | 12 payments | we call them | `DuesPort.DuesSummary(studentIDs)` and `OpenInvoices(studentID)` | degraded (`dues: null`) |
| I-9 | 12 payments | they call us | `GuardiansOf` / `ListGuardiansOfStudents` (fee-due fan-out, G0), `IsGuardianOf` *(exists)* (entitlement and receipts) | fan-out degraded (student still pushed); entitlement fatal (fail closed) |
| I-10 | 14 lms-erp-sync | they call us | `guardians.CreateInvitesFromRoster(ctx, schoolID, []RosterGuardian)` (G2), `users.SetStudentCode` (03 export) | degraded (import report lists failed invites) |
| I-11 | 10 tuition-marketplace | they call us | `IsGuardianOf` for `forStudentId` (G2) | fatal for that post (FORBIDDEN) |
| I-12 | 07 command-center-web | UI | Console shell, `INSTITUTION_NAV`, `/institution/users` (web) | n/a |
| I-13 | api → app | we notify | FCM directed pushes (via 06). The app invalidates `['guardian', …]` on tap. | degraded |
| I-14 | SMS gateway (via 06 `smsout`) | outbound | HTTPS (existing adapter) | degraded; retried |

## 2. Exported Contract

```text
// frozen (03 06 §2) — signatures unchanged
guardians.LinkedStudents(ctx, guardianID uuid.UUID) ([]StudentRef, error)          // StudentRef{UserID, SchoolID, Relation}
guardians.GuardiansOf(ctx, studentID uuid.UUID) ([]uuid.UUID, error)
guardians.IsGuardianOf(ctx, guardianID, studentID uuid.UUID) (bool, error)

// new (16, additive)
guardians.ChildrenOf(ctx, guardianID uuid.UUID) ([]ChildRef, error)                // ChildRef{UserID, SchoolID, Relation, IsPrimary, LinkID}
guardians.ListGuardiansOfStudents(ctx, studentIDs []uuid.UUID) (map[uuid.UUID][]uuid.UUID, error)
guardians.IsLinked(ctx, guardianID, studentID uuid.UUID) (bool, error)             // alias of IsGuardianOf for the 05 policy port
guardians.CandidatesFor(ctx, schoolID uuid.UUID, code, name string, sectionID *uuid.UUID) ([]Candidate, error)
guardians.CreateInvitesFromRoster(ctx, schoolID uuid.UUID, rows []RosterGuardian) (InviteImportResult, error) // G2
guardians.RevokeAllForStudent(ctx, studentID uuid.UUID, reasonKey string) error    // 03 user removal path
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| `LinkedStudents` | 04 enrollGuardian, 12 | `[]StudentRef` | db errors | frozen |
| `GuardiansOf` | 04, 05, 12 | `[]uuid.UUID` | db errors | frozen |
| `IsGuardianOf` | 12 entitlement, 10, 05 | `bool` | db errors | frozen |
| `ChildrenOf` | 05 contacts, 16 home | `[]ChildRef` | db errors | new |
| `ListGuardiansOfStudents` | 12 fee-due fan-out (bulk) | map | db errors | Batched; avoids N+1 |
| `IsLinked` | 05 `DirectAllowed` policy | `bool` | db errors | Callers fail closed |
| `CandidatesFor` | 03 verification decorate, 16 queue | `[]Candidate{StudentUserID, FullName, StudentCode?, Section?, MatchedBy}` | `problem` (tenant) | Admin-only callers. Caller's school is asserted. |
| `CreateInvitesFromRoster` | 14 import commit, LMS pull | counts plus per-row errors | `problem` | G2. Runs in 14's chunk tx. |
| `RevokeAllForStudent` | 03 user deletion | — | db errors | System actor; audited |

Rules: exports return DTOs, never sqlc rows. Admin-only exports check role claims in the
context. Services return domain errors, mapped at the handler. Signature changes are additive
first.

**Ports consumed by `guardians`, injected in `cmd/api/main.go`.** These avoid the import cycle,
because `hierarchy` already imports `guardians`.

```text
type EnrollmentPort interface {
    EnsureGuardianEnrollments(ctx, guardianID uuid.UUID) error
    EndGuardianEnrollment(ctx, guardianID, studentID uuid.UUID) error
    ChildPlacements(ctx, studentIDs []uuid.UUID) (map[uuid.UUID]Placement, error) // section, class, session, class teacher
}
type GroupPort   interface { JoinGuardianGroups(ctx, guardianID uuid.UUID) error; LeaveGuardianGroups(ctx, guardianID, sectionID uuid.UUID) error } // G2
type NoticesPort interface { RecentForSections(ctx, schoolID uuid.UUID, sectionIDs []uuid.UUID, limit int) ([]NoticeSummary, error); UnreadCounts(ctx, userID uuid.UUID, sectionIDs []uuid.UUID) (map[uuid.UUID]int, error) }
type DuesPort    interface { DuesSummary(ctx, studentIDs []uuid.UUID) (map[uuid.UUID]Dues, error); OpenInvoices(ctx, studentID uuid.UUID) ([]InvoiceSummary, error) }
type Notifier    interface { SendToUser(ctx, userID uuid.UUID, pushType string, data map[string]string) error }
type SMSSender   interface { Send(ctx, phoneE164, templateKey string, vars map[string]string) error } // G2
```

The adapters in `main.go` translate the plain types into the owners' own types. For example,
`Notifier` builds `notify.Payload` for the existing `(*notify.Service).SendToUser(ctx, userID,
payload)`, and `SMSSender` wraps the existing `internal/smsout` gateway and templates.

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| `hierarchy.EnsureGuardianEnrollments` / `EndGuardianEnrollment` / `ChildPlacements` (new 04 exports) | 04 | Retry via `guardians.sync_enrollments`; reconcile nightly |
| `chat` notices read (`RecentForSections`, `UnreadCounts`), guardian groups (G2) | 05 | Hub notices section shows retry; no failure of the children list |
| `notify.SendToUser` (existing 06 export), new push types | 06 | Logged; the Requests list is the source of truth |
| `smsout` send (existing adapter) | 06 | Retry ×5; admin "SMS not sent" |
| `payments` dues summary and open invoices (new 12 exports) | 12 | `dues: null` |
| `users` display reads, `SetStudentCode`, OTP proof check | 03 | Request fails (fatal) |

## 4. Cache-Tag Contract

The api has no server-side cache for guardian data; every response is `no-store`. These are the
client query keys:

| Mutation | Revalidates |
| --- | --- |
| link request create / cancel | app `['guardian','link-requests']` |
| consent accept | app `['guardian','children']` |
| unlink / invite claim | app `['guardian','children']`, `['guardian','child',id]`, `['payments','invoices']` |
| admin approve / reject request | web `['school','guardian-link-requests']`, `['school','guardian-links']` |
| admin create / edit / revoke link | web `['school','guardian-links']` (+ sheet keys) |
| admin invite create / revoke / resend | web `['school','guardian-invites']` |
| push `guardian_link_decided` / `guardian_link_revoked` / `guardian_child_placed` received | app `['guardian','children']`, `['guardian','link-requests']` |

| Read | Tagged with |
| --- | --- |
| `GET /guardian/children` | `['guardian','children']` |
| `GET /guardian/children/{id}` | `['guardian','child',id]` |
| `GET /guardian/link-requests` | `['guardian','link-requests']` |
| `GET /payments/invoices?studentId=` (12) | `['payments','invoices',{studentId}]` |
| `GET /school/guardian-links` | `['school','guardian-links',filters]` |
| `GET /school/guardian-link-requests` | `['school','guardian-link-requests',status]` |
| `GET /school/guardian-invites` | `['school','guardian-invites',status]` |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| FCM (via 06) | HTTPS | `FCM_SERVICE_ACCOUNT_JSON` (06) | 06 default | 06 policy | No push; in-app state still correct |
| SMS gateway (via 06 `smsout`, G2) | HTTPS | existing smsout env (03/06) | smsout default | ×5 job retry | Invite exists without SMS; resend |

There is no new environment variable. The notice version is a code constant, and SMS opt-in is
a per-school setting (later).

## 6. UI ↔ Server Seam

| UI element | Calls | Contract |
| --- | --- | --- |
| App `GuardianHome`, `ChildSwitcher` | `GET /api/v1/guardian/children` | `GuardianChildrenResult` |
| App child hub | `GET /api/v1/guardian/children/{studentId}` | `GuardianChildDetail` |
| App consent modal | `POST /api/v1/guardian/consent` | `GuardianConsentInput` |
| App add child / requests | `POST`/`GET /api/v1/guardian/link-requests`, `POST …/{id}/cancel` | `GuardianLinkRequestInput`, `GuardianLinkRequest` |
| App unlink | `POST /api/v1/guardian/links/{linkId}/unlink` | `GuardianUnlinkInput` |
| App invite claim (G2) | `POST /api/v1/guardian/invites/{inviteId}/claim` | `GuardianChild` |
| App student "My guardians" | `GET /api/v1/me/guardians` | `MyGuardian[]` |
| App payments | `GET /api/v1/payments/invoices?studentId=` (12) | `PaymentsInvoice[]` + totals |
| Web links tab, sheet, dialogs | `/api/v1/school/guardian-links` (GET, POST), `/{id}` PATCH, `/{id}/revoke` | `GuardianLinkRow`, `GuardianLinkCreateInput`, `GuardianLinkPatch`, `GuardianRevokeInput` |
| Web requests tab, `MatchStudentDialog` | `/api/v1/school/guardian-link-requests` (GET), `/{id}/approve`, `/{id}/reject` | `GuardianLinkRequestRow`, `GuardianApproveInput`, `GuardianRejectInput` |
| Web invites tab (G2) | `/api/v1/school/guardian-invites` (GET, POST), `/{id}/revoke`, `/{id}/resend` | `GuardianInvite`, `GuardianInviteInput` |
| Web `/institution/users` guardian approve (G0) | `POST /api/v1/verification-requests/{id}/approve` (03) | `ApproveInput.studentUserId` *(exists)* + `VerificationRequestItem.guardianCandidates` (new) |

## 7. Contract Stability

- **The relation enum widening is the one breaking-shaped change.** Sequence it as follows:
  1. api accepts the new values (DB CHECK and OpenAPI enum) while still emitting only old values
     to old clients. (There are no stored new values until a client sends one.)
  2. web and app sync the spec, regenerate, and widen `RELATIONS` and the i18n keys.
  3. Run `make contracts-check` and both clients' `contracts:check`.
- **Everything else is additive:** new paths, new optional fields (`guardianCandidates`,
  `studentCode`, `audience`, `forStudentId`, `inviteId`) and new push types.
- **The `GET /school/invoices` role gate is a behaviour change.** It ships in the same release
  as the app's switch to `GET /payments/invoices` (`GRD-INT-001`). Otherwise guardians and
  students lose their fee list.

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| 04 enrollment port | Links, children list, fees | Child hub notices may lag; no new topics | Job retry; nightly reconcile |
| 05 notices port | Children list, fees, chat | "Notices unavailable — retry" in the hub | Retry |
| 05 policy lookup error | Everything except new DMs to students | DM refused (fail closed) | Retry later |
| 06 push / SMS | All in-app flows | No push; "SMS not sent" badge (admin) | Retry, resend |
| 12 dues port | Children list, hub | Dues "—" | Retry |
| Postgres | Nothing | Error state with retry | 15 runbooks |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `GRD-UT-011` | 05 `DirectAllowed` v2 matrix: guardian ↔ staff instant; ↔ own child instant; ↔ other guardian request; ↔ non-linked student blocked (also via request); policy error → deny | Unit (05 package) | `GRD-BR-009` |
| `GRD-UT-012` | 12 fee-due fan-out recipients = student + `ListGuardiansOfStudents` | Unit (12 package) | `GRD-BR-016` |
| `GRD-UT-013` | 04 migration plan: GUARDIAN enrollments move with the promoted child, stay when a sibling remains, end on graduation | Unit (04 pure planner) | `GRD-US-015` |
| `GRD-IT-011` | `GET /school/invoices` as student or guardian → `FORBIDDEN`; `GET /payments/invoices` returns only own and linked-children invoices | Integration, pending owner run | `GRD-INT-001` |
| `GRD-IT-012` | Guardian verified before child placement: provision succeeds; placing the child creates the GUARDIAN enrollment and topics | Integration, pending owner run | `GRD-INT-004` |
| `GRD-IT-013` | Ambassador approving a guardian verification request → `FORBIDDEN` | Integration, pending owner run | `GRD-INT-006` |
| `GRD-IT-014` | `ListNotices` for a guardian resolves sections from GUARDIAN enrollments (no group membership) | Integration, pending owner run | `GRD-INT-010` |
| `GRD-E2E-001` | Web: admin approves a link request with a code-matched candidate, then revokes it | Playwright, run by the owner | `GRD-US-006/007` |
| `GRD-E2E-002` | App: guardian adds a child → (admin approves) → child appears → pays a due → receipt | Maestro, run by the owner | `GRD-US-001/003/011` |

## 10. Task Checklist

> Status on 2026-10-19: planned, not built. "Owner module" is where the code lives. 16 tracks it.

### G0 — hardening (no new tables; prerequisite for any wider guardian rollout)

- [ ] `GRD-INT-001` **(12, P0, security)** Role-gate `GET /api/v1/school/invoices` to school_admin and super_admin. Add the payer-scoped `GET /api/v1/payments/invoices?studentId&status` (own invoices plus `IsGuardianOf` children). Switch the app (`src/lib/payments/live.ts`) in the same release. Update 12 `03`/`technical-document`.
- [ ] `GRD-INT-002` **(12)** Fee-due fan-out to `ListGuardiansOfStudents` plus the student (closes 12 G-7). Receipts readable by any ACTIVE guardian of the invoice's student.
- [ ] `GRD-INT-003` **(03 + 07)** `VerificationRequestItem.guardianCandidates` (via `guardians.CandidatesFor`) and evidence on guardian rows. Web `/institution/users` approves with `studentUserId` (`GRD-FE-010`).
- [ ] `GRD-INT-004` **(04)** Guardian enrollment follows the child: `enrollGuardian` returns success when no child is placed; student verify or placement runs `EnsureGuardianEnrollments` for `GuardiansOf(student)`; the year-end migration moves or ends GUARDIAN enrollments. New exports `EnsureGuardianEnrollments`, `EndGuardianEnrollment`, `ChildPlacements`.
- [ ] `GRD-INT-005` **(05)** Guardian DM and contacts policy (`GuardianPolicy` port, `GRD-BR-009`). `SearchContacts` for guardians returns staff, own children and the class teachers of the children's sections. Also verify the suspected case mismatch in `JoinSectionGroups` (`enrollment.Role == "teacher"` vs hierarchy's `TEACHER`/`CLASS_TEACHER`) and fix it in 05 if confirmed.
- [ ] `GRD-INT-006` **(03, owner decision OQ-1)** Ambassadors excluded from guardian verification decisions. The ambassador queue scope drops `guardian` (`verification_requests.sql`).

### G1 — core guardian experience (module 16)

- [ ] `GRD-INT-007` **(03 + web + app)** Relation enum widening as one contract change (DB CHECK in `GRD-BE-002`, `RegisterInput.relation`, `RELATIONS` in both clients, `auth.relation.*` keys)
- [ ] `GRD-INT-008` **(03)** `users.student_code` (`GRD-BE-001`), `SchoolUser.studentCode` and `sectionLabel`, and the student search used by the pickers
- [ ] `GRD-INT-009` **(06)** Register push types `guardian_link_decided`, `guardian_link_revoked` and `guardian_child_placed` (preference class `account`), with bn/en copy in `internal/i18n` and app routing
- [ ] `GRD-INT-010` **(05)** `ListNotices` resolves sections from STUDENT and GUARDIAN enrollments instead of group membership. Prerequisite for G2 group moves.
- [ ] `GRD-INT-011` **(04/05/12)** Implement the read ports for 16: `ChildPlacements` (04), `RecentForSections` and `UnreadCounts` (05), `DuesSummary` and `OpenInvoices` (12)
- [ ] `GRD-INT-012` **(07)** Console nav entry plus route stub (`GRD-FE-002`, `GRD-FE-003`)
- [ ] `GRD-INT-013` **(registries)** Register error codes `GUARDIAN_LINK_LIMIT` and `CONSENT_REQUIRED` in 01 `technical-document.md` §10. Add the app namespace `guardian` to 02 §1.1. Update the README migration-version registry when versions are stamped.

### G2 — community and onboarding at scale

- [ ] `GRD-INT-014` **(05/06/04)** Notice audience (`all`/`students`/`guardians`), guardian topics (`SECTION_GUARDIANS`, `SCHOOL_GUARDIANS`), guardian section groups with `post_policy`, and the membership data migration (owner decision OQ-3)
- [ ] `GRD-INT-015` **(14)** Roster template optional columns `student_code`, `guardian_name`, `guardian_phone` and `guardian_relation`. The LMS mapping consumes `student_code` and `guardian_phone`, and both call `guardians.CreateInvitesFromRoster`.
- [ ] `GRD-INT-016` **(06 smsout)** SMS invite template (school name plus download link only), per-school opt-in, and caps
- [ ] `GRD-INT-017` **(03, owner decision OQ-2)** Invite claim during registration: optional `RegisterInput.inviteId` with OTP proof; auto-verify only if approved
- [ ] `GRD-INT-018` **(10)** Optional `forStudentId` on `POST /tuition/requirements` (IsGuardianOf, prefill class level), and fix `posterRoleFor` to store the caller's real role

### G3 — later (design or owner decisions only)

- [ ] `GRD-INT-019` **(03, ADR)** Multi-school guardians and staff who are also parents: per-link tenancy, `Principal` children and schools context, payments entitlement per invoice school
- [ ] `GRD-INT-020` **(new module, owner decision OQ-11)** `17-academic-records` (attendance and results) plus a 14 LMS extension. 16 supplies only the hub slot.
- [ ] `GRD-INT-021` **(13, OQ-13)** Guardian audience decision (stay excluded by default)
- [ ] `GRD-INT-022` **(03, OQ-8)** Phone-less managed student profiles
- [ ] `GRD-INT-023` **(docs sync)** Mark 03 OQ-3 and 04 OQ-4 resolved (defaults implemented). Tick the 03 IDT-BE-006a and IDT-BE-033 checkboxes if the owner confirms the existing code. Add cross-references from 03/04/05/06/12/14 to this module.

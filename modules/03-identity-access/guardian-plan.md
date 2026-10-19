# Plan — Student's Guardian (module 03 extension)

Owner instruction 2026-10-19 · planning deliverable (no code in this run) · precedence §1.1 #1
Status: DRAFT for owner decision · depends on 03 (identity/OTP/roles) + 04 (hierarchy) + 06 (push)

## 0. Current state (what exists today)

- `users.role` already carries `guardian` (principal.Role, users_role_chk) — the identity layer
  recognises guardians but nothing onboards or links them.
- `hierarchy.Enrollment` seats a user in a section with a role — a guardian can technically be
  enrolled, but there is no **link to a specific student** and no consent trail.
- OTP phone sign-in (`03` §5) is guardian-ready: a guardian needs only a phone, not an email.
- Chat `official` section groups already follow section enrollment (`05` COM-BE-013) — a linked
  guardian would land in the right rooms automatically once enrolled.
- Notices fan out per section topic (`06` NTF topics) — guardians receive what the section
  receives once enrolled; student-specific events (results, fees) need a per-student link.

## 1. Goal

A parent/guardian sees exactly their own children's school life — notices, attendance-ish
updates, fee state, chat rooms — with **school-admin-approved, consent-backed links**, and
nothing else. No guardian ever sees another student.

## 2. Data model (one migration, additive)

```
guardian_links (
  id            uuid PK,
  guardian_id   uuid NOT NULL REFERENCES users(id),     -- role=guardian
  student_id    uuid NOT NULL REFERENCES users(id),     -- role=student
  school_id     uuid NOT NULL REFERENCES schools(id),   -- tenant column
  status        text NOT NULL DEFAULT 'PENDING',        -- PENDING | ACTIVE | REVOKED
  relation      text NOT NULL,                          -- father | mother | other (+free text)
  consent_at    timestamptz NULL,                       -- guardian accepted the link
  requested_by  uuid NULL REFERENCES users(id),         -- school admin (or guardian self-request)
  created_at / updated_at
)
UNIQUE (guardian_id, student_id)          -- one link per pair
INDEX (student_id) WHERE status='ACTIVE'  -- "who may see this child"
INDEX (guardian_id) WHERE status='ACTIVE' -- "this guardian's children"
```

Rules (BR candidates):
- **BR-G1** A link is visible/usable only when `ACTIVE` — `PENDING` grants nothing.
- **BR-G2** A student may hold ≤ N ACTIVE links (default 2, `TODO: Confirm`) — guardians are
  father/mother/one other; school admin can raise it per student.
- **BR-G3** Both ends must be `VERIFIED`; revocation is immediate and audited.
- **BR-G4** Cross-school links are impossible (school_id column + TENANT_MISMATCH 404).
- **BR-G5** Consent: the guardian confirms via OTP-bound deep link; the student (age ≥ 13) is
  notified; a school admin can override consent for minors with an audited action.

## 3. Lifecycle

1. **Invite (school admin)** — from the student detail view: enter guardian phone + relation →
   if no account exists, create a PENDING guardian account; create the link (PENDING); send an
   SMS/OTP deep link (06 class `account`).
2. **Consent (guardian)** — first sign-in (phone OTP) shows a pending-link banner; accept →
   `consent_at=now()`; if the student is a minor and admin-initiated, the link activates
   immediately (BR-G5 override), else it stays PENDING until accept.
3. **Activation** — link goes ACTIVE: enrollment row (`hierarchy.Enrollment`, role guardian,
   same section as the student, session 2026) is created by the service so chat rooms +
   section notices work unchanged; notify both admins.
4. **Revocation** — school admin (or guardian) revokes; enrollment row + chat membership removed
   in the same transaction; audit `guardian.link.revoke`.

## 4. API surface (super-slim, additive to 03)

| Endpoint | Purpose | Gate |
| --- | --- | --- |
| `GET /api/v1/me/children` | The guardian's ACTIVE children (name, section, school) | guardian |
| `POST /api/v1/students/{studentId}/guardians` | Invite/link a guardian (phone, relation) | school_admin (own school) / super_admin |
| `GET /api/v1/students/{studentId}/guardians` | The student's guardians + link states | school_admin (own school) / super_admin |
| `POST /api/v1/guardian-links/{linkId}/consent` | Guardian accepts (OTP-bound session) | guardian (link owner) |
| `DELETE /api/v1/guardian-links/{linkId}` | Revoke (either side's admin, or guardian) | school_admin / super_admin / guardian |

All six are class `auth`-rate-limited, audited (`guardian.link.*`), and tenant-checked.

## 5. Surfaces

- **App (guardian)**: "My children" section on the You tab; per-child chips on notices/fees.
- **App/Web (school admin)**: student detail → guardians block (invite, revoke, states).
- **Web console**: tenant drill-down Students tab gains a guardian column (already stubbed in the
  2026-10-19 tabbed page's data shape).

## 6. Rollout

- **Phase 1**: tables + endpoints + admin invite/consent/revoke + "My children" list (read-only).
- **Phase 2**: student-specific notifications (fee state, verification) addressed to ACTIVE
  guardians via 06 `SendToUser` (frozen export; mute respected).
- **Phase 3**: multi-school guardians (one account, children across schools — the data model
  already allows it; UX gating only), guardian-scoped chat participation review.

## 7. Open questions (owner decisions)

1. Cap of ACTIVE guardians per student (proposed 2) and the admin override policy.
2. Minor-consent override: should school-admin links activate without guardian consent, or does
   consent always gate visibility?
3. Should guardians see fee amounts or only "paid/unpaid" state? (privacy decision)
4. Does a guardian count toward section chat rooms, or get a read-only digest instead?

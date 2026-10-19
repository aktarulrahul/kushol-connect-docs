# Guardian Experience — User Stories

**Module:** `16-guardian-experience` · **ID prefix:** `GRD`
**Status:** 📝 Spec drafted 2026-10-19 (planned, not built; owner asked "also plan for student's guardian")
**Owner:** Rahul (product owner)
**Last updated:** 2026-10-19

---

## 1. Purpose

Module 16 makes the guardian (অভিভাবক) a first-class user. A guardian links to one or more
children through institution verification, then sees each child's class, notices and fees in one
place, pays fees, and talks to the school safely. Institution admins get the tools to verify,
manage and revoke those links. It serves `brd.md` §3 (Guardians/Parents B2C: school notices,
books and tutors for their children) and BR-01 (community management), and `prd.md` §2 (guardians
need direct school updates, easy fee payment and verified tutors), §4B (the mobile app serves
guardians) and §5.4 (fee collection).

The pieces exist today but are scattered: the role, a single-child link written at registration
approval (03 `guardian_links`), a GUARDIAN enrollment (04), membership in the students' section
group (05), and a payer entitlement (12). Nothing owns the guardian experience from end to end.
This module does that, and its first phase (G0) fixes the safety and privacy gaps found while
planning (§9 and `technical-document.md` §14).

## 2. Actors

| Actor | What they do in this module |
| --- | --- |
| Unverified user (pending) | A guardian who registered but is not yet approved sees nothing about any child (IDT-BR-001). They see only the pending screen, with guardian-specific copy. |
| Student | Is the child in a link. Can see which guardians are linked to them (names and relations only). Never sees guardian phones. |
| Guardian | Links to 1..n children (link requests, invites). Sees each child's class, class teacher, notices and fees. Pays fees and messages staff. Can unlink themselves. |
| Teacher | Is reachable by the guardians of their sections (instant DM). Moderates the guardian section group (G2). Does not decide links (default, OQ-1). |
| School Admin | Decides guardian verification and link requests for their own school only. Lists, edits, revokes and invites guardian links. Publishes guardian-audience notices (G2). |
| Super Admin | Same rights as a School Admin on any school when passing `?schoolId=` (existing `/school/*` convention). Reads aggregate guardian counts. |
| Vendor / EdTech brand | None. Guardians are not an ad audience until the owner decides (OQ-13). |
| System (jobs, webhooks) | Request SLA reminders, invite expiry and SMS, and enrollment follow-up when links change or children move class. Fans out fee-due pushes to guardians. |

The roles come from module 03. Verification gates every participatory action (`prd.md` §5.1).
Only a VERIFIED guardian with an ACTIVE link sees anything about a child.

## 3. Scope

**In scope**

- **Guardian self-service.** A children list and a per-child hub, an active-child switcher,
  link requests for a 2nd or later child, request status and cancel, self-unlink, and a one-time
  guardian privacy-notice acknowledgement (consent).
- **Institution link management.** A links list with filters, edit relation, set the primary
  guardian, revoke with a reason, a link-request queue with student matching, and guardian
  invites by phone (G2).
- **Data model.** `guardian_links` v2 (wider relation set, primary guardian, more sources,
  revocation fields), plus the new `guardian_link_requests`, `guardian_invites` and
  `guardian_consents` tables. `users.student_code` is added as an 03 schema amendment so that a
  studentCode claim can be matched.
- **Guardian views of other modules' data**, through their exports: notices (05), fees and
  receipts (12), class teacher and section (04), and chat entry points (05).
- **Pushes:** link decided, link revoked and child placed (types registered with 06).
- **Phase G0 hardening**, done as amendments inside the owning modules and tracked here as
  `GRD-INT` tasks: the payer-scoped invoice list and the school-invoice role gate (12), fee-due
  fan-out (12 G-7), guardian approval with a student picker on web (07/03), guardian enrollment
  that follows the child (04), the guardian DM and contacts policy (05), and no ambassador
  decisions on guardians (03).

**Out of scope** (explicit — prevents scope drift)

- **Attendance and exam results data.** No table, source or teacher entry exists anywhere. The
  child hub reserves space for them behind a flag. Capturing the data needs an owner decision and
  a future module (proposed `17-academic-records`, fed by a 14 LMS extension or teacher entry).
  `GRD-US-019` is recorded only so the design keeps a place for it.
- A guardian reading a child's chats, DMs, AI scans (08) or analytics (09). This is never
  allowed.
- A web portal for guardians. Guardians use the app. The web work in this module is the
  institution admin console (07 shell).
- **Multi-school guardians and staff who are also parents (G3).** Today one user has one role and
  one `school_id`, and phones are globally unique. This module records the design direction only
  (`technical-document.md` §4.4 and §16).
- Phone-less "managed" student profiles for primary classes (G3, OQ-8).
- Payment mechanics, gateways and ledgers (12). Guardian ad targeting (13, OQ-13). Tuition
  matching (10). Only the optional `forStudentId` hook is in scope.

**Depends on**

| Module | What this module needs from it |
| --- | --- |
| 03 identity-access | `users` (role guardian, status, phone), `verification_requests` (the first-child path), `guardian_links` (table plus the frozen exports), the register contract (relation enum), the ambassador rule, OTP proof for invite claims |
| 04 organization-hierarchy | GUARDIAN enrollments, `OnUserVerified`, year-end migration, FCM topic bindings, section and class-teacher reads |
| 05 communication-engine | Official groups, DM policy, contact search, notices (list, publish, audience), system groups |
| 06 notifications | `SendToUser` directed pushes, new push types and preference classes, topic fan-out, the SMS sender (`smsout`) |
| 07 command-center-web | The institution console shell, `INSTITUTION_NAV`, the `/institution/users` verification queue |
| 10 tuition-marketplace | Optional `forStudentId` on requirements, and the `posterRoleFor` fix |
| 12 payments | Invoices, the payer-scoped invoice list, guardian fee-due fan-out, receipts, `IsGuardianOf` entitlement |
| 14 lms-erp-sync | Roster template and LMS mapping for `student_code` and `guardian_phone` (G2) |

---

## 4. User Stories

Phase tags (G0–G3) follow the rollout in `technical-document.md` §16.

### `GRD-US-001` — Guardian sees all linked children at a glance

**Priority:** P0 · **Phase:** G1 · **Traces:** BR-01 / PRD §2, §4B · **Depends on:** `IDT-US-002`

**Story** — As a **guardian**, I want **my home screen to show every child linked to me**, so
that **I can see each child's class, dues and latest notice without searching**.

**Acceptance criteria**

- **Given** I am VERIFIED with two ACTIVE links, **when** I open the app, **then** home shows one
  card per child. Each card has the name, class and section, school, a dues badge (৳ with bn
  digits in bn), the latest notice title, and actions to message the class teacher, pay and view.
- **Given** a child is linked but not yet placed in a section, **when** home renders, **then**
  the card says "waiting for the school to place {name} in a class" and has no broken actions.
- **Given** I have no ACTIVE links (all revoked), **when** home renders, **then** an empty state
  explains this and offers "Add child".
- **Given** I am PENDING, **when** I open the app, **then** I see only the pending screen, which
  says the school is matching me with student ID {code}.

**Notes**

- Co-guardians appear on the child hub by name and relation only, never by phone (`GRD-BR-007`).

### `GRD-US-002` — Guardian switches the active child and opens the child hub

**Priority:** P0 · **Phase:** G1 · **Traces:** PRD §4B · **Depends on:** `GRD-US-001`

**Story** — As a **guardian of more than one child**, I want **a child switcher and a hub for
each child**, so that **notices, fees and chat are always shown for the right child**.

**Acceptance criteria**

- **Given** two or more linked children, **when** I tap the switcher, **then** a bottom sheet
  lists them. Choosing one sets the active child, which persists across restarts on this device.
- **Given** an active child, **when** I open the hub, **then** I see these sections: Overview
  (class, section, class teacher, co-guardians), Notices (that child's school and section),
  Fees (that child's invoices), and Chat (class teacher DM, plus the guardian group in G2).
  Attendance and Results stay hidden while the academic-records flag is off.
- **Given** the active child's link is revoked while I am in the hub, **when** the next request
  returns `FORBIDDEN`, **then** the hub closes with a message and the switcher drops that child.

### `GRD-US-003` — Guardian adds another child

**Priority:** P0 · **Phase:** G1 · **Traces:** BR-01 / IDT OQ-3 · **Depends on:** `GRD-US-001`

**Story** — As a **verified guardian**, I want **to request a link to another child at the same
school**, so that **one account covers all my children**.

**Acceptance criteria**

- **Given** I am VERIFIED, **when** I submit school (prefilled with my school), class and section
  (optional), student ID, relation and the child's name (optional), **then** a PENDING link
  request is created and appears under "Requests".
- **Given** a PENDING request with the same student ID, **when** I submit again, **then** I get
  `CONFLICT` and the existing request is shown.
- **Given** I already have 8 ACTIVE children, **when** I submit, **then** I get
  `GUARDIAN_LINK_LIMIT` with bn/en copy and no request is created.
- **Given** I choose a school other than mine, **when** I submit, **then** I get
  `VALIDATION_FAILED` ("children in another institution are not supported yet") until
  multi-school mode (G3).

**Notes**

- A request is never approved automatically, even when the student ID matches exactly
  (IDT-US-002, `GRD-BR-012`).

### `GRD-US-004` — Guardian tracks link requests and hears the decision

**Priority:** P1 · **Phase:** G1 · **Traces:** PRD §5.1 · **Depends on:** `GRD-US-003`

**Story** — As a **guardian**, I want **to see my request status, cancel a request, and get a
push when it is decided**, so that **I am never left guessing**.

**Acceptance criteria**

- **Given** a PENDING request, **when** I tap cancel and confirm, **then** it becomes CANCELLED
  and leaves the admin queue.
- **Given** the school approves, **when** the decision commits, **then** I receive a
  `guardian_link_decided` push (ids and keys only). Tapping it opens `/children/{studentId}`, and
  the new child appears on home.
- **Given** the school rejects with a reason, **when** I open Requests, **then** I see the
  reason in my language and can submit a corrected request.

### `GRD-US-005` — Guardian acknowledges the guardian privacy notice

**Priority:** P0 · **Phase:** G1 · **Traces:** `prompt.txt` §12 / 03 `02` §6 privacy · **Depends on:** `GRD-US-001`

**Story** — As a **guardian**, I want **to be told what I will see about my child and how to
use it**, so that **I understand my access and responsibilities before seeing child data**.

**Acceptance criteria**

- **Given** I have not accepted the current notice version, **when** I open home, **then** a
  consent sheet (bn default, en available) explains what I can see, what I cannot see (the
  child's chats, AI work and analytics), and how to unlink. Child cards show names only.
- **Given** I accept, **when** the call succeeds, **then** a `guardian_consents` row is stored
  (version, locale, time) and full child cards load.
- **Given** the notice version changes, **when** I next open home, **then** I am asked again.
  Earlier acceptances stay on record.

**Notes**

- The notice text is legal copy. It ships as `TODO: Confirm` and blocks release until the owner
  approves it (`GRD-BR-015`).

### `GRD-US-006` — Institution admin matches a guardian to the right student

**Priority:** P0 · **Phase:** G0 (web approve) + G1 (link-request queue) · **Traces:** BR-01 / 07 WEB-FE-018 / IDT OQ-3 · **Depends on:** 03 verification queue

**Story** — As a **school admin**, I want **to see the guardian's evidence and a ranked list of
candidate students before approving**, so that **the wrong child is never linked**.

**Acceptance criteria**

- **Given** a guardian verification request or link request, **when** I open it, **then** I see
  the claimed student ID, the relation, the claimed name and section, and a candidate list
  (exact `student_code` match first, then name matches in the claimed section). I can also search
  the school's students.
- **Given** I pick a VERIFIED student of my school, **when** I approve, **then** one transaction
  writes the link (and, for a registration request, verifies the guardian), audits it, and
  queues enrollment follow-up and the decision push.
- **Given** I reject, **when** I give a reason (10–500 characters), **then** the request becomes
  REJECTED and the guardian is told.
- **Given** a Student Ambassador opens a guardian request, **then** they cannot decide it
  (`FORBIDDEN`). This is the default pending OQ-1.

### `GRD-US-007` — Institution admin manages guardian links

**Priority:** P0 · **Phase:** G1 · **Traces:** BR-01 · **Depends on:** `GRD-US-006`

**Story** — As a **school admin**, I want **to list, edit and revoke guardian links**, so that
**I can correct mistakes and respond to custody changes**.

**Acceptance criteria**

- **Given** my school, **when** I open Guardians → Links, **then** I see a paginated table
  (guardian, masked phone, student, class and section, relation, primary, source, status, date).
  It filters by section, relation, source and status and searches by name or student ID.
- **Given** a link, **when** I change the relation or mark it primary, **then** any other primary
  link of that student is cleared in the same transaction, and the change is audited.
- **Given** a link, **when** I revoke it with a reason, **then** it becomes REVOKED (never
  deleted). The guardian loses access to that child immediately. The guardian's enrollment in
  that section ends unless another linked child is in it. The guardian receives a
  `guardian_link_revoked` push.
- **Given** a student would exceed 4 ACTIVE guardians, **when** I add a link, **then** I get
  `GUARDIAN_LINK_LIMIT`.

### `GRD-US-008` — Institution admin invites a guardian by phone

**Priority:** P1 · **Phase:** G2 · **Traces:** BR-01 · **Depends on:** `GRD-US-007`

**Story** — As a **school admin**, I want **to invite a guardian by phone for a given student**,
so that **guardians join pre-linked without typing student IDs**.

**Acceptance criteria**

- **Given** a VERIFIED student of my school and a BD mobile number, **when** I create an invite,
  **then** a PENDING invite (30-day expiry) is stored. If "send SMS" is ticked and SMS invites
  are enabled for my school, one SMS goes out. It names the school and links to `/download`, and
  carries no child PII.
- **Given** the phone already belongs to a VERIFIED guardian of my school, **when** I submit,
  **then** the link is created directly (source ADMIN) and no invite is made.
- **Given** the phone belongs to a non-guardian user (for example a teacher), **when** I submit,
  **then** I get `CONFLICT` ("this number is used by another role"), pending G3 staff-parents.
- **Given** a PENDING invite, **when** I revoke or resend it, **then** the status and
  `sms_sent_at` change, with the resend capped per day.

### `GRD-US-009` — Guardian claims a school invite

**Priority:** P1 · **Phase:** G2 · **Traces:** IDT-US-002 · **Depends on:** `GRD-US-008`, OQ-2

**Story** — As an **invited guardian**, I want **the app to recognise my invite after I verify
my phone**, so that **I do not have to wait in the verification queue**.

**Acceptance criteria**

- **Given** I am new and my OTP-proven phone matches a PENDING invite, **when** I register,
  **then** I am shown "{School} invited you for {child first name}". If the owner approves
  auto-verify (OQ-2), confirming creates a VERIFIED guardian with an ACTIVE link (source INVITE)
  and marks the invite CLAIMED.
- **Given** I am already a VERIFIED guardian, **when** a new invite matches my phone, **then**
  home shows it as a pending invite with Accept and Decline.
- **Given** an EXPIRED or REVOKED invite, **when** I try to claim it, **then** I get `NOT_FOUND`
  and the normal registration path.

### `GRD-US-010` — Roster and LMS bring guardian phones and student codes

**Priority:** P1 · **Phase:** G2 · **Traces:** 14 roster / vendor LMS spec §5.2 · **Depends on:** `GRD-US-008`

**Story** — As a **school admin**, I want **roster uploads and LMS sync to carry each student's
code and guardian phones**, so that **guardians are invited in bulk**.

**Acceptance criteria**

- **Given** a roster row with `student_code`, `guardian_name`, `guardian_phone` and
  `guardian_relation`, **when** the import commits, **then** the student's code is set and one
  invite (source ROSTER) is created per new guardian phone. The import report counts invites.
- **Given** an LMS student with `student_code` and `guardian_phone`, **when** the sync runs,
  **then** the same happens with source LMS. Re-running is idempotent (one PENDING invite per
  student and phone).

### `GRD-US-011` — Guardian sees and pays each child's fees

**Priority:** P0 · **Phase:** G0 (list and fan-out) + G1 (child filter) · **Traces:** PRD §5.4 / PAY-US-003…005 / PAY-BR-003 · **Depends on:** 12

**Story** — As a **guardian**, I want **a fee-due push and a list of invoices for my children
only**, so that **I pay on time and never see other families' fees**.

**Acceptance criteria**

- **Given** an invoice is issued to my child, **when** the fee-due job runs, **then** the student
  and every ACTIVE guardian of that student get `payments_fee_due` (closes 12 G-7).
- **Given** I open Payments, **when** the list loads, **then** it comes from the payer-scoped
  `GET /api/v1/payments/invoices`. It shows only invoices of my linked children, with child
  filter chips. Calling the school-wide `/school/invoices` returns `FORBIDDEN` for guardians and
  students.
- **Given** I paid, **when** the other guardian opens the receipt, **then** they can view it
  (IsGuardianOf on the invoice's student).

### `GRD-US-012` — Guardian receives notices for each child

**Priority:** P0 · **Phase:** G0/G1 (read path) + G2 (audience) · **Traces:** BR-01 / PRD §2 · **Depends on:** 05, 04

**Story** — As a **guardian**, I want **every school and section notice for each child**, with
the option to filter by child, so that **I never miss a circular, holiday or meeting**.

**Acceptance criteria**

- **Given** my child is placed in a section, **when** a notice is published to that section or
  to the school, **then** I can read it and receive the topic push, through my GUARDIAN
  enrollment and not through chat-group membership.
- **Given** a notice with audience `guardians` (G2), **when** it is published, **then** guardians
  of that section receive it and students do not.
- **Given** two children in different sections, **when** I filter by child, **then** only that
  child's school and section notices show.

### `GRD-US-013` — Guardian messages the class teacher and school safely

**Priority:** P0 · **Phase:** G0 · **Traces:** COM-BR-004 / 05 technical-document §9 privacy · **Depends on:** 05

**Story** — As a **guardian**, I want **to message my child's class teacher and the school
office directly**, so that **I can raise issues quickly**, while **other people's children
cannot be messaged by me**.

**Acceptance criteria**

- **Given** I am a verified guardian, **when** I open a DM with a teacher or admin of my school,
  **then** it opens instantly.
- **Given** a student who is not my linked child, **when** I try to DM or send a message request,
  **then** I get `FORBIDDEN`. Contact search never lists non-linked students to me.
- **Given** another guardian of a shared section, **when** I message them, **then** it goes
  through a message request.

### `GRD-US-014` — Guardian community per section

**Priority:** P2 · **Phase:** G2 · **Traces:** BR-01 · **Depends on:** `GRD-US-012`, OQ-4

**Story** — As a **guardian**, I want **a guardians-only group for my child's section, moderated
by teachers**, so that **parents coordinate without being in the children's group**.

**Acceptance criteria**

- **Given** G2 is enabled, **when** I am enrolled as GUARDIAN in a section, **then** I join the
  `section_guardians:{sectionId}` official group (teachers are moderators) and am no longer a
  member of the students' group.
- **Given** the group's post policy is `moderators`, **when** I try to post, **then** I get
  `FORBIDDEN` and the composer is hidden.

### `GRD-US-015` — Guardian access follows the child

**Priority:** P0 · **Phase:** G0 · **Traces:** BR-01 (year-end migration) / 04 OQ-4 · **Depends on:** 04

**Story** — As the **system**, I want **guardian enrollments to track each linked child's
placement**, so that **guardians keep getting the right notices and topics**.

**Acceptance criteria**

- **Given** a guardian is verified before the child is placed, **when** provisioning runs,
  **then** it succeeds with no enrollment (and does not fail ×5 with `NOT_FOUND`). **When** the
  child is later verified or placed, **then** the guardian's enrollment, topics and groups are
  created.
- **Given** year-end migration promotes a child, **when** it commits, **then** the guardian's
  enrollment moves to the new section (source MIGRATION). The old one ends unless a sibling is
  still there.
- **Given** the child graduates or the link is revoked, **then** the guardian's enrollment for
  that section ends.

### `GRD-US-016` — Guardian unlinks themselves

**Priority:** P2 · **Phase:** G1 · **Traces:** privacy · **Depends on:** `GRD-US-007`, OQ-10

**Story** — As a **guardian**, I want **to remove my own link to a child**, so that **I stop
receiving that child's information when it no longer applies**.

**Acceptance criteria**

- **Given** an ACTIVE link of mine, **when** I confirm unlink (optional reason), **then** it is
  REVOKED with `revoked_by` set to me. The school admin sees it in the links list, and my access
  ends at once.

### `GRD-US-017` — Student sees who is linked as their guardian

**Priority:** P2 · **Phase:** G1 · **Traces:** privacy / transparency · **Depends on:** 03

**Story** — As a **student**, I want **to see which guardians are linked to me**, so that **I
can tell the school if a link is wrong**.

**Acceptance criteria**

- **Given** I am VERIFIED, **when** I open You → My guardians, **then** I see names, relations
  and the primary flag, never phones. A note tells me to contact the institution office if
  something is wrong.

### `GRD-US-018` — Guardian posts a tuition requirement for a specific child

**Priority:** P2 · **Phase:** G2 · **Traces:** BR-03 / TUT-US-001 · **Depends on:** 10

**Story** — As a **guardian**, I want **to pick which child a tuition requirement is for**, so
that **the class level is prefilled and my requirements stay organised per child**.

**Acceptance criteria**

- **Given** two children, **when** I start a requirement, **then** I may pick a child. This
  requires IsGuardianOf and prefills the class level. The poster role stored is the caller's real
  role.

### `GRD-US-019` — Guardian sees a child's attendance and results (reserved)

**Priority:** P2 · **Phase:** G3 · **Traces:** none in BRD/PRD; needs owner decision (OQ-11) · **Depends on:** future `17-academic-records` + 14 LMS extension

**Story** — As a **guardian**, I want **to see my child's attendance and published results**, so
that **I can follow progress without visiting school**.

**Acceptance criteria**

- **Given** the academic-records flag is off (default), **then** the hub shows no attendance or
  results section and no push of those kinds exists.
- **Given** the owner approves the future module, **then** this story moves there. Module 16
  supplies only the hub slot and the IsGuardianOf gate.

---

## 5. Business Rules

| ID | Rule | Enforced where |
| --- | --- | --- |
| `GRD-BR-001` | Only a VERIFIED guardian with an ACTIVE link to the child may read anything about that child. Pending guardians see nothing (IDT-BR-001). | service (`IsGuardianOf` gate on every child read) |
| `GRD-BR-002` | Link decisions (registration approval with a guardian, link-request approve or reject, admin link, revoke) are made by `school_admin` (own school) or `super_admin`. Ambassadors and teachers cannot decide them (default, OQ-1). | service (03 verification + 16) |
| `GRD-BR-003` | Guardian and child belong to the same school while single-school mode holds. Every link row carries the tenant `school_id`. | service + tests; DB FK on `school_id` |
| `GRD-BR-004` | Caps: at most 4 ACTIVE guardians per student and at most 8 ACTIVE children per guardian (defaults, OQ-9). | service, in the write tx with row locks |
| `GRD-BR-005` | At most one primary ACTIVE guardian per student. Setting a new primary clears the old one in the same transaction. | DB partial unique + service |
| `GRD-BR-006` | Links are never hard-deleted. Revoking needs a reason (10–500 characters) from an admin; a guardian's self-unlink may omit it (a system reason key is stored). Every transition is audited. | DB CHECK + service + `audit.Record` |
| `GRD-BR-007` | Guardian phones are masked in every admin response and never shown to co-guardians or students. Co-guardians are shown by name and relation only. | DTO mapping + tests |
| `GRD-BR-008` | Guardians never read a child's chats, DMs, AI scans (08) or analytics (09). | no endpoint exists; 05/08/09 boundary |
| `GRD-BR-009` | Guardian DM policy: instant with same-school staff (teacher, school_admin) and with their own linked children. Message request with other guardians who share a section. Blocked (`FORBIDDEN`, including requests) with non-linked students. | 05 `DirectAllowed` via the GuardianPolicy port |
| `GRD-BR-010` | Invites: the phone must be OTP-proven by the claimer. At most one PENDING invite per (student, phone). Invites expire after 30 days. SMS invites are opt-in per school. | DB partial unique + service + job |
| `GRD-BR-011` | Push payloads carry ids and keys only. The SMS invite contains the school name and the download link, with no child PII. | 06 payload builder + SMS template test |
| `GRD-BR-012` | A studentCode match is only a hint. No link is ever created automatically from a code (IDT-US-002). Only a school-vouched phone (invite) may auto-link, and only if the owner approves (OQ-2). | service |
| `GRD-BR-013` | Every mutation writes `audit_log` in the same transaction (`guardian_link.*`, `guardian_link_request.*`, `guardian_invite.*`, `guardian_consent.accepted`). | service (`db.InTx` + `audit.Record`) |
| `GRD-BR-014` | Content accuracy (`prompt.txt` §12): demo data is fictional and marked ডেমো. Guardian notice copy marked `TODO: Confirm` blocks release. | seed review + release checklist |
| `GRD-BR-015` | Child details (beyond names) are returned only after the guardian accepts the current guardian-notice version. | service (`CONSENT_REQUIRED`) |
| `GRD-BR-016` | The fee-due push goes to the student and every ACTIVE guardian of that student. Receipts are visible to the payer and to any ACTIVE guardian of the invoice's student. | 12 service via `GuardiansOf` / `IsGuardianOf` |

## 6. Validation Rules

| Field | Rule | Message key (per-app `src/i18n` catalog) |
| --- | --- | --- |
| `studentCode` | trimmed, 3–20 characters, `[A-Za-z0-9-/]` | `validation.guardian.student_code` (exists in web and app) |
| `relation` | one of `father`, `mother`, `grandfather`, `grandmother`, `brother`, `sister`, `uncle`, `aunt`, `legal_guardian`, `other` (G1 widening; `father`/`mother`/`other` stay valid) | `validation.guardian.relation` (new) |
| `studentName` (claimed) | optional, trimmed, 2–80 characters | `validation.guardian.student_name` (new) |
| `sectionId` | optional uuid that must belong to `schoolId` | `validation.guardian.section` (new) |
| `reason` (revoke or reject) | trimmed, 10–500 characters | `validation.guardian.reason` (new) |
| `phone` (invite) | BD mobile in E.164 (`+8801[3-9]XXXXXXXX`), normalised server-side | `validation.phone.invalid` (exists in the app) |
| `guardianName` (invite) | optional, 2–80 characters | `validation.guardian.name` (new) |
| `noticeVersion` (consent) | must equal the server's current version | `errors.consent_required` (new) |
| `studentUserId` (approve) | a VERIFIED student of the same school | `validation.guardian.student_pick` (new) |

The OpenAPI schemas carry the same limits. Web and app zod schemas mirror them. The relation enum
change ships as one contract change across api, web and app (`GRD-INT-007`).

## 7. Edge Cases & Negative Paths

| # | Scenario | Expected behaviour |
| --- | --- | --- |
| 1 | Unauthenticated call to a protected action | `UNAUTHENTICATED`, no side effect |
| 2 | Cross-tenant read or write (admin of school A on a link of school B; guardian asks about a child in another school) | `TENANT_MISMATCH` returned as 404, no data leaked |
| 3 | Unverified (pending) guardian calls `/guardian/*` | `NOT_VERIFIED` with how to get verified |
| 4 | Child's avatar missing in R2 | Initials placeholder, never a crash |
| 5 | Reduced motion enabled | Child switcher sheet and card transitions are instant |
| 6 | Offline action (app) | Link request, unlink and consent are refused offline with a message (not queued). The cached children list stays readable with an offline banner. |
| 7 | Guardian verified before the child is placed | Provisioning succeeds with zero enrollments. Placement of the child later triggers enrollment (`GRD-US-015`). |
| 8 | Child promoted at year end, sibling stays in the old section | Guardian enrollment is added in the new section. The old one stays ACTIVE because of the sibling. |
| 9 | Link revoked while the guardian has the hub open | Next call returns `FORBIDDEN`. The hub closes and the cache entry is evicted. |
| 10 | Two admins set different primaries at the same time | Partial unique index: one wins, the other gets `CONFLICT` and refetches |
| 11 | Two admins decide the same link request | First decision wins. The second gets `CONFLICT` (status guard in `UPDATE … WHERE status='PENDING'`). |
| 12 | Invite phone belongs to a teacher or admin | `CONFLICT` (role mismatch) until G3 staff-parents |
| 13 | Student code matches nobody | Request stays PENDING with name-based candidates. The admin searches manually or rejects with a reason. |
| 14 | Student suspended or deleted | Links stay ACTIVE but child reads return a "not available" state. A deleted student's links are revoked by the system (reason key `student_removed`). |
| 15 | Guardian suspended (03) | All `/guardian/*` calls are refused by the existing suspension guard. Links are unchanged. |
| 16 | Guardian at the 8-child cap or student at the 4-guardian cap | `GUARDIAN_LINK_LIMIT` (409), with bn/en copy |
| 17 | Guardian picks a school other than their own | `VALIDATION_FAILED` (multi-school not supported until G3) |
| 18 | Notice-version bump during a session | The next child-detail call returns `CONSENT_REQUIRED`, and the consent sheet opens |
| 19 | Ambassador opens a guardian request | `FORBIDDEN` (default for OQ-1). The queue hides guardian rows from ambassadors. |
| 20 | SMS gateway down when sending an invite | The invite is created. `sms_sent_at` stays NULL, and the job retries ×5. The admin sees "SMS not sent" with a resend action. |

## 8. Reporting Needs

These are aggregate counts only, used by the 07 institution dashboard and the super-admin school
detail (`map_institution` stats):

- guardians (VERIFIED, with at least one ACTIVE link)
- the percentage of VERIFIED students with at least one ACTIVE guardian
- pending link requests, with the oldest age (SLA)
- invites by status (PENDING, CLAIMED, EXPIRED) for the last 30 days
- revocations in the last 30 days

No per-guardian activity tracking.

## 9. Open Questions

| # | Question | Owner | Status | Default if unanswered |
| --- | --- | --- | --- | --- |
| 1 | Who may decide guardian links: school_admin only, or also the class teacher of the child's section? Should Student Ambassadors (minors) lose guardian approvals? | Rahul | Open | school_admin or super_admin only. Ambassadors are refused on guardian rows. |
| 2 | May a school-vouched phone (admin, roster or LMS invite) auto-link and auto-verify a guardian once the phone is OTP-proven? | Rahul | Open | Yes for invites only (source INVITE). Code-based claims always go through the queue. |
| 3 | Should guardians stay in the students' official section group, move to a guardian-only group, or both? Can guardians post there? | Rahul | Open | G0–G1: stay (current behaviour), with the DM policy fixed. G2: move to `section_guardians:{sectionId}` with post policy `all` and teachers as moderators. |
| 4 | Guardian DM policy details (guardian ↔ guardian, guardian ↔ teacher) | Rahul | Open | `GRD-BR-009` |
| 5 | Multi-school guardians and staff who are also parents: support now, or record as a G3 limitation? | Rahul | Open | G3. Documented limitation; `CONFLICT` with a clear message meanwhile. |
| 6 | Where does the student code live: `users.student_code` (03 amendment) or a separate table? Store a roll number per session? | Rahul | Open | `users.student_code`, unique per school (case-insensitive). No roll number. |
| 7 | Final BD relation list. Is a primary guardian needed? | Rahul | Open | The 10-value list in §6. One optional primary per student. |
| 8 | Students without phones (primary classes): add phone-less managed profiles? | Rahul | Open | G3. Until then those guardians cannot link (documented). |
| 9 | Caps per student and per guardian | Rahul | Open | 4 and 8 |
| 10 | Can a guardian unlink themselves? Can a student (18+) remove a guardian? | Rahul | Open | The guardian may self-unlink. The student sees links read-only and asks the institution. |
| 11 | Attendance and results: in scope at all? Source (LMS pull or teacher entry), phase, "absent today" push? | Rahul | Open | Out of scope. Hub slot reserved behind a flag. Future module 17. |
| 12 | Should guardians see a child's Auto-CT scores (08)? | Rahul | Open | No (current 08 rule) |
| 13 | Should guardians be an ad or campaign audience (13)? | Rahul | Open | No. Excluded from `AudienceCount`. |
| 14 | SMS invite cost: who pays? Per-school opt-in? Invite copy? | Rahul | Open | Per-school opt-in, off by default. Copy `TODO: Confirm`. |
| 15 | Notice audiences (all / students / guardians): who may publish guardian-only notices? | Rahul | Open | Add audience in G2. school_admin publishes for any section; class teachers for their own section. |
| 16 | Tie tuition requirements to a specific child? | Rahul | Open | Optional `forStudentId` (G2) |
| 17 | Guardian registration: app-only, or web sign-up with email verification? | Rahul | Open | App-only (03 G-12 stands) |
| 18 | Guardian privacy notice: legal copy, version cadence, and whether withdrawing consent must unlink | Rahul | Open | One versioned notice. Withdrawal = self-unlink. Copy `TODO: Confirm`. |

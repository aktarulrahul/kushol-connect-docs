# Partner Module Specification & Architecture Reference
**Module**: `07-command-center-web`, `11-campus-commerce`, `13-b2b-ads-events`
**Status**: APPROVED SPECIFICATION
**Version**: 2.0 (Terminology Migration: Partner -> Partner)
**Date**: 2026-10-21

---

## 1. Terminology & System Entities
- **Primary Entity**: **Partner** (Bangla: **পার্টনার** / **সহযোগী প্রতিষ্ঠান**). Replaces "Partner" throughout all documentation, database tables, OpenAPI contracts, and codebases.
- **Roles**:
  - `PARTNER_ADMIN` (Seat #1 / Executive Partner): Full management including bank/MFS payouts, seat upgrades, campaign budgets, paid add-on unlocks, team permissions, and immutable audit logs.
  - `PARTNER_EXECUTIVE` (Operations / Staff Member): Day-to-day operations: managing store catalog, fulfilling orders, reviewing campaign participants/volunteers, assigning volunteer tasks, and issuing certificates. Cannot initiate payouts, modify financial settlement accounts, or view audit logs.
- **Routing**: Single unified role-driven entry point at `/dashboard` across `applications/web` and `applications/app`. No role-prefixed URLs (no `/partner/dashboard` or `/console/partner/[id]`).

---

## 2. Public Landing Page Partner Self-Registration & KYC Verification Pipeline

### 2.1 Public Self-Registration (`applications/web` & `applications/app`)
- **Cost**: 100% Free (`registration_fee = 0`).
- **Multi-Step Form**:
  - **Step 1 — Account & Contact**: Contact Person Full Name, Official Email, Phone (verified via SMS OTP), Password (hashed via `argon2id`, kept inactive).
  - **Step 2 — Business Details**: Organization Name (`en` & `bn`), Partner Category (`BOOKSTORE`, `UNIFORMS`, `STATIONERY`, `EDTECH_COACHING`, `EVENT_ORGANIZER`, `OTHER`), Physical Store/Office Address, City, Website/Social URL, Settlement Account details (bKash/Nagad Merchant or Bank).
  - **Step 3 — KYC Document Uploads (Direct Cloudflare R2 Presigned URLs)**:
    - Owner/Signatory NID Front & Back (*Required*)
    - Trade License / Business Registration (*Required*)
    - TIN/BIN Certificate or Institutional Authorization Letter (*Optional/Conditional*)
    - Client uploads directly to Cloudflare R2; Go API validates magic bytes (`PDF`, `JPG`, `PNG`) and file size.
  - **Step 4 — Verification Preference**: Choose `PHYSICAL_VISIT` or `VIRTUAL_MEETING` + preferred time slot and notes.
- **Post-Submission**: Confirmation screen with Reference ID (`KUSHOL-PARTNER-XXXX`), explaining review status.

### 2.2 Super Admin "Partner Leads" Pipeline (`/dashboard`)
- **Queue**: Super Admin navigates to `/dashboard` -> **Leads -> Partner Leads**.
- **Lifecycle Statuses**:
  1. `NEW_LEAD`: Submitted with uploaded KYC documents.
  2. `UNDER_REVIEW`: Assigned to a Kushol Admin for document inspection.
  3. `MEETING_SCHEDULED`: Admin logs/schedules a Physical Visit or Virtual Meeting (date, link/address, verifier).
  4. `VERIFICATION_COMPLETED`: Admin records meeting notes, KYC checklist pass, and agreed delivery commission rate (15%–20%).
  5. `APPROVED`: Final approval.
  6. `REJECTED` / `CHANGES_REQUESTED`: Reason sent via Email/SMS for re-upload.

### 2.3 Pre-Approval Login Block
- Unapproved partners attempting to log in receive `403 Forbidden` (`PARTNER_APPROVAL_PENDING` or `PARTNER_REJECTED`) displaying current review status. No active session or token is granted.

### 2.4 Atomic Partner Provisioning on Approval
When Super Admin clicks "Approve Partner", an atomic PostgreSQL transaction:
1. Marks `partner_leads.status = 'APPROVED'`.
2. Creates/activates `partners` record (`status = 'ACTIVE'`, `free_seat_quota = 5`, unique referral code, agreed `commission_rate_bps` 1500–2000).
3. Activates the applicant's user record and assigns Seat #1 as `PARTNER_ADMIN` in `partner_members`.
4. Provisions the partner's internal chat group (`room_type = PARTNER_INTERNAL`, FCM topic `partner_{partner_id}_team`) and subscribes `PARTNER_ADMIN`.
5. Logs `PARTNER_APPROVED_AND_PROVISIONED` to `partner_audit_logs`.
6. Enqueues bilingual Welcome & Approval Email + SMS.

---

## 3. Core Partner Capabilities (Web & Mobile)

### 3.1 Dynamic Unified Dashboard (`/dashboard`)
- **`PARTNER_ADMIN`**: Overview, Institutions, Campaigns & Registrations, Store & Orders, Team Chat, Members & Seats, Finance & Payouts, Referrals (XP), and Audit Logs.
- **`PARTNER_EXECUTIVE`**: Overview, Institutions (Drafts), Campaigns & Registrations, Store & Orders, Team Chat, Referrals (XP). Finance, Seat Billing, and Audit Logs are hidden.

### 3.2 Institution Onboarding & 3-Tier Campaign Engine
- **Partner-Led Institution Onboarding**: Verified schools link via `institutions.onboarded_by_partner_id`.
- **Campaign Engine**: Basic campaign/event creation is **100% FREE**.
  - **Tier 1 — Own Onboarded Institutions (`OWN_INSTITUTIONS_FREE`)**: 100% FREE to run campaigns and notices on institutions onboarded by the partner.
  - **Tier 2 — Other Institutions (`OTHER_INSTITUTIONS_PAID`)**: Paid budget required for cross-institution targeting (`City -> Institution -> Section`).
  - **Tier 3 — Kushol App Global Banner (`GLOBAL_APP_BANNER_PAID`)**: Paid placement for app-wide banners.

### 3.3 Campus Commerce & 15%–20% Delivery Commission Escrow
- Buyer payment held in Kushol Escrow (`ESCROW_HELD`).
- On confirmed delivery (`DELIVERED` via courier webhook + buyer OTP/receipt confirmation), platform charge of **15% to 20%** (`commission_rate_bps` 1500–2000, default 1500 / 15%) is deducted, and remaining 80%–85% net is released to partner's withdrawable balance.

### 3.4 Team Members, Single Team Chat, XP Referrals & Audit Logs
- **Team Seats**: Up to 5 members FREE (`free_seat_quota = 5`); 6th member onward is BILLABLE (`is_billable = true`).
- **Internal Team Chat**: Single dedicated group per partner (`partner_{partner_id}_team`).
- **XP Referrals (`partner_xp_ledger`)**: Earn XP for referring verified institutions, partners, or campaign registrants. Redeem XP for banner impressions or seat credits.
- **Audit Logs (`partner_audit_logs`)**: Append-only log with before/after JSON diffs matching `/admin/audit` UI design.

---

## 4. Paid Extended Campaign/Event Operations Suite

Basic campaign creation is free; the following suite is **PAID** (`partner_campaigns.extended_suite_unlocked == true` or Partner Pro subscription):

### 4.1 Dual Rosters (Participants & Volunteers)
- **Participants (`CAMPAIGN_PARTICIPANT`)**: Attendees/competitors (`REGISTERED`, `PAID`, `CHECKED_IN`, `ATTENDED`, `NO_SHOW`, `CANCELLED`).
- **Volunteers (`CAMPAIGN_VOLUNTEER`)**: Staff/helpers (`PENDING`, `APPROVED`, `CHECKED_IN`, `COMPLETED`, `REVOKED`).
- Mobile QR check-in & CSV roster export.

### 4.2 Volunteer Task Management & Mobile Execution
- Partner creates tasks with priority, due date, XP reward, and proof requirement flag (`requires_proof`).
- Direct assignment or claimable task pool.
- Volunteers in `applications/app` execute tasks: `ASSIGNED` -> `IN_PROGRESS` -> `SUBMITTED_FOR_REVIEW` with Cloudflare R2 proof photo. Partner reviews and approves.

### 4.3 Rewards & Tamper-Evident E-Certificates
- Idempotent rewards ledger (`campaign_rewards_ledger`).
- PDF E-Certificates stored in Cloudflare R2 with verification code.
- Public authenticity verification endpoint `/api/v1/certificates/verify/{verificationCode}`.

### 4.4 Mobile Student Experience
- Any student can discover active campaigns/events in `applications/app`.
- Receive notifications when volunteer calls open.
- Apply as a Volunteer directly in-app.
- Earn XP upon completing tasks and event volunteering.

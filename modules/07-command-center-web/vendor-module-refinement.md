# Partner Module Refinement Specification

**Owner:** Rahul (Product Owner)  
**Standard:** Docs & Contracts First (`docs/persona.md`, `docs/tech-stack.md`)  
**Scope:** `applications/api`, `applications/web`, `applications/app`  

---

## 1. Executive Summary

This specification refines the Partner Module across the entire Kushol Connect platform. It unifies dashboard routing under `/dashboard`, establishes strict multi-tenant isolation, models partner-led institution onboarding, introduces a 3-tier campaign model, revises campus commerce to an escrow-protected 15%–20% completed delivery commission, provides immutable partner audit logs, introduces double-entry finance ledgers, creates a single dedicated internal partner group chat, bounds team seat quotas (5 free, billable beyond), and powers partner growth via an XP referral reward system.

---

## 2. Core Business Requirements

### 2.1 Free Partner Registration & In-App Registration Management
- **100% Free Registration:** Registration fee is 0 BDT (`registration_fee_bdt = 0`).
- **Registration Surfaces:** Web (`applications/web`) and Mobile App (`applications/app`).
- **KYB Flow:** Phone OTP / Email / OIDC verification -> Business Profile submission (Bengali & English company name, Category, Trade License and NID uploads to Cloudflare R2, Payout account details) -> `pending` status -> Super Admin approval (`approved`).
- **In-App Registration Management:** Partners manage custom registration forms, view registrants, filter by status (`registered`, `checked_in`, `cancelled`), perform QR check-ins, and export CSVs.

### 2.2 Unified Role-Based Dashboard Routing (No Role-Specific URLs)
- **Single Entry Point (`/dashboard`):** No role-prefixed URLs like `/console/partner` or `/partner/dashboard`. All authenticated users navigate to `/dashboard`.
- **Dynamic Session Resolution:** The dashboard inspects user claims:
  - `SUPER_ADMIN` -> Platform Super Admin Command Center.
  - `SCHOOL_ADMIN` / `TEACHER` -> Institution Command Center.
  - `PARTNER` -> Partner Command Center with sub-role rendering:
    - `VENDOR_ADMIN`: Full access to Overview, Institutions, Campaigns & Registrations, Store & Orders, Team Chat, Members & Seats, Finance & Payouts, Referrals (XP), and Audit Logs.
    - `VENDOR_EXECUTIVE`: Limited access to Overview, Institutions (Drafts), Campaigns & Registrations, Store & Orders, Team Chat, and Referrals (XP). Route guards and sidebar hide Finance, Seat Billing, and Audit Logs.
- **KPI Metrics:** Real-time metrics for Active Store Orders, Escrow Balance, Withdrawable Balance (Admin), Active Campaigns (Free vs. Paid), Campaign Registrations, Team Seat usage (`X/5 Free`, `Y Billable`), and XP Referral Balance.

### 2.3 Institution Onboarding & 3-Tier Campaign Engine
- **Partner-Led Institution Onboarding:** Partners submit school/college details (Name in bn/en, type, city, EIIN, admin contact info, authorization document). Once verified, the school is linked via `schools.onboarded_by_vendor_id`.
- **3 Campaign Placement Tiers:**
  1. `OWN_INSTITUTIONS_FREE`: Basic campaigns targeting institutions onboarded by this partner run for 0 BDT (100% Free).
  2. `OTHER_INSTITUTIONS_PAID`: Campaigns targeting other institutions across the hierarchy run as paid placements.
  3. `GLOBAL_APP_BANNER_PAID`: Banners placed on the main Kushol app (Marketplace / Notices) run as paid placements.

### 2.3.1 Paid Extended Event Operations Suite (Feature Gate & Entitlement)
- **Free vs. Paid Distinction:**
  - **FREE Tier:** Creating and managing basic campaigns, banners, and announcements is 100% free.
  - **PAID Tier:** The Extended Event Operations Suite (Dual Rosters, Volunteer Tasks, and Rewards/E-Certificates) requires an active unlock per campaign (`campaign.has_extended_features = true` / `extended_suite_unlocked = true`) or a Partner Pro subscription (`vendor_accounts.plan_tier = 'PRO'`).
  - **Server-Side Enforcement:** Attempting to mutate or access these extended features without an active entitlement triggers `402 Payment Required` (or `403 Forbidden` with code `PAID_FEATURE_REQUIRED`).
  - **Unlock Mechanism:** Only `VENDOR_ADMIN` can unlock via wallet balance deduction or gateway payment (`POST /api/v1/partner/campaigns/{id}/unlock-suite`). It records an audit log and financial debit in `vendor_ledger_entries`.
  - **UI Paywall States:** Locked badge (`PRO / PAID`) on Participants, Tasks, and E-Certificates tabs. Clicking prompts `VENDOR_ADMIN` to unlock instantly and prompts `VENDOR_EXECUTIVE` to notify their admin.

### 2.4 Protected E-Commerce Store & 15%–20% Delivery Commission
- **Commission Rate:** 15% to 20% charge on completed delivery (`commission_rate_bps` 1500–2000, default 1500 bps / 15%).
- **Escrow Pipeline:**
  - Buyer payment is held in Escrow (`ESCROW_HELD`).
  - Fulfillment occurs via courier or verified drop-off.
  - On delivery confirmation (`DELIVERED`), the platform fee (15%–20%) is deducted, and net funds (80%–85%) are released to the partner's withdrawable balance (`ESCROW_RELEASED`).

### 2.5 Immutable Partner Audit Logs (Matching `/admin/audit` Experience)
- Append-only `vendor_audit_logs` records all tenant mutations (`actor_user_id`, `actor_role`, `action`, `entity_type`, `entity_id`, `changes`, `ip_address`, `user_agent`, `created_at`). Filterable view restricted to `VENDOR_ADMIN`.
- **UI Parity with `/admin/audit`:**
  - Date-grouped rows ("Today", "Yesterday", and formatted dates).
  - Search by actor, action, entity, target, or details.
  - Action category filters (Team & Roles, Store & Orders, Campaigns & Tasks, Finance & Payouts, Institutions).
  - Actor filter dropdown with avatar + name.
  - Time range filter: All time, 24h, 7d, 30d.
  - Expandable row showing visual before/after JSON diffs (green additions, red deletions), IP address, and user agent.
  - Refresh button and CSV export.

### 2.10 Campaign Participants & Volunteers Management
- **Dual Rosters:**
  - **Participants (`CAMPAIGN_PARTICIPANT`):** Statuses: `REGISTERED`, `PAID`, `CHECKED_IN`, `ATTENDED`, `NO_SHOW`, `CANCELLED`.
  - **Volunteers (`CAMPAIGN_VOLUNTEER`):** Statuses: `PENDING`, `APPROVED`, `CHECKED_IN`, `COMPLETED`, `REVOKED`.
- Support QR code check-in via mobile app and CSV export on web.

### 2.11 Volunteer Task Management & Mobile Execution
- **Partner Task Distribution:** Title (`bn`/`en`), instructions, priority (`LOW`, `MEDIUM`, `HIGH`, `URGENT`), due date, XP reward, `requires_proof`, direct assignment vs. claimable pool task (`is_pool_task: true`).
- **Volunteer In-App Workflow:** Statuses `ASSIGNED` -> `IN_PROGRESS` -> `SUBMITTED_FOR_REVIEW` (with optional photo proof on Cloudflare R2 via presigned URL + notes) -> Partner `APPROVED` (triggers XP) or `REVISION_REQUESTED`.
- FCM push notifications on assignment, updates, and upcoming deadlines.

### 2.12 Rewards, XP & Tamper-Evident E-Certificates
- **Idempotent Rewards Ledger (`campaign_rewards_ledger`):** Prevents duplicate reward/XP crediting.
- **E-Certificates (`campaign_certificates`):**
  - Kinds: `PARTICIPATION`, `ACHIEVEMENT`, `VOLUNTEER_APPRECIATION`.
  - Stored in Cloudflare R2 as signed PDFs with unique verification codes and QR codes.
  - Bulk and individual issuance.
  - Public verification endpoint: `GET /api/v1/certificates/verify/{code}`.
  - In-app certificate viewing and sharing.

### 2.6 Partner Finance Management
- Double-entry ledger (`vendor_ledger_entries`) tracking Escrow vs. Withdrawable balances, Ad/Campaign Spend, and Seat Billing.
- Payout requests (`vendor_payout_requests`) to bKash, Nagad, or Bank accounts with status tracking.

### 2.7 Single Dedicated Partner Group Chat
- One server-managed internal chat group (`system_key = 'partner:{vendor_id}'`, `room_type = VENDOR_INTERNAL`) per partner tenant.
- Auto-syncs membership and FCM topic `vendor_{vendor_id}_team` as partner team members are invited or removed.

### 2.8 Team Members, Roles & Seat Quotas
- Two partner roles: `VENDOR_ADMIN` and `VENDOR_EXECUTIVE`.
- **Seat Quota:** Up to 5 active members are FREE (`free_seat_quota = 5`). The 6th member onward is BILLABLE (`is_billable = true`).

### 2.9 XP Referral Rewards
- Unique partner referral code/link.
- `vendor_xp_ledger` tracks earned XP for referring institutions, other partners, or campaign users. XP is redeemable for banner impressions or member seat credits.

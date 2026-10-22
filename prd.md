# Product Requirements Document (PRD)

| | |
| --- | --- |
| **Project Name** | Kushol (কুশল) |
| **Tagline** | The Educational Super App for Communities, Commerce, and AI-Driven Growth. |
| **Platforms** | Mobile App (iOS via TestFlight, Android via Expo CLI) & Web (Landing Page + Admin Dashboard) |
| **AI Infrastructure** | DeepSeek (via CommandCLI) |
| **Document Status** | VC Pitch Ready & Developer Handoff |

---

## 1. Executive Summary

Kushol is a zero-CAC (Customer Acquisition Cost) B2B2C educational super app tailored for
Bangladesh. By onboarding a single school, the platform instantly acquires thousands of captive
users (students, teachers, and guardians). It replaces chaotic WhatsApp groups with a strict,
hierarchy-driven messaging platform, and scales revenue through integrated fee payments, campus
commerce, peer-to-peer tuition matchmaking, and DeepSeek-powered AI study tools.

## 2. Target Audience

- **Students (B2C):** Need organized study materials, AI test prep, and senior tutors.
- **Guardians (B2C):** Need direct school updates, easy fee payment, and verified tutors.
- **Schools/Colleges (B2B):** Need streamlined communication, automated fee collection, and LMS
  integration.
- **Partners/Brands (B2B):** Need hyper-targeted access to student demographics for commerce and
  ads.
- **Campaign Volunteers (Students/Ambassadors):** Need access to volunteer opportunities, mobile task tracking, XP earnings, and verified e-certificates.

## 3. Product Phasing Strategy

> **Superseded ordering (2026-09-30).** The build order is set by `brd.md` §8, `prompt.txt`
> "Phase gates" and `docs/modules/README.md`: **Phase 2 = AI Hub + Auto-CT + Pain Point Matrix →
> tuition marketplace; Phase 3 = campus commerce → payments → B2B ads/events → LMS/ERP sync.**
> The phase contents below are kept as the original pitch; where they disagree, the build order wins.

### Phase 1: The MVP (Community & Communication)

- **Mobile App Release:** Built on React Native (Expo CLI). Android APK release and iOS Beta via
  TestFlight.
- **Web Dashboard:** Landing page for B2B lead generation (schools) and Super Admin portal.
- **Features:** Hierarchical group creation (City → School → Section), Student Ambassador
  verification, Role-based messaging (PDF, Images, Voice), and one-way Notice Boards.

### Phase 2: The Marketplace & FinTech Expansion

- **Features:** bKash/Nagad/SSLCommerz integration for fee payments with automated reconciliation.
- **Campus Commerce:** Local partners and schools setting up storefronts for books and uniforms.
- **Basic Migration:** CSV/Excel upload for year-end student migration.

### Phase 3: The AI & Ecosystem Scale

- **Features:** DeepSeek integration for Smart Study Hub (Notes scanning, Auto-CT generation).
- **Tuition Marketplace:** Location and skill-based matching for home tutors.
- **Advanced Migration:** REST API Webhooks for live LMS/ERP syncing.

## 4. Platform Interfaces

### A. The Landing Page & Web Admin Dashboard

The web portal serves two distinct purposes:

- **Public Landing Page:** A B2B marketing funnel designed to convert School Principals and
  Partners. Features ROI calculators for schools (time saved on fee collection), public partner self-registration, and KYC document submission.
- **Command Center (Dashboard):**
  - **Super Admin:** Manages tenant schools, reviews and verifies partner leads (document inspection, physical/virtual meetings), approves partners, and monitors platform revenue.
  - **School Admin:** Uploads CSV rosters, triggers fee payment links, sends global notices, and
    views the AI Teacher Assistant Pain Point Matrix.
  - **Partner Command Center (Unified `/dashboard` Entry Point):** Free onboarding & KYB/KYC verification, dynamic role-based rendering (`PARTNER_ADMIN` vs `PARTNER_EXECUTIVE`), storefront management, inventory tracking, order fulfillment with escrow protection, partner-led institution onboarding, 3-tier campaign creation (`OWN_INSTITUTIONS_FREE`, `OTHER_INSTITUTIONS_PAID`, `GLOBAL_APP_BANNER_PAID`), in-app event registration management, team seats (5 free, billable beyond), partner finance ledger with payout requests, immutable audit logs, and XP referral rewards. Pre-approval login is strictly blocked until Super Admin approval.

### B. Mobile App (Student, Teacher, Guardian)

Built using Expo CLI for rapid cross-platform deployment.

- **iOS Distribution:** Internal testing and early school rollouts managed via Apple TestFlight.
- **Android Distribution:** Direct APK downloads for immediate onboarding, followed by Play Store
  release.

**Core UI Tabs:**

| Tab | Contents |
| --- | --- |
| **Chat** | Segmented into Official (Class/Section), Custom (Clubs), and DMs. |
| **Notices & Events** | School broadcasts and city-wide educational campaigns. |
| **AI Hub** | Note scanner, MCQ generator, and study materials. |
| **Marketplace** | Pay fees, buy books, or find a home tutor. |

## 5. Core Feature Specifications

### 5.1 Communication Engine & Hierarchy

- **Strict Onboarding:** Users select City → Institution → Section. Status remains "Pending" until
  verified by an Admin or Student Ambassador.
- **Auto-Grouping:** Verified students are automatically placed in their Class group (managed by
  the Class Teacher) and the School Notice Board.
- **Multi-Tenant Privacy:** Data is completely isolated per institution. Inter-school DMs require
  a "Message Request" acceptance to prevent spam.

### 5.2 DeepSeek AI Integration

- **Smart Study Hub:** Students snap photos of notes/exams. DeepSeek's vision model tags and
  archives them into a searchable school-wide database.
- **Auto-CT (Class Test):** Teachers prompt the AI to generate MCQs based on specific chapters.
  The app administers and auto-grades the test.
- **Pain Point Matrix:** DeepSeek analyzes failed MCQ topics and chat queries, providing teachers
  a weekly dashboard report (e.g., "60% of Section B is struggling with Calculus limits").

### 5.3 Peer-to-Peer Tuition Marketplace

- **Post Requirements:** Guardians/Students post requirements (Subject, Budget, Location).
- **Smart Matching:** The system notifies verified university/senior students within the exact
  geo-radius whose profiles match the subject expertise.

### 5.4 Smart Payments & E-Commerce

- **Fee Collection:** Push notifications with deep links to payment gateways. Successful payments
  auto-generate PDF receipts and update the School Admin's dashboard ledger.
- **Campus Commerce:** Local stores list uniforms/books with options for in-store pickup or local
  courier delivery.

## 6. Technical Stack

| Layer | Technology |
| --- | --- |
| Frontend Mobile | React Native (Expo CLI) |
| Frontend Web/Dashboard | Next.js, Tailwind CSS |
| Backend & APIs | GoLang (chi REST + gorilla/websocket for high-concurrency messaging); AI service later extracted to Python FastAPI |
| Database | PostgreSQL (Multi-tenant architecture) + Redis (for real-time chat caching) |
| Real-time Engine | WebSockets & Firebase Cloud Messaging (FCM) via Topic Subscriptions |
| AI Infrastructure | DeepSeek V4 Flash API (via commandcli) for low-latency, low-cost NLP and vision tasks |

## 7. Revenue Model (VC Pitch)

Kushol utilizes a highly scalable B2B2C monetization matrix:

### 1. FinTech Convenience Fees (High Volume)

> **Superseded (2026-09-30).** `brd.md` §7 (revised business model) removes fees on financial
> transactions. Module 12 ships the fee as platform config with default **BDT 0 (off)**; turning it
> on is an owner decision recorded in 12's `07-progress.md`. The figures below are the original pitch.

- **Mechanism:** BDT 15–20 flat fee charged to guardians for every school fee/tuition transaction
  processed in-app.
- **Scale:** 100 schools × 2,000 students × 12 months = 2.4 million transactions annually.

### 2. Marketplace & Tuition Commissions (High Margin)

- **Tuition Matchmaking:** 50% cut of the tutor's first month salary as a successful
  matchmaking/lead fee, or a BDT 300/month premium tutor subscription.
- **Campus Commerce & Protected Delivery:** Free partner registration. Buyer payments are held in Kushol Escrow (`ESCROW_HELD`). Upon verified delivery confirmation (`DELIVERED`), a **15% to 20% platform charge** (`commission_rate_bps` between 1500 and 2000, configurable per partner/category by Super Admin, default 1500 bps / 15%) is deducted, and the net 80% to 85% is released to the partner's withdrawable balance.

### 3. Hyper-Targeted B2B Ads, 3-Tier Campaigns & Events

- **Partner Self-Registration, KYC & Super Admin Verification Pipeline:** Public multi-step registration on web landing and mobile app. Free registration, presigned Cloudflare R2 uploads for KYC docs (Trade License, Owner NID, TIN/BIN), and verification preference (`PHYSICAL_VISIT` or `VIRTUAL_MEETING`). Leads queue in Super Admin Command Center (`NEW_LEAD`, `UNDER_REVIEW`, `MEETING_SCHEDULED`, `VERIFICATION_COMPLETED`, `APPROVED`, `REJECTED`/`CHANGES_REQUESTED`). Strict pre-approval login block. On approval, atomic provisioning of partner tenant, Seat #1 (`PARTNER_ADMIN`), internal chat group (`partner_{partner_id}_team`), and audit trail.
- **3-Tier Campaign Engine (Free Basic Creation vs. Paid Tiers):**
  - **Tier 1 (Own Onboarded Institutions - Free):** Basic campaigns and events targeting institutions onboarded by the partner (`onboarded_by_partner_id == partner_id`) run for 100% free (`OWN_INSTITUTIONS_FREE`).
  - **Tier 2 (Other Institutions - Paid):** Campaigns targeting other institutions across the hierarchy run with a paid budget (`OTHER_INSTITUTIONS_PAID`).
  - **Tier 3 (Global App Banner - Paid):** Promoted banners on the main Kushol app surfaces run as paid placements (`GLOBAL_APP_BANNER_PAID`).
- **Paid Extended Event Operations Suite (Paid Add-On Gate):** Basic campaign and event creation/management is free. The advanced event suite requires an unlocked add-on per campaign (`extended_suite_unlocked = true`) or a Partner Pro plan subscription (`plan_tier = 'PRO'`):
  - **Dual Roster (Participants & Volunteers - PAID):** Partners manage separate rosters for event Participants (`CAMPAIGN_PARTICIPANT`: `REGISTERED`, `PAID`, `CHECKED_IN`, `ATTENDED`, `NO_SHOW`, `CANCELLED`) and Volunteers (`CAMPAIGN_VOLUNTEER`: `PENDING`, `APPROVED`, `CHECKED_IN`, `COMPLETED`, `REVOKED`) with QR check-in, status filtering, and CSV export. Students can view available campaigns/events in mobile app and apply to volunteer.
  - **Volunteer Task Management (PAID):** Partners create and assign tasks (direct or pool tasks) with Bengali/English descriptions, priority, deadlines, and XP rewards. Volunteers update tasks in-app (`ASSIGNED` -> `IN_PROGRESS` -> `SUBMITTED_FOR_REVIEW` with R2 photo proof) and partners approve or request revisions.
  - **Rewards & Tamper-Evident E-Certificates (PAID):** Milestone-based XP ledger (`campaign_rewards_ledger`) with idempotency keys. Partners issue PDF e-certificates (Participation, Achievement, Volunteer Appreciation) stored in Cloudflare R2 with unique verification codes and public verification links. Students earn XP for completed tasks and events.
- **Targeted Promotions & Lead Gen:** EdTech brands and coaching institutions pay for demographic-targeted sponsored push notifications and banners.
- **Partner Team Seats:** 5 active team members are included for free (`free_seat_quota = 5`); seats beyond 5 require a paid seat subscription (`PARTNER_ADMIN`, `PARTNER_EXECUTIVE`).
- **XP Referral System:** Partners earn XP rewards for referring verified institutions, other partners, or campaign users, redeemable for banner impressions or member seat credits.

### 4. B2B SaaS & Premium Consumer AI (Recurring)

- **B2B SaaS:** The basic app is free. Schools pay an annual licensing fee to unlock the ERP/LMS
  Sync, Automated Fee ledgers, and the AI Pain Point Matrix.
- **B2C Freemium:** Students receive 5 free AI-generated MCQs weekly. A "Kushol Pro" subscription
  (BDT 99/month) unlocks unlimited AI tests and advanced AI study notes.
